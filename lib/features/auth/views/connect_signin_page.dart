import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';

/// Entry point for the legacy `/login` route.
///
/// The locked-server build has no in-app server picker, so this page exists
/// only as a redirect into the authentication flow. Callers that previously
/// reached this route will now land directly on sign-in for the configured
/// OpenWebUI server.
class ConnectAndSignInPage extends ConsumerStatefulWidget {
  const ConnectAndSignInPage({super.key});

  @override
  ConsumerState<ConnectAndSignInPage> createState() =>
      _ConnectAndSignInPageState();
}

class _ConnectAndSignInPageState extends ConsumerState<ConnectAndSignInPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(Routes.authentication);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
