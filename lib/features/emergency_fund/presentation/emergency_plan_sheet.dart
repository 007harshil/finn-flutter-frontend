import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../goals/presentation/savings_widgets.dart';
import '../application/emergency_actions.dart';
import '../domain/emergency_fund.dart';

/// Set up or change the emergency fund plan: essential monthly spending,
/// months of cover and an optional custom target. No money moves.
class EmergencyPlanSheet extends ConsumerStatefulWidget {
  const EmergencyPlanSheet({super.key});

  @override
  ConsumerState<EmergencyPlanSheet> createState() => _EmergencyPlanSheetState();
}

class _EmergencyPlanSheetState extends ConsumerState<EmergencyPlanSheet> {
  static const _presetMonths = [3, 6, 9, 12];

  final _key = newIdempotencyKey();
  final _essentials = TextEditingController();
  final _override = TextEditingController();
  Money? _essentialsValue;
  Money? _overrideValue;
  int _months = 6;
  bool _custom = false;
  bool _loaded = false;
  bool _isEdit = false;
  Map<String, String> _errors = const {};
  bool _submitting = false;

  @override
  void dispose() {
    _essentials.dispose();
    _override.dispose();
    super.dispose();
  }

  void _load(EmergencyFundStatus s) {
    if (_loaded) return;
    _loaded = true;
    final plan = s.plan;
    if (plan == null) return;
    _isEdit = true;
    _essentialsValue = plan.essentialMonthlyExpenses;
    _essentials.text = MoneyFormatter.editable(plan.essentialMonthlyExpenses);
    _months = plan.targetMonths.clamp(minEmergencyMonths, maxEmergencyMonths);
    final o = plan.targetOverride;
    if (o != null) {
      _custom = true;
      _overrideValue = o;
      _override.text = MoneyFormatter.editable(o);
    }
  }

  void _clearError(String field) {
    if (_errors.containsKey(field))
      setState(() => _errors = {..._errors}..remove(field));
  }

  void _setMonths(int m) => setState(() {
    _months = m.clamp(minEmergencyMonths, maxEmergencyMonths);
    _errors = {..._errors}..remove('targetMonths');
  });

  void _useSuggestion(Money m) {
    _essentials.text = MoneyFormatter.editable(m);
    _essentials.selection = TextSelection.collapsed(
      offset: _essentials.text.length,
    );
    setState(() {
      _essentialsValue = m;
      _errors = {..._errors}..remove('essentialMonthlyExpenses');
    });
  }

  Future<void> _submit() async {
    final essentials = LedgerAmountField.parse(_essentials.text);
    final override = _custom ? LedgerAmountField.parse(_override.text) : null;
    final local = <String, String>{
      if (essentials == null || !essentials.isPositive)
        'essentialMonthlyExpenses': 'Enter your essential monthly spending.',
      if (_custom && (override == null || !override.isPositive))
        'targetOverride': 'Enter a target greater than zero.',
    };
    if (local.isNotEmpty) {
      setState(() => _errors = local);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _errors = const {};
    });
    final result = await runAction(
      context,
      ref,
      action: const ConfigureEmergencyFundAction(),
      input: ConfigureEmergencyFundInput(
        essentialMonthlyExpenses: essentials!,
        targetMonths: _months,
        targetOverride: override,
      ),
      idempotencyKey: _key,
      successTitle: _isEdit
          ? 'Emergency fund plan updated'
          : 'Emergency fund plan saved',
      onFieldErrors: (e) {
        if (mounted) setState(() => _errors = e);
      },
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result != null) await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(emergencyStatusProvider);
    if (value.hasValue) _load(value.requireValue);
    return FinnSheetScaffold(
      title: _isEdit ? 'Edit emergency fund plan' : 'Plan your emergency fund',
      footer: LedgerButton(
        label: _isEdit ? 'Save changes' : 'Save plan',
        expand: true,
        loading: _submitting,
        onPressed: _submitting || !value.hasValue ? null : _submit,
      ),
      child: value.hasValue
          ? _form(context, value.requireValue)
          : value.hasError
          ? const LedgerEmpty(
              title: 'Could not load your emergency fund',
              message: 'Please try again.',
            )
          : const SavingsMovementSkeleton(),
    );
  }

  Widget _form(BuildContext context, EmergencyFundStatus s) {
    final c = context.ink;
    final t = context.type;
    final suggestion = s.suggestedEssentialMonthly;
    final essentials = _essentialsValue ?? Money.zero;
    final preview = ConfigureEmergencyFundInput(
      essentialMonthlyExpenses: essentials,
      targetMonths: _months,
      targetOverride: _custom ? _overrideValue : null,
    );
    final target = preview.target;
    final remaining = Money.max(target - s.saved, Money.zero);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedgerAmountField(
          hero: true,
          controller: _essentials,
          label: 'Essential spending per month',
          hint: '0',
          helper: suggestion == null
              ? 'Needs only: rent, groceries, bills, EMIs.'
              : null,
          autofocus: !_isEdit && suggestion == null,
          errorText: _errors['essentialMonthlyExpenses'],
          textInputAction: TextInputAction.next,
          onChanged: (m) {
            setState(() => _essentialsValue = m);
            _clearError('essentialMonthlyExpenses');
          },
        ),
        if (suggestion != null) ...[
          const SizedBox(height: Sp.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Last 3 months: ${savingsMoney(context, suggestion)}/month',
                  style: t.label,
                ),
              ),
              if (suggestion == _essentialsValue)
                Text('Applied', style: t.labelStrong.copyWith(color: c.green))
              else
                LedgerButton(
                  label: 'Use this',
                  variant: LedgerButtonVariant.quiet,
                  small: true,
                  onPressed: () => _useSuggestion(suggestion),
                ),
            ],
          ),
        ],
        const SizedBox(height: LedgerForm.gap),
        LedgerField(
          label: 'Months of cover',
          errorText: _errors['targetMonths'],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  LedgerIconButton(
                    icon: LucideIcons.minus,
                    tooltip: 'Fewer months',
                    onPressed: _months > minEmergencyMonths
                        ? () => _setMonths(_months - 1)
                        : null,
                  ),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        '$_months month${_months == 1 ? '' : 's'}',
                        textAlign: TextAlign.center,
                        style: t.heading,
                      ),
                    ),
                  ),
                  LedgerIconButton(
                    icon: LucideIcons.plus,
                    tooltip: 'More months',
                    onPressed: _months < maxEmergencyMonths
                        ? () => _setMonths(_months + 1)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: Sp.md),
              LedgerChoiceChips<int>(
                options: [
                  for (final m in _presetMonths) LedgerOption(m, '$m months'),
                ],
                selected: _months,
                onChanged: _setMonths,
              ),
            ],
          ),
        ),
        const SizedBox(height: Sp.md),
        LedgerSwitchRow(
          title: 'Custom target',
          subtitle: 'Use your own amount instead of essentials × months.',
          value: _custom,
          onChanged: (v) => setState(() {
            _custom = v;
            _errors = {..._errors}..remove('targetOverride');
          }),
        ),
        if (_custom) ...[
          const SizedBox(height: Sp.sm),
          LedgerAmountField(
            controller: _override,
            label: 'Target amount',
            errorText: _errors['targetOverride'],
            onChanged: (m) {
              setState(() => _overrideValue = m);
              _clearError('targetOverride');
            },
          ),
        ],
        const SizedBox(height: LedgerForm.gap),
        LedgerPanel(
          children: [
            LedgerFact(
              label: 'Your target',
              text: target.isPositive ? savingsMoney(context, target) : '—',
            ),
            LedgerFact(
              label: 'Saved so far',
              text: savingsMoney(context, s.saved),
            ),
            LedgerFact(
              label: 'Still to set aside',
              text: target.isPositive ? savingsMoney(context, remaining) : '—',
            ),
          ],
        ),
      ],
    );
  }
}
