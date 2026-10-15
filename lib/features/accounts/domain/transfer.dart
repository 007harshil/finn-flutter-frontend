import 'package:flutter/foundation.dart';

import '../../../core/money/money.dart';

/// Money moved between two of the user's own accounts (ATM withdrawal,
/// credit-card bill payment). Never income or spending.
@immutable
class Transfer {
  const Transfer({
    required this.id,
    required this.fromAccountId,
    required this.toAccountId,
    required this.amount,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
    this.channel,
    this.note,
    this.version = 1,
  });

  final String id;
  final String fromAccountId;
  final String toAccountId;

  /// Always positive.
  final Money amount;
  final DateTime date;
  final String? channel;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;

  Transfer copyWith({
    String? fromAccountId,
    String? toAccountId,
    Money? amount,
    DateTime? date,
    String? Function()? channel,
    String? Function()? note,
    DateTime? updatedAt,
    int? version,
  }) =>
      Transfer(
        id: id,
        fromAccountId: fromAccountId ?? this.fromAccountId,
        toAccountId: toAccountId ?? this.toAccountId,
        amount: amount ?? this.amount,
        date: date ?? this.date,
        channel: channel != null ? channel() : this.channel,
        note: note != null ? note() : this.note,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        version: version ?? this.version,
      );

  @override
  bool operator ==(Object other) => other is Transfer && other.id == id && other.version == version;

  @override
  int get hashCode => Object.hash(id, version);
}
