import '../../../actions/action.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/result/result.dart';
import '../../../core/time/dates.dart';
import '../../../finance/finance_snapshot.dart';
import '../domain/asset.dart';

/// Input for creating or updating a user-managed asset valuation.
class AssetInput extends ActionInput {
  const AssetInput({
    required this.name,
    required this.type,
    required this.value,
    required this.valuedOn,
    this.note,
  });

  final String name;
  final AssetType type;

  /// The user's estimate of what the asset is worth (may be zero).
  final Money value;

  /// Date of the valuation (not in the future).
  final DateTime valuedOn;
  final String? note;

  factory AssetInput.fromJson(Map<String, Object?> j) => AssetInput(
        name: In.str(j, 'name'),
        type: In.enumeration(j, 'type', AssetType.values),
        value: In.money(j, 'value'),
        valuedOn: In.date(j, 'valuedOn'),
        note: In.strOpt(j, 'note'),
      );

  @override
  Map<String, Object?> toJson() => {
        'name': name,
        'type': type.name,
        'value': Out.money(value),
        'valuedOn': Out.date(valuedOn),
        'note': note,
      };
}

final _fields = [
  const ActionFieldSpec('name', FieldKind.string, 'Asset name, 2–40 characters'),
  ActionFieldSpec('type', FieldKind.enumeration, 'Kind of asset',
      allowedValues: [for (final t in AssetType.values) t.name]),
  const ActionFieldSpec('value', FieldKind.money, 'Estimated current value in rupees (zero or more)'),
  const ActionFieldSpec('valuedOn', FieldKind.date, 'Date of the valuation (not in the future)'),
  const ActionFieldSpec('note', FieldKind.string, 'Free-text note', required: false),
];

/// Largest single valuation accepted (₹1,000 crore) — guards against typos.
const Money maxAssetValue = Money.rupees(10000000000);

Map<String, String> validateAsset(AssetInput i, FinanceSnapshot s) {
  final errors = <String, String>{};
  final name = i.name.trim();
  if (name.length < 2) {
    errors['name'] = 'Use at least 2 characters.';
  } else if (name.length > 40) {
    errors['name'] = 'Keep the name under 40 characters.';
  }
  if (i.value.isNegative) errors['value'] = 'Enter zero or more.';
  if (i.value > maxAssetValue) errors['value'] = 'That value looks too large. Please check it.';
  if (i.valuedOn.dateOnly.isAfter(s.today)) errors['valuedOn'] = 'The valuation date cannot be in the future.';
  if ((i.note?.length ?? 0) > 500) errors['note'] = 'Keep the note under 500 characters.';
  return errors;
}

List<PreviewLine> _lines(AssetInput i) => [
      PreviewLine('Asset', i.name.trim()),
      PreviewLine('Type', i.type.label),
      PreviewLine('Value', i.value.format(), emphasis: true),
      PreviewLine('Valued on', DateFormats.dayMonthYear.format(i.valuedOn)),
    ];

class CreateAssetAction extends FinancialAction<AssetInput, Asset> {
  const CreateAssetAction();

  @override
  ActionDescriptor get descriptor => ActionDescriptor(
        id: 'assets.create',
        module: 'net_worth',
        title: 'Add an asset',
        description: 'Adds an estimated asset value (investments, gold, property…) to net worth. '
            'Does not change the cash balance.',
        risk: ActionRisk.low,
        fields: _fields,
      );

  @override
  AssetInput decode(Map<String, Object?> json) => AssetInput.fromJson(json);

  @override
  Result<ActionPreview> prepare(AssetInput input, FinanceSnapshot s, ActionEnvironment env) {
    final errors = validateAsset(input, s);
    if (errors.isNotEmpty) return Result.err(AppFailure.validation(errors.values.first, fields: errors));
    final warnings = <String>[
      if (s.assets.any((a) => a.name.trim().toLowerCase() == input.name.trim().toLowerCase()))
        'You already have an asset called "${input.name.trim()}".',
    ];
    return Result.ok(preview(
      input,
      title: 'Add asset',
      summary: 'Added ${input.name.trim()} at ${input.value.format()}',
      lines: _lines(input),
      warnings: warnings,
    ));
  }

  @override
  Future<Result<Asset>> execute(AssetInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final now = env.clock.now();
    final asset = Asset(
      id: env.ids.next('asset'),
      name: input.name.trim(),
      type: input.type,
      value: input.value,
      valuedOn: input.valuedOn.dateOnly,
      note: input.note?.trim().isEmpty ?? true ? null : input.note!.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await env.repos.assets.save(asset);
    return Result.ok(asset);
  }
}

class UpdateAssetInput extends ActionInput {
  const UpdateAssetInput({required this.id, required this.expectedVersion, required this.data});
  final String id;

  /// Version the user edited; a mismatch means it changed elsewhere.
  final int expectedVersion;
  final AssetInput data;

  @override
  Map<String, Object?> toJson() => {'id': id, 'expectedVersion': expectedVersion, ...data.toJson()};
}

class UpdateAssetAction extends FinancialAction<UpdateAssetInput, Asset> {
  const UpdateAssetAction();

  @override
  ActionDescriptor get descriptor => ActionDescriptor(
        id: 'assets.update',
        module: 'net_worth',
        title: 'Update an asset',
        description: 'Changes an asset\'s name, type or estimated value. Net worth updates automatically.',
        risk: ActionRisk.low,
        fields: [
          const ActionFieldSpec('id', FieldKind.id, 'Asset id'),
          const ActionFieldSpec('expectedVersion', FieldKind.integer, 'Version that was read'),
          ..._fields,
        ],
      );

  @override
  UpdateAssetInput decode(Map<String, Object?> json) => UpdateAssetInput(
        id: In.str(json, 'id'),
        expectedVersion: In.integer(json, 'expectedVersion'),
        data: AssetInput.fromJson(json),
      );

  @override
  Result<ActionPreview> prepare(UpdateAssetInput input, FinanceSnapshot s, ActionEnvironment env) {
    final existing = s.assets.where((a) => a.id == input.id).firstOrNull;
    if (existing == null) return const Result.err(AppFailure.notFound('This asset no longer exists.'));
    if (existing.version != input.expectedVersion) {
      return const Result.err(
          AppFailure(FailureCode.staleData, 'This asset changed since you opened it. Reload and try again.'));
    }
    final errors = validateAsset(input.data, s);
    if (errors.isNotEmpty) return Result.err(AppFailure.validation(errors.values.first, fields: errors));
    final change = input.data.value - existing.value;
    return Result.ok(preview(
      input,
      title: 'Save changes',
      summary: change.isZero
          ? 'Updated ${input.data.name.trim()}'
          : 'Updated ${input.data.name.trim()} to ${input.data.value.format()}',
      lines: [
        ..._lines(input.data),
        if (!change.isZero) PreviewLine('Net worth effect', change.format(sign: SignDisplay.always)),
      ],
    ));
  }

  @override
  Future<Result<Asset>> execute(UpdateAssetInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final existing = s.assets.firstWhere((a) => a.id == input.id);
    final d = input.data;
    final updated = existing.copyWith(
      name: d.name.trim(),
      type: d.type,
      value: d.value,
      valuedOn: d.valuedOn.dateOnly,
      note: () => d.note?.trim().isEmpty ?? true ? null : d.note!.trim(),
      updatedAt: env.clock.now(),
      version: existing.version + 1,
    );
    await env.repos.assets.save(updated);
    return Result.ok(updated);
  }
}

class DeleteAssetInput extends ActionInput {
  const DeleteAssetInput({required this.id});
  final String id;

  @override
  Map<String, Object?> toJson() => {'id': id};
}

class DeleteAssetAction extends FinancialAction<DeleteAssetInput, Asset> {
  const DeleteAssetAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'assets.delete',
        module: 'net_worth',
        title: 'Delete an asset',
        description: 'Removes an asset valuation. Net worth goes down by its value. Cash is not affected.',
        risk: ActionRisk.consequential,
        reversible: false,
        fields: [ActionFieldSpec('id', FieldKind.id, 'Asset id')],
      );

  @override
  DeleteAssetInput decode(Map<String, Object?> json) => DeleteAssetInput(id: In.str(json, 'id'));

  @override
  Result<ActionPreview> prepare(DeleteAssetInput input, FinanceSnapshot s, ActionEnvironment env) {
    final a = s.assets.where((x) => x.id == input.id).firstOrNull;
    if (a == null) return const Result.err(AppFailure.notFound('This asset no longer exists.'));
    return Result.ok(preview(
      input,
      title: 'Delete asset?',
      summary: 'Deleted ${a.name}',
      lines: [
        PreviewLine('Type', a.type.label),
        PreviewLine('Net worth effect', (-a.value).format(sign: SignDisplay.always), emphasis: true),
      ],
      warnings: const ['This cannot be undone. Your cash balance is not affected.'],
    ));
  }

  @override
  Future<Result<Asset>> execute(DeleteAssetInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final a = s.assets.firstWhere((x) => x.id == input.id);
    await env.repos.assets.delete(a.id);
    return Result.ok(a);
  }
}
