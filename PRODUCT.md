# FiNN — product context

FiNN is a personal-finance app for people in India (amounts in ₹, Indian digit grouping). It records
income and expenses and builds everything else from them: what is available to spend, monthly budgets,
savings goals, an emergency fund, loans and EMIs, subscriptions and money owed between people. An
assistant ("Agent") can make changes on the user's behalf after they approve them.

## Who uses it
Everyday earners managing a household or their own money on a phone, often in short sessions:
checking whether they can afford something, recording a payment, seeing what is due. Many are not
finance-savvy, so wording is plain and numbers are never left unexplained.

## What the interface must do
- Answer "how much can I spend?" and "what needs me?" within seconds of opening Home.
- Keep important information and actions discoverable without hunting: one main number per screen,
  then short sections; sections with nothing to say hide themselves.
- Be accurate. A figure is shown only when it is right; hidden-balances mode masks every amount.

## Design direction ("calm ledger", chosen 2026-10-14)
Warm paper page, white panels with hairline edges, ink text, one green. Colour only carries meaning:
green for money in and progress, red for over-limit or overdue, amber for getting close. One typeface
(Atkinson Hyperlegible Next, bundled) with tabular figures for money. Sentence case, no all-caps labels.
Premium comes from type, spacing and accuracy — never from gradients, gold, glow or decorative
components (earlier redesigns were rejected for exactly that).

The tokens and components live in `lib/kit/` (`kit.dart` barrel). Screens move onto it one at a
time; `lib/design_system/` remains for screens and form sheets not yet migrated.
