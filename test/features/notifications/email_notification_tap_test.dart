import 'dart:convert';

import 'package:conduit/features/notifications/services/local_notification_service.dart';
import 'package:conduit_core/features/notifications/models/app_notification.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationTap email variant', () {
    test('round-trips a message id', () {
      final tap = NotificationTap.tryDecode(NotificationTap.encodeEmail('m-1'));
      expect(tap, isNotNull);
      expect(tap!.kind, isNull);
      expect(tap.sourceId, 'm-1');
    });

    test('without a message it still opens Email', () {
      final tap = NotificationTap.tryDecode(NotificationTap.encodeEmail(null));
      expect(tap, isNotNull);
      expect(tap!.kind, isNull);
      expect(tap.sourceId, isEmpty);
    });

    test('core kinds decode as before', () {
      final tap = NotificationTap.tryDecode(
        jsonEncode({'kind': 'chatCompletion', 'sourceId': 'chat-1'}),
      );
      expect(tap!.kind, NotificationKind.chatCompletion);
      expect(tap.sourceId, 'chat-1');
      expect(
        NotificationTap.tryDecode(
          jsonEncode({'kind': 'unknown', 'sourceId': 'x'}),
        ),
        isNull,
      );
      expect(
        NotificationTap.tryDecode(
          jsonEncode({'kind': 'chatCompletion', 'sourceId': ''}),
        ),
        isNull,
      );
    });
  });
}
