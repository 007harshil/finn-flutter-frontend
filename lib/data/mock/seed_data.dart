import 'dart:math';

import '../../core/money/money.dart';
import '../../core/time/dates.dart';
import '../../core/time/frequency.dart';
import '../../features/budgets/domain/budget.dart';
import '../../features/categories/domain/category.dart';
import '../../features/emergency_fund/domain/emergency_fund.dart';
import '../../features/goals/domain/goal.dart';
import '../../features/loans/domain/loan.dart';
import '../../features/loans/domain/loan_calculator.dart';
import '../../features/net_worth/domain/asset.dart';
import '../../features/pending/domain/pending_payment.dart';
import '../../features/settings/domain/financial_profile.dart';
import '../../features/subscriptions/domain/subscription.dart';
import '../../features/transactions/domain/transaction.dart';
import '../local/local_data_store.dart';
import 'finn_users.dart';

/// Ids of seeded standard categories (stable so tests can reference them).
abstract final class SeedCategoryIds {
  static const food = 'cat_food';
  static const groceries = 'cat_groceries';
  static const rent = 'cat_rent';
  static const utilities = 'cat_utilities';
  static const transport = 'cat_transport';
  static const shopping = 'cat_shopping';
  static const entertainment = 'cat_entertainment';
  static const health = 'cat_health';
  static const education = 'cat_education';
  static const travel = 'cat_travel';
  static const personalCare = 'cat_personal_care';
  static const gifts = 'cat_gifts';
  static const insurance = 'cat_insurance';
  static const subscriptions = 'cat_subscriptions';
  static const family = 'cat_family';
  static const fitness = 'cat_fitness';
  static const salary = 'cat_salary';
  static const freelance = 'cat_freelance';
  static const interest = 'cat_interest';
  static const refunds = 'cat_refunds';
  static const giftsReceived = 'cat_gifts_in';
  static const rental = 'cat_rental';
}

/// A complete dataset for the local mock backend.
class SeedData {
  SeedData._();

  late List<TransactionCategory> categories;
  List<Transaction> transactions = [];
  List<Budget> budgets = [];
  List<SavingsGoal> goals = [];
  List<SavingsMovement> savingsMovements = [];
  List<Loan> loans = [];
  List<LoanPayment> loanPayments = [];
  List<Subscription> subscriptions = [];
  List<PendingPayment> pending = [];
  List<PendingSettlement> settlements = [];

  /// Other people's side of shared pending items (mock network).
  List<MirrorEntry> mirrors = [];
  List<Asset> assets = [];
  FinancialProfile? profile;
  EmergencyFundPlan? emergencyPlan;

  static List<TransactionCategory> standardCategories() {
    TransactionCategory e(String id, String name, String icon, int color, String desc, {bool essential = false}) =>
        TransactionCategory(id: id, name: name, type: TransactionType.expense, iconKey: icon, colorIndex: color, description: desc, isEssential: essential);
    TransactionCategory i(String id, String name, String icon, int color, String desc) =>
        TransactionCategory(id: id, name: name, type: TransactionType.income, iconKey: icon, colorIndex: color, description: desc);
    TransactionCategory sys(String id, String name, TransactionType t, String icon, int color, String desc) =>
        TransactionCategory(id: id, name: name, type: t, iconKey: icon, colorIndex: color, description: desc, isSystem: true);
    return [
      e(SeedCategoryIds.food, 'Food & Dining', 'utensils', 12, 'Restaurants, cafés, Swiggy, Zomato'),
      e(SeedCategoryIds.groceries, 'Groceries', 'shoppingCart', 2, 'BigBasket, DMart, kirana, vegetables', essential: true),
      e(SeedCategoryIds.rent, 'Rent & Housing', 'home', 9, 'Rent, maintenance, society charges', essential: true),
      e(SeedCategoryIds.utilities, 'Bills & Utilities', 'zap', 3, 'Electricity, water, gas, broadband, mobile', essential: true),
      e(SeedCategoryIds.transport, 'Transport', 'car', 0, 'Fuel, Uber, Ola, metro, parking', essential: true),
      e(SeedCategoryIds.shopping, 'Shopping', 'shoppingBag', 1, 'Amazon, Flipkart, Myntra, electronics'),
      e(SeedCategoryIds.entertainment, 'Entertainment', 'clapperboard', 13, 'Movies, concerts, events, games'),
      e(SeedCategoryIds.health, 'Health & Medical', 'heartPulse', 4, 'Doctor, pharmacy, diagnostics', essential: true),
      e(SeedCategoryIds.education, 'Education', 'graduationCap', 5, 'Courses, books, fees'),
      e(SeedCategoryIds.travel, 'Travel', 'plane', 10, 'Flights, trains, hotels, holidays'),
      e(SeedCategoryIds.personalCare, 'Personal Care', 'sparkles', 8, 'Salon, grooming, Urban Company'),
      e(SeedCategoryIds.gifts, 'Gifts & Donations', 'gift', 4, 'Gifts, festivals, charity'),
      e(SeedCategoryIds.insurance, 'Insurance', 'shieldCheck', 11, 'Health, term and vehicle insurance', essential: true),
      e(SeedCategoryIds.subscriptions, 'Subscriptions', 'repeat', 1, 'OTT, music, cloud storage, apps'),
      e(SeedCategoryIds.family, 'Family Support', 'users', 7, 'Money sent to parents and family', essential: true),
      e(SeedCategoryIds.fitness, 'Fitness', 'dumbbell', 2, 'Gym, yoga, sports'),
      i(SeedCategoryIds.salary, 'Salary', 'briefcase', 11, 'Monthly salary and bonuses'),
      i(SeedCategoryIds.freelance, 'Freelance', 'laptop', 5, 'Side projects and consulting'),
      i(SeedCategoryIds.interest, 'Interest & Dividends', 'percent', 2, 'Savings interest, FD payouts, dividends'),
      i(SeedCategoryIds.refunds, 'Refunds & Cashback', 'receipt', 0, 'Refunds, cashback, rewards'),
      i(SeedCategoryIds.giftsReceived, 'Gifts Received', 'gift', 8, 'Money received as gifts'),
      i(SeedCategoryIds.rental, 'Rental Income', 'building', 9, 'Rent received'),
      sys(SystemCategories.loanEmi, 'EMI & Loan Repayment', TransactionType.expense, 'scale', 10, 'Recorded from the Loans module'),
      sys(SystemCategories.loanGiven, 'Loan Given', TransactionType.expense, 'handCoins', 6, 'Money lent, recorded from Loans'),
      sys(SystemCategories.settlementPaid, 'Settlement Paid', TransactionType.expense, 'handshake', 13, 'Recorded from Pending payments'),
      sys(SystemCategories.uncategorizedExpense, 'Other Expense', TransactionType.expense, 'circleDot', 6, 'Anything else'),
      sys(SystemCategories.loanReceived, 'Loan Received', TransactionType.income, 'landmark', 6, 'Loan disbursement, recorded from Loans'),
      sys(SystemCategories.loanRepaymentReceived, 'Loan Repayment Received', TransactionType.income, 'handCoins', 11, 'Repayments of money you lent'),
      sys(SystemCategories.settlementReceived, 'Settlement Received', TransactionType.income, 'handshake', 2, 'Recorded from Pending payments'),
      sys(SystemCategories.uncategorizedIncome, 'Other Income', TransactionType.income, 'circleDot', 6, 'Anything else'),
    ];
  }

  static SeedData build(DataScenario scenario, DateTime today) {
    final s = SeedData._()..categories = standardCategories();
    if (scenario == DataScenario.empty) return s;
    _Builder(s, today.dateOnly, stressed: scenario == DataScenario.stressed).run();
    return s;
  }
}

class _Builder {
  _Builder(this.s, this.today, {required this.stressed})
      : opening = DateTime(today.year, today.month - 6, 1),
        stamp = DateTime(today.year, today.month - 6, 1, 9);

  final SeedData s;
  final DateTime today;
  final bool stressed;
  final DateTime opening;
  final DateTime stamp;
  final _r = Random(7);
  int _seq = 0;
  static const _calc = LoanCalculator();

  String _id(String p) => '${p}_seed_${++_seq}';
  Money _rs(int min, int max) => Money.rupees(min + _r.nextInt(max - min + 1));
  T _pick<T>(List<T> list) => list[_r.nextInt(list.length)];

  Transaction _tx(
    TransactionType type,
    Money amount,
    String cat,
    DateTime date, {
    String? who,
    String? note,
    PaymentMethod method = PaymentMethod.upi,
    TransactionOrigin origin = TransactionOrigin.manual,
    String? ref,
  }) {
    final t = Transaction(
      id: _id('tx'),
      type: type,
      amount: amount,
      categoryId: cat,
      date: date,
      paymentMethod: method,
      counterparty: who,
      note: note,
      origin: origin,
      originRefId: ref,
      createdAt: date.add(const Duration(hours: 12)),
      updatedAt: date.add(const Duration(hours: 12)),
    );
    s.transactions.add(t);
    return t;
  }

  Transaction _out(int min, int max, String cat, DateTime d, String who, {PaymentMethod m = PaymentMethod.upi, String? note}) =>
      _tx(TransactionType.expense, _rs(min, max), cat, d, who: who, method: m, note: note);

  bool _inPast(DateTime d) => !d.isAfter(today);

  void run() {
    s.profile = FinancialProfile(
      displayName: 'Aarav',
      openingBalance: Money.rupees(360000),
      openingDate: opening,
      monthlyIncomeEstimate: Money.rupees(125000),
    );
    _monthlyActivity();
    _subscriptions();
    _loans();
    _pending();
    _goals();
    _emergency();
    _budgets();
    _assets();
    s.transactions.sort((a, b) => b.date.compareTo(a.date));
  }

  void _monthlyActivity() {
    for (var m = 0; m <= 6; m++) {
      final month = DateTime(opening.year, opening.month + m);
      DateTime d(int day) => DateTime(month.year, month.month, day.clamp(1, month.daysInMonth));
      void at(int day, void Function(DateTime) f) {
        final date = d(day);
        if (_inPast(date)) f(date);
      }

      final isCurrent = month.isSameMonth(today);
      if (!(stressed && isCurrent)) {
        at(1, (x) => _tx(TransactionType.income, Money.rupees(125000), SeedCategoryIds.salary, x,
            who: 'Acme Technologies Pvt Ltd', note: 'Salary credit', method: PaymentMethod.bankTransfer));
      }
      at(3, (x) => _tx(TransactionType.expense, Money.rupees(28000), SeedCategoryIds.rent, x,
          who: 'Mr. Sharma (Landlord)', note: 'House rent', method: PaymentMethod.bankTransfer));
      at(5, (x) => _tx(TransactionType.expense, Money.rupees(10000), SeedCategoryIds.family, x,
          who: 'Mom', note: 'Monthly support', method: PaymentMethod.bankTransfer));
      at(8, (x) => _tx(TransactionType.expense, Money.rupees(1178), SeedCategoryIds.utilities, x, who: 'Airtel Xstream', note: 'Broadband'));
      at(12, (x) => _out(1750, 2650, SeedCategoryIds.utilities, x, 'BESCOM', note: 'Electricity bill'));
      for (final day in [2, 7, 13, 19, 26]) {
        at(day, (x) => _out(900, 3100, SeedCategoryIds.groceries, x, _pick(['BigBasket', 'DMart', 'Zepto', 'Blinkit', 'Nature\'s Basket'])));
      }
      for (final day in [4, 6, 9, 11, 16, 20, 23, 28]) {
        at(day, (x) => _out(180, 1350, SeedCategoryIds.food, x, _pick(['Swiggy', 'Zomato', 'Starbucks', 'Chai Point', 'Truffles', 'Meghana Foods'])));
      }
      for (final day in [3, 8, 14, 18, 22, 27]) {
        at(day, (x) => _out(120, 640, SeedCategoryIds.transport, x, _pick(['Uber', 'Ola', 'Rapido', 'Namma Metro'])));
      }
      for (final day in [10, 24]) {
        at(day, (x) => _out(2000, 3000, SeedCategoryIds.transport, x, 'Indian Oil', m: PaymentMethod.card, note: 'Fuel'));
      }
      if (!isCurrent) {
        at(15, (x) => _out(800, 4200, SeedCategoryIds.shopping, x, _pick(['Amazon', 'Flipkart', 'Myntra', 'Croma']), m: PaymentMethod.card));
        at(25, (x) => _out(600, 2600, SeedCategoryIds.shopping, x, _pick(['Amazon', 'Nykaa', 'Decathlon']), m: PaymentMethod.card));
        at(17, (x) => _out(450, 1300, SeedCategoryIds.entertainment, x, 'BookMyShow'));
      }
      at(21, (x) => _out(280, 1200, SeedCategoryIds.health, x, 'Apollo Pharmacy'));
      at(18, (x) => _out(499, 1499, SeedCategoryIds.personalCare, x, 'Urban Company'));
      if (m.isOdd) {
        at(20, (x) => _tx(TransactionType.income, _rs(18000, 34000), SeedCategoryIds.freelance, x,
            who: _pick(['Northwind Studio', 'Pixel Labs', 'Kite Media']), note: 'Design project', method: PaymentMethod.bankTransfer));
      }
      if (m == 2 || m == 5) {
        at(28, (x) => _tx(TransactionType.income, _rs(2100, 3400), SeedCategoryIds.interest, x, who: 'HDFC Bank', note: 'Savings interest', method: PaymentMethod.bankTransfer));
      }
      if (m == 3) {
        at(11, (x) => _out(9500, 9500, SeedCategoryIds.insurance, x, 'Star Health', m: PaymentMethod.card, note: 'Health insurance premium'));
        at(14, (x) => _out(14500, 18500, SeedCategoryIds.travel, x, 'IndiGo', m: PaymentMethod.card, note: 'Diwali trip flights'));
        at(16, (x) => _out(3500, 6500, SeedCategoryIds.gifts, x, 'Tanishq', m: PaymentMethod.card, note: 'Festival gifts'));
      }
      if (m == 4) at(9, (x) => _tx(TransactionType.income, Money.rupees(1240), SeedCategoryIds.refunds, x, who: 'Amazon', note: 'Return refund'));
    }
    // Current-month spending that pushes budgets into warning / breach.
    final cm = today.startOfMonth;
    DateTime cd(int day) => DateTime(cm.year, cm.month, min(day, today.day));
    _tx(TransactionType.expense, Money.rupees(5420), SeedCategoryIds.shopping, cd(6), who: 'Myntra', note: 'Festive kurta set', method: PaymentMethod.card);
    _tx(TransactionType.expense, Money.rupees(2350), SeedCategoryIds.entertainment, cd(4), who: 'BookMyShow', note: 'Coldplay tribute night');
  }

  void _subscriptions() {
    const cat = SeedCategoryIds.subscriptions;
    void sub(String name, int rupees, Frequency f, int dueInDays, {String category = cat, PaymentMethod method = PaymentMethod.card, SubscriptionStatus status = SubscriptionStatus.active, int historyMonths = 6}) {
      final id = _id('sub');
      final next = today.add(Duration(days: dueInDays)).dateOnly;
      final amount = Money.rupees(rupees);
      var paid = f.nth(next, -1);
      var count = 0;
      while (!paid.isBefore(opening) && count < historyMonths && status != SubscriptionStatus.cancelled) {
        if (_inPast(paid)) {
          _tx(TransactionType.expense, amount, category, paid, who: name, note: '${f.label} renewal',
              method: method, origin: TransactionOrigin.subscription, ref: id);
        }
        count++;
        paid = f.nth(next, -(count + 1));
      }
      s.subscriptions.add(Subscription(
        id: id,
        name: name,
        amount: amount,
        categoryId: category,
        frequency: f,
        nextDueDate: next,
        startDate: DateTime(opening.year - 1, opening.month, next.day.clamp(1, 28)),
        status: status,
        paymentMethod: method,
        createdAt: stamp,
        updatedAt: stamp,
      ));
    }

    sub('Netflix Premium', 649, Frequency.monthly, 3);
    sub('Spotify Premium', 119, Frequency.monthly, 11, method: PaymentMethod.upi);
    sub('YouTube Premium', 149, Frequency.monthly, 19);
    sub('Jio Postpaid', 399, Frequency.monthly, 15, category: SeedCategoryIds.utilities, method: PaymentMethod.upi);
    sub('Cult.fit Elite', 1999, Frequency.monthly, stressed ? -9 : -2, category: SeedCategoryIds.fitness);
    sub('Amazon Prime', 1499, Frequency.yearly, 142);
    sub('Google One 2TB', 650, Frequency.quarterly, 37);
    sub('Disney+ Hotstar', 299, Frequency.monthly, 24, status: SubscriptionStatus.paused, historyMonths: 2);
  }

  void _loans() {
    // Car loan: amortizing EMI with a bank.
    final carStart = DateTime(today.year, today.month - 14, 20);
    final car = Loan(
      id: 'loan_seed_car',
      name: 'Car loan',
      counterparty: 'HDFC Bank',
      direction: LoanDirection.borrowed,
      structure: LoanStructure.amortizing,
      principal: Money.rupees(600000),
      rate: const InterestRate(950),
      startDate: carStart,
      firstDueDate: DateTime(carStart.year, carStart.month + 1, 5),
      frequency: Frequency.monthly,
      tenureInstallments: 60,
      createdAt: stamp,
      updatedAt: stamp,
    );
    s.loans.add(car);
    for (final row in _calc.originalSchedule(car)) {
      if (row.dueDate.isAfter(today)) break;
      _loanPayment(car, LoanPaymentKind.installment, row.dueDate, row.interest, row.principal, row.number);
    }

    // Family loan: interest-only, with a partial principal repayment.
    final famStart = DateTime(today.year, today.month - 10, 7);
    final fam = Loan(
      id: 'loan_seed_family',
      name: 'Home renovation loan',
      counterparty: 'Ramesh Uncle',
      direction: LoanDirection.borrowed,
      structure: LoanStructure.interestOnly,
      principal: Money.rupees(200000),
      rate: const InterestRate(1200),
      startDate: famStart,
      firstDueDate: DateTime(famStart.year, famStart.month + 1, 7),
      frequency: Frequency.monthly,
      note: 'Informal family loan, 1% per month. No fixed end date.',
      createdAt: stamp,
      updatedAt: stamp,
    );
    s.loans.add(fam);
    final prepayDate = DateTime(today.year, today.month - 4, 15);
    var outstanding = fam.principal;
    for (var n = 1; n <= 24; n++) {
      final due = fam.frequency.nth(fam.firstDueDate, n - 1);
      // Leave this month's interest unpaid so it shows as overdue.
      if (due.isSameMonth(today) || due.isAfter(today)) break;
      if (due.isAfter(prepayDate) && outstanding == fam.principal) {
        _loanPayment(fam, LoanPaymentKind.principal, prepayDate, Money.zero, Money.rupees(50000), null);
        outstanding = outstanding - Money.rupees(50000);
      }
      final interest = _calc.periodInterest(outstanding, fam.rate, 12);
      _loanPayment(fam, LoanPaymentKind.interest, due, interest, Money.zero, n);
    }

    // Money lent to a friend, interest-free, partially repaid.
    final lentStart = DateTime(today.year, today.month - 3, 2);
    final lent = Loan(
      id: 'loan_seed_lent',
      name: 'Bike down payment',
      counterparty: 'Karan Mehta',
      direction: LoanDirection.lent,
      structure: LoanStructure.interestOnly,
      principal: Money.rupees(40000),
      rate: const InterestRate(0),
      startDate: lentStart,
      firstDueDate: DateTime(lentStart.year, lentStart.month + 1, 2),
      frequency: Frequency.monthly,
      maturityDate: DateTime(today.year, today.month + 5, 2),
      createdAt: stamp,
      updatedAt: stamp,
    );
    final disb = _tx(TransactionType.expense, lent.principal, SystemCategories.loanGiven, lentStart,
        who: 'Karan Mehta', note: 'Loan given', method: PaymentMethod.bankTransfer,
        origin: TransactionOrigin.loanDisbursement, ref: lent.id);
    s.loans.add(Loan(
      id: lent.id, name: lent.name, counterparty: lent.counterparty, direction: lent.direction,
      structure: lent.structure, principal: lent.principal, rate: lent.rate, startDate: lent.startDate,
      firstDueDate: lent.firstDueDate, frequency: lent.frequency, maturityDate: lent.maturityDate,
      disbursementTransactionId: disb.id, createdAt: stamp, updatedAt: stamp,
    ));
    _loanPayment(s.loans.last, LoanPaymentKind.principal, DateTime(today.year, today.month - 1, 12),
        Money.zero, Money.rupees(15000), null);
  }

  void _loanPayment(Loan loan, LoanPaymentKind kind, DateTime date, Money interest, Money principal, int? period) {
    final total = interest + principal;
    String? txId;
    if (!date.isBefore(opening) && total.isPositive) {
      final borrowed = loan.isBorrowed;
      txId = _tx(
        borrowed ? TransactionType.expense : TransactionType.income,
        total,
        borrowed ? SystemCategories.loanEmi : SystemCategories.loanRepaymentReceived,
        date,
        who: loan.counterparty,
        note: '${loan.name} · ${kind.label}${period != null ? ' #$period' : ''}',
        method: PaymentMethod.bankTransfer,
        origin: TransactionOrigin.loanRepayment,
        ref: loan.id,
      ).id;
    }
    s.loanPayments.add(LoanPayment(
      id: _id('lp'),
      loanId: loan.id,
      kind: kind,
      date: date,
      interestComponent: interest,
      principalComponent: principal,
      periodNumber: period,
      transactionId: txId,
      createdAt: date.add(const Duration(hours: 10)),
    ));
  }

  void _pending() {
    PendingPayment p(String who, PendingDirection dir, PendingKind kind, int rupees, String purpose, int createdAgo, {String? notes, String? userId, bool createdByMe = true, PendingSplit? split}) {
      final created = today.subtract(Duration(days: createdAgo));
      final id = _id('pend');
      final item = PendingPayment(
        id: id,
        counterparty: who,
        direction: dir,
        kind: kind,
        originalAmount: Money.rupees(rupees),
        purpose: purpose,
        createdDate: created,
        notes: notes,
        link: userId == null
            ? null
            : PendingLink(
                userId: userId,
                handle: mockFinnUsers.firstWhere((u) => u.id == userId).handle,
                sharedId: 'shr_$id',
                createdByMe: createdByMe,
              ),
        createdAt: created,
        updatedAt: created,
        split: split,
      );
      s.pending.add(item);
      return item;
    }

    void settle(PendingPayment item, int rupees, int daysAgo, {PaymentMethod method = PaymentMethod.upi}) {
      final date = today.subtract(Duration(days: daysAgo));
      final owe = item.direction == PendingDirection.iOwe;
      final tx = _tx(
        owe ? TransactionType.expense : TransactionType.income,
        Money.rupees(rupees),
        owe ? SystemCategories.settlementPaid : SystemCategories.settlementReceived,
        date,
        who: item.counterparty,
        note: 'Settlement · ${item.purpose}',
        method: method,
        origin: TransactionOrigin.pendingSettlement,
        ref: item.id,
      );
      s.settlements.add(PendingSettlement(
        id: _id('set'),
        pendingId: item.id,
        amount: Money.rupees(rupees),
        date: date,
        method: method,
        transactionId: tx.id,
        createdAt: date,
      ));
    }

    // Priya, Ananya and Rahul use FiNN: those items are shared (double entry).
    // Rahul added the concert item himself, so only he can edit it.
    p('Priya Nair', PendingDirection.owedToMe, PendingKind.sharedExpense, 6500, 'Goa trip hotel share', 20,
        userId: 'u_priya',
        notes: 'Paid the full booking at Taj Fort Aguada');
    final rahul = p('Rahul Verma', PendingDirection.iOwe, PendingKind.borrowed, 3200, 'Concert tickets', 24,
        userId: 'u_rahul', createdByMe: false);
    settle(rahul, 1200, 14);
    p('Neha Kapoor', PendingDirection.owedToMe, PendingKind.reimbursement, 850, 'Office lunch', 35);
    final vikram = p('Vikram Rao', PendingDirection.iOwe, PendingKind.sharedExpense, 1450, 'Flat electricity split', 40);
    settle(vikram, 1450, 31);
    final ananya = p('Ananya Iyer', PendingDirection.owedToMe, PendingKind.lent, 5000, 'Emergency cash', 50,
        userId: 'u_ananya');
    settle(ananya, 2000, 18);
    p('Rahul Verma', PendingDirection.iOwe, PendingKind.sharedExpense, 780, 'Cab to airport', 9);
    // One bill split four ways (the user included): one item per person.
    const dinner = PendingSplit(id: 'spl_dinner', method: SplitMethod.equally, includesMe: true, myShare: Money.fromPaise(120000));
    p('Karan Mehta', PendingDirection.owedToMe, PendingKind.sharedExpense, 1200, 'Team dinner at Toit', 6,
        userId: 'u_karan', split: dinner);
    final sneha = p('Sneha Patil', PendingDirection.owedToMe, PendingKind.sharedExpense, 1200, 'Team dinner at Toit', 6,
        split: dinner);
    settle(sneha, 1200, 4);
    p('Arjun Shah', PendingDirection.owedToMe, PendingKind.sharedExpense, 1200, 'Team dinner at Toit', 6, split: dinner);
    if (stressed) {
      p('Society Office', PendingDirection.iOwe, PendingKind.other, 12000, 'Maintenance arrears', 70);
    }
    final me = mockMe(s.profile?.displayName);
    s.mirrors = [
      for (final item in s.pending.where((x) => x.link != null))
        mirrorOf(item, s.settlements.where((x) => x.pendingId == item.id).toList()..sort((a, b) => b.date.compareTo(a.date)), me: me),
    ];
  }

  void _goals() {
    SavingsGoal g(String id, String name, GoalCategory cat, int target, int color, {int? monthsAhead, int? plan}) {
      final goal = SavingsGoal(
        id: id,
        name: name,
        category: cat,
        target: Money.rupees(target),
        targetDate: monthsAhead == null ? null : DateTime(today.year, today.month + monthsAhead, 28),
        plannedMonthlyContribution: plan == null ? null : Money.rupees(plan),
        colorIndex: color,
        createdAt: stamp,
        updatedAt: stamp,
      );
      s.goals.add(goal);
      return goal;
    }

    void contrib(String bucketId, int rupees, DateTime date, {SavingsBucketType type = SavingsBucketType.goal, SavingsMovementKind kind = SavingsMovementKind.contribution, String? note}) {
      if (date.isAfter(today)) return;
      s.savingsMovements.add(SavingsMovement(
        id: _id('sv'),
        bucketType: type,
        bucketId: bucketId,
        kind: kind,
        amount: Money.rupees(rupees),
        date: date,
        note: note,
        createdAt: date,
      ));
    }

    final japan = g('goal_seed_japan', 'Japan cherry blossom trip', GoalCategory.travel, 300000, 12, monthsAhead: 6, plan: 32000);
    final mac = g('goal_seed_macbook', 'MacBook Pro', GoalCategory.purchase, 220000, 9, monthsAhead: 2, plan: 15000);
    final study = g('goal_seed_masters', 'Masters abroad fund', GoalCategory.education, 800000, 5, monthsAhead: 30);
    final bike = g('goal_seed_bike', 'Royal Enfield down payment', GoalCategory.vehicle, 60000, 2);
    contrib(mac.id, 120000, opening, note: 'Existing savings earmarked');
    contrib(bike.id, 45000, opening, note: 'Existing savings earmarked');
    for (var m = 0; m <= 6; m++) {
      final d = DateTime(opening.year, opening.month + m, 2);
      contrib(japan.id, 16000 + _r.nextInt(7) * 1000, d);
      if (m < 5) contrib(mac.id, 12000, d);
      if (m.isEven) contrib(study.id, 15000, d);
      if (m == 2) contrib(bike.id, 15000, d);
    }
    contrib(japan.id, 8000, DateTime(opening.year, opening.month + 3, 20),
        kind: SavingsMovementKind.withdrawal, note: 'Visa fee moved back to spending');
  }

  void _emergency() {
    s.emergencyPlan = EmergencyFundPlan(
      essentialMonthlyExpenses: Money.rupees(55000),
      targetMonths: 6,
      updatedAt: stamp,
    );
    for (var m = 0; m <= 6; m++) {
      final d = DateTime(opening.year, opening.month + m, 2);
      if (d.isAfter(today)) continue;
      s.savingsMovements.add(SavingsMovement(
        id: _id('sv'),
        bucketType: SavingsBucketType.emergencyFund,
        bucketId: SavingsMovement.emergencyFundBucketId,
        kind: SavingsMovementKind.contribution,
        amount: Money.rupees(m == 0 ? 50000 : 15000),
        date: d,
        note: m == 0 ? 'Initial buffer' : 'Monthly top-up',
        createdAt: d,
      ));
    }
  }

  void _budgets() {
    Budget b(String cat, int rupees, {BudgetStatus status = BudgetStatus.active}) => Budget(
          id: _id('bud'),
          categoryId: cat,
          limit: Money.rupees(rupees),
          status: status,
          createdAt: stamp,
          updatedAt: stamp,
        );
    s.budgets.addAll([
      b(SeedCategoryIds.food, 7000),
      b(SeedCategoryIds.groceries, 11000),
      b(SeedCategoryIds.shopping, 6000),
      b(SeedCategoryIds.transport, 8500),
      b(SeedCategoryIds.entertainment, 2000),
      b(SeedCategoryIds.personalCare, 1500, status: BudgetStatus.paused),
    ]);
    s.budgets.add(Budget(
      id: _id('bud'),
      categoryId: SeedCategoryIds.travel,
      limit: Money.rupees(20000),
      note: 'Weekend trips and travel bookings',
      createdAt: stamp,
      updatedAt: stamp,
    ));
  }

  void _assets() {
    Asset a(String name, AssetType type, int rupees, {String? note}) => Asset(
          id: _id('asset'),
          name: name,
          type: type,
          value: Money.rupees(rupees),
          valuedOn: today.subtract(const Duration(days: 12)),
          note: note,
          createdAt: stamp,
          updatedAt: stamp,
        );
    s.assets.addAll([
      a('Mutual fund portfolio', AssetType.investment, 462000, note: 'Nifty 50 index + flexi cap SIPs'),
      a('EPF balance', AssetType.retirement, 328500),
      a('Gold jewellery', AssetType.gold, 185000),
      a('SBI fixed deposit', AssetType.bankDeposit, 200000, note: '7.1% p.a., matures Mar 2027'),
      a('Hyundai i20', AssetType.vehicle, 520000, note: 'Approximate resale value'),
    ]);
  }
}
