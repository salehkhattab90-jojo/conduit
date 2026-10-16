import 'dart:async';

import 'package:riverpod/riverpod.dart';

import 'package:conduit_core/features/email/providers/email_providers.dart';

import '../../shared/services/navigation_service.dart';

/// Opens the Email section for a tapped notification: return to the chat
/// shell (which hosts the sidebar), then let the shell select the Email tab
/// and open the drawer. [messageId], when present, is opened once the web app
/// has loaded.
void openEmailFromNotification(Ref ref, String? messageId) {
  requestEmailOpen(ref, messageId);
  unawaited(NavigationService.navigateToChat());
}
