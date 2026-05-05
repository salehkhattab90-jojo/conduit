import 'dart:io' show Platform;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/locked_server.dart';
import '../../../core/models/backend_config.dart';
import '../../../core/models/server_config.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/input_validation_service.dart';
import '../../../core/services/navigation_service.dart';
import '../../../core/widgets/error_boundary.dart';
import '../../../shared/services/brand_service.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/adaptive_route_shell.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../core/auth/auth_state_manager.dart';
import '../../../core/utils/debug_logger.dart';
import 'package:conduit/l10n/app_localizations.dart';
import '../providers/unified_auth_providers.dart';
import '../../../core/auth/webview_cookie_helper.dart' show isWebViewSupported;

/// Authentication mode options.
///
/// This build only supports the credentials form plus a Google SSO button —
/// LDAP, raw JWT token entry, and other OAuth providers have been removed.
enum AuthMode {
  credentials, // Email/password
}

class AuthenticationPage extends ConsumerStatefulWidget {
  final ServerConfig? serverConfig;
  final BackendConfig? backendConfig;

  const AuthenticationPage({super.key, this.serverConfig, this.backendConfig});

  @override
  ConsumerState<AuthenticationPage> createState() => _AuthenticationPageState();
}

class _AuthenticationPageState extends ConsumerState<AuthenticationPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  String? _loginError;
  bool _isSigningIn = false;
  bool _serverConfigSaved = false;

  /// Resolves the backend config, falling back to the cached/refreshing
  /// provider when the page wasn't given one explicitly. The locked-server
  /// build skips the connection page that used to populate
  /// [AuthenticationPage.backendConfig], so we read it here.
  BackendConfig? get _resolvedBackendConfig =>
      widget.backendConfig ?? ref.watch(backendConfigProvider).asData?.value;

  /// Whether the Google OAuth provider is configured on the server. The other
  /// providers are intentionally ignored — this build only surfaces Google.
  bool get _hasGoogleSso =>
      _resolvedBackendConfig?.oauthProviders.google != null &&
      isWebViewSupported;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    // Check for auth errors (e.g., forced logout due to API key)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthStateError();
    });
  }

  void _checkAuthStateError() {
    final authState = ref.read(authStateManagerProvider).asData?.value;
    if (authState?.error != null && authState!.error!.isNotEmpty) {
      setState(() {
        _loginError = _formatLoginError(authState.error!);
      });
    }
  }

  Future<void> _loadSavedCredentials() async {
    final storage = ref.read(optimizedStorageServiceProvider);
    final savedCredentials = await storage.getSavedCredentials();
    if (savedCredentials != null) {
      setState(() {
        _usernameController.text = savedCredentials['username'] ?? '';
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_isSigningIn) return;

    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSigningIn = true;
      _loginError = null;
    });

    try {
      // Save server config on first sign-in attempt if it's a new config
      // This persists the server so user can retry with different credentials
      if (widget.serverConfig != null && !_serverConfigSaved) {
        await _saveServerConfig(widget.serverConfig!);
        _serverConfigSaved = true;
      }

      final actions = ref.read(authActionsProvider);
      final success = await actions.login(
        _usernameController.text.trim(),
        _passwordController.text,
        rememberCredentials: true,
      );

      if (!success) {
        final authState = ref.read(authStateManagerProvider);
        throw Exception(authState.error ?? l10n.loginFailed);
      }

      // Success - navigation will be handled by auth state change
    } catch (e) {
      // Don't clear server config on auth failure - user should be able to retry
      // The server config is valid (passed OpenWebUI verification), only the
      // credentials were wrong or there was a network issue
      setState(() {
        _loginError = _formatLoginError(e.toString());
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSigningIn = false;
        });
      }
    }
  }

  Future<void> _saveServerConfig(ServerConfig config) async {
    final storage = ref.read(optimizedStorageServiceProvider);
    await storage.saveServerConfigs([config]);
    await storage.setActiveServerId(config.id);
    ref.invalidate(serverConfigsProvider);
    ref.invalidate(activeServerProvider);
    ref.invalidate(apiServiceProvider);

    await ref.read(activeServerProvider.future);
    await _waitForApiService(config.id);
  }

  Future<void> _waitForApiService(String serverId) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(deadline)) {
      final api = ref.read(apiServiceProvider);
      if (api?.serverConfig.id == serverId) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  String _formatLoginError(String error) {
    final l10n = AppLocalizations.of(context)!;
    if (error.contains('apiKeyNotSupported')) {
      return l10n.apiKeyNotSupported;
    } else if (error.contains('apiKeyNoLongerSupported')) {
      return l10n.apiKeyNoLongerSupported;
    } else if (error.contains('LDAP authentication is not enabled')) {
      return l10n.ldapNotEnabled;
    } else if (error.contains('401') || error.contains('Unauthorized')) {
      return l10n.invalidCredentials;
    } else if (error.contains('redirect')) {
      return l10n.serverRedirectingHttps;
    } else if (error.contains('SocketException')) {
      return l10n.unableToConnectServer;
    } else if (error.contains('timeout')) {
      return l10n.requestTimedOut;
    }
    return l10n.genericSignInFailed;
  }

  @override
  Widget build(BuildContext context) {
    // Listen for auth state changes to run post-login side effects.
    ref.listen<AsyncValue<AuthState>>(authStateManagerProvider, (
      previous,
      next,
    ) {
      final nextState = next.asData?.value;
      final prevState = previous?.asData?.value;
      if (mounted &&
          nextState?.isAuthenticated == true &&
          prevState?.isAuthenticated != true) {
        DebugLogger.auth(
          'Authentication successful, initializing background resources',
        );

        // Model selection will be handled by the chat page
        // to avoid widget disposal issues

        // Navigation is handled automatically by the router when auth state
        // changes to authenticated. Calling context.go() here can race with
        // the redirect and duplicate the shell navigator during auth recovery.
      }
    });

    final safePadding = MediaQuery.of(context).padding;

    return ErrorBoundary(
      child: AdaptiveRouteShell(
        backgroundColor: context.conduitTheme.surfaceBackground,
        body: Column(
          children: [
            // Main scrollable content
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: Spacing.pagePadding,
                        right: Spacing.pagePadding,
                        top: safePadding.top + Spacing.md,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: Spacing.xl),

                            // Brand icon + title header
                            _buildHeader(),

                            const SizedBox(height: Spacing.xxl),

                            // Authentication form
                            _buildAuthForm(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Bottom action button
            Padding(
              padding: EdgeInsets.fromLTRB(
                Spacing.pagePadding,
                Spacing.md,
                Spacing.pagePadding,
                safePadding.bottom + Spacing.md,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: _buildSignInButton(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final theme = context.conduitTheme;

    return Column(
      children: [
        // Brand icon with subtle glow
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.buttonPrimary.withValues(alpha: 0.12),
                theme.buttonPrimary.withValues(alpha: 0.04),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.buttonPrimary.withValues(alpha: 0.15),
              width: BorderWidth.standard,
            ),
          ),
          child: Center(
            child: BrandService.createBrandIcon(
              size: 36,
              useGradient: true,
              context: context,
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),

        // Title
        Text(
          AppLocalizations.of(context)!.signIn,
          textAlign: TextAlign.center,
          style: theme.headingLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: AppTypography.letterSpacingTight,
          ),
        ),
        const SizedBox(height: Spacing.sm),

        // Brand tagline subtitle (replaces the raw server URL).
        _buildBrandTagline(),
      ],
    );
  }

  Widget _buildBrandTagline() {
    return Text(
      kBrandTagline,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
      style: context.conduitTheme.bodySmall?.copyWith(
        color: context.conduitTheme.textSecondary,
      ),
    );
  }

  Widget _buildAuthForm() {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCredentialsForm(),
        if (_hasGoogleSso) ...[
          const SizedBox(height: Spacing.lg),
          _buildDividerWithText(l10n.or),
          const SizedBox(height: Spacing.lg),
          _buildGoogleButton(l10n),
        ],
        if (_loginError != null) ...[
          const SizedBox(height: Spacing.md),
          _buildErrorMessage(_loginError!),
        ],
      ],
    );
  }

  Widget _buildDividerWithText(String text) {
    return Row(
      children: [
        Expanded(
          child: Divider(
            color: context.conduitTheme.dividerColor.withValues(alpha: 0.5),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          child: Text(
            text,
            style: context.conduitTheme.bodySmall?.copyWith(
              color: context.conduitTheme.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Divider(
            color: context.conduitTheme.dividerColor.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildGoogleButton(AppLocalizations l10n) {
    final displayName = _resolvedBackendConfig?.oauthProviders.google ?? 'Google';
    return ConduitButton(
      text: l10n.continueWithProvider(displayName),
      icon: Icons.g_mobiledata,
      onPressed: _navigateToSso,
      isSecondary: true,
      isFullWidth: true,
    );
  }

  Widget _buildCredentialsForm() {
    return AutofillGroup(
      child: Column(
        key: const ValueKey('credentials_form'),
        children: [
          AdaptiveTextFormField(
            controller: _usernameController,
            placeholder: AppLocalizations.of(context)!.usernameOrEmailHint,
            validator: (value) {
              final v = value ?? _usernameController.text;
              return InputValidationService.combine([
                InputValidationService.validateRequired,
                (val) => InputValidationService.validateEmailOrUsername(val),
              ])(v);
            },
            keyboardType: TextInputType.emailAddress,
            prefixIcon: Icon(
              Platform.isIOS ? CupertinoIcons.person : Icons.person_outline,
              color: context.conduitTheme.iconSecondary,
            ),
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            cupertinoDecoration: BoxDecoration(
              color: CupertinoColors.tertiarySystemBackground,
              border: Border.all(color: context.conduitTheme.inputBorder),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          AdaptiveTextFormField(
            controller: _passwordController,
            placeholder: AppLocalizations.of(context)!.passwordHint,
            validator: (value) {
              final v = value ?? _passwordController.text;
              return InputValidationService.combine([
                InputValidationService.validateRequired,
                (val) => InputValidationService.validateMinLength(
                  val,
                  1,
                  fieldName: AppLocalizations.of(context)!.password,
                ),
              ])(v);
            },
            obscureText: _obscurePassword,
            prefixIcon: Icon(
              Platform.isIOS ? CupertinoIcons.lock : Icons.lock_outline,
              color: context.conduitTheme.iconSecondary,
            ),
            suffixIcon: ConduitIconButton(
              icon: _obscurePassword
                  ? (Platform.isIOS
                        ? CupertinoIcons.eye_slash
                        : Icons.visibility_off)
                  : (Platform.isIOS ? CupertinoIcons.eye : Icons.visibility),
              iconColor: context.conduitTheme.iconSecondary,
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              tooltip: _obscurePassword ? 'Show password' : 'Hide password',
              isCompact: true,
            ),
            onSubmitted: (_) => _signIn(),
            autofillHints: const [AutofillHints.password],
            cupertinoDecoration: BoxDecoration(
              color: CupertinoColors.tertiarySystemBackground,
              border: Border.all(color: context.conduitTheme.inputBorder),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToSso() async {
    if (!mounted) return;

    // Save server config first if needed
    if (widget.serverConfig != null && !_serverConfigSaved) {
      await _saveServerConfig(widget.serverConfig!);
      _serverConfigSaved = true;
      if (!mounted) return;
    }

    context.pushNamed(RouteNames.ssoAuth, extra: widget.serverConfig);
  }

  Widget _buildSignInButton() {
    final l10n = AppLocalizations.of(context)!;
    return ConduitButton(
      text: _isSigningIn ? l10n.signingIn : l10n.signIn,
      icon: _isSigningIn
          ? null
          : (Platform.isIOS ? CupertinoIcons.arrow_right : Icons.arrow_forward),
      onPressed: _isSigningIn ? null : _signIn,
      isLoading: _isSigningIn,
      isFullWidth: true,
    );
  }

  Widget _buildErrorMessage(String message) {
    return Semantics(
      liveRegion: true,
      label: message,
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: context.conduitTheme.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppBorderRadius.small),
          border: Border.all(
            color: context.conduitTheme.error.withValues(alpha: 0.2),
            width: BorderWidth.standard,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Platform.isIOS
                  ? CupertinoIcons.exclamationmark_circle
                  : Icons.error_outline,
              color: context.conduitTheme.error,
              size: IconSize.small,
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                message,
                style: context.conduitTheme.bodySmall?.copyWith(
                  color: context.conduitTheme.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
