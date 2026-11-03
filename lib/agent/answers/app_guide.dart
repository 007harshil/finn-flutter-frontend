/// The "how do I use FiNN" answer, written once so it is the same every
/// time and costs no model call. Keep it in step with the app's menus.
const agentGuideText = '''FiNN keeps your money records in one place. Nothing is deducted for real: you record what happened.

Getting around
- Home: balance, what needs attention and what is due in the next 7 days.
- Activity: every expense, income and transfer. Search, filter by period, category or account, and sort with the arrows button.
- Agent (centre button): tell me what happened and I record it after you approve.
- Budgets: monthly limits per category.
- Goals: savings goals and your emergency fund.
- Menu (top left): Accounts, Loans & EMIs, Pending payments, Subscriptions, Friends, Net worth, Insights, Categories, Export, Settings.

Recording money
- Tap + to add an expense or income. Long-press + to record a transfer between your own accounts.
- Pick the account it came from: cash, bank or card.

Debts
- Pending payments tracks who owes you and whom you owe. Mark a payment received or paid to settle it, or write it off.
- Sharing a pending item with a friend needs a friend request first (add them by their FiNN ID).

Loans and subscriptions
- Loans & EMIs: add a loan, then record each EMI as it is paid.
- Subscriptions: Mark paid records one renewal and moves the due date forward. Skip moves the date without a payment.

Budgets and goals
- Set a limit per category and watch it fill through the month.
- Add money to a goal or the emergency fund; it is set aside from your available balance.

Things to say to me
- "Spent 450 on lunch today via UPI"
- "Rahul paid me back 2,000"
- "How much did I spend on food this month?"
- "Paid the Netflix subscription"
- "Add 5,000 to my emergency fund"
You approve every change before it is saved.''';

/// Short "how do I…" answers for one page, keyed like `agentPages`. The
/// model picks the page (`{"reply":"help","topic":"budgets"}`); the words
/// are always these.
const agentGuideTopics = <String, String>{
  'home': 'Home shows your balance, what needs attention and what is due in the next 7 days.',
  'activity':
      'Activity lists every expense, income and transfer. Search, filter by period, category or account, and sort with the arrows button. Tap + to add one, or tell me "spent 450 on lunch".',
  'budgets':
      'Budgets set a monthly limit per category and fill up as you spend. Tap + on Budgets to add one, or tell me "set a 5,000 budget for food".',
  'goals':
      'Goals track what you save for. Add money to a goal and it is set aside from your available balance. Try "add 2,000 to my Japan trip goal".',
  'emergency_fund': 'The emergency fund is money set aside for surprises. Try "add 5,000 to my emergency fund".',
  'loans': 'Loans & EMIs: add a loan, then record each EMI as it is paid. Try "paid the car loan EMI".',
  'subscriptions':
      'Subscriptions: Mark paid records one renewal and moves the due date forward. Skip moves the date without a payment. Try "paid Netflix".',
  'pending':
      'Pending payments track who owes you and whom you owe. Mark one received or paid to settle it, or write it off. Try "Rahul owes me 500" or "Rahul paid me back".',
  'accounts': 'Accounts hold your cash, bank accounts and cards. Pick one when you record money so balances stay right.',
  'categories': 'Categories group your spending and income. Add or edit them in Menu → Categories, or tell me "create a Pets category".',
  'insights': 'Insights show where your money went, month by month and by category.',
  'net_worth': 'Net worth adds up your accounts and assets, minus what you owe.',
  'export': 'Export saves your records as a file from Menu → Export.',
  'settings': 'Settings hold your profile, privacy, alerts and data options.',
  'friends': 'Friends lets you share pending items with other FiNN users. Add them by their FiNN ID first.',
  'alerts': 'Alerts list what needs your attention, like budgets close to their limit and payments due soon.',
  'profile': 'Your profile is in Settings → Profile. I cannot change it for you.',
};
