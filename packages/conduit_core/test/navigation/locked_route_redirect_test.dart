import 'package:checks/checks.dart';
import 'package:conduit_core/auth/auth_state_manager.dart';
import 'package:conduit_core/deployment/deployment_policy.dart';
import 'package:conduit_core/features/auth/providers/unified_auth_providers.dart';
import 'package:conduit_core/features/direct_connections/models/direct_connection_profile.dart';
import 'package:conduit_core/features/direct_connections/providers/direct_connection_providers.dart';
import 'package:conduit_core/features/hermes/models/hermes_config.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/navigation/route_redirect.dart';
import 'package:conduit_core/navigation/routes.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/providers/backend_mode_providers.dart';
import 'package:conduit_core/providers/chat_entry_readiness_providers.dart';
import 'package:conduit_core/providers/openwebui_accounts_controller.dart';
import 'package:conduit_core/providers/openwebui_route_resolver.dart';
import 'package:riverpod/misc.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

const _lockedServer = LockedServer(
  id: 'locked-server',
  name: 'Example',
  urls: ['https://chat.example.test'],
);

const _locked = DeploymentPolicy.locked(_lockedServer);

const _server = ServerConfig(
  id: 'locked-server',
  name: 'Example',
  url: 'https://chat.example.test',
);

/// Routes a locked build must never show.
const _lockedOut = <String>[
  Routes.login,
  Routes.backendChooser,
  Routes.serverConnection,
  Routes.addServer,
  Routes.accounts,
  Routes.serverAddresses,
  Routes.serverAddressEditor,
  Routes.directConnections,
  '/profile/direct-connections/some-id',
  '/profile/direct-connections/mcp/some-id',
  Routes.hermesSettings,
  '/profile/hermes/connections/new',
  Routes.hermesJobs,
  Routes.hermesMcp,
];

/// A [ProviderRead] over fixed values. With a locked policy the preferred
/// backend, Hermes and Direct providers read as the locked build makes them:
/// Open WebUI, Hermes off, no Direct profiles, no accountless backend.
ProviderRead _reader({
  DeploymentPolicy policy = _locked,
  bool reviewerMode = false,
  AsyncValue<ServerConfig?> activeServer = const AsyncData(_server),
  AuthNavigationState auth = AuthNavigationState.authenticated,
  String? addingAccountFrom,
}) {
  final values = <ProviderListenable<Object?>, Object?>{
    deploymentPolicyProvider: policy,
    accountAdditionOriginProvider: addingAccountFrom,
    settledActiveAccountIdProvider: null,
    proxySignInForRouteEditingProvider: false,
    reviewerModeProvider: reviewerMode,
    activeServerProvider: activeServer,
    authNavigationStateProvider: auth,
    preferredBackendProvider: PreferredBackend.owui,
    hermesConfigProvider: const HermesConfig(),
    hermesSecretsLoadingProvider: false,
    effectiveDirectConnectionProfilesProvider:
        const AsyncData<List<DirectConnectionProfile>>([]),
    accountlessPrimaryBackendUsableProvider: false,
    authStateManagerProvider: const AsyncData<AuthState>(
      AuthState(status: AuthStatus.unauthenticated),
    ),
  };
  return <T>(ProviderListenable<T> provider) {
    if (!values.containsKey(provider)) {
      throw StateError('Unexpected provider read: $provider');
    }
    return values[provider] as T;
  };
}

void main() {
  group('a locked deployment', () {
    test('re-evaluates when the policy changes', () {
      check(routeRedirectDependencies).contains(deploymentPolicyProvider);
    });

    test('holds the splash, not the backend chooser, with no server', () {
      final read = _reader(
        activeServer: const AsyncData(null),
        auth: AuthNavigationState.needsLogin,
      );

      check(resolveRouteRedirect(Routes.chat, read)).equals(Routes.splash);
      check(resolveRouteRedirect(Routes.splash, read)).isNull();
      check(resolveRouteRedirect(Routes.authentication, read))
          .equals(Routes.splash);
      check(resolveRouteRedirect(Routes.backendChooser, read))
          .equals(Routes.splash);
      check(resolveRouteRedirect(Routes.serverConnection, read))
          .equals(Routes.splash);
    });

    test('sends a signed-out user to sign-in, never to server setup', () {
      final read = _reader(auth: AuthNavigationState.needsLogin);

      check(resolveRouteRedirect(Routes.chat, read))
          .equals(Routes.authentication);
      check(resolveRouteRedirect(Routes.authentication, read)).isNull();
      check(resolveRouteRedirect(Routes.ssoAuth, read)).isNull();
      check(resolveRouteRedirect(Routes.proxyAuth, read)).isNull();
      for (final location in _lockedOut) {
        check(
          because: location,
          resolveRouteRedirect(location, read),
        ).equals(Routes.authentication);
      }
    });

    test('sends a signed-in user from every locked-out page to chat', () {
      final read = _reader();

      for (final location in _lockedOut) {
        check(
          because: location,
          resolveRouteRedirect(location, read),
        ).equals(Routes.chat);
      }
      check(resolveRouteRedirect(Routes.chat, read)).isNull();
      check(resolveRouteRedirect(Routes.profile, read)).isNull();
      check(resolveRouteRedirect(Routes.about, read)).isNull();
    });

    test('keeps the splash while the session is established', () {
      final read = _reader(auth: AuthNavigationState.loading);

      for (final location in _lockedOut) {
        check(
          because: location,
          resolveRouteRedirect(location, read),
        ).equals(Routes.splash);
      }
    });

    test('never adds an account', () {
      final read = _reader(addingAccountFrom: _server.id);

      check(resolveRouteRedirect(Routes.addServer, read)).equals(Routes.chat);
      check(resolveRouteRedirect(Routes.serverConnection, read))
          .equals(Routes.chat);
    });

    test('ignores reviewer mode', () {
      final read = _reader(
        reviewerMode: true,
        auth: AuthNavigationState.needsLogin,
      );

      check(resolveRouteRedirect(Routes.chat, read))
          .equals(Routes.authentication);
      check(resolveRouteRedirect(Routes.profile, read))
          .equals(Routes.authentication);
    });

    test('no route leads to a locked-out page', () {
      for (final auth in AuthNavigationState.values) {
        for (final active in <AsyncValue<ServerConfig?>>[
          const AsyncData(_server),
          const AsyncData(null),
          const AsyncLoading(),
          AsyncError<ServerConfig?>('boom', StackTrace.empty),
        ]) {
          final read = _reader(activeServer: active, auth: auth);
          for (final location in [..._lockedOut, Routes.chat, Routes.splash]) {
            final destination = resolveRouteRedirect(location, read);
            if (destination == null) {
              check(
                because: '$auth $active $location stays',
                _locked.closesLocation(location),
              ).isFalse();
            } else {
              check(
                because: '$auth $active $location -> $destination',
                _locked.closesLocation(Uri.parse(destination).path),
              ).isFalse();
            }
          }
        }
      }
    });
  });

  test('the unlocked policy keeps the backend chooser for a new install', () {
    final read = _reader(
      policy: DeploymentPolicy.unlocked,
      activeServer: const AsyncData(null),
      auth: AuthNavigationState.needsLogin,
    );

    check(resolveRouteRedirect(Routes.chat, read))
        .equals(Routes.backendChooser);
    check(resolveRouteRedirect(Routes.serverConnection, read)).isNull();
    check(resolveRouteRedirect(Routes.backendChooser, read)).isNull();
  });
}
