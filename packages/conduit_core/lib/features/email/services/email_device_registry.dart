import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'package:conduit_core/auth/api_auth_interceptor.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/network/conduit_user_agent.dart';
import 'package:conduit_core/persistence/account_scoped_preferences.dart';
import 'package:conduit_core/persistence/preferences_store.dart';
import 'package:conduit_core/services/server_tls_http_client_factory.dart';

/// Preference holding this installation's push device id, one per Open WebUI
/// account (stored under [accountScopedPreferenceKey], so removing the account
/// removes it).
const String emailPushDeviceIdPreferenceKey = 'email_push_device_id';

/// Platform names the email service accepts at registration.
enum EmailPushPlatform { android, ios }

/// This installation's push device id for [accountId], created on first use.
///
/// The email service keys registrations by (user, device id), so a stable id
/// lets a token refresh replace the previous registration instead of adding
/// one, and lets sign-out remove exactly this device.
Future<String> emailPushDeviceId(
  String accountId, {
  String Function()? generate,
}) async {
  final key = accountScopedPreferenceKey(
    emailPushDeviceIdPreferenceKey,
    accountId,
  );
  final existing = PreferencesStore.getString(key);
  if (existing != null && existing.isNotEmpty) return existing;
  final id = (generate ?? const Uuid().v4)();
  await PreferencesStore.put(key, id);
  return id;
}

/// Registers this device's push token with the server's email service.
///
/// Runs on the app's own API client (`ApiService.dio`), so the server's TLS,
/// mTLS and proxy-header settings apply and the bearer is attached only for
/// the server's own origin. Auth failures here never mark the session
/// expired: the email service is optional and answers for itself.
final class EmailDeviceRegistry {
  const EmailDeviceRegistry(this._dio);

  final Dio _dio;

  static const String registerPath = '/email/devices/register';

  static String devicePath(String deviceId) =>
      '/email/devices/${Uri.encodeComponent(deviceId)}';

  static const String _suppressAuthFailureKey =
      'suppressAuthFailureNotification';

  /// A short-lived client for [server], authorised as [bearer], for removing
  /// a registration after the app has moved to an account on another server
  /// (the app's own client then points elsewhere). Built like the app's own
  /// client: the server's TLS / mTLS settings and headers apply, the bearer
  /// goes only to its origin, and redirects are not followed. Close it when
  /// done.
  static Dio detachedClient(ServerConfig server, {required String bearer}) {
    final dio = Dio(
      BaseOptions(
        baseUrl: server.url,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (status) => status != null && status < 300,
      ),
    );
    ServerTlsHttpClientFactory.configureDio(
      dio,
      server,
      userAgent: ConduitUserAgent.value,
    );
    dio.interceptors.add(
      ApiAuthInterceptor(
        serverUrl: server.url,
        authToken: bearer,
        customHeaders: server.customHeaders,
      ),
    );
    return dio;
  }

  /// `POST /email/devices/register {device_id, platform, fcm_token}`.
  ///
  /// [bearer], when given, pins the request to that session even if the
  /// client's live token changes before it is sent.
  Future<void> register({
    required String deviceId,
    required EmailPushPlatform platform,
    required String fcmToken,
    String? bearer,
  }) async {
    await _dio.post<Object?>(
      registerPath,
      data: <String, Object?>{
        'device_id': deviceId,
        'platform': platform.name,
        'fcm_token': fcmToken,
      },
      options: Options(extra: _extra(bearer)),
    );
  }

  /// `DELETE /email/devices/{device_id}`.
  ///
  /// [bearer] is the session that registered the device. Sign-out clears the
  /// client's live token while this request may still be queued, so the
  /// departing session's token is passed explicitly (the interceptor still
  /// sends it only to the server's own origin).
  Future<void> unregister({required String deviceId, String? bearer}) async {
    await _dio.delete<Object?>(
      devicePath(deviceId),
      options: Options(extra: _extra(bearer)),
    );
  }

  static Map<String, Object?> _extra(String? bearer) => <String, Object?>{
    _suppressAuthFailureKey: true,
    if (bearer != null && bearer.isNotEmpty)
      ApiAuthInterceptor.candidateAuthTokenExtraKey: bearer,
  };
}
