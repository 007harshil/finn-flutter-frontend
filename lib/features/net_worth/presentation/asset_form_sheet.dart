import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../core/money/money_format.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/category_icons.dart';
import '../application/asset_actions.dart';
import '../application/net_worth_view.dart';
import '../domain/asset.dart';

/// Add or edit an asset valuation (and delete it when editing).
class AssetFormSheet extends ConsumerStatefulWidget {
  const AssetFormSheet({super.key, this.assetId});

  final String? assetId;

  @override
  ConsumerState<AssetFormSheet> createState() => _AssetFormSheetState();
}

class _AssetFormSheetState extends ConsumerState<AssetFormSheet> {
  final _key = newIdempotencyKey();
  final _deleteKey = newIdempotencyKey();
  final _name = TextEditingController();
  final _value = TextEditingController();
  final _note = TextEditingController();
  AssetType _type = AssetType.investment;
  DateTime? _valuedOn;
  Map<String, String> _errors = const {};
  bool _submitting = false;
  bool _loaded = false;
  Asset? _existing;

  bool get _isEdit => widget.assetId != null;

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    _note.dispose();
    super.dispose();
  }

  void _load(Asset? a) {
    if (_loaded) return;
    _loaded = true;
    if (a == null) return;
    _existing = a;
    _name.text = a.name;
    _value.text = MoneyFormatter.editable(a.value);
    _note.text = a.note ?? '';
    _type = a.type;
    _valuedOn = a.valuedOn;
  }

  void _clearError(String field) {
    if (_errors.containsKey(field))
      setState(() => _errors = {..._errors}..remove(field));
  }

  void _onErrors(Map<String, String> e) {
    if (mounted) setState(() => _errors = e);
  }

  Future<void> _submit() async {
    final value = LedgerAmountField.parse(_value.text);
    final local = <String, String>{
      if (_name.text.trim().length < 2) 'name': 'Use at least 2 characters.',
      if (value == null) 'value': 'Enter the current value (zero is fine).',
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
    final data = AssetInput(
      name: _name.text.trim(),
      type: _type,
      value: value!,
      valuedOn: _valuedOn ?? ref.read(todayProvider),
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    final existing = _existing;
    final Asset? result;
    if (existing == null) {
      result = await runAction(
        context,
        ref,
        action: const CreateAssetAction(),
        input: data,
        idempotencyKey: _key,
        successTitle: 'Asset added',
        successSubtitle: data.name,
        onFieldErrors: _onErrors,
      );
    } else {
      result = await runAction(
        context,
        ref,
        action: const UpdateAssetAction(),
        input: UpdateAssetInput(
          id: existing.id,
          expectedVersion: existing.version,
          data: data,
        ),
        idempotencyKey: _key,
        successTitle: 'Asset updated',
        onFieldErrors: _onErrors,
      );
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result != null) await Navigator.of(context).maybePop();
  }

  Future<void> _delete() async {
    final existing = _existing;
    if (existing == null || _submitting) return;
    setState(() => _submitting = true);
    final result = await runAction(
      context,
      ref,
      action: const DeleteAssetAction(),
      input: DeleteAssetInput(id: existing.id),
      idempotencyKey: _deleteKey,
      successTitle: 'Asset deleted',
      successSubtitle: existing.name,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result != null) await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final value = _isEdit
        ? ref.watch(assetByIdProvider(widget.assetId!))
        : null;
    final ready = value == null || value.hasValue || _loaded;
    if (value != null && value.hasValue) _load(value.value);
    if (value == null) _loaded = true;
    final missing = _isEdit && ready && _existing == null;
    return FinnSheetScaffold(
      title: _isEdit ? 'Edit asset' : 'Add asset',
      description: 'Counts towards net worth, not your cash balance.',
      footer: LedgerButton(
        label: _isEdit ? 'Save changes' : 'Add asset',
        expand: true,
        loading: _submitting,
        onPressed: _submitting || !ready || missing ? null : _submit,
      ),
      child: !ready
          ? const _FormSkeleton()
          : missing
          ? const LedgerEmpty(
              title: 'Asset not found',
              message: 'It may have been deleted.',
            )
          : _form(context),
    );
  }

  Widget _form(BuildContext context) {
    final c = context.ink;
    final today = ref.watch(todayProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedgerAmountField(
          hero: true,
          controller: _value,
          label: 'Current value',
          helper: 'What it would fetch today.',
          errorText: _errors['value'],
          textInputAction: TextInputAction.next,
          onChanged: (_) => _clearError('value'),
        ),
        const SizedBox(height: LedgerForm.gap),
        LedgerTextField(
          controller: _name,
          label: 'Name',
          hint: 'e.g. HDFC mutual funds',
          errorText: _errors['name'],
          maxLength: 40,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _clearError('name'),
        ),
        const SizedBox(height: LedgerForm.gap),
        LedgerField(
          label: 'Type',
          child: LedgerChoiceChips<AssetType>(
            options: [
              for (final type in AssetType.values)
                LedgerOption(
                  type,
                  type.label,
                  icon: CategoryIcons.of(type.iconKey),
                ),
            ],
            selected: _type,
            onChanged: (v) => setState(() => _type = v),
          ),
        ),
        const SizedBox(height: LedgerForm.groupGap),
        LedgerDateField(
          label: 'Valued on',
          value: _valuedOn ?? today,
          firstDate: DateTime(1970),
          lastDate: today,
          errorText: _errors['valuedOn'],
          onChanged: (d) => setState(() {
            _valuedOn = d;
            _errors = {..._errors}..remove('valuedOn');
          }),
        ),
        const SizedBox(height: LedgerForm.gap),
        LedgerTextField(
          controller: _note,
          label: 'Note (optional)',
          hint: 'e.g. Matures March 2027',
          errorText: _errors['note'],
          maxLength: 500,
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => _clearError('note'),
        ),
        if (_isEdit) ...[
          const SizedBox(height: LedgerForm.groupGap),
          Align(
            child: LedgerButton(
              label: 'Delete asset',
              icon: LucideIcons.trash2,
              variant: LedgerButtonVariant.quiet,
              color: c.red,
              onPressed: _submitting ? null : _delete,
            ),
          ),
        ],
      ],
    );
  }
}

class _FormSkeleton extends StatelessWidget {
  const _FormSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: const ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LedgerSkeleton(width: 200, height: 44),
            SizedBox(height: LedgerForm.gap),
            LedgerSkeleton(height: 52),
            SizedBox(height: LedgerForm.gap),
            LedgerSkeleton(height: 52),
          ],
        ),
      ),
    );
  }
}
