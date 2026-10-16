import 'dart:convert';

import 'package:conduit_core/auth/api_auth_interceptor.dart';
import 'package:conduit_core/features/email/email_push_payload.dart';
import 'package:conduit_core/features/email/services/email_device_registry.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/persistence/account_scoped_preferences.dart';
import 'package:conduit_core/persistence/preferences_store.dart';
import 'package:conduit_core/ports/key_value_store.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// Records every request and answers 200.
final class _Recorder implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final bodies = <Object?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    bodies.add(options.data);
    return ResponseBody.fromString(
      jsonEncode({'ok': true}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('EmailDeviceRegistry', () {
    late Dio dio;
    late _Recorder recorder;

    setUp(() {
      recorder = _Recorder();
      dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com'))
        ..httpClientAdapter = recorder;
    });

    test('register posts the device to the email service', () async {
      await EmailDeviceRegistry(dio).register(
        deviceId: 'dev-1',
        platform: EmailPushPlatform.android,
        fcmToken: 'fcm-token',
        bearer: 'jwt-a',
      );

      final request = recorder.requests.single;
      expect(request.method, 'POST');
      expect(
        request.uri.toString(),
        'https://chat.example.com/email/devices/register',
      );
      expect(recorder.bodies.single, {
        'device_id': 'dev-1',
        'platform': 'android',
        'fcm_token': 'fcm-token',
      });
      expect(request.extra['suppressAuthFailureNotification'], isTrue);
      expect(
        request.extra[ApiAuthInterceptor.candidateAuthTokenExtraKey],
        'jwt-a',
      );
    });

    test('unregister deletes the device with the departing session', () async {
      await EmailDeviceRegistry(dio)
          .unregister(deviceId: 'dev/1 ?', bearer: 'jwt-a');

      final request = recorder.requests.single;
      expect(request.method, 'DELETE');
      expect(request.uri.path, '/email/devices/dev%2F1%20%3F');
      expect(request.extra['suppressAuthFailureNotification'], isTrue);
      expect(
        request.extra[ApiAuthInterceptor.candidateAuthTokenExtraKey],
        'jwt-a',
      );
    });

    test('without a bearer the client keeps its own session', () async {
      await EmailDeviceRegistry(dio).unregister(deviceId: 'dev-1');
      expect(
        recorder.requests.single.extra.containsKey(
          ApiAuthInterceptor.candidateAuthTokenExtraKey,
        ),
        isFalse,
      );
    });
  });

  group('detachedClient', () {
    test(
      'sends the bearer to its server only, and never follows redirects',
      () async {
        const server = ServerConfig(
          id: 'acct-a',
          name: 'A',
          url: 'https://a.example.com',
          customHeaders: {'X-Proxy': 'p'},
        );
        final dio = EmailDeviceRegistry.detachedClient(server, bearer: 'jwt-a');
        final recorder = _Recorder();
        dio.httpClientAdapter = recorder;
        addTearDown(dio.close);

        expect(dio.options.followRedirects, isFalse);
        expect(dio.options.baseUrl, 'https://a.example.com');

        await EmailDeviceRegistry(dio).unregister(deviceId: 'dev-1');
        await dio.getUri<Object?>(Uri.parse('https://elsewhere.example/x'));

        final own = recorder.requests[0];
        expect(own.uri.toString(), 'https://a.example.com/email/devices/dev-1');
        expect(own.headers['Authorization'], 'Bearer jwt-a');
        expect(own.headers['X-Proxy'], 'p');

        final foreign = recorder.requests[1];
        expect(foreign.headers.containsKey('Authorization'), isFalse);
        expect(foreign.headers.containsKey('X-Proxy'), isFalse);
      },
    );
  });

  group('emailPushDeviceId', () {
    setUp(() async {
      PreferencesStore.installLoader(() async => InMemoryKeyValueStore());
      await PreferencesStore.ensureInitialized();
    });

    tearDown(PreferencesStore.debugReset);

    test('is created once per account and then reused', () async {
      var counter = 0;
      String next() => 'id-${++counter}';

      final a1 = await emailPushDeviceId('acct-a', generate: next);
      final a2 = await emailPushDeviceId('acct-a', generate: next);
      final b1 = await emailPushDeviceId('acct-b', generate: next);

      expect(a1, 'id-1');
      expect(a2, 'id-1');
      expect(b1, 'id-2');
      expect(
        PreferencesStore.getString(
          accountScopedPreferenceKey(emailPushDeviceIdPreferenceKey, 'acct-a'),
        ),
        'id-1',
      );
    });

    test('defaults to a random uuid', () async {
      final id = await emailPushDeviceId('acct-a');
      expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-')));
    });
  });

  group('EmailPushPayload', () {
    test('decodes an email push', () {
      final payload = EmailPushPayload.fromData({
        'type': 'email',
        'email_message_id': ' 42 ',
        'user_email': 'a@example.com',
      });
      expect(payload, isNotNull);
      expect(payload!.messageId, '42');
    });

    test('a push without a message opens the section only', () {
      expect(
        EmailPushPayload.fromData({
          'type': 'email',
          'email_message_id': '',
          'reason': 'reconnect',
        })!.messageId,
        isNull,
      );
      expect(EmailPushPayload.fromData({'type': 'email'})!.messageId, isNull);
    });

    test('ignores other pushes', () {
      expect(EmailPushPayload.fromData({'type': 'chat'}), isNull);
      expect(EmailPushPayload.fromData(const {}), isNull);
    });

    test('the channel id is the one the server names', () {
      expect(emailNotificationChannelId, 'email_significant');
    });
  });
}
