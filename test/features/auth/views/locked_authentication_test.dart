import 'package:checks/checks.dart';
import 'package:conduit/core/deployment/deployment_providers.dart';
import 'package:conduit/features/auth/views/authentication_page.dart';
import 'package:conduit/platform/webview_cookie_helper.dart';
import 'package:conduit/shared/services/navigation_service.dart';
import 'package:conduit/shared/widgets/platform_ui/platform_ui.dart';
import 'package:conduit_core/models/backend_config.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:flutter/widgets.dart' show ValueKey;
import 'package:flutter_test/flutter_test.dart';

import 'support/adaptive_auth_harness.dart';

const _server = ServerConfig(
  id: 'locked-server',
  name: 'Example',
  url: 'https://chat.example.test',
  isActive: true,
);

const _lockedServer = LockedServer(
  id: 'locked-server',
  name: 'Example',
  urls: ['https://chat.example.test'],
);

const _backButton = ValueKey<String>('authentication-back-button');
const _tagline = ValueKey<String>('authentication-brand-tagline');

const _brand = BrandConfig(
  appName: 'Example',
  tagline: 'Example assistant',
  licenseAppName: 'Example',
  callkitAppName: 'Example',
);

/// The server's config, as the provider has it once fetched: a locked page
/// is reached by redirect, with nothing handed over.
final class _ServerConfigFrom extends BackendConfigNotifier {
  _ServerConfigFrom(this._config);

  final BackendConfig? _config;

  @override
  Future<BackendConfig?> build() async => _config;
}

void main() {
  setUp(() => debugIsWebViewSupportedOverride = true);
  tearDown(() => debugIsWebViewSupportedOverride = null);

  AdaptiveAuthHarness locked({
    DeploymentPolicy policy = const DeploymentPolicy.locked(_lockedServer),
    BackendConfig? serverConfig,
  }) => AdaptiveAuthHarness(
    server: _server,
    backendConfig: null,
    extraOverrides: [
      deploymentPolicyProvider.overrideWithValue(policy),
      brandConfigProvider.overrideWithValue(_brand),
      backendConfigProvider.overrideWith(() => _ServerConfigFrom(serverConfig)),
    ],
  );

  List<String> methodLabels(WidgetTester tester) => tester
      .widget<AdaptiveSegmentedControl>(find.byType(AdaptiveSegmentedControl))
      .labels;

  testWidgets('offers no way back to server setup and shows the tagline', (
    tester,
  ) async {
    final harness = locked(
      serverConfig: const BackendConfig(
        oauthProviders: OAuthProviders(google: 'Google'),
      ),
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      harness.build(initialLocation: Routes.authentication),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(_backButton), findsNothing);
    expect(find.byKey(_tagline), findsOneWidget);
    expect(find.text('Example assistant'), findsOneWidget);
    expect(find.text('https://chat.example.test'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('offers only the methods the deployment allows', (tester) async {
    final harness = locked(
      policy: const DeploymentPolicy.locked(
        _lockedServer,
        authModes: {DeploymentSignInMode.credentials, DeploymentSignInMode.sso},
      ),
      serverConfig: const BackendConfig(
        enableLdap: true,
        oauthProviders: OAuthProviders(google: 'Google', github: 'GitHub'),
      ),
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      harness.build(initialLocation: Routes.authentication),
    );
    await tester.pumpAndSettle();

    check(methodLabels(tester)).deepEquals(['Password', 'SSO']);

    await harness.unmount(tester);
  });

  testWidgets('goes by the server for SSO, never assuming it', (tester) async {
    final harness = locked(serverConfig: null);
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      harness.build(initialLocation: Routes.authentication),
    );
    await tester.pumpAndSettle();

    check(methodLabels(tester)).deepEquals(['Password', 'Token']);

    await harness.unmount(tester);
  });

  testWidgets('picks SSO when it is the one provider the deployment allows', (
    tester,
  ) async {
    final harness = locked(
      policy: const DeploymentPolicy.locked(
        _lockedServer,
        authModes: {DeploymentSignInMode.credentials, DeploymentSignInMode.sso},
        ssoProviders: ['google'],
      ),
      serverConfig: const BackendConfig(
        oauthProviders: OAuthProviders(google: 'Google', github: 'GitHub'),
      ),
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      harness.build(initialLocation: Routes.authentication),
    );
    await tester.pumpAndSettle();

    check(methodLabels(tester)).deepEquals(['Password', 'SSO']);
    expect(find.byKey(const ValueKey('sso_form')), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('stock sign-in keeps its way back and the server address', (
    tester,
  ) async {
    final harness = AdaptiveAuthHarness(
      server: _server,
      backendConfig: const BackendConfig(),
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      harness.build(initialLocation: Routes.authentication),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(_backButton), findsOneWidget);
    expect(find.byKey(_tagline), findsNothing);
    expect(find.text('https://chat.example.test'), findsOneWidget);

    await harness.unmount(tester);
  });

  test('deployment filtering keeps every method for stock', () {
    check(
      filterAuthModesForDeployment(AuthMode.values, DeploymentPolicy.unlocked),
    ).deepEquals(AuthMode.values);
    check(
      filterAuthModesForDeployment(
        AuthMode.values,
        const DeploymentPolicy.locked(
          _lockedServer,
          authModes: {DeploymentSignInMode.ldap},
        ),
      ),
    ).deepEquals([AuthMode.ldap]);
  });
}
