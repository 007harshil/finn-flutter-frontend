import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../kit/kit.dart';
import '../application/auth_controller.dart';
import '../domain/auth_session.dart';
import 'auth_scaffold.dart';

/// Email entry: sign in or sign up with a one-time code.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  late final _email = TextEditingController(text: widget.initialEmail);
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    final email = normaliseEmail(_email.text);
    if (!isValidEmail(email)) {
      setState(() => _error = 'Invalid email address.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).requestCode(email);
      if (!mounted) return;
      FinnToast.success(context, 'Verification code sent!', subtitle: 'Check your email.');
      await context.push(AppRoutes.verifyOtp(email));
    } on AuthFailure catch (e) {
      if (mounted) FinnToast.error(context, e.message);
    } catch (_) {
      if (mounted) FinnToast.error(context, 'An unexpected error occurred.', subtitle: 'Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      footer: LedgerButton(
        key: const ValueKey('send-code'),
        label: 'Send verification code',
        expand: true,
        loading: _sending,
        onPressed: _sending ? null : _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthHeader(
            title: 'Sign in or sign up',
            body: Text('Enter your email and we\'ll send you a 6-digit code. No password needed.'),
          ),
          const SizedBox(height: Sp.xl),
          LedgerTextField(
            key: const ValueKey('login-email'),
            controller: _email,
            label: 'Email address',
            hint: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.go,
            errorText: _error,
            enabled: !_sending,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: Sp.lg),
          const AuthPrivacyNote(
            text: 'Your email is only used to sign you in. Your financial records stay on this device.',
          ),
        ],
      ),
    );
  }
}
