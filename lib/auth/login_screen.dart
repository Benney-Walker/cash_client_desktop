import 'package:flutter/material.dart';

import '../common/gradient_backdrop.dart';
import '../common/gradient_button.dart';
import '../settings/app_info.dart';
import '../theme/app_gradients.dart';
import '../theme/app_status_colors.dart';
import 'sign_in_panel.dart';

/// Tries to sign in. Returns null on success, or a message to show the user.
typedef SignInHandler = Future<String?> Function(
  String staffId,
  String password,
);

/// Opens password reset for [staffId] (possibly empty). Returns null when it
/// opened, or a message to show the user.
typedef ForgotPasswordHandler = Future<String?> Function(String staffId);

/// The sign-in screen (option A1, light): the gradient panel with the shield
/// on the left, the form on the right, and the version line in the
/// bottom-right corner.
///
/// It only collects the staff ID and password and reports the outcome;
/// talking to the backend is up to [onSignIn].
///
/// "Forgot password?" sits under the password field (option R1, owner
/// decision 24 November 2026) and opens the backend's password reset page
/// in the browser; new staff set their first password there too.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.appInfo,
    required this.onSignIn,
    this.onForgotPassword,
    this.notice,
  });

  final AppInfo appInfo;
  final SignInHandler onSignIn;

  /// Shows the "Forgot password?" link when set.
  final ForgotPasswordHandler? onForgotPassword;

  /// Shown above the form until the next sign-in attempt, for example to
  /// explain that the session ended.
  final String? notice;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _staffId = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _busy = false;
  String? _error;
  late bool _showNotice = widget.notice != null;

  @override
  void dispose() {
    _staffId.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _forgotPassword() async {
    final open = widget.onForgotPassword;
    if (open == null || _busy) return;
    final error = await open(_staffId.text.trim());
    if (!mounted) return;
    setState(() {
      _error = error;
      if (error != null) _showNotice = false;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
      _showNotice = false;
    });
    String? error;
    try {
      // Staff IDs are trimmed; passwords are sent exactly as typed.
      error = await widget.onSignIn(_staffId.text.trim(), _password.text);
    } catch (_) {
      error = "Couldn't sign in. Check your connection and try again.";
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final panelWidth = (constraints.maxWidth * 0.44).clamp(440.0, 640.0);
          return Stack(
            children: [
              const Positioned.fill(child: PageGlows()),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: panelWidth,
                child: const SignInPanel(),
              ),
              Positioned(
                left: panelWidth,
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 48,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: _buildForm(context),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 24,
                bottom: 16,
                child: _Footer(appInfo: widget.appInfo),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final onButton = AppGradients.of(context).onButton;
    final error = _error;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Welcome back',
            style:
                textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Sign in with your staff ID and password.',
            style:
                textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          if (_showNotice && widget.notice != null) ...[
            _NoticeBanner(message: widget.notice!),
            const SizedBox(height: 16),
          ],
          if (error != null) ...[
            _ErrorBanner(message: error),
            const SizedBox(height: 16),
          ],
          TextFormField(
            key: const Key('login.staffId'),
            controller: _staffId,
            autofocus: true,
            enabled: !_busy,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username],
            decoration: const InputDecoration(labelText: 'Staff ID'),
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'Enter your staff ID'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('login.password'),
            controller: _password,
            obscureText: _obscurePassword,
            enabled: !_busy,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onFieldSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                key: const Key('login.togglePassword'),
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (value) =>
                (value == null || value.isEmpty) ? 'Enter your password' : null,
          ),
          if (widget.onForgotPassword != null)
            Align(
              alignment: Alignment.centerRight,
              child: Tooltip(
                message: 'Opens the password reset page in your browser',
                child: TextButton.icon(
                  key: const Key('login.forgotPassword'),
                  onPressed: _busy ? null : _forgotPassword,
                  // Text first, then the "opens elsewhere" mark.
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Forgot password?'),
                ),
              ),
            )
          else
            const SizedBox(height: 8),
          const SizedBox(height: 16),
          GradientButton(
            key: const Key('login.signIn'),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: onButton,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text('Signing in…'),
                    ],
                  )
                : const Text('Sign in'),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Announced by screen readers as soon as it appears.
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('login.error'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A neutral message, such as "your session has ended". Not an error, so it
/// uses the neutral status colours, with an icon as well as text.
class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);

    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('login.notice'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: status.neutralContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 20, color: status.neutral),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: status.neutral),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.appInfo});

  final AppInfo appInfo;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Version ${appInfo.versionLabel} · Powered by Bynex Labs',
      key: const Key('login.footer'),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}
