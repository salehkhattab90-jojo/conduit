import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../features/auth/providers/unified_auth_providers.dart';
import '../../features/navigation/providers/sidebar_providers.dart';
import '../constants/locked_server.dart';
import '../persistence/persistence_keys.dart';
import '../persistence/preferences_store.dart';
import '../providers/app_providers.dart';
import '../services/navigation_service.dart';
import '../utils/debug_logger.dart';

/// Android channel id the SERVER dictates — the push sets
/// `android.notification.channel_id = "email_significant"` (see
/// mcps/email_pipeline/email_notify.py). A backgrounded Android notification
/// renders on this channel, so the app MUST create it with this exact id.
const String kEmailNotificationChannelId = 'email_significant';

/// Visible sidebar index of the Email tab (`_SidebarTabId.email` is index 1).
const int _kEmailSidebarTabIndex = 1;

/// FCM background handler. MUST be a top-level/static function with the
/// vm:entry-point pragma — it runs in its own isolate. The server sends a
/// `notification` block, so the OS renders the tray notification itself while
/// backgrounded/terminated; this only needs Firebase initialized.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // best-effort; nothing to render here
  }
}

/// Owns all FCM + local-notification logic for the email-pipeline push.
///
/// Cleanly inert when Firebase wasn't configured (the guarded init in main
/// leaves `Firebase.apps` empty), so this ships safely without the gitignored
/// Firebase config files. Metadata-only: it never sees email bodies.
class PushMessagingService {
  PushMessagingService(this._ref);

  final Ref _ref;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  bool _started = false;
  // Last non-null bearer seen. Used to unregister at logout, which may clear the
  // live token before our listener fires — the JWT stays server-valid briefly,
  // so the snapshot still authorizes the DELETE.
  String? _lastBearer;
  String? _deviceIdCache;

  /// Idempotent. No-op if Firebase isn't configured.
  Future<void> initializeAndStart() async {
    if (_started) return;
    if (Firebase.apps.isEmpty) return;
    _started = true;

    _ref.listen<String?>(authTokenProvider3, (_, next) {
      if (next != null && next.isNotEmpty) _lastBearer = next;
    }, fireImmediately: true);

    await _initLocalNotifications();
    await _requestPermission();

    FirebaseMessaging.instance.onTokenRefresh.listen(registerToken);
    FirebaseMessaging.onMessage.listen(_renderForeground);
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _deepLink(m.data));

    // Terminated -> launched by tapping the notification.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _deepLink(initial.data);
  }

  Future<void> _initLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onLocalTap,
    );
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        kEmailNotificationChannelId,
        'Email',
        description: 'New email notifications',
        importance: Importance.high,
      );
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }
  }

  Future<void> _requestPermission() async {
    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (_) {/* user can grant later */}
    if (Platform.isAndroid) {
      try {
        await _local
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      } catch (_) {/* Android 13+ runtime permission */}
    }
  }

  String _deviceId() {
    final cached = _deviceIdCache;
    if (cached != null) return cached;
    var id = PreferencesStore.getString(PreferenceKeys.pushDeviceId);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      PreferencesStore.put(PreferenceKeys.pushDeviceId, id);
    }
    _deviceIdCache = id;
    return id;
  }

  /// Register (or refresh) this device's token with email-api. Bearer is
  /// attached automatically by ApiAuthInterceptor.
  Future<void> registerToken([String? token]) async {
    if (Firebase.apps.isEmpty) return;
    final api = _ref.read(apiServiceProvider);
    if (api == null) return;
    String? fcm = token;
    try {
      fcm ??= await FirebaseMessaging.instance.getToken();
    } catch (_) {
      // iOS: APNs token not ready yet — onTokenRefresh will register later.
      return;
    }
    if (fcm == null || fcm.isEmpty) return;
    try {
      await api.dio.post(
        '/email/devices/register',
        data: {
          'device_id': _deviceId(),
          'platform': Platform.isIOS ? 'ios' : 'android',
          'fcm_token': fcm,
        },
      );
    } on DioException catch (e) {
      DebugLogger.warning(
        'device register failed',
        scope: 'push/register',
        data: {'error': e.toString()},
      );
    }
  }

  /// Unregister at logout so a logged-out (or different) user stops receiving
  /// this user's email pushes. Best-effort.
  Future<void> unregisterToken() async {
    if (Firebase.apps.isEmpty) return;
    final deviceId = _deviceId();
    final api = _ref.read(apiServiceProvider);
    final liveToken = _ref.read(authTokenProvider3);
    try {
      if (api != null && liveToken != null && liveToken.isNotEmpty) {
        await api.dio.delete('/email/devices/$deviceId');
      } else if (_lastBearer != null) {
        // Live token already cleared by logout; DELETE with the snapshot bearer
        // via a one-off client (the JWT is still server-valid).
        final dio = Dio(BaseOptions(baseUrl: kLockedServerUrl));
        await dio.delete(
          '/email/devices/$deviceId',
          options: Options(headers: {'Authorization': 'Bearer $_lastBearer'}),
        );
      }
    } catch (_) {/* best-effort */}
  }

  void _renderForeground(RemoteMessage m) {
    // Android does not auto-show a notification-block push while foregrounded.
    final n = m.notification;
    final title =
        n?.title ?? (m.data['user_email'] as String?) ?? 'New email';
    final body = n?.body ?? '';
    final androidDetails = const AndroidNotificationDetails(
      kEmailNotificationChannelId,
      'Email',
      channelDescription: 'New email notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final id =
        (m.data['email_message_id'] as String?)?.hashCode ??
        m.messageId?.hashCode ??
        DateTime.now().millisecondsSinceEpoch.remainder(1 << 31);
    unawaited(
      _local.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        ),
        payload: jsonEncode(m.data),
      ),
    );
  }

  void _onLocalTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final data = (jsonDecode(payload) as Map).cast<String, dynamic>();
      _deepLink(data);
    } catch (_) {/* malformed payload */}
  }

  void _deepLink(Map<String, dynamic> data) {
    if (data['type'] != 'email') return;
    // Mount the chat shell (which hosts the sidebar), then switch to Email.
    // Per-message deep-link is deferred — the email webapp has no
    // "open message" handler yet (see NOTIFICATIONS.md), so we open the section.
    unawaited(NavigationService.navigateToChat());
    try {
      _ref
          .read(sidebarActiveTabProvider.notifier)
          .set(_kEmailSidebarTabIndex);
    } catch (_) {/* sidebar not ready */}
  }
}
