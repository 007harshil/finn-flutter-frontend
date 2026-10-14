import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../design_system/design_system.dart';
import '../../../design_system/luxe/luxe.dart';
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
    if (_errors.containsKey(field)) setState(() => _errors = {..._errors}..remove(field));
  }

  void _setMonths(int m) => setState(() {
        _months = m.clamp(minEmergencyMonths, maxEmergencyMonths);
        _errors = {..._errors}..remove('targetMonths');
      });

  void _useSuggestion(Money m) {
    _essentials.text = MoneyFormatter.editable(m);
    _essentials.selection = TextSelection.collapsed(offset: _essentials.text.length);
    setState(() {
      _essentialsValue = m;
      _errors = {..._errors}..remove('essentialMonthlyExpenses');
    });
  }

  Future<void> _submit() async {
    final essentials = AmountField.parse(_essentials.text);
    final override = _custom ? AmountField.parse(_override.text) : null;
    final local = <String, String>{
      if (essentials == null || !essentials.isPositive)
        'essentialMonthlyExpenses': 'Enter your essential monthly spending.',
      if (_custom && (override == null || !override.isPositive)) 'targetOverride': 'Enter a target greater than zero.',
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
      successTitle: _isEdit ? 'Emergency fund plan updated' : 'Emergency fund plan saved',
      onFieldErrors: (e) {
        if (mounted) setState(() => _errors = e);
      },
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result != null) await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) => LuxeScope(paint: true, child: Builder(builder: _buildSheet));

  Widget _buildSheet(BuildContext context) {
    final value = ref.watch(emergencyStatusProvider);
    if (value.hasValue) _load(value.requireValue);
    return FinnSheetScaffold(
      title: _isEdit ? 'Edit emergency fund plan' : 'Plan your emergency fund',
      description: 'A safety net for job loss, medical bills or urgent repairs. '
          'Most people aim for 3–6 months of essential spending.',
      footer: FinnButton(
        label: _isEdit ? 'Save changes' : 'Save plan',
        icon: LucideIcons.check,
        expand: true,
        size: FinnButtonSize.lg,
        loading: _submitting,
        onPressed: _submitting || !value.hasValue ? null : _submit,
      ),
      child: value.hasValue
          ? _form(context, value.requireValue)
          : value.hasError
              ? const ErrorState(title: 'Could not load your emergency fund')
              : const SkeletonPulse(child: ListSkeleton(count: 4, padding: EdgeInsets.zero)),
    );
  }

  Widget _form(BuildContext context, EmergencyFundStatus s) {
    final c = context.colors;
    final t = context.text;
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
        AmountField(
            prominent: true,
          controller: _essentials,
          label: 'Essential spending per month',
          hint: 'Rent, groceries, bills, EMIs',
          autofocus: !_isEdit && suggestion == null,
          errorText: _errors['essentialMonthlyExpenses'],
          textInputAction: TextInputAction.next,
          onChanged: (m) {
            setState(() => _essentialsValue = m);
            _clearError('essentialMonthlyExpenses');
          },
        ),
        const SizedBox(height: Space.x2),
        if (suggestion != null)
          _SuggestionRow(
            suggestion: suggestion,
            applied: suggestion == _essentialsValue,
            onUse: () => _useSuggestion(suggestion),
          )
        else
          Text(
            'Only needs, not wants. Mark categories as essential to get a suggestion from your spending.',
            style: t.caption,
          ),
        const SizedBox(height: Space.x5),
        Text('Months of cover', style: t.label),
        const SizedBox(height: Space.x2),
        Row(
          children: [
            FinnIconButton(
              icon: LucideIcons.minus,
              tooltip: 'Fewer months',
              variant: FinnIconButtonVariant.outline,
              onPressed: _months > minEmergencyMonths ? () => _setMonths(_months - 1) : null,
            ),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  '$_months month${_months == 1 ? '' : 's'}',
                  textAlign: TextAlign.center,
                  style: t.sectionTitle,
                ),
              ),
            ),
            FinnIconButton(
              icon: LucideIcons.plus,
              tooltip: 'More months',
              variant: FinnIconButtonVariant.outline,
              onPressed: _months < maxEmergencyMonths ? () => _setMonths(_months + 1) : null,
            ),
          ],
        ),
        const SizedBox(height: Space.x2),
        Wrap(
          spacing: Space.x2,
          runSpacing: Space.x2,
          children: [
            for (final m in _presetMonths)
              ChoiceChip(
                label: Text('$m months'),
                selected: _months == m,
                onSelected: (_) => _setMonths(m),
              ),
          ],
        ),
        if (_errors['targetMonths'] != null) ...[
          const SizedBox(height: Space.x1_5),
          Text(_errors['targetMonths']!, style: t.caption.copyWith(color: c.negative)),
        ],
        const SizedBox(height: Space.x4),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _custom,
          title: Text('Set a custom target', style: t.bodyStrong),
          subtitle: Text('Use your own amount instead of essentials × months.', style: t.caption),
          onChanged: (v) => setState(() {
            _custom = v;
            _errors = {..._errors}..remove('targetOverride');
          }),
        ),
        if (_custom) ...[
          const SizedBox(height: Space.x2),
          AmountField(
            controller: _override,
            label: 'Custom target',
            errorText: _errors['targetOverride'],
            onChanged: (m) {
              setState(() => _overrideValue = m);
              _clearError('targetOverride');
            },
          ),
        ],
        const SizedBox(height: Space.x5),
        FinnCard(
          variant: FinnCardVariant.muted,
          padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
          child: Column(
            children: [
              KeyValueRow(
                label: 'Your target',
                value: target.isPositive ? savingsMoney(context, target) : '—',
                valueColor: target.isPositive ? null : c.textSecondary,
              ),
              KeyValueRow(label: 'Saved so far', value: savingsMoney(context, s.saved)),
              KeyValueRow(
                label: 'Still to set aside',
                value: target.isPositive ? savingsMoney(context, remaining) : '—',
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.x2),
        Text('Saving the plan does not move any money.', style: t.caption),
      ],
    );
  }
}

/// "Last 3 months: ₹X/month · Use this".
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.suggestion, required this.applied, required this.onUse});

  final Money suggestion;
  final bool applied;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return FinnCard(
      variant: FinnCardVariant.outlined,
      padding: const EdgeInsets.fromLTRB(Space.x3, Space.x2, Space.x2, Space.x2),
      child: Row(
        children: [
          Icon(LucideIcons.sparkles, size: 16, color: c.textSecondary),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Suggested from your spending', style: t.caption),
                Text('${savingsMoney(context, suggestion)}/month', style: t.bodyStrong),
                Text('Average of essentials and EMIs, last 3 months', style: t.micro.copyWith(color: c.textTertiary)),
              ],
            ),
          ),
          if (applied)
            StatusPill(label: 'Applied', color: c.positive, icon: LucideIcons.check)
          else
            FinnButton(
              label: 'Use this',
              variant: FinnButtonVariant.ghost,
              size: FinnButtonSize.sm,
              onPressed: onUse,
            ),
        ],
      ),
    );
  }
}
