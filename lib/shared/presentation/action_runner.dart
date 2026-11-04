import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../actions/action.dart';
import '../../actions/dispatcher.dart';
import '../../app/di/action_providers.dart';
import '../../app/di/core_providers.dart';
import '../../core/result/result.dart';
import '../../kit/kit.dart';

/// Generates a fresh idempotency key per form session. Keep one per open
/// form so double-taps never execute twice; create a new one after success.
String newIdempotencyKey() => 'ui_${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(Object())}';

/// UI glue around [OperationDispatcher]:
/// 1. dispatches the action behind a blocking loader ([runWithLoader]);
/// 2. if confirmation is needed, shows the preview in a review sheet that
///    stays open, with a spinner on its approve button, until the
///    confirmed dispatch has a response;
/// 3. shows success/error feedback.
///
/// Returns the result value, or null when cancelled or rejected. Field
/// errors are returned through [onFieldErrors] so forms can show them inline.
Future<O?> runAction<I extends ActionInput, O>(
  BuildContext context,
  WidgetRef ref, {
  required FinancialAction<I, O> action,
  required I input,
  required String idempotencyKey,
  String? successTitle,
  String? successSubtitle,
  bool celebrate = false,
  String confirmLabel = 'Confirm',
  bool destructive = false,
  void Function(Map<String, String> fieldErrors)? onFieldErrors,
}) async {
  final dispatcher = ref.read(actionDispatcherProvider);
  final haptics = ref.read(settingsProvider).hapticsEnabled;
  var outcome = await runWithLoader(
    context,
    () => dispatcher.dispatch(action, input, idempotencyKey: idempotencyKey),
  );

  if (outcome is ActionNeedsConfirmation<O>) {
    if (!context.mounted) return null;
    final preview = outcome.preview;
    ActionOutcome<O>? confirmed;
    final approved = await showActionReview(
      context,
      preview,
      confirmLabel: confirmLabel,
      destructive: destructive,
      onApprove: () async {
        try {
          confirmed = await dispatcher.dispatch(
            action,
            input,
            idempotencyKey: idempotencyKey,
            confirmation: ActionConfirmation(preview.fingerprint),
          );
        } catch (e) {
          confirmed = ActionRejected(
            AppFailure(FailureCode.unknown, 'Something went wrong. Please try again.', retryable: true),
          );
        }
      },
    );
    final result = confirmed;
    if (!approved || result == null) return null;
    outcome = result;
  }
  if (!context.mounted) return null;

  switch (outcome) {
    case ActionCompleted<O>(:final value, :final preview, :final replayed):
      if (replayed) return value;
      if (haptics) HapticFeedback.mediumImpact();
      if (celebrate) {
        await showSuccessOverlay(context, title: successTitle ?? preview.summary, subtitle: successSubtitle);
      } else {
        FinnToast.success(context, successTitle ?? preview.summary, subtitle: successSubtitle);
      }
      return value;
    case ActionRejected<O>(:final failure):
      if (failure.fieldErrors.isNotEmpty && onFieldErrors != null) {
        onFieldErrors(failure.fieldErrors);
      } else if (failure.code != FailureCode.duplicate) {
        FinnToast.error(
          context,
          failure.message,
          subtitle: failure.retryable ? 'Nothing was changed. You can try again.' : null,
        );
      }
      return null;
    case ActionNeedsConfirmation<O>():
      FinnToast.warning(context, 'Details changed while you were reviewing', subtitle: 'Please check and try again.');
      return null;
  }
}

/// Review sheet for consequential operations: shows exactly what will
/// happen and asks for explicit approval. [destructive] draws the approve
/// button in red outline (like [showFinnConfirm]) for irreversible deletes.
///
/// With [onApprove] the sheet stays open after approval, with a spinner on
/// the approve button and dismissal blocked, until that work completes.
Future<bool> showActionReview(
  BuildContext context,
  ActionPreview preview, {
  String confirmLabel = 'Confirm',
  bool destructive = false,
  Future<void> Function()? onApprove,
}) async {
  final result = await showFinnSheet<bool>(
    context,
    // Drag-to-close skips PopScope; the close button and barrier respect it.
    enableDrag: onApprove == null,
    builder: (_) => _ActionReviewSheet(
      preview: preview,
      confirmLabel: confirmLabel,
      destructive: destructive,
      onApprove: onApprove,
    ),
  );
  return result ?? false;
}

class _ActionReviewSheet extends StatefulWidget {
  const _ActionReviewSheet({
    required this.preview,
    required this.confirmLabel,
    required this.destructive,
    required this.onApprove,
  });

  final ActionPreview preview;
  final String confirmLabel;
  final bool destructive;
  final Future<void> Function()? onApprove;

  @override
  State<_ActionReviewSheet> createState() => _ActionReviewSheetState();
}

class _ActionReviewSheetState extends State<_ActionReviewSheet> {
  bool _busy = false;

  Future<void> _approve() async {
    final work = widget.onApprove;
    if (_busy) return;
    if (work == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _busy = true);
    try {
      await work();
    } finally {
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.ink;
    final preview = widget.preview;
    return PopScope(
      canPop: !_busy,
      child: FinnSheetScaffold(
        title: preview.title,
        description: preview.lines.isEmpty && preview.warnings.isEmpty ? null : preview.summary,
        onClose: _busy ? () {} : null,
        footer: Row(
          children: [
            Expanded(
              child: LedgerButton(
                label: 'Cancel',
                variant: LedgerButtonVariant.secondary,
                expand: true,
                onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              ),
            ),
            const SizedBox(width: Sp.md),
            Expanded(
              flex: 2,
              child: LedgerButton(
                label: widget.confirmLabel,
                expand: true,
                variant: widget.destructive ? LedgerButtonVariant.secondary : LedgerButtonVariant.primary,
                color: widget.destructive ? c.red : null,
                loading: _busy,
                onPressed: _approve,
              ),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < preview.lines.length; i++) ...[
              if (i > 0) const LedgerDivider(),
              LedgerFact(
                inset: false,
                label: preview.lines[i].label,
                value: Text(
                  preview.lines[i].value,
                  textAlign: TextAlign.end,
                  style: preview.lines[i].emphasis ? t.figureL.copyWith(fontSize: 22) : t.body,
                ),
              ),
            ],
            for (final w in preview.warnings) ...[
              const SizedBox(height: Sp.md),
              LedgerNote(text: w, tone: NoteTone.caution, icon: LucideIcons.triangleAlert),
            ],
            if (preview.lines.isEmpty && preview.warnings.isEmpty) Text(preview.summary, style: t.body),
          ],
        ),
      ),
    );
  }
}
