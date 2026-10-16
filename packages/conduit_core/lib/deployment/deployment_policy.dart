import 'package:riverpod/riverpod.dart';

import 'package:conduit_core/navigation/routes.dart';
import 'package:conduit_core/providers/backend_mode_providers.dart';

/// The one Open WebUI server a locked build talks to.
///
/// [id] is the account id the server is saved under. It keys the account's
/// database file, token vault and settings, so a deployment keeps it stable
/// across releases: changing it signs every user out and leaves their local
/// data behind.
final class LockedServer {
  const LockedServer({
    required this.id,
    required this.name,
    required this.urls,
  });

  /// Account id of the seeded server (see the class comment).
  final String id;

  /// Display name of the server.
  final String name;

  /// Addresses of the server in order of preference: the first is the
  /// primary, the rest are failover routes to the same server. Never empty.
  final List<String> urls;
}

/// The ways of signing in a deployment can offer. Open WebUI decides which of
/// them it supports; a deployment can only narrow that.
enum DeploymentSignInMode { credentials, sso, ldap, token }

/// What a build of the app is allowed to do, decided at build time.
///
/// [DeploymentPolicy.unlocked] is stock Conduit: every entry point exists.
/// A locked policy pins the app to one Open WebUI server and closes the
/// entry points that would leave it -- server setup, the backend chooser,
/// account management, Hermes, Direct connections and on-device Apple
/// models, reviewer mode.
///
/// Pure data with no Flutter dependency, so the router policy, the backend
/// providers and the app's widgets all read the same answer.
final class DeploymentPolicy {
  const DeploymentPolicy({
    this.lockedServer,
    this.allowAccountManagement = true,
    this.allowedBackends = const {
      PreferredBackend.owui,
      PreferredBackend.direct,
      PreferredBackend.hermes,
    },
    this.authModes = const {
      DeploymentSignInMode.credentials,
      DeploymentSignInMode.sso,
      DeploymentSignInMode.ldap,
      DeploymentSignInMode.token,
    },
    this.ssoProviders,
    this.allowOnDeviceWebSearch = true,
  });

  /// A build locked to [server], Open WebUI only, with no account management
  /// and no on-device web search. [authModes] and [ssoProviders] narrow the
  /// sign-in methods the server offers.
  const DeploymentPolicy.locked(
    LockedServer server, {
    Set<DeploymentSignInMode> authModes = const {
      DeploymentSignInMode.credentials,
      DeploymentSignInMode.sso,
      DeploymentSignInMode.ldap,
      DeploymentSignInMode.token,
    },
    List<String>? ssoProviders,
    bool allowOnDeviceWebSearch = false,
  }) : this(
         lockedServer: server,
         allowAccountManagement: false,
         allowedBackends: const {PreferredBackend.owui},
         authModes: authModes,
         ssoProviders: ssoProviders,
         allowOnDeviceWebSearch: allowOnDeviceWebSearch,
       );

  /// Stock Conduit: nothing is locked.
  static const unlocked = DeploymentPolicy();

  /// The server this build is locked to; null for stock Conduit.
  final LockedServer? lockedServer;

  /// Whether accounts can be added, switched and removed, and a server's
  /// addresses edited.
  final bool allowAccountManagement;

  /// The backends the app may use. `{owui}` is Open WebUI only.
  final Set<PreferredBackend> allowedBackends;

  /// The sign-in methods offered, where the server supports them.
  final Set<DeploymentSignInMode> authModes;

  /// Open WebUI OAuth provider keys (`google`, `microsoft`, `github`, `oidc`,
  /// `feishu`) single sign-on may use; null allows every provider the server
  /// has. With exactly one, SSO opens that provider's login directly.
  final List<String>? ssoProviders;

  /// Whether Direct models may search the web from the device (queries go
  /// from the phone to public search engines).
  final bool allowOnDeviceWebSearch;

  /// Whether the build is pinned to [lockedServer].
  bool get isLocked => lockedServer != null;

  /// Whether [backend] may be used. [PreferredBackend.unset] is "not chosen
  /// yet", which only exists while there is more than one to choose from.
  bool allowsBackend(PreferredBackend backend) =>
      backend == PreferredBackend.unset
      ? allowedBackends.length > 1
      : allowedBackends.contains(backend);

  /// The backend the app uses when [stored] was saved: [stored] when
  /// allowed, else Open WebUI (or the only allowed backend).
  PreferredBackend effectiveBackend(PreferredBackend stored) {
    if (allowsBackend(stored)) return stored;
    if (allowedBackends.contains(PreferredBackend.owui)) {
      return PreferredBackend.owui;
    }
    return allowedBackends.isEmpty ? stored : allowedBackends.first;
  }

  /// Whether the sign-in method [mode] may be offered.
  bool allowsSignInMode(DeploymentSignInMode mode) => authModes.contains(mode);

  /// Whether single sign-on may use the OAuth provider [provider].
  bool allowsSsoProvider(String provider) =>
      ssoProviders == null || ssoProviders!.contains(provider);

  /// Where the SSO web view starts on the server: straight into the one
  /// allowed provider's login, which skips Open WebUI's own sign-in page and
  /// its second "Continue with ..." tap, else that sign-in page.
  String get ssoInitialPath {
    final providers = ssoProviders;
    if (providers != null && providers.length == 1) {
      return '/oauth/${Uri.encodeComponent(providers.single)}/login';
    }
    return '/auth';
  }

  /// Whether [location] is a page this build does not have: server setup
  /// and the backend chooser when locked, account and address management
  /// without [allowAccountManagement], Hermes and Direct settings when their
  /// backend is not allowed. The router sends such a request elsewhere.
  bool closesLocation(String location) {
    if (isLocked &&
        (location == Routes.backendChooser ||
            location == Routes.serverConnection ||
            location == Routes.addServer ||
            location == Routes.login)) {
      return true;
    }
    if (!allowAccountManagement &&
        (location == Routes.accounts ||
            location == Routes.serverAddresses ||
            location == Routes.serverAddressEditor ||
            location.startsWith('${Routes.serverAddresses}/') ||
            location.startsWith('${Routes.serverAddressEditor}/'))) {
      return true;
    }
    if (!allowsBackend(PreferredBackend.hermes) &&
        (location == Routes.hermesSettings ||
            location.startsWith('${Routes.hermesSettings}/'))) {
      return true;
    }
    if (!allowsBackend(PreferredBackend.direct) &&
        (location == Routes.directConnections ||
            location.startsWith('${Routes.directConnections}/'))) {
      return true;
    }
    return false;
  }
}

/// The deployment this build was made for. Stock Conduit unless the host
/// overrides it (`main.dart` binds the app's deployment config).
final deploymentPolicyProvider = Provider<DeploymentPolicy>(
  (ref) => DeploymentPolicy.unlocked,
);
