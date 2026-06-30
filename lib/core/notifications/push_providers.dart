import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'push_messaging_service.dart';

/// The FCM email-notification service. Kept alive via the app-startup flow that
/// reads it; inert until Firebase is configured.
final pushMessagingServiceProvider = Provider<PushMessagingService>(
  (ref) => PushMessagingService(ref),
);
