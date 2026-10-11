import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../design_system/design_system.dart';
import '../../../features/transactions/domain/transaction.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/category_icons.dart';
import '../application/category_actions.dart';
import '../domain/category.dart';
import 'category_providers.dart';

/// Create or edit a category. On create, the sheet pops with the new
/// category id so callers (e.g. the transaction form) can select it.
class CategoryFormSheet extends ConsumerWidget {
  const CategoryFormSheet({super.key, this.categoryId, this.initialType = TransactionType.expense});

  final String? categoryId;
  final TransactionType initialType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = categoryId;
    if (id == null) return _CategoryForm(initial: null, initialType: initialType);
    final all = ref.watch(categoriesByIdProvider);
    if (!all.hasValue) {
      return FinnSheetScaffold(
        title: 'Edit category',
        child: all.hasError
            ? ErrorState(title: 'Could not load this category', onRetry: () => refreshFinanceData(ref))
            : const SkeletonPulse(child: SkeletonBox(height: 240, radius: Radii.lg)),
      );
    }
    final cat = all.requireValue[id];
    if (cat == null) {
      return const FinnSheetScaffold(
        title: 'Edit category',
        child: EmptyState(
          icon: LucideIcons.searchX,
          title: 'Category not found',
          message: 'It may have been deleted.',
        ),
      );
    }
    return _CategoryForm(key: ValueKey(cat.id), initial: cat, initialType: cat.type);
  }
}

enum _Busy { none, saving, archiving, deleting }

class _CategoryForm extends ConsumerStatefulWidget {
  const _CategoryForm({super.key, required this.initial, required this.initialType});

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
      setState(() => _errors = {'name': 'Use $categoryNameMin to $categoryNameMax characters.'});
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
            input: UpdateCategoryInput(id: initial.id, expectedVersion: initial.version, data: _input()),
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
    final c = context.colors;
    final t = context.text;
    final initial = _initial;
    final editing = initial != null;
    final usage = editing ? ref.watch(categoryUsageProvider(initial.id)).value : null;
    final inUse = usage?.isInUse ?? false;
    final typeLocked = _system || (editing && inUse);
    final preview = TransactionCategory(
      id: initial?.id ?? 'preview',
      name: _name.text,
      type: _type,
      iconKey: _iconKey,
      colorIndex: _colorIndex,
    );
    final idle = _busy == _Busy.none;

    return FinnSheetScaffold(
      title: editing ? 'Edit category' : 'New category',
      description: editing ? 'Changes apply to every transaction in this category.' : 'Group similar money movements together.',
      footer: FinnButton(
        label: editing ? 'Save changes' : 'Create category',
        icon: LucideIcons.check,
        size: FinnButtonSize.lg,
        expand: true,
        loading: _busy == _Busy.saving,
        onPressed: idle ? _save : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CategoryAvatar(category: preview, size: 52),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValueListenableBuilder(
                      valueListenable: _name,
                      builder: (context, v, _) => Text(
                        v.text.trim().isEmpty ? 'Category name' : v.text.trim(),
                        style: t.title.copyWith(color: v.text.trim().isEmpty ? c.textTertiary : null),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(_type.label, style: t.caption),
                  ],
                ),
              ),
            ],
          ),
          if (_system) ...[
            const SizedBox(height: Space.x4),
            const InfoBanner(
              title: 'Managed automatically',
              message: 'FiNN uses this category for loans, settlements or uncategorised entries. '
                  'You can change its icon and colour.',
              icon: LucideIcons.lock,
            ),
          ],
          const SizedBox(height: Space.x5),
          Text('Type', style: t.label),
          const SizedBox(height: Space.x1_5),
          IgnorePointer(
            ignoring: typeLocked,
            child: Opacity(
              opacity: typeLocked ? 0.55 : 1,
              child: SegmentedTabs<TransactionType>(
                items: const [
                  SegmentItem(TransactionType.expense, 'Expense'),
                  SegmentItem(TransactionType.income, 'Income'),
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
              padding: const EdgeInsets.only(top: Space.x1_5),
              child: Text('Type is fixed because this category is used by ${usage!.describe()}.', style: t.caption),
            ),
          const SizedBox(height: Space.x5),
          FinnTextField(
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
          const SizedBox(height: Space.x3),
          FinnTextField(
            label: 'Description (optional)',
            hint: 'What belongs here, e.g. vet, pet food, grooming',
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
            const SizedBox(height: Space.x3),
            FinnCard(
              variant: FinnCardVariant.muted,
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x2, Space.x3),
              child: MergeSemantics(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Essential spending', style: t.bodyStrong),
                          const SizedBox(height: 2),
                          Text(
                            'Needs like rent, groceries and bills. Used to suggest your emergency-fund '
                            'target and to separate essentials from lifestyle spending.',
                            style: t.caption,
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _essential,
                      onChanged: _system ? null : (v) => setState(() => _essential = v),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: Space.x5),
          Text('Icon', style: t.label),
          const SizedBox(height: Space.x2),
          _IconPicker(
            selected: _iconKey,
            colorIndex: _colorIndex,
            onChanged: (k) => setState(() => _iconKey = k),
          ),
          if (_errors['iconKey'] != null) _ErrorText(_errors['iconKey']!),
          const SizedBox(height: Space.x5),
          Text('Colour', style: t.label),
          const SizedBox(height: Space.x2),
          _ColorPicker(selected: _colorIndex, onChanged: (i) => setState(() => _colorIndex = i)),
          if (_errors['colorIndex'] != null) _ErrorText(_errors['colorIndex']!),
          if (editing && !_system) ...[
            const SizedBox(height: Space.x6),
            const FinnDivider(),
            const SizedBox(height: Space.x4),
            Row(
              children: [
                Expanded(
                  child: FinnButton(
                    label: initial.isArchived ? 'Restore' : 'Archive',
                    icon: initial.isArchived ? LucideIcons.archiveRestore : LucideIcons.archive,
                    variant: FinnButtonVariant.outline,
                    expand: true,
                    loading: _busy == _Busy.archiving,
                    onPressed: idle ? _toggleArchive : null,
                  ),
                ),
                const SizedBox(width: Space.x3),
                Expanded(
                  child: FinnButton(
                    label: 'Delete',
                    icon: LucideIcons.trash2,
                    variant: FinnButtonVariant.destructive,
                    expand: true,
                    loading: _busy == _Busy.deleting,
                    onPressed: idle && usage != null && !inUse ? _delete : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.x2),
            Text(
              inUse
                  ? 'Used by ${usage!.describe()}, so it can’t be deleted. Archive it to hide it from pickers '
                      'while keeping your history intact.'
                  : initial.isArchived
                      ? 'Archived categories stay on past transactions but are hidden from pickers.'
                      : 'Not used anywhere yet, so it can be deleted safely.',
              style: t.caption,
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
        padding: const EdgeInsets.only(top: Space.x1_5, left: Space.x1),
        child: Text(message, style: context.text.caption.copyWith(color: context.colors.negative)),
      );
}

class _IconPicker extends StatelessWidget {
  const _IconPicker({required this.selected, required this.colorIndex, required this.onChanged});

  final String selected;
  final int colorIndex;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: Space.x2,
      runSpacing: Space.x2,
      children: [
        for (final key in CategoryIcons.pickable)
          Semantics(
            key: ValueKey('icon-$key'),
            button: true,
            selected: key == selected,
            label: 'Icon $key',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: Radii.rLg,
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(key);
              },
              child: AnimatedContainer(
                duration: context.motion.fast,
                width: Dimens.minTouch,
                height: Dimens.minTouch,
                decoration: BoxDecoration(
                  gradient: key == selected ? AccentSwatches.gradient(colorIndex) : null,
                  color: key == selected ? null : c.surfaceMuted,
                  borderRadius: Radii.rLg,
                ),
                child: Icon(
                  CategoryIcons.of(key),
                  size: 20,
                  color: key == selected ? Colors.white : c.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: Space.x2,
      runSpacing: Space.x2,
      children: [
        for (var i = 0; i < AccentSwatches.gradients.length && i < categoryColorCount; i++)
          Semantics(
            key: ValueKey('colour-$i'),
            button: true,
            selected: i == selected,
            label: 'Colour ${i + 1}',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(i);
              },
              child: SizedBox.square(
                dimension: Dimens.minTouch,
                child: Center(
                  child: AnimatedContainer(
                    duration: context.motion.fast,
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: AccentSwatches.gradient(i),
                      shape: BoxShape.circle,
                      border: Border.all(color: i == selected ? c.primary : Colors.transparent, width: 2.5),
                    ),
                    child: i == selected ? const Icon(LucideIcons.check, size: 16, color: Colors.white) : null,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
