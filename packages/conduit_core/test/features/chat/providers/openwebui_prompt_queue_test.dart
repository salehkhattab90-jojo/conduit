// The confirmation guarantees (one prompt on screen at a time in arrival
// order, nothing dropped, every request answered exactly once, declined when
// its stream ends or its chat is left, no silent client deny) on the live
// prompt queue.
import 'package:checks/checks.dart';
import 'package:conduit_core/features/chat/providers/openwebui_chat_prompt_provider.dart';
import 'package:conduit_core/models/openwebui_chat_prompt.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() => debugOpenWebUiPromptTimeoutOverride = null);

  late ProviderContainer container;
  late OpenWebUiLivePromptNotifier notifier;

  setUp(() {
    container = ProviderContainer();
    notifier = container.read(openWebUiLivePromptProvider.notifier);
  });
  tearDown(() => container.dispose());

  OpenWebUiComposerPrompt? onScreen() =>
      container.read(openWebUiLivePromptProvider)?.prompt;

  void confirm(
    List<dynamic> responses, {
    String conversationId = 'chat-1',
    String message = 'Send it?',
    Object? owner,
  }) {
    notifier.handleSocketRequest(
      conversationId: conversationId,
      type: 'confirmation',
      data: {'title': 'Confirm', 'message': message},
      acknowledge: responses.add,
      owner: owner,
    );
  }

  test('shows one request at a time, in arrival order', () {
    final a = <dynamic>[];
    final b = <dynamic>[];
    confirm(a, message: 'first');
    confirm(b, message: 'second');

    check(onScreen()!.message).equals('first');
    check(notifier.queuedCount).equals(1);
    notifier.decide(onScreen()!.identity, true);
    check(a).deepEquals([true]);
    check(b).isEmpty();
    check(notifier.queuedCount).equals(0);

    check(onScreen()!.message).equals('second');
    notifier.decide(onScreen()!.identity, false);
    check(b).deepEquals([false]);
    check(onScreen()).isNull();
  });

  test('a new request never replaces or answers the one on screen', () {
    final a = <dynamic>[];
    final b = <dynamic>[];
    confirm(a, message: 'first');
    final first = onScreen()!.identity;
    confirm(b, message: 'second');

    check(onScreen()!.identity).equals(first);
    check(a).isEmpty();
  });

  test('a request cancelled while queued is answered and never shown', () {
    final a = <dynamic>[];
    final b = <dynamic>[];
    confirm(a, conversationId: 'chat-1', message: 'first');
    confirm(b, conversationId: 'chat-2', message: 'second');

    notifier.cancelForConversation('chat-2');
    check(b).deepEquals([false]);
    check(onScreen()!.message).equals('first');

    notifier.decide(onScreen()!.identity, true);
    check(a).deepEquals([true]);
    check(onScreen()).isNull();
  });

  test('each request is answered exactly once', () {
    final responses = <dynamic>[];
    confirm(responses);
    final identity = onScreen()!.identity;

    notifier.decide(identity, true);
    notifier.decide(identity, false);
    notifier.cancel();
    notifier.cancelForConversation('chat-1');
    container.dispose();

    check(responses).deepEquals([true]);
  });

  test('a request delivered to two listeners is queued and answered once', () {
    final responses = <dynamic>[];
    void acknowledge(dynamic response) => responses.add(response);
    for (var i = 0; i < 2; i++) {
      notifier.handleSocketRequest(
        conversationId: 'chat-1',
        type: 'confirmation',
        data: const {'title': 'Confirm', 'message': 'Send it?'},
        acknowledge: acknowledge,
      );
    }

    check(notifier.queuedCount).equals(0);
    notifier.decide(onScreen()!.identity, true);
    check(responses).deepEquals([true]);
    check(onScreen()).isNull();
  });

  test('the end of a stream declines only the requests it raised', () {
    final ownStream = Object();
    final otherStream = Object();
    final own = <dynamic>[];
    final queuedOwn = <dynamic>[];
    final other = <dynamic>[];
    confirm(own, owner: ownStream, message: 'own');
    confirm(other, owner: otherStream, message: 'other');
    confirm(queuedOwn, owner: ownStream, message: 'own, queued');

    notifier.cancelForOwner(ownStream);

    check(own).deepEquals([false]);
    check(queuedOwn).deepEquals([false]);
    check(other).isEmpty();
    check(onScreen()!.message).equals('other');
  });

  test('leaving the chat declines its requests, shown or queued', () {
    final shown = <dynamic>[];
    final queued = <dynamic>[];
    final question = <dynamic>[];
    confirm(shown, conversationId: 'chat-1');
    notifier.handleSocketRequest(
      conversationId: 'chat-1',
      type: 'request:user_input',
      data: _questionData(),
      acknowledge: question.add,
    );
    confirm(queued, conversationId: 'chat-1');

    notifier.cancelForConversation('chat-1');

    check(shown).deepEquals([false]);
    check(question).deepEquals([
      {'status': 'cancelled', 'answers': {}},
    ]);
    check(queued).deepEquals([false]);
    check(onScreen()).isNull();
  });

  test('dismissing a question form answers only that form', () {
    final question = <dynamic>[];
    final queued = <dynamic>[];
    notifier.handleSocketRequest(
      conversationId: 'chat-1',
      type: 'request:user_input',
      data: _questionData(),
      acknowledge: question.add,
    );
    confirm(queued);

    notifier.dismiss(onScreen()!.identity);

    check(question).deepEquals([
      {'status': 'cancelled', 'answers': {}},
    ]);
    check(queued).isEmpty();
    check(onScreen()!.kind).equals(OpenWebUiComposerPromptKind.confirmation);
  });

  test('a deadline runs from arrival, also while queued', () async {
    final confirmation = <dynamic>[];
    final question = <dynamic>[];
    debugOpenWebUiPromptTimeoutOverride = const Duration(milliseconds: 5);
    confirm(confirmation);
    notifier.handleSocketRequest(
      conversationId: 'chat-1',
      type: 'request:user_input',
      data: _questionData(),
      acknowledge: question.add,
    );

    await Future<void>.delayed(const Duration(milliseconds: 30));

    check(question).deepEquals([
      {'status': 'cancelled', 'answers': {}},
    ]);
    check(confirmation).isEmpty();
    check(notifier.queuedCount).equals(0);
    check(onScreen()!.kind).equals(OpenWebUiComposerPromptKind.confirmation);
  });

  test('a tool call awaiting approval is declined at its deadline', () async {
    final responses = <dynamic>[];
    debugOpenWebUiPromptTimeoutOverride = const Duration(milliseconds: 5);
    notifier.handleSocketRequest(
      conversationId: 'local:chat-1',
      type: 'confirmation',
      data: const {
        'tool_call': {
          'id': 'call-1',
          'name': 'send_message',
          'arguments': {'to': 'someone'},
        },
      },
      acknowledge: responses.add,
    );

    check(onScreen()!.messageIsCode).isTrue();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    check(responses).deepEquals([false]);
    check(onScreen()).isNull();
  });

  test('disposing the provider declines everything still waiting', () {
    final shown = <dynamic>[];
    final queued = <dynamic>[];
    confirm(shown);
    notifier.handleSocketRequest(
      conversationId: 'chat-1',
      type: 'request:user_input',
      data: _questionData(),
      acknowledge: queued.add,
    );

    container.dispose();

    check(shown).deepEquals([false]);
    check(queued).deepEquals([
      {'status': 'cancelled', 'answers': {}},
    ]);
  });
}

Map<String, dynamic> _questionData() => {
  'questions': [
    {
      'id': 'scope',
      'header': 'Scope',
      'question': 'Which scope?',
      'options': [
        {'label': 'This chat', 'description': 'Use this chat only'},
        {'label': 'All chats', 'description': 'Use every chat'},
      ],
    },
  ],
  'timeout_ms': 60000,
};
