import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../data/dto/dtos.dart';
import '../../../finance/finance_snapshot.dart';
import '../../../finance/ledger.dart';
import '../../goals/domain/goal.dart';
import '../../loans/domain/loan.dart';
import '../../pending/domain/pending_payment.dart';
import '../../transactions/domain/transaction.dart';

/// Groups of records a user can export.
enum ExportModule {
  transactions('Transactions', 'Income and spending in the period'),
  budgets('Budgets', 'Limits with spending in the current period'),
  goals('Goals & savings', 'Goals plus contributions and withdrawals'),
  emergencyFund('Emergency fund', 'Plan plus contributions and withdrawals'),
  loans('Loans', 'Loans plus repayments'),
  subscriptions('Subscriptions', 'Recurring commitments'),
  pending('Pending payments', 'Money to pay or collect plus settlements'),
  assets('Assets', 'Your asset valuations');

  const ExportModule(this.label, this.description);
  final String label;
  final String description;
}

enum ExportFormat {
  csv('CSV', 'One spreadsheet file per table'),
  json('JSON', 'One complete, machine-readable file'),
  pdf('PDF', 'A printable summary report');

  const ExportFormat(this.label, this.description);
  final String label;
  final String description;
}

/// What to export.
@immutable
class ExportRequest {
  const ExportRequest({
    required this.range,
    required this.modules,
    required this.format,
    this.categoryIds,
  });

  /// Applies to dated records: transactions, payments, movements and
  /// settlements. Ongoing records (loans, budgets, assets…) are exported
  /// in full.
  final DateRange range;
  final Set<ExportModule> modules;

  /// When non-null, only transactions in these categories are exported.
  final Set<String>? categoryIds;
  final ExportFormat format;
}

/// One generated file.
@immutable
class ExportArtifact {
  const ExportArtifact({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    required this.recordCount,
  });

  final String fileName;
  final String mimeType;
  final Uint8List bytes;

  /// Number of data records (rows) in the file.
  final int recordCount;
}

/// Above this many transactions, generation runs off the UI isolate.
const int exportIsolateThreshold = 2000;

/// Maximum transaction rows printed in the PDF report.
const int pdfTransactionRowLimit = 500;

/// Top-level entry point usable with `compute` / `Isolate.run`.
Future<List<ExportArtifact>> generateExport(ExportJob job) =>
    const ExportService().generate(job.snapshot, job.request, exportedAt: job.exportedAt);

/// Message passed to [generateExport] across isolates.
@immutable
class ExportJob {
  const ExportJob(this.snapshot, this.request, this.exportedAt);
  final FinanceSnapshot snapshot;
  final ExportRequest request;
  final DateTime exportedAt;
}

/// Turns a [FinanceSnapshot] into export files. Pure: no I/O, no Flutter
/// bindings, so it can run on a background isolate.
class ExportService {
  const ExportService();

  // ---------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------

  List<Transaction> transactionsFor(FinanceSnapshot s, ExportRequest r) {
    final cats = r.categoryIds;
    // Snapshot transactions are newest first; exports read oldest first.
    return s.transactions.reversed
        .where((t) => r.range.contains(t.date) && (cats == null || cats.contains(t.categoryId)))
        .toList();
  }

  List<SavingsMovement> _movements(FinanceSnapshot s, ExportRequest r, SavingsBucketType type) =>
      s.savingsMovements.where((m) => m.bucketType == type && r.range.contains(m.date)).toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  List<LoanPayment> _loanPayments(FinanceSnapshot s, ExportRequest r) =>
      s.loanPayments.where((p) => r.range.contains(p.date)).toList()..sort((a, b) => a.date.compareTo(b.date));

  List<PendingSettlement> _settlements(FinanceSnapshot s, ExportRequest r) =>
      s.settlements.where((x) => r.range.contains(x.date)).toList()..sort((a, b) => a.date.compareTo(b.date));

  /// Number of records each module would export for [r] (format ignored).
  Map<ExportModule, int> counts(FinanceSnapshot s, ExportRequest r) => {
        for (final m in ExportModule.values) m: _count(s, r, m),
      };

  int _count(FinanceSnapshot s, ExportRequest r, ExportModule m) => switch (m) {
        ExportModule.transactions => transactionsFor(s, r).length,
        ExportModule.budgets => s.budgets.length,
        ExportModule.goals => s.goals.length + _movements(s, r, SavingsBucketType.goal).length,
        ExportModule.emergencyFund =>
          (s.emergencyPlan == null ? 0 : 1) + _movements(s, r, SavingsBucketType.emergencyFund).length,
        ExportModule.loans => s.loans.length + _loanPayments(s, r).length,
        ExportModule.subscriptions => s.subscriptions.length,
        ExportModule.pending => s.pending.length + _settlements(s, r).length,
        ExportModule.assets => s.assets.length,
      };

  /// Generates the files for [r].
  Future<List<ExportArtifact>> generate(FinanceSnapshot s, ExportRequest r, {required DateTime exportedAt}) async {
    if (r.modules.isEmpty) return const [];
    return switch (r.format) {
      ExportFormat.csv => buildCsv(s, r),
      ExportFormat.json => [buildJson(s, r, exportedAt: exportedAt)],
      ExportFormat.pdf => [await buildPdf(s, r, exportedAt: exportedAt)],
    };
  }

  String _suffix(ExportRequest r) => '${DateFormats.iso.format(r.range.start)}_to_${DateFormats.iso.format(r.range.end)}';

  // ---------------------------------------------------------------------
  // CSV
  // ---------------------------------------------------------------------

  /// One CSV per table (modules with child records produce two files).
  List<ExportArtifact> buildCsv(FinanceSnapshot s, ExportRequest r) {
    final out = <ExportArtifact>[];
    final suffix = _suffix(r);
    void add(String table, List<String> header, List<List<Object?>> rows) {
      out.add(ExportArtifact(
        fileName: 'finn_${table}_$suffix.csv',
        mimeType: 'text/csv',
        bytes: Uint8List.fromList(utf8.encode(Csv.encode(header, rows))),
        recordCount: rows.length,
      ));
    }

    String cat(String id) => s.category(id)?.name ?? 'Uncategorised';
    String d(DateTime? v) => v == null ? '' : DateFormats.iso.format(v);
    String amt(Money m) => m.toDecimalString();
    String fmt(Money m) => MoneyFormatter.format(m, decimals: DecimalDisplay.always);

    for (final m in ExportModule.values.where(r.modules.contains)) {
      switch (m) {
        case ExportModule.transactions:
          add('transactions', const [
            'date', 'type', 'category', 'amount', 'amount_formatted', 'signed_amount', //
            'payment_method', 'counterparty', 'note', 'source', 'id',
          ], [
            for (final t in transactionsFor(s, r))
              [
                d(t.date), t.type.label, Csv.text(cat(t.categoryId)), amt(t.amount), fmt(t.amount),
                amt(t.signedAmount), t.paymentMethod?.label ?? '', Csv.text(t.counterparty), Csv.text(t.note),
                t.origin.label, t.id,
              ],
          ]);
        case ExportModule.budgets:
          final usage = {for (final u in s.budgetUsages) u.budget.id: u};
          add('budgets', const [
            'category', 'limit', 'limit_formatted', 'period', 'current_period_start', 'current_period_end', //
            'spent_in_period', 'spent_formatted', 'status', 'health', 'id',
          ], [
            for (final b in s.budgets)
              [
                Csv.text(cat(b.categoryId)), amt(b.limit), fmt(b.limit), 'Monthly',
                d(usage[b.id]?.period.start), d(usage[b.id]?.period.end),
                amt(usage[b.id]?.spent ?? Money.zero), fmt(usage[b.id]?.spent ?? Money.zero),
                b.status.name, usage[b.id]?.health.label ?? '', b.id,
              ],
          ]);
        case ExportModule.goals:
          final progress = {for (final g in s.goalProgress) g.goal.id: g};
          final goalNames = {for (final g in s.goals) g.id: g.name};
          add('goals', const [
            'name', 'category', 'target', 'target_formatted', 'saved', 'saved_formatted', //
            'target_date', 'status', 'id',
          ], [
            for (final g in s.goals)
              [
                Csv.text(g.name), g.category.label, amt(g.target), fmt(g.target),
                amt(progress[g.id]?.saved ?? Money.zero), fmt(progress[g.id]?.saved ?? Money.zero),
                d(g.targetDate), g.status.name, g.id,
              ],
          ]);
          add('goal_movements', const ['date', 'goal', 'kind', 'amount', 'amount_formatted', 'signed_amount', 'note', 'id'], [
            for (final mv in _movements(s, r, SavingsBucketType.goal))
              [
                d(mv.date), Csv.text(goalNames[mv.bucketId] ?? 'Deleted goal'), mv.kind.label, amt(mv.amount),
                fmt(mv.amount), amt(mv.signedAmount), Csv.text(mv.note), mv.id,
              ],
          ]);
        case ExportModule.emergencyFund:
          add('emergency_fund', const ['date', 'kind', 'amount', 'amount_formatted', 'signed_amount', 'note', 'id'], [
            for (final mv in _movements(s, r, SavingsBucketType.emergencyFund))
              [d(mv.date), mv.kind.label, amt(mv.amount), fmt(mv.amount), amt(mv.signedAmount), Csv.text(mv.note), mv.id],
          ]);
        case ExportModule.loans:
          final states = {for (final l in s.loanStates) l.loan.id: l};
          final loanNames = {for (final l in s.loans) l.id: l.name};
          add('loans', const [
            'name', 'counterparty', 'direction', 'structure', 'principal', 'principal_formatted', //
            'outstanding', 'outstanding_formatted', 'interest_rate_pct', 'start_date', 'status', 'id',
          ], [
            for (final l in s.loans)
              [
                Csv.text(l.name), Csv.text(l.counterparty), l.direction.label, l.structure.label, amt(l.principal),
                fmt(l.principal), amt(states[l.id]?.outstanding ?? Money.zero),
                fmt(states[l.id]?.outstanding ?? Money.zero), (l.rate.bps / 100).toStringAsFixed(2),
                d(l.startDate), l.status.name, l.id,
              ],
          ]);
          add('loan_payments', const [
            'date', 'loan', 'kind', 'total', 'total_formatted', 'principal', 'interest', 'note', 'id',
          ], [
            for (final p in _loanPayments(s, r))
              [
                d(p.date), Csv.text(loanNames[p.loanId] ?? 'Deleted loan'), p.kind.label, amt(p.total), fmt(p.total),
                amt(p.principalComponent), amt(p.interestComponent), Csv.text(p.note), p.id,
              ],
          ]);
        case ExportModule.subscriptions:
          add('subscriptions', const [
            'name', 'category', 'amount', 'amount_formatted', 'frequency', 'monthly_equivalent', //
            'next_due_date', 'status', 'payment_method', 'id',
          ], [
            for (final x in s.subscriptions)
              [
                Csv.text(x.name), Csv.text(cat(x.categoryId)), amt(x.amount), fmt(x.amount), x.frequency.label,
                amt(x.monthlyEquivalent), d(x.nextDueDate), x.status.label, x.paymentMethod?.label ?? '', x.id,
              ],
          ]);
        case ExportModule.pending:
          final views = {for (final v in s.pendingViews) v.payment.id: v};
          final names = {for (final p in s.pending) p.id: p.counterparty};
          add('pending', const [
            'counterparty', 'direction', 'kind', 'purpose', 'original_amount', 'original_formatted', //
            'outstanding', 'outstanding_formatted', 'created_date', 'days_open', 'status', 'id',
          ], [
            for (final p in s.pending)
              [
                Csv.text(p.counterparty), p.direction.label, p.kind.label, Csv.text(p.purpose), amt(p.originalAmount),
                fmt(p.originalAmount), amt(views[p.id]?.outstanding ?? Money.zero),
                fmt(views[p.id]?.outstanding ?? Money.zero), d(p.createdDate), '${views[p.id]?.daysOpen ?? ''}',
                views[p.id]?.status.label ?? '', p.id,
              ],
          ]);
          add('pending_settlements', const ['date', 'counterparty', 'amount', 'amount_formatted', 'method', 'note', 'id'], [
            for (final x in _settlements(s, r))
              [
                d(x.date), Csv.text(names[x.pendingId] ?? 'Deleted record'), amt(x.amount), fmt(x.amount),
                x.method?.label ?? '', Csv.text(x.note), x.id,
              ],
          ]);
        case ExportModule.assets:
          add('assets', const ['name', 'type', 'value', 'value_formatted', 'valued_on', 'note', 'id'], [
            for (final a in s.assets)
              [Csv.text(a.name), a.type.label, amt(a.value), fmt(a.value), d(a.valuedOn), Csv.text(a.note), a.id],
          ]);
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------
  // JSON
  // ---------------------------------------------------------------------

  /// A single JSON document using the persistence DTOs (money as integer
  /// paise, dates as `yyyy-MM-dd`).
  ExportArtifact buildJson(FinanceSnapshot s, ExportRequest r, {required DateTime exportedAt}) {
    var count = 0;
    List<Map<String, Object?>> rows<T>(Iterable<T> items, Map<String, Object?> Function(T) enc) {
      final list = items.map(enc).toList();
      count += list.length;
      return list;
    }

    final data = <String, Object?>{};
    final has = r.modules.contains;
    if (has(ExportModule.transactions)) {
      final txs = transactionsFor(s, r);
      final usedCats = txs.map((t) => t.categoryId).toSet();
      data['categories'] = s.categories.where((c) => usedCats.contains(c.id)).map(CategoryDto.toJson).toList();
      data['transactions'] = rows(txs, TransactionDto.toJson);
    }
    if (has(ExportModule.budgets)) data['budgets'] = rows(s.budgets, BudgetDto.toJson);
    if (has(ExportModule.goals)) {
      data['goals'] = rows(s.goals, GoalDto.toJson);
      data['goalMovements'] = rows(_movements(s, r, SavingsBucketType.goal), SavingsMovementDto.toJson);
    }
    if (has(ExportModule.emergencyFund)) {
      if (s.emergencyPlan != null) count++;
      data['emergencyFund'] = {
        'plan': EmergencyPlanDto.toJson(s.emergencyPlan),
        'movements': rows(_movements(s, r, SavingsBucketType.emergencyFund), SavingsMovementDto.toJson),
      };
    }
    if (has(ExportModule.loans)) {
      data['loans'] = rows(s.loans, LoanDto.toJson);
      data['loanPayments'] = rows(_loanPayments(s, r), LoanPaymentDto.toJson);
    }
    if (has(ExportModule.subscriptions)) data['subscriptions'] = rows(s.subscriptions, SubscriptionDto.toJson);
    if (has(ExportModule.pending)) {
      data['pending'] = rows(s.pending, PendingDto.toJson);
      data['settlements'] = rows(_settlements(s, r), SettlementDto.toJson);
    }
    if (has(ExportModule.assets)) data['assets'] = rows(s.assets, AssetDto.toJson);

    final doc = <String, Object?>{
      'exportedAt': exportedAt.toIso8601String(),
      'app': 'FiNN',
      'version': 1,
      'range': {'start': DateFormats.iso.format(r.range.start), 'end': DateFormats.iso.format(r.range.end)},
      'modules': [for (final m in ExportModule.values.where(has)) m.name],
      if (r.categoryIds != null) 'categoryIds': r.categoryIds!.toList()..sort(),
      'conventions': {'money': 'integer paise (₹1 = 100 paise)', 'dates': 'yyyy-MM-dd'},
      'data': data,
    };
    return ExportArtifact(
      fileName: 'finn_export_${_suffix(r)}.json',
      mimeType: 'application/json',
      bytes: Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(doc))),
      recordCount: count,
    );
  }

  // ---------------------------------------------------------------------
  // PDF
  // ---------------------------------------------------------------------

  /// A printable summary report. Uses the built-in Helvetica font, which
  /// has no rupee glyph, so amounts are written as "Rs.".
  Future<ExportArtifact> buildPdf(FinanceSnapshot s, ExportRequest r, {required DateTime exportedAt}) async {
    final has = r.modules.contains;
    final txs = transactionsFor(s, r);
    final summary = const CashFlowCalculator().summarize(txs, r.range);
    var count = 0;

    String rs(Money m) {
      final body = MoneyFormatter.format(m.abs(), withSymbol: false, decimals: DecimalDisplay.always);
      return '${m.isNegative ? '-' : ''}Rs. $body';
    }

    String d(DateTime? v) => v == null ? '-' : DateFormats.dayMonthYear.format(v);
    final period = '${d(r.range.start)} - ${d(r.range.end)}';

    final regularFont = pw.Font.helvetica();
    final boldFont = pw.Font.helveticaBold();
    final base = pw.TextStyle(font: regularFont, fontSize: 9);
    final bold = pw.TextStyle(font: boldFont, fontSize: 9);
    final muted = base.copyWith(color: PdfColors.grey700);
    const navy = PdfColor.fromInt(0xFF0F1B33);

    pw.Widget heading(String text) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
          child: pw.Text(pdfSafe(text), style: bold.copyWith(fontSize: 13, color: navy)),
        );

    pw.Widget table(List<String> headers, List<List<String>> data, {Set<int> numeric = const {}}) {
      count += data.length;
      return pw.TableHelper.fromTextArray(
        headers: headers.map(pdfSafe).toList(),
        data: [for (final row in data) row.map(pdfSafe).toList()],
        headerStyle: bold.copyWith(color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: navy),
        cellStyle: base,
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        cellAlignments: {for (final i in numeric) i: pw.Alignment.centerRight},
        headerAlignments: {for (final i in numeric) i: pw.Alignment.centerRight},
        border: null,
      );
    }

    pw.Widget stat(String label, String value) => pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(4)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(pdfSafe(label.toUpperCase()), style: muted.copyWith(fontSize: 7)),
              pw.SizedBox(height: 3),
              pw.Text(pdfSafe(value), style: bold.copyWith(fontSize: 12)),
            ]),
          ),
        );

    final body = <pw.Widget>[];
    if (has(ExportModule.transactions)) {
      body
        ..add(heading('Cash flow'))
        ..add(pw.Row(children: [
          stat('Income', rs(summary.income)),
          pw.SizedBox(width: 6),
          stat('Spending', rs(summary.expense)),
          pw.SizedBox(width: 6),
          stat('Net', rs(summary.net)),
        ]));
      if (r.categoryIds != null) {
        body.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Text('Filtered to ${r.categoryIds!.length} selected categories.', style: muted),
        ));
      }
      if (summary.byCategory.isNotEmpty) {
        body
          ..add(heading('Spending by category'))
          ..add(table(
            ['Category', 'Amount', 'Share'],
            [
              for (final e in summary.byCategory)
                [
                  s.category(e.key)?.name ?? 'Uncategorised',
                  rs(e.value),
                  formatBps(e.value.ratioBps(summary.expense) ?? 0),
                ],
            ],
            numeric: {1, 2},
          ));
      }
      final shown = txs.reversed.take(pdfTransactionRowLimit).toList();
      body
        ..add(heading('Transactions'))
        ..add(txs.isEmpty
            ? pw.Text('No transactions in this period.', style: muted)
            : table(
                ['Date', 'Type', 'Category', 'Details', 'Amount'],
                [
                  for (final t in shown)
                    [
                      d(t.date),
                      t.type.label,
                      s.category(t.categoryId)?.name ?? 'Uncategorised',
                      t.displayTitle ?? '',
                      rs(t.signedAmount),
                    ],
                ],
                numeric: {4},
              ));
      if (txs.length > shown.length) {
        body.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Text(
            'Showing the latest ${shown.length} of ${txs.length} transactions. Export CSV or JSON for the full list.',
            style: muted,
          ),
        ));
      }
    }
    if (has(ExportModule.budgets) && s.budgetUsages.isNotEmpty) {
      body
        ..add(heading('Budgets (current period)'))
        ..add(table(
          ['Category', 'Limit', 'Spent', 'Status'],
          [
            for (final u in s.budgetUsages)
              [s.category(u.budget.categoryId)?.name ?? 'Uncategorised', rs(u.budget.limit), rs(u.spent), u.health.label],
          ],
          numeric: {1, 2},
        ));
    }
    if (has(ExportModule.goals) && s.goalProgress.isNotEmpty) {
      body
        ..add(heading('Goals'))
        ..add(table(
          ['Goal', 'Target', 'Saved', 'Progress'],
          [
            for (final g in s.goalProgress)
              [g.goal.name, rs(g.goal.target), rs(g.saved), formatBps(g.progressBps, decimals: 0)],
          ],
          numeric: {1, 2, 3},
        ));
    }
    if (has(ExportModule.emergencyFund)) {
      final e = s.emergency;
      count += s.emergencyPlan == null ? 0 : 1;
      body
        ..add(heading('Emergency fund'))
        ..add(pw.Text(
          pdfSafe(s.emergencyPlan == null
              ? 'Not set up. Saved: ${rs(e.saved)}.'
              : 'Saved ${rs(e.saved)} of ${rs(e.target)} target'
                  '${e.coverageMonths == null ? '' : ' (${e.coverageMonths!.toStringAsFixed(1)} months of essentials)'}.'),
          style: base,
        ));
    }
    if (has(ExportModule.loans) && s.loanStates.isNotEmpty) {
      body
        ..add(heading('Loans'))
        ..add(table(
          ['Loan', 'With', 'Direction', 'Principal', 'Outstanding'],
          [
            for (final l in s.loanStates)
              [l.loan.name, l.loan.counterparty, l.loan.direction.label, rs(l.loan.principal), rs(l.outstanding)],
          ],
          numeric: {3, 4},
        ));
      final paid = _loanPayments(s, r);
      if (paid.isNotEmpty) {
        body.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Text(
            pdfSafe('${paid.length} repayments in this period totalling '
                '${rs(Money.sum(paid.map((p) => p.total)))} '
                '(principal ${rs(Money.sum(paid.map((p) => p.principalComponent)))}).'),
            style: muted,
          ),
        ));
      }
    }
    if (has(ExportModule.pending)) {
      final open = s.pendingViews.where((v) => v.status.isActive).toList();
      body
        ..add(heading('Pending payments'))
        ..add(pw.Text(
          pdfSafe('To collect: ${rs(s.pendingToCollect)}   To pay: ${rs(s.pendingToPay)}'),
          style: bold,
        ));
      if (open.isNotEmpty) {
        body
          ..add(pw.SizedBox(height: 6))
          ..add(table(
            ['With', 'Direction', 'Purpose', 'Waiting', 'Outstanding'],
            [
              for (final v in open)
                [v.payment.counterparty, v.payment.direction.shortLabel, v.payment.purpose, '${v.daysOpen} days', rs(v.outstanding)],
            ],
            numeric: {4},
          ));
      }
    }
    if (has(ExportModule.subscriptions) && s.subscriptions.isNotEmpty) {
      body
        ..add(heading('Subscriptions'))
        ..add(table(
          ['Name', 'Amount', 'Frequency', 'Next due', 'Status'],
          [
            for (final x in s.subscriptions)
              [x.name, rs(x.amount), x.frequency.label, d(x.nextDueDate), x.status.label],
          ],
          numeric: {1},
        ));
    }
    if (has(ExportModule.assets) && s.assets.isNotEmpty) {
      body
        ..add(heading('Assets (your estimates)'))
        ..add(table(
          ['Asset', 'Type', 'Valued on', 'Value'],
          [for (final a in s.assets) [a.name, a.type.label, d(a.valuedOn), rs(a.value)]],
          numeric: {3},
        ));
    }

    final doc = pw.Document(title: 'FiNN summary $period', author: 'FiNN', creator: 'FiNN');
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
      header: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('FiNN financial summary', style: bold.copyWith(fontSize: 18, color: navy)),
          pw.SizedBox(height: 2),
          pw.Text(pdfSafe('Period: $period'), style: base.copyWith(fontSize: 10)),
          pw.Text(pdfSafe('Generated ${DateFormats.timestamp.format(exportedAt)}. Amounts in Indian rupees (Rs.).'),
              style: muted),
          pw.Divider(color: PdfColors.grey300),
        ],
      ),
      footer: (ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Created on your device by FiNN. Nothing was uploaded.', style: muted.copyWith(fontSize: 7)),
          pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: muted.copyWith(fontSize: 7)),
        ],
      ),
      build: (ctx) => body.isEmpty ? [pw.Text('Nothing selected to report.', style: base)] : body,
    ));
    final bytes = await doc.save();
    return ExportArtifact(
      fileName: 'finn_summary_${_suffix(r)}.pdf',
      mimeType: 'application/pdf',
      bytes: bytes,
      recordCount: count,
    );
  }
}

/// Replaces characters the built-in PDF fonts cannot draw.
String pdfSafe(String input) {
  const map = {
    '₹': 'Rs.',
    '−': '-',
    '–': '-',
    '—': '-',
    '…': '...',
    '‘': "'",
    '’': "'",
    '“': '"',
    '”': '"',
    '·': '-',
    '→': '->',
    '•': '*',
  };
  final b = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    final mapped = map[ch];
    if (mapped != null) {
      b.write(mapped);
    } else if (rune < 0x80) {
      b.write(ch);
    } else {
      b.write('?');
    }
  }
  return b.toString();
}

/// RFC 4180 CSV encoding.
abstract final class Csv {
  /// Encodes [header] and [rows] with CRLF line endings. Starts with a
  /// UTF-8 byte-order mark so spreadsheet apps detect the ₹ symbol.
  static String encode(List<String> header, List<List<Object?>> rows) {
    final b = StringBuffer('﻿');
    b.write(header.map(field).join(','));
    b.write('\r\n');
    for (final row in rows) {
      b.write(row.map(field).join(','));
      b.write('\r\n');
    }
    return b.toString();
  }

  /// Quotes a value when it contains a comma, quote or line break.
  static String field(Object? value) {
    final s = value?.toString() ?? '';
    if (s.contains(RegExp(r'[",\r\n]'))) return '"${s.replaceAll('"', '""')}"';
    return s;
  }

  /// Neutralises user text that a spreadsheet would run as a formula
  /// (`=`, `+`, `-`, `@` at the start). Only applied to free-text columns.
  static String text(String? value) {
    final s = value ?? '';
    if (s.isNotEmpty && '=+-@\t\r'.contains(s[0])) return "'$s";
    return s;
  }

  /// Parses CSV produced by [encode] (used by tests and re-import).
  static List<List<String>> decode(String input) {
    var s = input;
    if (s.startsWith('﻿')) s = s.substring(1);
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    var i = 0;
    while (i < s.length) {
      final ch = s[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < s.length && s[i + 1] == '"') {
            cell.write('"');
            i += 2;
            continue;
          }
          quoted = false;
        } else {
          cell.write(ch);
        }
      } else if (ch == '"') {
        quoted = true;
      } else if (ch == ',') {
        row.add(cell.toString());
        cell.clear();
      } else if (ch == '\r' || ch == '\n') {
        if (ch == '\r' && i + 1 < s.length && s[i + 1] == '\n') i++;
        row.add(cell.toString());
        cell.clear();
        rows.add(row);
        row = <String>[];
      } else {
        cell.write(ch);
      }
      i++;
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString());
      rows.add(row);
    }
    return rows;
  }
}
