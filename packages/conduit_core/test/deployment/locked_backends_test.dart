import 'package:checks/checks.dart';
import 'package:conduit_core/deployment/deployment_policy.dart';
import 'package:conduit_core/features/direct_connections/providers/direct_connection_providers.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/persistence/persistence_keys.dart';
import 'package:conduit_core/persistence/preferences_store.dart';
import 'package:conduit_core/ports/key_value_store.dart';
import 'package:conduit_core/providers/backend_mode_providers.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

const _locked = DeploymentPolicy.locked(
  LockedServer(
    id: 'locked-server',
    name: 'Example',
    urls: ['https://chat.example.test'],
  ),
);

/// What a locked build may offer besides its Open WebUI server: nothing.
/// Upstream turns the on-device Apple models on by default and merges them
/// into the model list, so they are checked on a device that has them.
void main() {
  setUp(() async {
    PreferencesStore.installLoader(() async => InMemoryKeyValueStore());
    await PreferencesStore.ensureInitialized();
  });

  tearDown(PreferencesStore.debugReset);

  ProviderContainer container(DeploymentPolicy policy) {
    final c = ProviderContainer(
      overrides: [
        deploymentPolicyProvider.overrideWithValue(policy),
        applePccPlatformSupportedProvider.overrideWithValue(true),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('stock', () {
    test('turns the on-device Apple models on by default', () {
      final c = container(DeploymentPolicy.unlocked);

      check(c.read(appleOnDeviceEnabledProvider)).isTrue();
      check(c.read(applePccEnabledProvider)).isTrue();
    });

    test('keeps the saved backend', () async {
      await PreferencesStore.put(PreferenceKeys.preferredBackend, 'hermes');
      final c = container(DeploymentPolicy.unlocked);

      check(c.read(preferredBackendProvider)).equals(PreferredBackend.hermes);
      await c
          .read(preferredBackendProvider.notifier)
          .set(PreferredBackend.direct);
      check(c.read(preferredBackendProvider)).equals(PreferredBackend.direct);
    });
  });

  group('locked', () {
    test('keeps the on-device Apple models off whatever was saved', () async {
      await PreferencesStore.put(PreferenceKeys.appleOnDeviceEnabled, true);
      await PreferencesStore.put(PreferenceKeys.applePccEnabled, true);
      final c = container(_locked);

      check(c.read(appleOnDeviceEnabledProvider)).isFalse();
      check(c.read(applePccEnabledProvider)).isFalse();

      await c.read(appleOnDeviceEnabledProvider.notifier).setEnabled(true);
      await c.read(applePccEnabledProvider.notifier).setEnabled(true);
      check(c.read(appleOnDeviceEnabledProvider)).isFalse();
      check(c.read(applePccEnabledProvider)).isFalse();
    });

    test(
      'offers no Direct profile, so only server models are listed',
      () async {
        final c = container(_locked);

        check(await c.read(directConnectionProfilesProvider.future)).isEmpty();
        check(c.read(effectiveDirectConnectionProfilesProvider).requireValue)
            .isEmpty();
        check(
          await c.read(effectiveDirectConnectionProfilesFutureProvider.future),
        ).isEmpty();
      },
    );

    test('keeps Hermes off and its secrets settled', () async {
      await PreferencesStore.put(PreferenceKeys.hermesEnabled, true);
      final c = container(_locked);

      check(c.read(hermesConfigProvider).enabled).isFalse();
      check(c.read(hermesConfigProvider).isUsable).isFalse();
      check(c.read(hermesEnabledProvider)).isFalse();
      check(c.read(hermesConnectionsProvider)).isEmpty();
      check(c.read(hermesSecretsLoadingProvider)).isFalse();

      await c.read(hermesConfigProvider.notifier).setEnabled(true);
      check(c.read(hermesEnabledProvider)).isFalse();
    });

    test('uses Open WebUI whatever backend was saved', () async {
      await PreferencesStore.put(PreferenceKeys.preferredBackend, 'direct');
      final c = container(_locked);

      check(c.read(preferredBackendProvider)).equals(PreferredBackend.owui);
      for (final backend in [
        PreferredBackend.hermes,
        PreferredBackend.direct,
        PreferredBackend.unset,
      ]) {
        await c.read(preferredBackendProvider.notifier).set(backend);
        check(
          because: '$backend',
          c.read(preferredBackendProvider),
        ).equals(PreferredBackend.owui);
      }
      check(PreferencesStore.getString(PreferenceKeys.preferredBackend))
          .equals('direct');
    });
  });
}
