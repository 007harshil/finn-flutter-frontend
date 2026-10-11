import 'package:flutter/foundation.dart';

import 'pending_payment.dart';

/// Another person who uses FiNN, found through the user directory.
@immutable
class FinnUser {
  const FinnUser({required this.id, required this.name, required this.handle, this.phoneHint});

  final String id;
  final String name;

  /// Public handle, e.g. "@ramesh.k".
  final String handle;

  /// Last digits of the registered phone ("•• 4821") to tell people with
  /// the same name apart. Never the full number.
  final String? phoneHint;

  @override
  bool operator ==(Object other) => other is FinnUser && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Ties a pending item to a FiNN user. A shared item is a double entry: the
/// same obligation lives in both people's accounts, mirrored (my "I owe
/// Ramesh ₹1,000" is Ramesh's "Harshil owes me ₹1,000"). Both entries carry
/// the same [sharedId].
@immutable
class PendingLink {
  const PendingLink({
    required this.userId,
    required this.handle,
    required this.sharedId,
    required this.createdByMe,
  });

  /// The other person.
  final String userId;
  final String handle;

  /// Same on both sides of the double entry.
  final String sharedId;

  /// True when this account created the item. Only the creator can edit
  /// the details or delete it; either person can record a settlement.
  final bool createdByMe;

  PendingLink flipped({required String myUserId, required String myHandle}) =>
      PendingLink(userId: myUserId, handle: myHandle, sharedId: sharedId, createdByMe: !createdByMe);

  @override
  bool operator ==(Object other) =>
      other is PendingLink &&
      other.userId == userId &&
      other.handle == handle &&
      other.sharedId == sharedId &&
      other.createdByMe == createdByMe;

  @override
  int get hashCode => Object.hash(userId, handle, sharedId, createdByMe);
}

/// The other side of a shared item: what [ownerId]'s FiNN holds, from their
/// point of view (direction reversed, counterparty = this user).
@immutable
class MirrorEntry {
  const MirrorEntry({required this.ownerId, required this.payment, required this.settlements});

  final String ownerId;
  final PendingPayment payment;

  /// Newest first. Mirrored settlements never move the owner's cash here;
  /// their own app decides that.
  final List<PendingSettlement> settlements;

  String get sharedId => payment.link!.sharedId;

  /// Storage id: one entry per owner and shared item.
  String get key => keyOf(ownerId, sharedId);

  static String keyOf(String ownerId, String sharedId) => '$ownerId:$sharedId';

  PendingView view(DateTime today) => const PendingCalculator().view(payment, settlements, today);

  @override
  bool operator ==(Object other) =>
      other is MirrorEntry &&
      other.ownerId == ownerId &&
      other.payment == payment &&
      listEquals(other.settlements, settlements);

  @override
  int get hashCode => Object.hash(ownerId, payment, Object.hashAll(settlements));
}

/// Builds the other person's side of [p] (with its [settlements]).
MirrorEntry mirrorOf(PendingPayment p, List<PendingSettlement> settlements, {required FinnUser me}) {
  final link = p.link!;
  return MirrorEntry(
    ownerId: link.userId,
    payment: PendingPayment(
      id: 'mir_${link.sharedId}',
      counterparty: me.name,
      direction: p.direction == PendingDirection.iOwe ? PendingDirection.owedToMe : PendingDirection.iOwe,
      kind: _mirrorKind(p.kind),
      originalAmount: p.originalAmount,
      purpose: p.purpose,
      createdDate: p.createdDate,
      notes: p.notes,
      isCancelled: p.isCancelled,
      createdAt: p.createdAt,
      updatedAt: p.updatedAt,
      version: p.version,
      link: link.flipped(myUserId: me.id, myHandle: me.handle),
    ),
    settlements: [
      for (final s in settlements)
        PendingSettlement(
          id: 'mir_${s.id}',
          pendingId: 'mir_${link.sharedId}',
          amount: s.amount,
          date: s.date,
          method: s.method,
          note: s.note,
          createdAt: s.createdAt,
        ),
    ],
  );
}

/// "Borrowed" on one side is "lent" on the other.
PendingKind _mirrorKind(PendingKind k) => switch (k) {
      PendingKind.borrowed => PendingKind.lent,
      PendingKind.lent => PendingKind.borrowed,
      _ => k,
    };
