import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:conduit_core/features/email/providers/email_providers.dart';
import 'package:conduit_core/features/navigation/models/sidebar_navigation_model.dart';

import '../../../shared/widgets/sidebar_layout_contract.dart';
import '../../navigation/providers/sidebar_providers.dart';
import '../../navigation/widgets/sidebar_page.dart' show selectSidebarTab;

/// Turns an [emailOpenRequestProvider] request (a tapped email notification)
/// into navigation: select the Email tab through the normal tab-selection
/// path and open the sidebar drawer.
///
/// Mounted inside the drawer shell's layout, where the drawer controller is
/// in scope. A request made before the shell exists, or before the server's
/// config has made the Email tab visible, waits until both are true.
class EmailOpenRequestListener extends ConsumerStatefulWidget {
  const EmailOpenRequestListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<EmailOpenRequestListener> createState() =>
      _EmailOpenRequestListenerState();
}

class _EmailOpenRequestListenerState
    extends ConsumerState<EmailOpenRequestListener> {
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<bool>(emailOpenRequestProvider, (_, requested) {
      if (requested) _schedule();
    }, fireImmediately: true);
    ref.listenManual<SidebarNavigationSnapshot>(
      sidebarNavigationSnapshotProvider,
      (_, navigation) {
        if (navigation.isVisible(SidebarTabId.email) &&
            ref.read(emailOpenRequestProvider)) {
          _schedule();
        }
      },
    );
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _openEmail();
    });
  }

  void _openEmail() {
    if (!ref.read(emailOpenRequestProvider)) return;
    final navigation = ref.read(sidebarNavigationSnapshotProvider);
    final index = navigation.tabs.indexOf(SidebarTabId.email);
    if (index < 0) return;
    selectSidebarTab(context, ref, index);
    final drawer = SidebarDrawerControllerScope.maybeOf(context);
    if (drawer != null && !drawer.isOpen) drawer.open();
    ref.read(emailOpenRequestProvider.notifier).consume();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
