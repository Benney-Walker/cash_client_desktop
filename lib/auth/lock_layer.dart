import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_exception.dart';
import '../common/gradient_button.dart';
import '../common/initials_avatar.dart';
import '../common/names.dart';
import '../theme/app_colors.dart';
import '../theme/app_gradients.dart';
import '../theme/app_theme.dart';
import 'auth_session.dart';
import 'inactivity_lock.dart';
import 'session_manager.dart';
import 'sign_in.dart';

/// Wraps the whole app (from `MaterialApp.builder`, above the navigator) to
/// watch for activity while someone is signed in and, once [lock] trips,
/// cover everything, dialogs included, with the lock card (option L1).
///
/// While locked, the app underneath can't be clicked, focused or read by
/// screen readers. Unlocking signs in again with the same staff ID, so it
/// also gets fresh tokens.
class LockLayer extends StatefulWidget {
  const LockLayer({
    super.key,
    required this.sessions,
    required this.lock,
    required this.child,
  });

  final SessionManager sessions;
  final InactivityLock lock;
  final Widget child;

  @override
  State<LockLayer> createState() => _LockLayerState();
}

class _LockLayerState extends State<LockLayer> {
  @override
  void initState() {
    super.initState();
    widget.sessions.addListener(_onSessionChanged);
    HardwareKeyboard.instance.addHandler(_onKey);
    _onSessionChanged();
  }

  @override
  void dispose() {
    widget.sessions.removeListener(_onSessionChanged);
    HardwareKeyboard.instance.removeHandler(_onKey);
    // Nothing is left to watch once the app is gone.
    widget.lock.stop();
    super.dispose();
  }

  void _onSessionChanged() {
    final signedIn = widget.sessions.session != null;
    if (signedIn && !widget.lock.running) {
      widget.lock.start();
    } else if (!signedIn && widget.lock.running) {
      widget.lock.stop();
    }
  }

  // Never consumes the key; it only notes that someone is there.
  bool _onKey(KeyEvent event) {
    widget.lock.recordActivity();
    return false;
  }

  void _onPointer(PointerEvent event) => widget.lock.recordActivity();

  Future<String?> _unlock(String password) async {
    final session = widget.sessions.session;
    if (session == null) return null;
    try {
      await widget.sessions.signIn(
        staffId: session.staffId,
        password: password,
      );
      widget.lock.unlock();
      return null;
    } on NotOfficeStaffException {
      // Their roles changed while the app was locked: they can't carry on.
      widget.sessions.signOut();
      return null;
    } on ApiException catch (e) {
      if (e.failure == ApiFailure.unauthorized) {
        return 'Wrong password. Try again.';
      }
      return signInErrorMessage(e);
    } catch (e) {
      return signInErrorMessage(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointer,
      onPointerMove: _onPointer,
      onPointerHover: _onPointer,
      onPointerSignal: _onPointer,
      child: ListenableBuilder(
        listenable: Listenable.merge([widget.sessions, widget.lock]),
        builder: (context, child) {
          final session = widget.sessions.session;
          final locked = widget.lock.locked && session != null;
          return Stack(
            children: [
              // The app stays visible but out of reach while locked.
              IgnorePointer(
                ignoring: locked,
                child: ExcludeFocus(
                  excluding: locked,
                  child: ExcludeSemantics(excluding: locked, child: child!),
                ),
              ),
              if (locked)
                Positioned.fill(
                  child: _LockScreen(
                    session: session,
                    timeout: widget.lock.timeout,
                    onUnlock: _unlock,
                    onSignOut: widget.sessions.signOut,
                  ),
                ),
            ],
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({
    required this.session,
    required this.timeout,
    required this.onUnlock,
    required this.onSignOut,
  });

  final AuthSession session;
  final Duration timeout;
  final Future<String?> Function(String password) onUnlock;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    // This sits above the navigator, so it brings its own Overlay (for the
    // text field's selection handles) and Material.
    return Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (context) => ColoredBox(
            key: const Key('lock.screen'),
            color: dark ? AppColors.darkLockScrim : AppColors.lightLockScrim,
            child: Center(
              child: Material(
                type: MaterialType.transparency,
                child: _LockCard(
                  session: session,
                  timeout: timeout,
                  onUnlock: onUnlock,
                  onSignOut: onSignOut,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LockCard extends StatefulWidget {
  const _LockCard({
    required this.session,
    required this.timeout,
    required this.onUnlock,
    required this.onSignOut,
  });

  final AuthSession session;
  final Duration timeout;
  final Future<String?> Function(String password) onUnlock;
  final VoidCallback onSignOut;

  @override
  State<_LockCard> createState() => _LockCardState();
}

class _LockCardState extends State<_LockCard> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onUnlock(_password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error != null) _password.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final scheme = theme.colorScheme;
    final gradients = AppGradients.of(context);
    final dark = theme.brightness == Brightness.dark;
    final role = widget.session.role;
    final error = _error;

    return Container(
      key: const Key('lock.card'),
      width: 380,
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkLockCard : AppColors.lightLockCard,
        border: Border.all(color: gradients.glassCardBorder),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius + 4),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: InitialsAvatar(name: widget.session.staffName, size: 56),
            ),
            const SizedBox(height: 10),
            Text(
              displayName(widget.session.staffName),
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              [if (role != null) role.label, widget.session.staffId]
                  .join(' · '),
              textAlign: TextAlign.center,
              style: textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline,
                    size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Locked after ${widget.timeout.inMinutes} minutes of '
                    'inactivity',
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (error != null) ...[
              Semantics(
                liveRegion: true,
                child: Container(
                  key: const Key('lock.error'),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline,
                          size: 18, color: scheme.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error,
                          style: textTheme.bodyMedium
                              ?.copyWith(color: scheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              key: const Key('lock.password'),
              controller: _password,
              autofocus: true,
              obscureText: _obscure,
              enabled: !_busy,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (value) => (value == null || value.isEmpty)
                  ? 'Enter your password'
                  : null,
            ),
            const SizedBox(height: 16),
            GradientButton(
              key: const Key('lock.unlock'),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: gradients.onButton,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text('Unlocking…'),
                      ],
                    )
                  : const Text('Unlock'),
            ),
            const SizedBox(height: 6),
            TextButton(
              key: const Key('lock.signOut'),
              onPressed: _busy ? null : widget.onSignOut,
              child: const Text('Not you? Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
