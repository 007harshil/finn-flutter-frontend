// Serialization models (DTOs) for every domain entity.
//
// Domain models never know about JSON. These codecs are used by local
// persistence, backup/export, and will be the starting point for API
// mappers when a backend is introduced (see docs/BACKEND_INTEGRATION.md).

import '../../core/persistence/entity_collection.dart';
import '../../core/persistence/json_utils.dart';
import '../../core/time/dates.dart';
import '../../core/time/frequency.dart';
import '../../features/accounts/domain/money_account.dart';
import '../../features/accounts/domain/transfer.dart';
import '../../features/alerts/domain/alert.dart';
import '../../features/budgets/domain/budget.dart';
import '../../features/categories/domain/category.dart';
import '../../features/emergency_fund/domain/emergency_fund.dart';
import '../../features/goals/domain/goal.dart';
import '../../features/loans/domain/loan.dart';
import '../../features/net_worth/domain/asset.dart';
import '../../features/pending/domain/pending_payment.dart';
import '../../features/settings/domain/financial_profile.dart';
import '../../features/subscriptions/domain/subscription.dart';
import '../../features/transactions/domain/transaction.dart';

/// Channel label for a legacy `paymentMethod` value (old device data and
/// payloads). `cash`, `other` and unknown values have no channel.
String? legacyChannelOf(Object? method) => switch (method) {
      'upi' => 'UPI',
      'bankTransfer' => 'Bank transfer',
      'card' => 'Card',
      'wallet' => 'Wallet',
      _ => null,
    };

abstract final class TransactionDto {
  static JsonMap toJson(Transaction t) => {
        'id': t.id,
        'type': t.type.name,
        'amountPaise': J.money(t.amount),
        'categoryId': t.categoryId,
        'date': J.date(t.date),
        'accountId': t.accountId,
        'channel': t.channel,
        'counterparty': t.counterparty,
        'note': t.note,
        'origin': t.origin.name,
        'originRefId': t.originRefId,
        'createdAt': J.instant(t.createdAt),
        'updatedAt': J.instant(t.updatedAt),
        'version': t.version,
      };

  static Transaction fromJson(JsonMap j) => Transaction(
        id: j['id'] as String,
        type: J.enumByName(TransactionType.values, j['type'], TransactionType.expense),
        amount: J.toMoney(j['amountPaise']),
        categoryId: j['categoryId'] as String,
        date: J.toDate(j['date']),
        // Old device data has no accountId: it belongs to the Cash account
        // and its payment method becomes the channel.
        accountId: (j['accountId'] as String?) ?? cashAccountId,
        channel: j.containsKey('channel') || j.containsKey('accountId')
            ? j['channel'] as String?
            : legacyChannelOf(j['paymentMethod']),
        counterparty: j['counterparty'] as String?,
        note: j['note'] as String?,
        origin: J.enumByName(TransactionOrigin.values, j['origin'], TransactionOrigin.manual),
        originRefId: j['originRefId'] as String?,
        createdAt: J.toInstant(j['createdAt']),
        updatedAt: J.toInstant(j['updatedAt']),
        version: (j['version'] as num?)?.toInt() ?? 1,
      );
}

abstract final class CategoryDto {
  static JsonMap toJson(TransactionCategory c) => {
        'id': c.id,
        'name': c.name,
        'type': c.type.name,
        'iconKey': c.iconKey,
        'colorIndex': c.colorIndex,
        'description': c.description,
        'isSystem': c.isSystem,
        'isArchived': c.isArchived,
        'isEssential': c.isEssential,
        'version': c.version,
      };

  static TransactionCategory fromJson(JsonMap j) => TransactionCategory(
        id: j['id'] as String,
        name: j['name'] as String,
        type: J.enumByName(TransactionType.values, j['type'], TransactionType.expense),
        iconKey: j['iconKey'] as String,
        colorIndex: (j['colorIndex'] as num).toInt(),
        description: (j['description'] as String?) ?? '',
        isSystem: (j['isSystem'] as bool?) ?? false,
        isArchived: (j['isArchived'] as bool?) ?? false,
        isEssential: (j['isEssential'] as bool?) ?? false,
        version: (j['version'] as num?)?.toInt() ?? 1,
      );
}

abstract final class BudgetDto {
  static JsonMap toJson(Budget b) => {
        'id': b.id,
        'categoryId': b.categoryId,
        'limitPaise': J.money(b.limit),
        'previousLimits': [
          for (final c in b.previousLimits) {'until': c.until.id, 'limitPaise': J.money(c.limit)},
        ],
        'status': b.status.name,
        'warningThresholdBps': b.warningThresholdBps,
        'note': b.note,
        'createdAt': J.instant(b.createdAt),
        'updatedAt': J.instant(b.updatedAt),
        'version': b.version,
      };

  static Budget fromJson(JsonMap j) => Budget(
        id: j['id'] as String,
        categoryId: j['categoryId'] as String,
        limit: J.toMoney(j['limitPaise']),
        status: J.enumByName(BudgetStatus.values, j['status'], BudgetStatus.active),
        warningThresholdBps: (j['warningThresholdBps'] as num?)?.toInt() ?? 8000,
        // Older data may carry a custom period; budgets are monthly now, so
        // those fields are ignored.
        previousLimits: [
          for (final c in ((j['previousLimits'] as List?) ?? const []).cast<Map>())
            if (MonthKey.tryParse(c['until'] as String?) case final until?)
              BudgetLimitChange(until: until, limit: J.toMoney(c['limitPaise'])),
        ],
        note: j['note'] as String?,
        createdAt: J.toInstant(j['createdAt']),
        updatedAt: J.toInstant(j['updatedAt']),
        version: (j['version'] as num?)?.toInt() ?? 1,
      );
}

abstract final class GoalDto {
  static JsonMap toJson(SavingsGoal g) => {
        'id': g.id,
        'name': g.name,
        'category': g.category.name,
        'targetPaise': J.money(g.target),
        'targetDate': g.targetDate == null ? null : J.date(g.targetDate!),
        'plannedMonthlyPaise': g.plannedMonthlyContribution?.paise,
        'colorIndex': g.colorIndex,
        'status': g.status.name,
        'note': g.note,
        'createdAt': J.instant(g.createdAt),
        'updatedAt': J.instant(g.updatedAt),
        'version': g.version,
      };

  static SavingsGoal fromJson(JsonMap j) => SavingsGoal(
        id: j['id'] as String,
        name: j['name'] as String,
        category: J.enumByName(GoalCategory.values, j['category'], GoalCategory.other),
        target: J.toMoney(j['targetPaise']),
        targetDate: J.toDateOrNull(j['targetDate']),
        plannedMonthlyContribution: J.toMoneyOrNull(j['plannedMonthlyPaise']),
        colorIndex: (j['colorIndex'] as num).toInt(),
        status: J.enumByName(GoalStatus.values, j['status'], GoalStatus.active),
        note: j['note'] as String?,
        createdAt: J.toInstant(j['createdAt']),
        updatedAt: J.toInstant(j['updatedAt']),
        version: (j['version'] as num?)?.toInt() ?? 1,
      );
}

abstract final class SavingsMovementDto {
  static JsonMap toJson(SavingsMovement m) => {
        'id': m.id,
        'bucketType': m.bucketType.name,
        'bucketId': m.bucketId,
        'kind': m.kind.name,
        'amountPaise': J.money(m.amount),
        'date': J.date(m.date),
        'note': m.note,
        'createdAt': J.instant(m.createdAt),
      };

  static SavingsMovement fromJson(JsonMap j) => SavingsMovement(
        id: j['id'] as String,
        bucketType: J.enumByName(SavingsBucketType.values, j['bucketType'], SavingsBucketType.goal),
        bucketId: j['bucketId'] as String,
        kind: J.enumByName(SavingsMovementKind.values, j['kind'], SavingsMovementKind.contribution),
        amount: J.toMoney(j['amountPaise']),
        date: J.toDate(j['date']),
        note: j['note'] as String?,
        createdAt: J.toInstant(j['createdAt']),
      );
}

abstract final class EmergencyPlanDto {
  static JsonMap toJson(EmergencyFundPlan? p) => p == null
      ? {'configured': false}
      : {
          'configured': true,
          'essentialMonthlyPaise': J.money(p.essentialMonthlyExpenses),
          'targetMonths': p.targetMonths,
          'targetOverridePaise': p.targetOverride?.paise,
          'updatedAt': J.instant(p.updatedAt),
        };

  static EmergencyFundPlan? fromJson(JsonMap j) => j['configured'] != true
      ? null
      : EmergencyFundPlan(
          essentialMonthlyExpenses: J.toMoney(j['essentialMonthlyPaise']),
          targetMonths: (j['targetMonths'] as num).toInt(),
          targetOverride: J.toMoneyOrNull(j['targetOverridePaise']),
          updatedAt: J.toInstant(j['updatedAt']),
        );
}

abstract final class LoanDto {
  static JsonMap toJson(Loan l) => {
        'id': l.id,
        'name': l.name,
        'counterparty': l.counterparty,
        'direction': l.direction.name,
        'structure': l.structure.name,
        'principalPaise': J.money(l.principal),
        'rateBps': l.rate.bps,
        'startDate': J.date(l.startDate),
        'firstDueDate': J.date(l.firstDueDate),
        'frequency': l.frequency.name,
        'tenureInstallments': l.tenureInstallments,
        'maturityDate': l.maturityDate == null ? null : J.date(l.maturityDate!),
        'prepaymentStrategy': l.prepaymentStrategy.name,
        'status': l.status.name,
        'disbursementTransactionId': l.disbursementTransactionId,
        'note': l.note,
        'createdAt': J.instant(l.createdAt),
        'updatedAt': J.instant(l.updatedAt),
        'version': l.version,
      };

  static Loan fromJson(JsonMap j) => Loan(
        id: j['id'] as String,
        name: j['name'] as String,
        counterparty: j['counterparty'] as String,
        direction: J.enumByName(LoanDirection.values, j['direction'], LoanDirection.borrowed),
        structure: J.enumByName(LoanStructure.values, j['structure'], LoanStructure.amortizing),
        principal: J.toMoney(j['principalPaise']),
        rate: InterestRate((j['rateBps'] as num).toInt()),
        startDate: J.toDate(j['startDate']),
        firstDueDate: J.toDate(j['firstDueDate']),
        frequency: J.enumByName(Frequency.values, j['frequency'], Frequency.monthly),
        tenureInstallments: (j['tenureInstallments'] as num?)?.toInt(),
        maturityDate: J.toDateOrNull(j['maturityDate']),
        prepaymentStrategy: J.enumByName(
            PrepaymentStrategy.values, j['prepaymentStrategy'], PrepaymentStrategy.reduceTenure),
        status: J.enumByName(LoanStatus.values, j['status'], LoanStatus.active),
        disbursementTransactionId: j['disbursementTransactionId'] as String?,
        note: j['note'] as String?,
        createdAt: J.toInstant(j['createdAt']),
        updatedAt: J.toInstant(j['updatedAt']),
        version: (j['version'] as num?)?.toInt() ?? 1,
      );
}

abstract final class LoanPaymentDto {
  static JsonMap toJson(LoanPayment p) => {
        'id': p.id,
        'loanId': p.loanId,
        'kind': p.kind.name,
        'date': J.date(p.date),
        'interestPaise': J.money(p.interestComponent),
        'principalPaise': J.money(p.principalComponent),
        'periodNumber': p.periodNumber,
        'transactionId': p.transactionId,
        'note': p.note,
        'createdAt': J.instant(p.createdAt),
      };

  static LoanPayment fromJson(JsonMap j) => LoanPayment(
        id: j['id'] as String,
        loanId: j['loanId'] as String,
        kind: J.enumByName(LoanPaymentKind.values, j['kind'], LoanPaymentKind.installment),
        date: J.toDate(j['date']),
        interestComponent: J.toMoney(j['interestPaise']),
        principalComponent: J.toMoney(j['principalPaise']),
        periodNumber: (j['periodNumber'] as num?)?.toInt(),
        transactionId: j['transactionId'] as String?,
        note: j['note'] as String?,
        createdAt: J.toInstant(j['createdAt']),
      );
}

abstract final class SubscriptionDto {
  static JsonMap toJson(Subscription s) => {
        'id': s.id,
        'name': s.name,
        'amountPaise': J.money(s.amount),
        'categoryId': s.categoryId,
        'frequency': s.frequency.name,
        'nextDueDate': J.date(s.nextDueDate),
        'startDate': s.startDate == null ? null : J.date(s.startDate!),
        'status': s.status.name,
        'autoRenews': s.autoRenews,
        'accountId': s.accountId,
        'note': s.note,
        'createdAt': J.instant(s.createdAt),
        'updatedAt': J.instant(s.updatedAt),
        'version': s.version,
      };

  static Subscription fromJson(JsonMap j) => Subscription(
        id: j['id'] as String,
        name: j['name'] as String,
        amount: J.toMoney(j['amountPaise']),
        categoryId: j['categoryId'] as String,
        frequency: J.enumByName(Frequency.values, j['frequency'], Frequency.monthly),
        nextDueDate: J.toDate(j['nextDueDate']),
        startDate: J.toDateOrNull(j['startDate']),
        status: J.enumByName(SubscriptionStatus.values, j['status'], SubscriptionStatus.active),
        autoRenews: (j['autoRenews'] as bool?) ?? true,
        accountId: (j['accountId'] as String?) ?? (j['paymentMethod'] != null ? cashAccountId : null),
        note: j['note'] as String?,
        createdAt: J.toInstant(j['createdAt']),
        updatedAt: J.toInstant(j['updatedAt']),
        version: (j['version'] as num?)?.toInt() ?? 1,
      );
}

abstract final class PendingDto {
  static JsonMap toJson(PendingPayment p) => {
        'id': p.id,
        'counterparty': p.counterparty,
        'direction': p.direction.name,
        'kind': p.kind.name,
        'originalPaise': J.money(p.originalAmount),
        'purpose': p.purpose,
        'createdDate': J.date(p.createdDate),
        'notes': p.notes,
        'isCancelled': p.isCancelled,
        'createdAt': J.instant(p.createdAt),
        'updatedAt': J.instant(p.updatedAt),
        'version': p.version,
        'link': p.link == null ? null : PendingLinkDto.toJson(p.link!),
        'split': p.split == null ? null : PendingSplitDto.toJson(p.split!),
      };

  static PendingPayment fromJson(JsonMap j) => PendingPayment(
        id: j['id'] as String,
        counterparty: j['counterparty'] as String,
        direction: J.enumByName(PendingDirection.values, j['direction'], PendingDirection.iOwe),
        kind: J.enumByName(PendingKind.values, j['kind'], PendingKind.other),
        originalAmount: J.toMoney(j['originalPaise']),
        purpose: j['purpose'] as String,
        createdDate: J.toDate(j['createdDate']),
        notes: j['notes'] as String?,
        isCancelled: (j['isCancelled'] as bool?) ?? false,
        createdAt: J.toInstant(j['createdAt']),
        updatedAt: J.toInstant(j['updatedAt']),
        version: (j['version'] as num?)?.toInt() ?? 1,
        link: j['link'] == null ? null : PendingLinkDto.fromJson((j['link'] as Map).cast<String, Object?>()),
        split: j['split'] == null ? null : PendingSplitDto.fromJson((j['split'] as Map).cast<String, Object?>()),
      );
}

abstract final class PendingSplitDto {
  static JsonMap toJson(PendingSplit s) => {
        'id': s.id,
        'method': s.method.name,
        'includesMe': s.includesMe,
        'mySharePaise': J.money(s.myShare),
        'part': s.part,
      };

  static PendingSplit fromJson(JsonMap j) => PendingSplit(
        id: j['id'] as String,
        method: J.enumByName(SplitMethod.values, j['method'], SplitMethod.equally),
        includesMe: (j['includesMe'] as bool?) ?? false,
        myShare: J.toMoney(j['mySharePaise'] ?? 0),
        part: (j['part'] as num?)?.toInt(),
      );
}

abstract final class SettlementDto {
  static JsonMap toJson(PendingSettlement s) => {
        'id': s.id,
        'pendingId': s.pendingId,
        'amountPaise': J.money(s.amount),
        'date': J.date(s.date),
        'accountId': s.accountId,
        'channel': s.channel,
        'transactionId': s.transactionId,
        'note': s.note,
        'createdAt': J.instant(s.createdAt),
      };

  static PendingSettlement fromJson(JsonMap j) => PendingSettlement(
        id: j['id'] as String,
        pendingId: j['pendingId'] as String,
        amount: J.toMoney(j['amountPaise']),
        date: J.toDate(j['date']),
        accountId: (j['accountId'] as String?) ?? (j['method'] != null || j['transactionId'] != null ? cashAccountId : null),
        channel: j.containsKey('channel') || j.containsKey('accountId')
            ? j['channel'] as String?
            : legacyChannelOf(j['method']),
        transactionId: j['transactionId'] as String?,
        note: j['note'] as String?,
        createdAt: J.toInstant(j['createdAt']),
      );
}

abstract final class PendingLinkDto {
  static JsonMap toJson(PendingLink l) => {
        'userId': l.userId,
        'handle': l.handle,
        'sharedId': l.sharedId,
        'createdByMe': l.createdByMe,
      };

  static PendingLink fromJson(JsonMap j) => PendingLink(
        userId: j['userId'] as String,
        handle: j['handle'] as String,
        sharedId: j['sharedId'] as String,
        createdByMe: (j['createdByMe'] as bool?) ?? true,
      );
}

/// The other person's side of a shared pending item (mock network).
abstract final class MirrorEntryDto {
  static JsonMap toJson(MirrorEntry m) => {
        'ownerId': m.ownerId,
        'payment': PendingDto.toJson(m.payment),
        'settlements': [for (final s in m.settlements) SettlementDto.toJson(s)],
      };

  static MirrorEntry fromJson(JsonMap j) => MirrorEntry(
        ownerId: j['ownerId'] as String,
        payment: PendingDto.fromJson((j['payment'] as Map).cast<String, Object?>()),
        settlements: [
          for (final s in (j['settlements'] as List? ?? const [])) SettlementDto.fromJson((s as Map).cast<String, Object?>()),
        ],
      );
}

abstract final class AssetDto {
  static JsonMap toJson(Asset a) => {
        'id': a.id,
        'name': a.name,
        'type': a.type.name,
        'valuePaise': J.money(a.value),
        'valuedOn': J.date(a.valuedOn),
        'note': a.note,
        'createdAt': J.instant(a.createdAt),
        'updatedAt': J.instant(a.updatedAt),
        'version': a.version,
      };

  static Asset fromJson(JsonMap j) => Asset(
        id: j['id'] as String,
        name: j['name'] as String,
        type: J.enumByName(AssetType.values, j['type'], AssetType.other),
        value: J.toMoney(j['valuePaise']),
        valuedOn: J.toDate(j['valuedOn']),
        note: j['note'] as String?,
        createdAt: J.toInstant(j['createdAt']),
        updatedAt: J.toInstant(j['updatedAt']),
        version: (j['version'] as num?)?.toInt() ?? 1,
      );
}

abstract final class MoneyAccountDto {
  static JsonMap toJson(MoneyAccount a) => {
        'id': a.id,
        'name': a.name,
        'kind': a.kind.name,
        'institution': a.institution,
        'last4': a.last4,
        'openingPaise': J.money(a.opening),
        'openingDate': J.date(a.openingDate),
        'creditLimitPaise': a.creditLimit == null ? null : J.money(a.creditLimit!),
        'isDefault': a.isDefault,
        'isArchived': a.isArchived,
        'sortOrder': a.sortOrder,
        'note': a.note,
        'createdAt': J.instant(a.createdAt),
        'updatedAt': J.instant(a.updatedAt),
        'version': a.version,
      };

  static MoneyAccount fromJson(JsonMap j) => MoneyAccount(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: J.enumByName(MoneyAccountKind.values, j['kind'], MoneyAccountKind.bank),
        institution: j['institution'] as String?,
        last4: j['last4'] as String?,
        opening: J.toMoney(j['openingPaise']),
        openingDate: J.toDate(j['openingDate']),
        creditLimit: J.toMoneyOrNull(j['creditLimitPaise']),
        isDefault: (j['isDefault'] as bool?) ?? false,
        isArchived: (j['isArchived'] as bool?) ?? false,
        sortOrder: (j['sortOrder'] as num?)?.toInt() ?? 0,
        note: j['note'] as String?,
        createdAt: J.toInstant(j['createdAt']),
        updatedAt: J.toInstant(j['updatedAt']),
        version: (j['version'] as num?)?.toInt() ?? 1,
      );
}

abstract final class TransferDto {
  static JsonMap toJson(Transfer t) => {
        'id': t.id,
        'fromAccountId': t.fromAccountId,
        'toAccountId': t.toAccountId,
        'amountPaise': J.money(t.amount),
        'date': J.date(t.date),
        'channel': t.channel,
        'note': t.note,
        'createdAt': J.instant(t.createdAt),
        'updatedAt': J.instant(t.updatedAt),
        'version': t.version,
      };

  static Transfer fromJson(JsonMap j) => Transfer(
        id: j['id'] as String,
        fromAccountId: j['fromAccountId'] as String,
        toAccountId: j['toAccountId'] as String,
        amount: J.toMoney(j['amountPaise']),
        date: J.toDate(j['date']),
        channel: j['channel'] as String?,
        note: j['note'] as String?,
        createdAt: J.toInstant(j['createdAt']),
        updatedAt: J.toInstant(j['updatedAt']),
        version: (j['version'] as num?)?.toInt() ?? 1,
      );
}

abstract final class ProfileDto {
  static JsonMap toJson(FinancialProfile? p) => p == null
      ? {'exists': false}
      : {
          'exists': true,
          'displayName': p.displayName,
          'openingPaise': J.money(p.openingBalance),
          'openingDate': J.date(p.openingDate),
          'monthlyIncomeEstimatePaise': p.monthlyIncomeEstimate?.paise,
        };

  static FinancialProfile? fromJson(JsonMap j) => j['exists'] != true
      ? null
      : FinancialProfile(
          displayName: j['displayName'] as String,
          openingBalance: J.toMoney(j['openingPaise']),
          openingDate: J.toDate(j['openingDate']),
          monthlyIncomeEstimate: J.toMoneyOrNull(j['monthlyIncomeEstimatePaise']),
        );
}

abstract final class AlertInboxDto {
  static JsonMap toJson(AlertInboxState s) => {
        'read': s.readKeys.toList(),
        'dismissed': s.dismissedKeys.toList(),
      };

  static AlertInboxState fromJson(JsonMap j) => AlertInboxState(
        readKeys: ((j['read'] as List?) ?? const []).cast<String>().toSet(),
        dismissedKeys: ((j['dismissed'] as List?) ?? const []).cast<String>().toSet(),
      );
}
