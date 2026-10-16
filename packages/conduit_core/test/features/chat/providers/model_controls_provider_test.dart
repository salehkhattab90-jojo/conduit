import 'package:checks/checks.dart';
import 'package:conduit_core/features/auth/providers/unified_auth_providers.dart';
import 'package:conduit_core/features/chat/providers/model_controls_provider.dart';
import 'package:conduit_core/models/model.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/models/server_user_settings.dart';
import 'package:conduit_core/models/user.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/services/api_service.dart';
import 'package:conduit_core/services/worker_manager.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

const _member = User(
  id: 'member',
  username: 'Member',
  email: 'member@example.test',
  role: 'user',
);
const _admin = User(
  id: 'admin',
  username: 'Admin',
  email: 'admin@example.test',
  role: 'admin',
);

const _model = Model(
  id: 'm1',
  name: 'Model',
  metadata: {
    'info': {
      'id': 'm1',
      'params': {
        'model_controls': {
          'thinking': {
            'label': 'Thinking',
            'default': 'off',
            'options': {
              'off': {'label': 'Off'},
              'on': {'label': 'On'},
            },
          },
          'style': {
            'label': 'Style',
            'options': {
              'short': {'label': 'Short'},
              'long': {'label': 'Long'},
            },
          },
        },
      },
    },
  },
);

/// Stands in for the server: applies picks like
/// `ApiService.updateUserModelControls`, or drops them like a server does for
/// an account without the permissions.
final class _RecordingSettings extends PersonalizationSettings {
  _RecordingSettings(this.settings, {this.serverKeepsPicks = true});

  ServerUserSettings settings;
  final bool serverKeepsPicks;
  final writes = <(String, Map<String, String?>)>[];

  @override
  Future<ServerUserSettings> build() async => settings;

  @override
  Future<ServerUserSettings> setModelControls(
    String modelId,
    Map<String, String?> picks,
  ) async {
    writes.add((modelId, picks));
    if (!serverKeepsPicks) return settings;
    final all = {
      for (final entry in settings.modelControls.entries)
        entry.key: Map<String, String>.of(entry.value),
    };
    final choice = all.putIfAbsent(modelId, () => <String, String>{});
    for (final pick in picks.entries) {
      if (pick.value == null) {
        choice.remove(pick.key);
      } else {
        choice[pick.key] = pick.value!;
      }
    }
    if (choice.isEmpty) all.remove(modelId);
    settings = settings.copyWith(modelControls: all);
    state = AsyncData(settings);
    return settings;
  }
}

final class _FixedSelectedModel extends SelectedModel {
  _FixedSelectedModel(this.model);

  final Model model;

  @override
  Model build() => model;
}

void main() {
  ProviderContainer container({
    User user = _member,
    Map<String, dynamic> permissions = const {},
    Model model = _model,
    _RecordingSettings? settings,
    bool withApi = true,
  }) {
    final c = ProviderContainer(
      overrides: [
        apiServiceProvider.overrideWithValue(
          withApi
              ? ApiService(
                  serverConfig: const ServerConfig(
                    id: 'server',
                    name: 'Server',
                    url: 'https://example.test',
                  ),
                  workerManager: WorkerManager(),
                )
              : null,
        ),
        currentUserProvider2.overrideWith((ref) => user),
        userPermissionsProvider.overrideWith((ref) async => permissions),
        selectedModelProvider.overrideWith(() => _FixedSelectedModel(model)),
        personalizationSettingsProvider.overrideWith(
          () => settings ?? _RecordingSettings(const ServerUserSettings()),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> settle(ProviderContainer c) async {
    await c.read(userPermissionsProvider.future);
    await c.read(personalizationSettingsProvider.future);
  }

  group('who may change model controls', () {
    test('missing permissions mean allowed, as on the web', () async {
      final c = container(permissions: {'chat': <String, dynamic>{}});
      c.listen(modelControlsPermittedProvider, (_, _) {});
      await settle(c);
      check(c.read(modelControlsPermittedProvider)).isTrue();
      check(c.read(modelControlsVisibleProvider)).isTrue();
    });

    test('either permission switched off hides them', () async {
      for (final chat in [
        {'controls': false, 'params': true},
        {'controls': true, 'params': false},
      ]) {
        final c = container(permissions: {'chat': chat});
        c.listen(modelControlsPermittedProvider, (_, _) {});
        await settle(c);
        check(c.read(modelControlsPermittedProvider)).isFalse();
        check(c.read(modelControlsVisibleProvider)).isFalse();
      }
    });

    test('an admin always may', () async {
      final c = container(
        user: _admin,
        permissions: {
          'chat': {'controls': false, 'params': false},
        },
      );
      check(c.read(modelControlsPermittedProvider)).isTrue();
    });

    test('unknown permissions or no server hide them', () {
      check(
        container().read(modelControlsPermittedProvider),
      ).isFalse(); // still loading
      check(
        container(withApi: false).read(modelControlsPermittedProvider),
      ).isFalse();
    });
  });

  group('which models offer them', () {
    test('pipes and direct models have none', () async {
      for (final metadata in [
        {..._model.metadata!, 'pipe': <String, dynamic>{'type': 'pipe'}},
        {..._model.metadata!, 'direct': true},
      ]) {
        final c = container(
          model: Model(id: 'm1', name: 'Model', metadata: metadata),
        );
        check(c.read(selectedModelControlsProvider)).isEmpty();
      }
    });

    test('a server model shows its controls', () {
      check(
        container().read(selectedModelControlsProvider).keys.toList(),
      ).deepEquals(['thinking', 'style']);
    });
  });

  group('picking', () {
    test('the current pick drops options the model no longer offers', () async {
      final c = container(
        settings: _RecordingSettings(
          const ServerUserSettings(
            modelControls: {
              'm1': {'thinking': 'on', 'style': 'gone'},
            },
          ),
        ),
      );
      c.listen(selectedModelControlChoiceProvider, (_, _) {});
      await settle(c);
      check(
        c.read(selectedModelControlChoiceProvider),
      ).deepEquals({'thinking': 'on'});
    });

    test('a pick is stored and stale picks are cleared with it', () async {
      final settings = _RecordingSettings(
        const ServerUserSettings(
          modelControls: {
            'm1': {'style': 'gone'},
            'm2': {'thinking': 'on'},
          },
        ),
      );
      final c = container(settings: settings);
      c.listen(selectedModelControlChoiceProvider, (_, _) {});
      await settle(c);

      await setModelControlOption(c.read, _model, 'thinking', 'on');

      check(settings.writes.single.$1).equals('m1');
      check(
        settings.writes.single.$2,
      ).deepEquals({'style': null, 'thinking': 'on'});
      check(
        c.read(selectedModelControlChoiceProvider),
      ).deepEquals({'thinking': 'on'});
      // Other models' picks are untouched.
      check(c.read(modelControlChoicesProvider)['m2']).isNotNull().deepEquals({
        'thinking': 'on',
      });

      await setModelControlOption(c.read, _model, 'thinking', null);
      check(c.read(selectedModelControlChoiceProvider)).isEmpty();
      check(c.read(modelControlChoicesProvider).containsKey('m1')).isFalse();
    });

    test('an option the model does not offer is refused', () async {
      final settings = _RecordingSettings(const ServerUserSettings());
      final c = container(settings: settings);
      await settle(c);

      await check(
        setModelControlOption(c.read, _model, 'thinking', 'max'),
      ).throws<FormatException>();
      await check(
        setModelControlOption(c.read, _model, 'unknown', 'on'),
      ).throws<ArgumentError>();
      check(settings.writes).isEmpty();
    });

    test('a pick the server drops is reported', () async {
      final c = container(
        settings: _RecordingSettings(
          const ServerUserSettings(),
          serverKeepsPicks: false,
        ),
      );
      await settle(c);

      await check(
        setModelControlOption(c.read, _model, 'thinking', 'on'),
      ).throws<ModelControlsNotSavedException>();
    });
  });
}
