import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../kit/kit.dart';
import '../../../features/transactions/domain/transaction.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/category_icons.dart';
import '../application/category_actions.dart';
import '../domain/category.dart';
import 'category_providers.dart';

/// Create or edit a category. On create, the sheet pops with the new
/// category id so callers (e.g. the transaction form) can select it.
class CategoryFormSheet extends ConsumerWidget {
  const CategoryFormSheet({
    super.key,
    this.categoryId,
    this.initialType = TransactionType.expense,
  });

  final String? categoryId;
  final TransactionType initialType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = categoryId;
    if (id == null)
      return _CategoryForm(initial: null, initialType: initialType);
    final all = ref.watch(categoriesByIdProvider);
    if (!all.hasValue) {
      return FinnSheetScaffold(
        title: 'Edit category',
        child: all.hasError
            ? LedgerEmpty(
                title: 'Could not load this category',
                message: 'Please try again.',
                actionLabel: 'Try again',
                onAction: () => refreshFinanceData(ref),
              )
            : const LedgerSkeleton(height: 240),
      );
    }
    final cat = all.requireValue[id];
    if (cat == null) {
      return const FinnSheetScaffold(
        title: 'Edit category',
        child: LedgerEmpty(
          title: 'Category not found',
          message: 'It may have been deleted.',
        ),
      );
    }
    return _CategoryForm(
      key: ValueKey(cat.id),
      initial: cat,
      initialType: cat.type,
    );
  }
}

enum _Busy { none, saving, archiving, deleting }

class _CategoryForm extends ConsumerStatefulWidget {
  const _CategoryForm({
    super.key,
    required this.initial,
    required this.initialType,
  });

  final TransactionCategory? initial;
  final TransactionType initialType;

  @override
  ConsumerState<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends ConsumerState<_CategoryForm> {
  // Separate keys: one idempotency key must never serve two operations.
  final String _saveKey = newIdempotencyKey();
  final String _archiveKey = newIdempotencyKey();
  final String _deleteKey = newIdempotencyKey();

  final _name = TextEditingController();
  final _description = TextEditingController();
  late TransactionType _type = widget.initialType;
  bool _essential = false;
  String _iconKey = 'tag';
  int _colorIndex = 0;
  Map<String, String> _errors = const {};
  _Busy _busy = _Busy.none;

  TransactionCategory? get _initial => widget.initial;
  bool get _system => _initial?.isSystem ?? false;

  @override
  void initState() {
    super.initState();
    final c = _initial;
    if (c != null) {
      _name.text = c.name;
      _description.text = c.description;
      _essential = c.isEssential;
      _iconKey = c.iconKey;
      _colorIndex = c.colorIndex;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _clearError(String field) {
    if (!_errors.containsKey(field)) return;
    setState(() => _errors = Map.of(_errors)..remove(field));
  }

  CategoryInput _input() => CategoryInput(
    name: _name.text.trim(),
    type: _type,
    iconKey: _iconKey,
    colorIndex: _colorIndex,
    description: _description.text.trim(),
    isEssential: _type == TransactionType.expense && _essential,
  );

  Future<void> _save() async {
    if (_busy != _Busy.none) return;
    FocusScope.of(context).unfocus();
    final name = _name.text.trim();
    if (name.length < categoryNameMin || name.length > categoryNameMax) {
      setState(
        () => _errors = {
          'name': 'Use $categoryNameMin to $categoryNameMax characters.',
        },
      );
      return;
    }
    setState(() {
      _errors = const {};
      _busy = _Busy.saving;
    });
    void onErrors(Map<String, String> e) => setState(() => _errors = e);
    final initial = _initial;
    final TransactionCategory? saved = initial == null
        ? await runAction(
            context,
            ref,
            action: const CreateCategoryAction(),
            input: _input(),
            idempotencyKey: _saveKey,
            successTitle: 'Category created',
            successSubtitle: name,
            onFieldErrors: onErrors,
          )
        : await runAction(
            context,
            ref,
            action: const UpdateCategoryAction(),
            input: UpdateCategoryInput(
              id: initial.id,
              expectedVersion: initial.version,
              data: _input(),
            ),
            idempotencyKey: _saveKey,
            successTitle: 'Category updated',
            successSubtitle: name,
            onFieldErrors: onErrors,
          );
    _finish(saved?.id);
  }

  Future<void> _toggleArchive() async {
    final c = _initial;
    if (c == null || _busy != _Busy.none) return;
    setState(() => _busy = _Busy.archiving);
    final result = await runAction(
      context,
      ref,
      action: const ArchiveCategoryAction(),
      input: CategoryIdInput(id: c.id),
      idempotencyKey: _archiveKey,
    );
    _finish(result?.id);
  }

  Future<void> _confirmDelete() async {
    final ok = await showFinnConfirm(
      context,
      title: 'Delete category?',
      message: 'This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok && mounted) await _delete();
  }

  Future<void> _delete() async {
    final c = _initial;
    if (c == null || _busy != _Busy.none) return;
    setState(() => _busy = _Busy.deleting);
    final result = await runAction(
      context,
      ref,
      action: const DeleteCategoryAction(),
      input: CategoryIdInput(id: c.id),
      idempotencyKey: _deleteKey,
      successTitle: 'Category deleted',
    );
    _finish(result?.id);
  }

  void _finish(String? id) {
    if (!mounted) return;
    if (id == null) {
      setState(() => _busy = _Busy.none);
      return;
    }
    Navigator.of(context).maybePop(id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final initial = _initial;
    final editing = initial != null;
    final usage = editing
        ? ref.watch(categoryUsageProvider(initial.id)).value
        : null;
    final inUse = usage?.isInUse ?? false;
    final typeLocked = _system || (editing && inUse);
    final idle = _busy == _Busy.none;

    return FinnSheetScaffold(
      title: editing ? 'Edit category' : 'New category',
      footer: LedgerButton(
        label: editing ? 'Save changes' : 'Create category',
        expand: true,
        loading: _busy == _Busy.saving,
        onPressed: idle ? _save : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_system) ...[
            const LedgerNote(
              icon: LucideIcons.lock,
              text: 'Managed by FiNN for loans, settlements and uncategorised entries. You can change its icon.',
            ),
            const SizedBox(height: LedgerForm.gap),
          ],
          IgnorePointer(
            ignoring: typeLocked,
            child: Opacity(
              opacity: typeLocked ? 0.55 : 1,
              child: LedgerSegmented<TransactionType>(
                segments: const [
                  LedgerSegment(TransactionType.expense, 'Expense'),
                  LedgerSegment(TransactionType.income, 'Income'),
                ],
                selected: _type,
                onChanged: (v) => setState(() {
                  _type = v;
                  _errors = Map.of(_errors)
                    ..remove('type')
                    ..remove('name');
                }),
              ),
            ),
          ),
          if (_errors['type'] != null)
            _ErrorText(_errors['type']!)
          else if (editing && inUse && !_system)
            Padding(
              padding: const EdgeInsets.only(top: Sp.sm),
              child: Text(
                'Type is fixed: used by ${usage!.describe()}.',
                style: t.label,
              ),
            ),
          const SizedBox(height: LedgerForm.gap),
          LedgerTextField(
            label: 'Name',
            hint: 'e.g. Pets, Side hustle, Dining out',
            controller: _name,
            enabled: !_system,
            maxLength: categoryNameMax,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            errorText: _errors['name'],
            onChanged: (_) => _clearError('name'),
          ),
          const SizedBox(height: LedgerForm.gap),
          LedgerTextField(
            label: 'Description (optional)',
            controller: _description,
            enabled: !_system,
            minLines: 1,
            maxLines: 3,
            maxLength: categoryDescriptionMax,
            textCapitalization: TextCapitalization.sentences,
            errorText: _errors['description'],
            onChanged: (_) => _clearError('description'),
          ),
          if (_type == TransactionType.expense) ...[
            const SizedBox(height: Sp.sm),
            LedgerSwitchRow(
              title: 'Essential spending',
              subtitle: 'Needs like rent and bills. Used to suggest your emergency fund.',
              value: _essential,
              enabled: !_system,
              onChanged: (v) => setState(() => _essential = v),
            ),
          ],
          const SizedBox(height: LedgerForm.gap),
          LedgerField(
            label: 'Icon',
            errorText: _errors['iconKey'],
            child: _IconPicker(
              selected: _iconKey,
              onChanged: (k) => setState(() => _iconKey = k),
            ),
          ),
          if (editing && !_system) ...[
            const SizedBox(height: LedgerForm.groupGap),
            const LedgerDivider(),
            const SizedBox(height: Sp.lg),
            Text(
              inUse
                  ? 'Used by ${usage!.describe()}, so it can’t be deleted. Archive it to hide it from pickers.'
                  : initial.isArchived
                  ? 'Archived categories stay on past transactions but are hidden from pickers.'
                  : 'Not used anywhere yet, so it can be deleted safely.',
              style: t.label,
            ),
            const SizedBox(height: Sp.md),
            Row(
              children: [
                Expanded(
                  child: LedgerButton(
                    label: initial.isArchived ? 'Restore' : 'Archive',
                    variant: LedgerButtonVariant.secondary,
                    loading: _busy == _Busy.archiving,
                    onPressed: idle ? _toggleArchive : null,
                  ),
                ),
                const SizedBox(width: Sp.md),
                Expanded(
                  child: LedgerButton(
                    label: 'Delete',
                    variant: LedgerButtonVariant.secondary,
                    color: c.red,
                    loading: _busy == _Busy.deleting,
                    onPressed: idle && usage != null && !inUse
                        ? _confirmDelete
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Sp.sm),
    child: Text(
      message,
      style: context.type.label.copyWith(color: context.ink.red),
    ),
  );
}

class _IconPicker extends StatelessWidget {
  const _IconPicker({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    return Wrap(
      spacing: Sp.sm,
      runSpacing: Sp.sm,
      children: [
        for (final key in CategoryIcons.pickable)
          Semantics(
            key: ValueKey('icon-$key'),
            button: true,
            selected: key == selected,
            label: 'Icon $key',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: Rad.rMd,
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(key);
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: key == selected ? c.ink : c.sunken,
                  borderRadius: Rad.rMd,
                ),
                child: Icon(
                  CategoryIcons.of(key),
                  size: 20,
                  color: key == selected ? c.onInk : c.inkSoft,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
