import 'dart:convert';

import 'package:conduit/features/chat/providers/text_to_speech_provider.dart';
import 'package:conduit/features/chat/widgets/assistant_message_widget.dart';
import 'package:conduit/features/chat/widgets/delivery_cards.dart';
import 'package:conduit/features/chat/widgets/enhanced_attachment.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit/shared/widgets/web_content_embed.dart';
import 'package:conduit_core/models/chat_message.dart';
import 'package:conduit_core/services/settings_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _SilentTextToSpeechController extends TextToSpeechController {
  @override
  TextToSpeechState build() => const TextToSpeechState();
}

ChatMessage _assistant({
  List<Map<String, dynamic>>? files,
  List<Map<String, dynamic>>? embeds,
  List<Map<String, dynamic>>? output,
}) => ChatMessage(
  id: 'assistant-1',
  role: 'assistant',
  content: 'Here you go.',
  timestamp: DateTime(2026, 1, 1),
  model: 'model',
  files: files,
  embeds: embeds,
  output: output,
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  ChatMessage message,
) async {
  final container = ProviderContainer(
    overrides: [
      textToSpeechControllerProvider.overrideWith(
        _SilentTextToSpeechController.new,
      ),
      streamingHapticsEnabledProvider.overrideWithValue(false),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(TweakcnThemes.t3Chat),
        localizationsDelegates: conduitLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AssistantMessageWidget(
              message: message,
              showFollowUps: false,
              animateOnMount: false,
              onDelete: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

List<Map<String, dynamic>> _toolCall({
  required String callId,
  required String name,
  Map<String, dynamic> arguments = const {},
  String resultText = 'done',
  List<Map<String, dynamic>>? files,
  List<Object>? embeds,
}) => [
  {
    'type': 'function_call',
    'call_id': callId,
    'name': name,
    'arguments': jsonEncode(arguments),
    'status': 'completed',
  },
  {
    'type': 'function_call_output',
    'call_id': callId,
    'output': [
      {'type': 'input_text', 'text': resultText},
    ],
    'status': 'completed',
    'files': ?files,
    'embeds': ?embeds,
  },
];

void main() {
  testWidgets('a document from a tool result shows as one card', (
    tester,
  ) async {
    await _pump(
      tester,
      _assistant(
        output: _toolCall(
          callId: 'c1',
          name: 'generate_document',
          files: [
            {
              'type': 'data',
              'url': '/api/v1/files/real-1/content',
              'name': 'Report.docx',
            },
          ],
          embeds: [
            {
              'type': 'preview',
              'url': '/api/v1/files/prev-1/content',
              'name': 'Report.docx.pdf',
              'content_type': 'application/pdf',
            },
          ],
        ),
      ),
    );

    expect(find.byType(DeliveryCard), findsOneWidget);
    expect(find.text('Report.docx'), findsOneWidget);
    expect(find.text('DOCX'), findsOneWidget);
    expect(find.text('Document · tap to preview'), findsOneWidget);
    expect(find.byType(EnhancedAttachment), findsNothing);
    expect(find.byType(WebContentEmbed), findsNothing);
  });

  testWidgets('a legacy HTML preview and its file fuse into one card', (
    tester,
  ) async {
    await _pump(
      tester,
      _assistant(
        files: const [
          {
            'type': 'file',
            'url': '/api/v1/files/real-1/content',
            'name': 'Budget.xlsx',
          },
        ],
        embeds: const [
          {'src': '<html><body>budget</body></html>'},
        ],
      ),
    );

    expect(find.byType(DeliveryCard), findsOneWidget);
    expect(find.text('Budget.xlsx'), findsOneWidget);
    expect(find.text('XLSX'), findsOneWidget);
    expect(find.byType(EnhancedAttachment), findsNothing);
    expect(find.byType(WebContentEmbed), findsNothing);
  });

  testWidgets('a preview object never renders as an inline embed', (
    tester,
  ) async {
    await _pump(
      tester,
      _assistant(
        embeds: const [
          {
            'type': 'preview',
            'url': '/api/v1/files/prev-1/content',
            'name': 'Deck.pptx.pdf',
            'content_type': 'application/pdf',
            'src': '/api/v1/files/prev-1/content',
          },
        ],
      ),
    );

    expect(find.byType(WebContentEmbed), findsNothing);
    expect(find.text('Deck.pptx'), findsOneWidget);
    expect(find.text('PPTX'), findsOneWidget);
  });

  test('identity colours stay open-ended', () {
    expect(deliveryIdentityColor('docx'), const Color(0xFF3B82F6));
    expect(deliveryIdentityColor('csv'), const Color(0xFF10B981));
    expect(deliveryIdentityColor('pptx'), const Color(0xFFF97316));
    expect(deliveryIdentityColor('pdf'), const Color(0xFFEF4444));
    expect(deliveryIdentityColor('svg'), const Color(0xFF8B5CF6));
    expect(deliveryIdentityColor('md'), const Color(0xFF6B7280));
    expect(deliveryIdentityColor('parquet'), isNull);
    expect(deliveryIdentityColor(null), isNull);
  });
}
