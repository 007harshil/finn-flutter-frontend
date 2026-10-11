import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../actions/action.dart';
import '../../actions/dispatcher.dart';
import '../../app/di/action_providers.dart';
import '../../app/di/core_providers.dart';
import '../../core/result/result.dart';
import '../../design_system/design_system.dart';

/// Generates a fresh idempotency key per form session. Keep one per open
/// form so double-taps never execute twice; create a new one after success.
String newIdempotencyKey() => 'ui_${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(Object())}';

/// UI glue around [OperationDispatcher]:
/// 1. dispatches the action;
/// 2. if confirmation is needed, shows the preview in a review sheet and
///    re-dispatches with the matching fingerprint;
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
  void Function(Map<String, String> fieldErrors)? onFieldErrors,
}) async {
  final dispatcher = ref.read(actionDispatcherProvider);
  final haptics = ref.read(settingsProvider).hapticsEnabled;
  var outcome = await dispatcher.dispatch(action, input, idempotencyKey: idempotencyKey);

  if (outcome is ActionNeedsConfirmation<O>) {
    if (!context.mounted) return null;
    final approved = await showActionReview(context, outcome.preview);
    if (!approved || !context.mounted) return null;
    outcome = await dispatcher.dispatch(
      action,
      input,
      idempotencyKey: idempotencyKey,
      confirmation: ActionConfirmation(outcome.preview.fingerprint),
    );
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
        FinnToast.error(context, failure.message,
            subtitle: failure.retryable ? 'Nothing was changed. You can try again.' : null);
      }
      return null;
    case ActionNeedsConfirmation<O>():
      FinnToast.warning(context, 'Details changed while you were reviewing', subtitle: 'Please check and try again.');
      return null;
  }
}

/// Review sheet for consequential operations: shows exactly what will
/// happen and asks for explicit approval.
Future<bool> showActionReview(BuildContext context, ActionPreview preview) async {
  final result = await showFinnSheet<bool>(
    context,
    builder: (ctx) {
      final c = ctx.colors;
      final t = ctx.text;
      return FinnSheetScaffold(
        title: preview.title,
        description: preview.summary,
        footer: Row(
          children: [
            Expanded(
              child: FinnButton(
                label: 'Cancel',
                variant: FinnButtonVariant.outline,
                expand: true,
                onPressed: () => Navigator.of(ctx).pop(false),
              ),
            ),
            const SizedBox(width: Space.x3),
            Expanded(
              flex: 2,
              child: FinnButton(
                label: 'Confirm',
                icon: Icons.check_rounded,
                expand: true,
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final line in preview.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.x2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(line.label, style: t.label)),
                    const SizedBox(width: Space.x3),
                    Flexible(
                      flex: 2,
                      child: Text(
                        line.value,
                        textAlign: TextAlign.end,
                        style: line.emphasis ? t.amountMedium : t.bodyStrong,
                      ),
                    ),
                  ],
                ),
              ),
            for (final w in preview.warnings) ...[
              const SizedBox(height: Space.x3),
              InfoBanner(message: w, tone: FinnTone.warning),
            ],
            if (preview.lines.isEmpty && preview.warnings.isEmpty)
              Text(preview.summary, style: t.body.copyWith(color: c.textSecondary)),
          ],
        ),
      );
    },
  );
  return result ?? false;
}
