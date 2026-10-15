import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../kit/kit.dart';
import '../../auth/application/account_deletion.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_session.dart';
import '../../auth/presentation/otp_input.dart';

/// Asks for confirmation, then emails a code and deletes the account once
/// the code is entered. On success the app signs out and this device
/// forgets everything.
Future<void> startAccountDeletion(BuildContext context) async {
  final ok = await showFinnConfirm(
    context,
    title: 'Delete your account?',
    message:
        'This permanently deletes your FiNN account and everything in it: transactions, budgets, '
        'goals, loans, subscriptions, pending items, assets and settings. Items you shared with '
        'other people are removed from their lists too. This cannot be undone.',
    confirmLabel: 'Continue',
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  await showFinnSheet<void>(
    context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => const DeleteAccountSheet(),
  );
}

/// Code entry for account deletion. Sends the code when it opens.
class DeleteAccountSheet extends ConsumerStatefulWidget {
  const DeleteAccountSheet({super.key});

  @override
  ConsumerState<DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends ConsumerState<DeleteAccountSheet> {
  static const _resendCooldown = 60;

  final _code = TextEditingController();
  Timer? _ticker;
  int _cooldown = 0;
  bool _sending = false;
  bool _sent = false;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _code.addListener(_onCodeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _send());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _onCodeChanged() => setState(() {
    if (_code.text.length < otpLength) _error = null;
  });

  void _startCooldown() {
    _ticker?.cancel();
    setState(() => _cooldown = _resendCooldown);
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) timer.cancel();
    });
  }

  Future<void> _send() async {
    if (_sending || !mounted) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(accountDeletionProvider).sendCode();
      if (!mounted) return;
      if (_sent) FinnToast.success(context, 'New code sent!');
      setState(() => _sent = true);
      _startCooldown();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete() async {
    final code = _code.text;
    if (_deleting || !isWellFormedOtp(code)) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final messenger = context;
    try {
      await ref
          .read(accountDeletionProvider)
          .confirm(
            code,
            onDeleted: () {
              // Before signing out redirects to the login screen.
              FinnToast.success(
                messenger,
                'Account deleted',
                subtitle: 'All of your data has been erased.',
              );
              navigator.pop();
            },
          );
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final email = ref.watch(authControllerProvider)?.email ?? '';
    final hint = ref.watch(authServiceProvider).demoHint;
    final busy = _deleting;
    final error = _error;

    return FinnSheetScaffold(
      title: 'Confirm account deletion',
      onClose: busy ? () {} : null,
      footer: LedgerButton(
        key: const ValueKey('confirm-delete-account'),
        label: 'Delete account permanently',
        color: c.red,
        expand: true,
        loading: busy,
        onPressed: _sent && isWellFormedOtp(_code.text) && !busy
            ? _delete
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: _sent
                      ? 'We sent a 6-digit code to '
                      : 'Sending a 6-digit code to ',
                ),
                TextSpan(
                  text: email.isEmpty ? 'your email' : email,
                  style: TextStyle(color: c.ink, fontWeight: FontWeight.w600),
                ),
                const TextSpan(
                  text:
                      '. Enter it to delete your account and all of its data.',
                ),
              ],
            ),
            style: t.body.copyWith(color: c.inkSoft),
          ),
          const SizedBox(height: Sp.xl),
          OtpInput(
            controller: _code,
            enabled: _sent && !busy,
            hasError: error != null,
            onCompleted: (_) => _delete(),
          ),
          const SizedBox(height: Sp.md),
          Center(
            child: _cooldown > 0
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: Sp.md),
                    child: Text(
                      'Resend code in ${_cooldown ~/ 60}:${(_cooldown % 60).toString().padLeft(2, '0')}',
                      style: t.label,
                    ),
                  )
                : LedgerButton(
                    key: const ValueKey('resend-delete-code'),
                    label: _sending
                        ? 'Sending…'
                        : (_sent ? 'Resend code' : 'Send code'),
                    variant: LedgerButtonVariant.quiet,
                    onPressed: busy || _sending ? null : _send,
                  ),
          ),
          if (error != null) ...[
            const SizedBox(height: Sp.md),
            LedgerNote(
              icon: LucideIcons.circleAlert,
              tone: NoteTone.alert,
              text: error,
            ),
          ],
          const SizedBox(height: Sp.md),
          const LedgerNote(
            icon: LucideIcons.triangleAlert,
            tone: NoteTone.caution,
            text: 'This cannot be undone. You can sign up again with the same email, but you will start with an empty account.',
          ),
          if (hint != null) ...[
            const SizedBox(height: Sp.md),
            LedgerNote(text: hint),
          ],
        ],
      ),
    );
  }
}
