import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Visible sidebar index of the Email tab (`_SidebarTabId.email`).
const int kEmailSidebarTabIndex = 1;

/// Set when a tapped email notification asks to open the Email section.
///
/// The notification handler runs in a non-widget context and can't reach the
/// drawer, so it `request()`s here; [DrawerShellPage] watches this and — once
/// the shell is mounted — switches to the Email tab and opens the drawer
/// (covering foreground, background, and cold-start taps), then `consume()`s.
class EmailOpenRequest extends Notifier<bool> {
  @override
  bool build() => false;

  void request() => state = true;
  void consume() => state = false;
}

final emailOpenRequestProvider = NotifierProvider<EmailOpenRequest, bool>(
  EmailOpenRequest.new,
);

/// The `email_message` id a tapped notification wants opened, held until the
/// EmailTab webview opens it. Separate from [emailOpenRequestProvider] (which
/// just opens the section) so the drawer-shell and EmailTab consumers don't
/// race. Non-autoDispose, so the id survives until EmailTab mounts + loads.
class PendingEmailMessage extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? id) => state = (id != null && id.isNotEmpty) ? id : null;
  void clear() => state = null;
}

final pendingEmailMessageProvider =
    NotifierProvider<PendingEmailMessage, String?>(PendingEmailMessage.new);
