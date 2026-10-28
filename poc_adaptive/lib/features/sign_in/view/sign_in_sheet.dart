import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/app/theme/typography.dart';

/// Opens the sign-in form in a full-screen native sheet. It cannot be dragged
/// away: only its close button, or signing in, closes it. Returns the
/// username on sign-in, or null when closed.
Future<String?> showSignInSheet(BuildContext context) =>
    AdaptiveNativeSheet.show<String>(
      context: context,
      route: 'signIn',
      decodeResult: (value) => value as String,
      fullScreen: true,
      backgroundColor: paper,
      builder: (_) => const SignInContent(),
    );

/// A red band holding the wordmark and the close button, over the username
/// and password fields and the sign-in button. Demo only: nothing is sent.
class SignInContent extends StatefulWidget {
  const SignInContent({super.key});

  @override
  State<SignInContent> createState() => _SignInContentState();
}

class _SignInContentState extends State<SignInContent> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  bool get _ready =>
      _username.text.trim().isNotEmpty && _password.text.isNotEmpty;

  void _signIn() {
    if (!_ready) return;
    AdaptiveNativeSheet.pop(context, _username.text.trim());
  }

  /// Empties the fields first: a password field leaving the screen with
  /// text in it makes iOS offer to save that password.
  void _close() {
    _username.clear();
    _password.clear();
    AdaptiveNativeSheet.pop(context);
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: red,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 16, 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // In a row the native button takes its own size,
                    // rather than the band's width.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        AdaptiveButton.sfSymbol(
                          onPressed: _close,
                          sfSymbol: const SFSymbol(
                            'xmark',
                            size: 17,
                            color: Colors.white,
                          ),
                          color: Colors.white,
                          size: AdaptiveButtonSize.large,
                          useSmoothRectangleBorder: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    Text(
                      'MERIDIAN',
                      style: barTitleStyle.copyWith(
                        color: Colors.white,
                        fontSize: 40,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  28,
                  40,
                  28,
                  24 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: ListenableBuilder(
                    listenable: Listenable.merge([_username, _password]),
                    builder: (context, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _FieldLine(
                          icon: Icons.person_outline_rounded,
                          child: AdaptiveTextField(
                            controller: _username,
                            placeholder: 'Username',
                            autocorrect: false,
                            autofillHints: const [AutofillHints.username],
                            textInputAction: TextInputAction.next,
                            onSubmitted: (_) => _passwordFocus.requestFocus(),
                          ),
                        ),
                        _FieldLine(
                          icon: Icons.lock_outline_rounded,
                          child: AdaptiveTextField(
                            controller: _password,
                            focusNode: _passwordFocus,
                            placeholder: 'Password',
                            obscureText: true,
                            autocorrect: false,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.go,
                            onSubmitted: (_) => _signIn(),
                          ),
                        ),
                        const SizedBox(height: 36),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: red,
                            disabledBackgroundColor: red.withValues(alpha: 0.3),
                            disabledForegroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: _ready ? _signIn : null,
                          icon: const Icon(Icons.login_rounded),
                          label: const Text('Sign in'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A leading icon beside a field, with room above and below.
class _FieldLine extends StatelessWidget {
  const _FieldLine({required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Icon(icon, color: muted),
        const SizedBox(width: 14),
        Expanded(child: child),
      ],
    ),
  );
}
