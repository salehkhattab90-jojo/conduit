import 'package:conduit/features/chat/widgets/confirmation_message_body.dart';
import 'package:conduit/features/chat/widgets/openwebui_prompt_overlay.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit_core/models/openwebui_chat_prompt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('a long confirmation is shown in full and scrolls', (
    tester,
  ) async {
    final lines = [
      for (var i = 0; i < 200; i++) 'Body line $i of the message.',
      'END OF MESSAGE',
    ];
    await _pump(
      tester,
      OpenWebUiPromptOverlay(
        prompt: parseOpenWebUiConfirmationPrompt({
          'title': 'Send this email?',
          'message': lines.join('\n'),
        }, identity: 'live:1'),
        onDecision: (_) {},
      ),
    );

    // Nothing is cut: the last line is in the body.
    expect(find.textContaining('END OF MESSAGE'), findsOneWidget);

    final body = find.byKey(const ValueKey('openwebui-prompt-message'));
    final scrollable = find.ancestor(
      of: body,
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    final viewport = tester.getSize(scrollable);
    // Most of the screen, but the buttons stay visible below it.
    expect(viewport.height, greaterThan(200));
    expect(find.text('Confirm').hitTestable(), findsOneWidget);

    await tester.scrollUntilVisible(
      find.textContaining('END OF MESSAGE'),
      200,
      scrollable: scrollable,
    );
    expect(find.textContaining('END OF MESSAGE').hitTestable(), findsOneWidget);
  });

  testWidgets('uses the server labels and reports the decision', (
    tester,
  ) async {
    final decisions = <bool>[];
    Future<void> show(String identity) => _pump(
      tester,
      OpenWebUiPromptOverlay(
        key: ValueKey(identity),
        prompt: parseOpenWebUiConfirmationPrompt({
          'title': 'Send email?',
          'message': '**To:** someone',
          'confirm_text': 'Send',
          'cancel_text': 'Keep draft',
        }, identity: identity),
        onDecision: decisions.add,
      ),
    );

    await show('live:1');
    expect(find.text('Confirm'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    await tester.tap(find.text('Keep draft'));
    await tester.pump();
    await show('live:2');
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(decisions, [false, true]);
  });

  testWidgets('tool-call arguments are shown as code, not rendered', (
    tester,
  ) async {
    await _pump(
      tester,
      OpenWebUiPromptOverlay(
        prompt: parseOpenWebUiConfirmationPrompt({
          'tool_call': {
            'id': 'c',
            'name': 'send_email',
            'arguments': {'body': '**not bold** > not a quote'},
          },
        }, identity: 'live:1'),
        onDecision: (_) {},
      ),
    );

    expect(find.byType(ConfirmationMessageBody), findsNothing);
    expect(find.textContaining('**not bold**'), findsOneWidget);
  });

  testWidgets('the body stays inert for an injection payload', (tester) async {
    const payload =
        '- **To:** attacker@example.com\n'
        '> quoted body line\n'
        '```mermaid\ngraph TD;A-->B;\n```\n'
        '<script>alert(1)</script>\n'
        '![x](http://example.com/beacon.png)\n'
        '[click me](http://example.com)';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ConfirmationMessageBody(
            message: payload,
            style: TextStyle(fontSize: 14),
            quoteColor: Colors.grey,
            quoteBorderColor: Colors.grey,
          ),
        ),
      ),
    );

    // Shown as literal text.
    expect(find.textContaining('attacker@example.com'), findsWidgets);
    expect(find.textContaining('quoted body line'), findsWidgets);
    expect(find.textContaining('beacon.png'), findsWidgets);
    expect(find.textContaining('<script>alert(1)</script>'), findsWidgets);
    expect(find.textContaining('[click me](http://example.com)'), findsWidgets);
    expect(find.textContaining('**To:**'), findsNothing);

    // Nothing that loads, runs or reacts to a tap.
    final body = find.byType(ConfirmationMessageBody);
    expect(
      find.descendant(of: body, matching: find.byType(Image)),
      findsNothing,
    );
    expect(
      find.descendant(of: body, matching: find.byType(GestureDetector)),
      findsNothing,
    );
    expect(
      find.descendant(of: body, matching: find.byType(InkWell)),
      findsNothing,
    );
    final richTexts = tester.widgetList<RichText>(
      find.descendant(of: body, matching: find.byType(RichText)),
    );
    for (final richText in richTexts) {
      richText.text.visitChildren((span) {
        expect(span is TextSpan && span.recognizer != null, isFalse);
        return true;
      });
    }
  });

  testWidgets('bold spans and quotes are the only marks', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ConfirmationMessageBody(
            message: '**Subject:** Hello\n> quoted\nplain ** unmatched',
            style: TextStyle(fontSize: 14),
            quoteColor: Colors.grey,
            quoteBorderColor: Colors.grey,
          ),
        ),
      ),
    );

    final subject = tester.widget<RichText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().startsWith('Subject:'),
      ),
    );
    final spans = <TextSpan>[];
    subject.text.visitChildren((span) {
      if (span is TextSpan && span.text != null) spans.add(span);
      return true;
    });
    expect(spans.first.text, 'Subject:');
    expect(spans.first.style?.fontWeight, FontWeight.w600);
    expect(find.text('quoted'), findsOneWidget);
    expect(find.text('plain ** unmatched'), findsOneWidget);
  });
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: conduitLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(width: 390, child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
