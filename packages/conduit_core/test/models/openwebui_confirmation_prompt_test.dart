import 'package:checks/checks.dart';
import 'package:conduit_core/models/openwebui_chat_prompt.dart';
import 'package:test/test.dart';

void main() {
  group('parseOpenWebUiConfirmationPrompt', () {
    test('keeps a long title and message in full', () {
      final title = List.filled(200, 'T').join();
      final message = List.filled(3000, 'x').join();
      final prompt = parseOpenWebUiConfirmationPrompt({
        'title': '  $title ',
        'message': message,
      }, identity: 'live:1');

      check(prompt.kind).equals(OpenWebUiComposerPromptKind.confirmation);
      check(prompt.title).equals(title);
      check(prompt.message).equals(message);
      check(prompt.messageIsCode).isFalse();
    });

    test('carries the server button labels', () {
      final prompt = parseOpenWebUiConfirmationPrompt({
        'title': 'Send email?',
        'message': 'To: someone',
        'confirm_text': 'Send',
        'cancel_text': ' ',
      }, identity: 'live:1');

      check(prompt.confirmText).equals('Send');
      check(prompt.cancelText).isNull();
    });

    test('a plain confirmation has no client deadline', () {
      final prompt = parseOpenWebUiConfirmationPrompt({
        'title': 'Continue?',
        'timeout_ms': 60000,
      }, identity: 'live:1');

      check(prompt.timeout).isNull();
    });

    test('a tool call honours timeout_ms clamped to 60-240 s', () {
      Duration? timeoutFor(Object? timeoutMs) =>
          parseOpenWebUiConfirmationPrompt({
            'tool_call': {'id': 'c', 'name': 'web_search', 'arguments': '{}'},
            'timeout_ms': ?timeoutMs,
          }, identity: 'live:1').timeout;

      check(timeoutFor(null)).equals(const Duration(minutes: 2));
      check(timeoutFor(1000)).equals(const Duration(seconds: 60));
      check(timeoutFor(90000)).equals(const Duration(seconds: 90));
      check(timeoutFor(999999)).equals(const Duration(seconds: 240));
      check(timeoutFor(true)).equals(const Duration(minutes: 2));
      check(timeoutFor('90000')).equals(const Duration(minutes: 2));
    });

    test('a tool call shows its full arguments as code', () {
      final body = List.filled(3000, 'y').join();
      final prompt = parseOpenWebUiConfirmationPrompt({
        'tool_call': {
          'id': 'c',
          'name': 'send_email',
          'arguments': {'body': body},
        },
      }, identity: 'live:1');

      check(prompt.title).equals('send_email');
      check(prompt.messageIsCode).isTrue();
      check(prompt.message).contains(body);
    });
  });

  test('question forms keep their bounds', () {
    final prompt = parseOpenWebUiAskUserPrompt({
      'questions': [
        {
          'id': 'scope',
          'header': List.filled(100, 'H').join(),
          'question': 'Which?',
          'options': [
            {'label': 'A', 'description': 'a'},
            {'label': 'B', 'description': 'b'},
          ],
        },
      ],
    }, identity: 'live:1');

    check(prompt!.questions.single.header.length).equals(48);
  });
}
