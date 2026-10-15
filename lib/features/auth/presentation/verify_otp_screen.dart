import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../kit/kit.dart';
import '../application/auth_controller.dart';
import '../domain/auth_session.dart';
import 'auth_scaffold.dart';
import 'otp_input.dart';

enum _Status { pending, verifying, success, failed }

/// Seconds before another code can be requested.
const _resendCooldown = 30;

/// Six-digit code entry. On success it shows a short confirmation, then
/// signs in; the router takes it from there (onboarding or Home).
class VerifyOtpScreen extends ConsumerStatefulWidget {
  const VerifyOtpScreen({super.key, required this.email});

  final String email;

  @override
  ConsumerState<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends ConsumerState<VerifyOtpScreen> {
  final _code = TextEditingController();
  _Status _status = _Status.pending;
  String? _failure;
  bool _resending = false;
  int _cooldown = _resendCooldown;
  Timer? _ticker;
  Timer? _signInDelay;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _signInDelay?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _ticker?.cancel();
    setState(() => _cooldown = _resendCooldown);
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) timer.cancel();
    });
  }

  Future<void> _verify() async {
    if (_status == _Status.verifying || !isWellFormedOtp(_code.text)) return;
    FocusScope.of(context).unfocus();
    setState(() => _status = _Status.verifying);
    final auth = ref.read(authControllerProvider.notifier);
    try {
      final session = await auth.verifyCode(widget.email, _code.text);
      if (!mounted) return;
      _ticker?.cancel();
      setState(() => _status = _Status.success);
      _signInDelay = Timer(context.reduceMotion ? const Duration(milliseconds: 400) : const Duration(seconds: 1), () {
        auth.signIn(session);
      });
    } on AuthFailure catch (e) {
      if (mounted) _fail(e.message);
    } catch (_) {
      if (mounted) _fail('An unexpected error occurred during verification.');
    }
  }

  void _fail(String message) => setState(() {
        _status = _Status.failed;
        _failure = message;
      });

  void _retry() {
    _code.clear();
    setState(() {
      _status = _Status.pending;
      _failure = null;
    });
  }

  Future<void> _resend() async {
    if (_resending || _cooldown > 0) return;
    setState(() => _resending = true);
    try {
      await ref.read(authControllerProvider.notifier).requestCode(widget.email);
      if (!mounted) return;
      _code.clear();
      _startCooldown();
      FinnToast.success(context, 'New code sent!', subtitle: 'Check your inbox.');
    } on AuthFailure catch (e) {
      if (mounted) FinnToast.error(context, e.message);
    } catch (_) {
      if (mounted) FinnToast.error(context, 'Failed to resend the code.', subtitle: 'Please try again.');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _changeEmail() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.loginWithEmail(widget.email));
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _status == _Status.verifying;
    return AuthScaffold(
      onBack: _status == _Status.success ? null : _changeEmail,
      footer: switch (_status) {
        _Status.pending || _Status.verifying => ListenableBuilder(
            listenable: _code,
            builder: (context, _) => LedgerButton(
              key: const ValueKey('verify-code'),
              label: 'Verify code',
              expand: true,
              loading: busy,
              onPressed: busy || !isWellFormedOtp(_code.text) ? null : _verify,
            ),
          ),
        _Status.success => null,
        _Status.failed => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LedgerButton(
                label: 'Try again',
                expand: true,
                onPressed: _retry,
              ),
              const SizedBox(height: Sp.sm),
              LedgerButton(
                label: 'Use a different email',
                variant: LedgerButtonVariant.quiet,
                expand: true,
                onPressed: _changeEmail,
              ),
            ],
          ),
      },
      child: AnimatedSwitcher(
        duration: context.motion.normal,
        child: switch (_status) {
          _Status.pending || _Status.verifying => _codeForm(context, busy),
          _Status.success => const _Outcome(
              key: ValueKey('success'),
              success: true,
              title: 'You\'re signed in',
              message: 'Verification complete. Taking you to FiNN…',
            ),
          _Status.failed => _Outcome(
              key: const ValueKey('failed'),
              success: false,
              title: 'Verification failed',
              message: '${_failure ?? 'The code was invalid or has expired.'} Check the code or request a new one.',
            ),
        },
      ),
    );
  }

  Widget _codeForm(BuildContext context, bool busy) {
    final c = context.ink;
    final t = context.type;
    final hint = ref.watch(authServiceProvider).demoHint;
    return Column(
      key: const ValueKey('form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthHeader(
          title: 'Enter verification code',
          body: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'We sent a 6-digit code to '),
                TextSpan(text: widget.email, style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: Sp.xl),
        OtpInput(controller: _code, enabled: !busy, onCompleted: (_) => _verify()),
        const SizedBox(height: Sp.lg),
        Center(
          child: _cooldown > 0
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: Sp.md),
                  child: Text('Resend code in 0:${_cooldown.toString().padLeft(2, '0')}', style: t.small),
                )
              : TextButton(
                  onPressed: busy || _resending ? null : _resend,
                  style: TextButton.styleFrom(foregroundColor: c.ink, textStyle: t.button, minimumSize: const Size(44, 44)),
                  child: Text(_resending ? 'Sending…' : 'Resend code'),
                ),
        ),
        if (hint != null) ...[
          const SizedBox(height: Sp.lg),
          LedgerNote(icon: LucideIcons.flaskConical, text: hint),
        ],
      ],
    );
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome({super.key, required this.success, required this.title, required this.message});

  final bool success;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: Sp.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(success ? LucideIcons.circleCheck : LucideIcons.triangleAlert, size: 28, color: success ? c.green : c.red),
            const SizedBox(height: Sp.lg),
            Semantics(header: true, child: Text(title, style: t.title)),
            const SizedBox(height: Sp.sm),
            Text(message, style: t.body.copyWith(color: c.inkSoft)),
          ],
        ),
      ),
    );
  }
}
