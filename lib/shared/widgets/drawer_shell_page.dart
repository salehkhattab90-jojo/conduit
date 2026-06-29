import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/email_open_request.dart';
import '../../features/chat/providers/chat_providers.dart';
import '../../features/navigation/providers/sidebar_providers.dart';
import '../../features/navigation/widgets/sidebar_page.dart';
import '../../shared/theme/theme_extensions.dart';
import 'responsive_drawer_layout.dart';

/// Shell widget that wraps child routes with a persistent
/// [ResponsiveDrawerLayout] + [SidebarPage] drawer.
///
/// Used inside a [ShellRoute] so the drawer survives navigation
/// between chat, channel, and note-editor pages on tablets.
///
/// This shell intentionally does not own an `AdaptiveRouteShell` because the
/// child routes still need route-specific app bars, native tab bars, and
/// fullscreen overlays.
class DrawerShellPage extends ConsumerWidget {
  final Widget child;

  const DrawerShellPage({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.shortestSide >= 600;
    final scrim = Platform.isIOS
        ? context.colorTokens.scrimMedium
        : context.colorTokens.scrimStrong;

    // A tapped email notification asks to open the Email section. The handler
    // can't reach the drawer from a non-widget context, so it requests here and
    // we switch to the Email tab + open the drawer once the shell is mounted
    // (covers foreground, background, and cold-start taps), then consume it.
    if (ref.watch(emailOpenRequestProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ref.read(sidebarActiveTabProvider.notifier).set(kEmailSidebarTabIndex);
        rootDrawerLayoutKey.currentState?.open();
        ref.read(emailOpenRequestProvider.notifier).consume();
      });
    }

    return ResponsiveDrawerLayout(
      key: rootDrawerLayoutKey,
      maxFraction: isTablet ? 0.42 : 1.0,
      edgeFraction: isTablet ? 0.36 : 0.50,
      settleFraction: 0.06,
      scrimColor: scrim,
      pushContent: true,
      contentScaleDelta: 0.0,
      mobileBottomDragGestureExclusion: isTablet
          ? 0.0
          : sidebarBottomBarGestureExclusionHeight(context),
      tabletDrawerWidth: 320.0,
      onOpenStart: () {
        // Suppress composer auto-focus when drawer opens on mobile
        try {
          ref.read(composerAutofocusEnabledProvider.notifier).set(false);
        } catch (_) {}
      },
      drawer: const SidebarPage(),
      child: child,
    );
  }
}
