import 'package:flutter/foundation.dart';

import '../../../core/money/money.dart';

enum AssetType {
  bankDeposit('Bank & FD', 'landmark'),
  investment('Investments', 'trendingUp'),
  retirement('Retirement (EPF/PPF/NPS)', 'shieldCheck'),
  gold('Gold & jewellery', 'gem'),
  property('Property', 'home'),
  vehicle('Vehicle', 'car'),
  other('Other', 'package');

  const AssetType(this.label, this.iconKey);
  final String label;
  final String iconKey;
}

/// A user-managed asset valuation. Cash tracked in FiNN is *not* an asset
/// entry, which keeps the net-worth calculation free of double counting.
@immutable
class Asset {
  const Asset({
    required this.id,
    required this.name,
    required this.type,
    required this.value,
    required this.valuedOn,
    required this.createdAt,
    required this.updatedAt,
    this.note,
    this.version = 1,
  });

  final String id;
  final String name;
  final AssetType type;
  final Money value;

  /// Date of the valuation.
  final DateTime valuedOn;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;

  Asset copyWith({
    String? name,
    AssetType? type,
    Money? value,
    DateTime? valuedOn,
    String? Function()? note,
    DateTime? updatedAt,
    int? version,
  }) =>
      Asset(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        value: value ?? this.value,
        valuedOn: valuedOn ?? this.valuedOn,
        note: note != null ? note() : this.note,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        version: version ?? this.version,
      );

  @override
  bool operator ==(Object other) => other is Asset && other.id == id && other.version == version;

  @override
  int get hashCode => Object.hash(id, version);
}
