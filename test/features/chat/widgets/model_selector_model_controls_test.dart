import 'dart:io';

import 'package:conduit/features/chat/widgets/model_selector_sheet.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit_core/database/app_database.dart';
import 'package:conduit_core/database/database_provider.dart';
import 'package:conduit_core/features/auth/providers/unified_auth_providers.dart';
import 'package:conduit_core/features/direct_connections/models/direct_connection_profile.dart';
import 'package:conduit_core/features/direct_connections/providers/direct_connection_providers.dart';
import 'package:conduit_core/models/model.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/models/server_user_settings.dart';
import 'package:conduit_core/models/user.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/services/api_service.dart';
import 'package:conduit_core/services/worker_manager.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _model = Model(
  id: 'm1',
  name: 'Model one',
  metadata: {
    'info': {
      'id': 'm1',
      'params': {
        'model_controls': {
          'thinking': {
            'label': 'Thinking',
            'description': 'Reason before answering',
            'default': 'off',
            'options': {
              'off': {'label': 'Off'},
              'on': {'label': 'On'},
            },
          },
        },
      },
    },
  },
);

class _RecordingPersonalization extends PersonalizationSettings {
  final writes = <(String, Map<String, String?>)>[];
  ServerUserSettings current = const ServerUserSettings();

  @override
  Future<ServerUserSettings> build() async => current;

  @override
  Future<ServerUserSettings> setModelControls(
    String modelId,
    Map<String, String?> picks,
  ) async {
    writes.add((modelId, picks));
    current = current.copyWith(
      modelControls: {
        modelId: {
          for (final pick in picks.entries)
            if (pick.value != null) pick.key: pick.value!,
        },
      },
    );
    state = AsyncData(current);
    return current;
  }
}

class _NoProfiles extends DirectConnectionProfilesController {
  @override
  Future<List<DirectConnectionProfile>> build() async => const [];
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await db.close();
  });

  Future<_RecordingPersonalization> pumpSheet(
    WidgetTester tester, {
    required Map<String, dynamic> permissions,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final personalization = _RecordingPersonalization();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        apiServiceProvider.overrideWithValue(
          ApiService(
            serverConfig: const ServerConfig(
              id: 'picker',
              name: 'picker',
              url: 'https://picker.example.test',
            ),
            workerManager: WorkerManager(),
          ),
        ),
        reviewerModeProvider.overrideWithValue(false),
        selectedModelProvider.overrideWithValue(_model),
        personalizationSettingsProvider.overrideWith(() => personalization),
        directConnectionProfilesProvider.overrideWith(_NoProfiles.new),
        currentUserProvider2.overrideWithValue(
          const User(
            id: 'me',
            username: 'me',
            email: 'me@example.test',
            role: 'user',
          ),
        ),
        userPermissionsProvider.overrideWith((ref) async => permissions),
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
          home: const Scaffold(body: ModelSelectorSheet(models: [_model])),
        ),
      ),
    );
    await settle(tester);
    await settle(tester);
    return personalization;
  }

  testWidgets('shows the model controls and stores a pick', (tester) async {
    final personalization = await pumpSheet(
      tester,
      permissions: {'chat': <String, dynamic>{}},
    );

    expect(find.text('Thinking'), findsOneWidget);
    expect(find.text('Default · Off'), findsOneWidget);

    await tester.tap(find.text('Thinking'));
    for (var i = 0; i < 5; i++) {
      await settle(tester);
    }
    expect(find.text('Reason before answering'), findsOneWidget);

    await tester.tap(find.text('On').last);
    await settle(tester);
    await settle(tester);

    expect(personalization.writes, hasLength(1));
    expect(personalization.writes.single.$1, 'm1');
    expect(personalization.writes.single.$2, {'thinking': 'on'});
    expect(find.text('On'), findsOneWidget);
  });

  testWidgets('hidden without the controls permission', (tester) async {
    await pumpSheet(
      tester,
      permissions: {
        'chat': {'controls': false},
      },
    );

    expect(find.text('Thinking'), findsNothing);
  });
}

// The sheet has a running animation, so it never "settles".
Future<void> settle(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 400));
