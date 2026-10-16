import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod/riverpod.dart';

import 'package:conduit_core/features/auth/providers/unified_auth_providers.dart';
import 'package:conduit_core/features/email/email_push_payload.dart';
import 'package:conduit_core/features/email/providers/email_providers.dart';
import 'package:conduit_core/features/email/services/email_device_registry.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/utils/debug_logger.dart';

import '../../email/email_open_navigation.dart';
import 'local_notification_service.dart';

bool _firebaseReady = false;

/// Whether Firebase came up at launch. Push stays off for the whole run when
/// it did not (no `google-services.json` / `GoogleService-Info.plist` in the
/// build, or an unsupported platform); everything else works as usual.
bool get emailPushAvailable => _firebaseReady;

/// Brings up Firebase for Email push. Called once from `main` before
/// `runApp`; never throws.
Future<void> initializeEmailPush() async {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 10));
    FirebaseMessaging.onBackgroundMessage(emailPushBackgroundHandler);
    _firebaseReady = true;
  } catch (error) {
    DebugLogger.info(
      'email-push-off',
      scope: 'push/email',
      data: {'reason': error.runtimeType.toString()},
    );
  }
}

/// Background / terminated-state messages run in their own isolate. Email
/// pushes carry a `notification` block, so the OS shows them itself; this only
/// has to bring Firebase up for the plugin.
@pragma('vm:entry-point')
Future<void> emailPushBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Nothing to show from here; the OS renders the notification.
  }
}

/// What this device registered with the email service, so it can be removed
/// with the same session even after the app has moved on.
typedef EmailPushRegistration = ({
  String accountId,
  ServerConfig server,
  String deviceId,
  String bearer,
  String fcmToken,
});

/// The single owner of Email push for the running app.
final emailPushServiceProvider = Provider<EmailPushService>((ref) {
  final service = EmailPushService(ref);
  ref.onDispose(service.dispose);
  // Without Firebase there is nothing to keep in sync.
  if (!emailPushAvailable) return service;
  ref.listen<bool>(emailFeatureEnabledProvider, (_, _) => service.resync());
  ref.listen<AuthNavigationState>(
    authNavigationStateProvider,
    service.handleAuthChange,
  );
  return service;
});

/// Email push: registers the signed-in account's device with the server's
/// email service, shows pushes that arrive in the foreground through
/// [LocalNotificationService] (it never initialises the notifications plugin
/// itself -- that service owns the plugin's single tap callback), and turns
/// notification taps into the Email open request.
///
/// Only the active Open WebUI account is registered. Leaving it (sign-out or
/// switching accounts) removes the registration with the session that made
/// it; signing out also drops this device's FCM token, so a registration the
/// server kept anyway stops delivering.
class EmailPushService {
  EmailPushService(this._ref);

  final Ref _ref;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  bool _listening = false;
  bool _permissionRequested = false;
  bool _disposed = false;
  bool _tokenUsedSinceReset = false;
  EmailPushRegistration? _registration;
  Future<void> _queue = Future<void>.value();

  @visibleForTesting
  EmailPushRegistration? get registration => _registration;

  /// Called after the post-sign-in startup work. Idempotent; a no-op when
  /// Firebase is not configured.
  Future<void> start() async {
    if (!_firebaseReady || _disposed) return;
    if (!_listening) {
      _listening = true;
      // The email service sends to FCM registration tokens (HTTP v1
      // `message.token`), not the installation ids of the newer
      // register()/onRegistered API, so the token API stays in use.
      _subscriptions
        ..add(
          // ignore: deprecated_member_use
          FirebaseMessaging.instance.onTokenRefresh.listen(
            (token) => _enqueue(() => _sync(fcmToken: token)),
          ),
        )
        ..add(FirebaseMessaging.onMessage.listen(_showForeground))
        ..add(
          FirebaseMessaging.onMessageOpenedApp.listen(
            (message) => _openFromData(message.data),
          ),
        );
      try {
        final initial = await FirebaseMessaging.instance.getInitialMessage();
        if (initial != null) _openFromData(initial.data);
      } catch (error) {
        _warn('email-push-initial-message-failed', error);
      }
    }
    await _enqueue(_sync);
  }

  /// Re-evaluates the registration (the Email feature was turned on or off).
  void resync() {
    if (!_firebaseReady || !_listening || _disposed) return;
    unawaited(_enqueue(_sync));
  }

  /// Leaving the signed-in state removes the registration right away, while
  /// the departing session is still valid on the server; settling signed out
  /// also drops the FCM token.
  void handleAuthChange(
    AuthNavigationState? previous,
    AuthNavigationState next,
  ) {
    if (!_firebaseReady || _disposed) return;
    if (next == AuthNavigationState.authenticated) return;
    unawaited(
      _enqueue(() async {
        await _unregisterCurrent();
        if (next == AuthNavigationState.needsLogin) await _dropFcmToken();
      }),
    );
  }

  Future<void> _enqueue(Future<void> Function() task) {
    final next = _queue.then((_) => task()).catchError((Object error) {
      _warn('email-push-task-failed', error);
    });
    _queue = next;
    return next;
  }

  Future<void> _sync({String? fcmToken}) async {
    if (_disposed) return;
    if (_ref.read(authNavigationStateProvider) !=
        AuthNavigationState.authenticated) {
      return;
    }
    final api = _ref.read(apiServiceProvider);
    final bearer = api?.authToken;
    if (api == null || bearer == null || bearer.isEmpty) return;
    final accountId = api.serverConfig.id;
    final enabled = _ref.read(emailFeatureEnabledProvider);

    final previous = _registration;
    if (previous != null && (previous.accountId != accountId || !enabled)) {
      await _unregisterCurrent();
    }
    if (!enabled) return;

    if (!_permissionRequested) {
      _permissionRequested = true;
      try {
        await FirebaseMessaging.instance.requestPermission();
      } catch (error) {
        _warn('email-push-permission-failed', error);
      }
    }

    final String? token;
    try {
      // ignore: deprecated_member_use
      token = fcmToken ?? await FirebaseMessaging.instance.getToken();
    } catch (error) {
      // iOS has no APNs token yet; onTokenRefresh registers once it arrives.
      _warn('email-push-token-unavailable', error);
      return;
    }
    if (token == null || token.isEmpty) return;

    final current = _registration;
    if (current != null &&
        current.accountId == accountId &&
        current.fcmToken == token &&
        current.bearer == bearer) {
      return;
    }

    final deviceId = await emailPushDeviceId(accountId);
    _tokenUsedSinceReset = true;
    await EmailDeviceRegistry(api.dio).register(
      deviceId: deviceId,
      platform: Platform.isIOS
          ? EmailPushPlatform.ios
          : EmailPushPlatform.android,
      fcmToken: token,
      bearer: bearer,
    );
    _registration = (
      accountId: accountId,
      server: api.serverConfig,
      deviceId: deviceId,
      bearer: bearer,
      fcmToken: token,
    );
  }

  Future<void> _unregisterCurrent() async {
    final registration = _registration;
    if (registration == null) return;
    _registration = null;
    final api = _ref.read(apiServiceProvider);
    try {
      if (api != null &&
          _sameServer(api.serverConfig.url, registration.server.url)) {
        await EmailDeviceRegistry(api.dio).unregister(
          deviceId: registration.deviceId,
          bearer: registration.bearer,
        );
        return;
      }
      final dio = EmailDeviceRegistry.detachedClient(
        registration.server,
        bearer: registration.bearer,
      );
      try {
        await EmailDeviceRegistry(dio)
            .unregister(deviceId: registration.deviceId);
      } finally {
        dio.close();
      }
    } catch (error) {
      _warn('email-push-unregister-failed', error);
    }
  }

  Future<void> _dropFcmToken() async {
    if (!_tokenUsedSinceReset) return;
    _tokenUsedSinceReset = false;
    try {
      // ignore: deprecated_member_use
      await FirebaseMessaging.instance.deleteToken();
    } catch (error) {
      _warn('email-push-token-delete-failed', error);
    }
  }

  void _showForeground(RemoteMessage message) {
    final payload = EmailPushPayload.fromData(message.data);
    // Only while this device is registered for the active account: a push
    // that raced a sign-out is not shown.
    if (payload == null || _registration == null) return;
    unawaited(
      _ref
          .read(localNotificationServiceProvider)
          .showEmail(
            title: message.notification?.title,
            body: message.notification?.body,
            messageId: payload.messageId,
          ),
    );
  }

  void _openFromData(Map<String, Object?> data) {
    final payload = EmailPushPayload.fromData(data);
    if (payload == null || _disposed) return;
    openEmailFromNotification(_ref, payload.messageId);
  }

  void _warn(String message, Object error) {
    DebugLogger.warning(
      message,
      scope: 'push/email',
      data: {'errorType': error.runtimeType.toString()},
    );
  }

  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }
}

bool _sameServer(String a, String b) {
  String normalize(String url) {
    final trimmed = url.trim();
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  return normalize(a) == normalize(b);
}
