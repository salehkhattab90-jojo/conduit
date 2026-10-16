import 'package:checks/checks.dart';
import 'package:conduit_core/deployment/deployment_policy.dart';
import 'package:conduit_core/navigation/routes.dart';
import 'package:conduit_core/providers/backend_mode_providers.dart';
import 'package:test/test.dart';

const _server = LockedServer(
  id: 'locked-server',
  name: 'Example',
  urls: ['https://chat.example.test'],
);

const _locked = DeploymentPolicy.locked(_server);

/// Every route path the app registers, by its pattern.
const _allRoutes = <String>[
  Routes.splash,
  Routes.chat,
  Routes.folder,
  Routes.login,
  Routes.backendChooser,
  Routes.serverConnection,
  Routes.addServer,
  Routes.connectionIssue,
  Routes.authentication,
  Routes.ssoAuth,
  Routes.proxyAuth,
  Routes.profile,
  Routes.personalization,
  Routes.audioSettings,
  Routes.voiceProviderSettings,
  Routes.accountSettings,
  Routes.accounts,
  Routes.serverAddresses,
  Routes.serverAddressEditor,
  Routes.notificationSettings,
  Routes.appearanceSettings,
  Routes.chatSettings,
  Routes.dataConnectionSettings,
  Routes.personalConnections,
  Routes.personalConnectionEditor,
  Routes.chatDataControls,
  Routes.scheduledTasks,
  Routes.scheduledTaskNew,
  Routes.scheduledTaskDetail,
  Routes.scheduledTaskEdit,
  Routes.calendar,
  Routes.directConnections,
  Routes.directConnectionEditor,
  Routes.directMcpServerEditor,
  Routes.hermesSettings,
  Routes.hermesConnectionEditor,
  Routes.hermesJobs,
  Routes.hermesMcp,
  Routes.about,
  Routes.notes,
  Routes.noteEditor,
  Routes.channel,
  Routes.workspace,
];

void main() {
  group('the unlocked policy', () {
    const policy = DeploymentPolicy.unlocked;

    test('is stock Conduit', () {
      check(policy.isLocked).isFalse();
      check(policy.lockedServer).isNull();
      check(policy.allowAccountManagement).isTrue();
      check(policy.allowOnDeviceWebSearch).isTrue();
      check(policy.ssoProviders).isNull();
      check(policy.authModes).deepEquals(DeploymentSignInMode.values.toSet());
    });

    test('closes no page', () {
      for (final route in _allRoutes) {
        check(because: route, policy.closesLocation(route)).isFalse();
      }
    });

    test('leaves every saved backend as it is', () {
      for (final backend in PreferredBackend.values) {
        check(because: '$backend', policy.allowsBackend(backend)).isTrue();
        check(policy.effectiveBackend(backend)).equals(backend);
      }
    });

    test('opens Open WebUI sign-in for SSO', () {
      check(policy.ssoInitialPath).equals('/auth');
      check(policy.allowsSsoProvider('google')).isTrue();
    });
  });

  group('a locked policy', () {
    test('is locked to its server, Open WebUI only', () {
      check(_locked.isLocked).isTrue();
      check(_locked.lockedServer).identicalTo(_server);
      check(_locked.allowAccountManagement).isFalse();
      check(_locked.allowOnDeviceWebSearch).isFalse();
      check(_locked.allowedBackends).deepEquals({PreferredBackend.owui});
    });

    test('closes server setup, accounts, Hermes and Direct', () {
      const closed = <String>{
        Routes.login,
        Routes.backendChooser,
        Routes.serverConnection,
        Routes.addServer,
        Routes.accounts,
        Routes.serverAddresses,
        Routes.serverAddressEditor,
        Routes.directConnections,
        Routes.directConnectionEditor,
        Routes.directMcpServerEditor,
        Routes.hermesSettings,
        Routes.hermesConnectionEditor,
        Routes.hermesJobs,
        Routes.hermesMcp,
      };
      for (final route in _allRoutes) {
        check(
          because: route,
          _locked.closesLocation(route),
        ).equals(closed.contains(route));
      }
      check(_locked.closesLocation(Routes.directConnectionEditorPath('a')))
          .isTrue();
      check(
        _locked.closesLocation(
          Routes.hermesConnectionEditorPath(Routes.hermesNewConnectionId),
        ),
      ).isTrue();
    });

    test('uses Open WebUI whatever backend was saved', () {
      for (final backend in PreferredBackend.values) {
        check(_locked.effectiveBackend(backend)).equals(PreferredBackend.owui);
      }
      check(_locked.allowsBackend(PreferredBackend.owui)).isTrue();
      check(_locked.allowsBackend(PreferredBackend.unset)).isFalse();
      check(_locked.allowsBackend(PreferredBackend.direct)).isFalse();
      check(_locked.allowsBackend(PreferredBackend.hermes)).isFalse();
    });

    test('opens the one allowed provider straight away', () {
      const google = DeploymentPolicy.locked(_server, ssoProviders: ['google']);
      check(google.ssoInitialPath).equals('/oauth/google/login');
      check(google.allowsSsoProvider('google')).isTrue();
      check(google.allowsSsoProvider('github')).isFalse();

      const two = DeploymentPolicy.locked(
        _server,
        ssoProviders: ['google', 'microsoft'],
      );
      check(two.ssoInitialPath).equals('/auth');
    });

    test('narrows the sign-in methods', () {
      const policy = DeploymentPolicy.locked(
        _server,
        authModes: {DeploymentSignInMode.credentials, DeploymentSignInMode.sso},
      );
      check(policy.allowsSignInMode(DeploymentSignInMode.credentials)).isTrue();
      check(policy.allowsSignInMode(DeploymentSignInMode.sso)).isTrue();
      check(policy.allowsSignInMode(DeploymentSignInMode.ldap)).isFalse();
      check(policy.allowsSignInMode(DeploymentSignInMode.token)).isFalse();
    });
  });
}
