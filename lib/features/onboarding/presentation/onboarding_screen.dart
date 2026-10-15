import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/time/clock.dart';
import '../../../data/local/local_data_store.dart';
import '../../../kit/kit.dart';
import '../../settings/domain/financial_profile.dart';

class _IntroPage {
  const _IntroPage(this.title, this.body, this.points);
  final String title;
  final String body;
  final List<String> points;
}

const _intro = [
  _IntroPage(
    'See where your money stands',
    'One calm view of what you can spend, what is set aside, and what is coming up.',
    ['Available to spend, explained', 'EMIs, renewals and dues ahead of time'],
  ),
  _IntroPage(
    'Plan with intention',
    'Budgets, goals, loans and an emergency fund that work together, not in silos.',
    ['Budgets that warn before you overspend', 'Goals and a safety net that grow steadily'],
  ),
  _IntroPage(
    'Your data stays on this device',
    'No bank logins, no ads, no selling your data. You decide what to record.',
    ['Stored locally on your phone', 'Export a copy whenever you like'],
  ),
];

enum _StartMode { fresh, sample }

/// Three short intro pages, then a one-step setup.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  final _name = TextEditingController();
  final _balance = TextEditingController();
  int _page = 0;
  _StartMode _mode = _StartMode.fresh;
  String? _nameError;
  String? _balanceError;
  bool _busy = false;

  static const _setupIndex = 3;

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    FocusScope.of(context).unfocus();
    _pages.animateToPage(index, duration: context.motion.page, curve: context.motion.standard);
  }

  Future<void> _finish() async {
    if (_busy) return;
    final name = _name.text.trim();
    final rawBalance = _balance.text.trim();
    final balance = rawBalance.isEmpty ? Money.zero : LedgerAmountField.parse(rawBalance);
    setState(() {
      _nameError = name.isEmpty ? 'Please tell us what to call you' : null;
      _balanceError = _mode == _StartMode.fresh && balance == null ? 'Enter a valid amount, e.g. 25,000' : null;
    });
    if (_nameError != null || _balanceError != null) return;

    setState(() => _busy = true);
    try {
      final repos = ref.read(financeRepositoriesProvider);
      final today = ref.read(clockProvider).today();
      // Connected: the account is the dataset; only the profile is written
      // (through the `profile.update` action endpoint).
      final remote = ref.read(remoteModeProvider);
      if (_mode == _StartMode.fresh) {
        if (!remote) await ref.read(localDataStoreProvider).reseed(DataScenario.empty, today);
        await repos.profile.set(FinancialProfile(displayName: name, openingBalance: balance!, openingDate: today));
      } else {
        final existing = repos.profile.current;
        await repos.profile.set(
          existing?.copyWith(displayName: name) ??
              FinancialProfile(displayName: name, openingBalance: Money.zero, openingDate: today),
        );
      }
      await ref.read(settingsProvider.notifier).update((s) => s.copyWith(onboardingComplete: true));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      FinnToast.error(context, 'Could not finish setup', subtitle: 'Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final onSetup = _page == _setupIndex;
    const total = _setupIndex + 1;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Sp.maxWidth),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.sm, Sp.sm, 0),
                  child: Row(
                    children: [
                      Text('FiNN', style: t.heading.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                      const Spacer(),
                      if (!onSetup)
                        TextButton(
                          onPressed: () => _goTo(_setupIndex),
                          style: TextButton.styleFrom(
                            foregroundColor: c.inkSoft,
                            textStyle: t.button,
                            minimumSize: const Size(44, 44),
                          ),
                          child: const Text('Skip'),
                        )
                      else
                        const SizedBox(height: 44),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _pages,
                    onPageChanged: (i) => setState(() => _page = i),
                    children: [
                      for (final p in _intro) _IntroView(page: p),
                      _buildSetup(context),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.md, Sp.gutter, Sp.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        label: 'Step ${_page + 1} of $total',
                        excludeSemantics: true,
                        child: Row(
                          children: [
                            Expanded(child: LedgerBar(value: (_page + 1) / total, height: 4)),
                            const SizedBox(width: Sp.md),
                            Text('${_page + 1} of $total', style: t.small),
                          ],
                        ),
                      ),
                      const SizedBox(height: Sp.lg),
                      if (onSetup)
                        LedgerButton(
                          label: _mode == _StartMode.fresh ? 'Start fresh' : 'Explore with sample data',
                          expand: true,
                          loading: _busy,
                          onPressed: _busy ? null : _finish,
                        )
                      else
                        LedgerButton(
                          label: _page == _setupIndex - 1 ? 'Set up FiNN' : 'Continue',
                          expand: true,
                          onPressed: () => _goTo(_page + 1),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSetup(BuildContext context) {
    final t = context.type;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.lg, Sp.gutter, Sp.lg),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text('A few details to begin', style: t.title)),
          const SizedBox(height: Sp.xs),
          Text('You can change any of this later in Settings.', style: t.label),
          const SizedBox(height: Sp.xl),
          LedgerTextField(
            label: 'What should we call you?',
            hint: 'Your first name',
            controller: _name,
            errorText: _nameError,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            maxLength: 40,
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
          const SizedBox(height: Sp.xl),
          LedgerSection(
            title: 'How would you like to start?',
            child: LedgerPanel(
              children: [
                LedgerOptionRow(
                  selected: _mode == _StartMode.fresh,
                  title: 'Start fresh',
                  subtitle: 'Begin with a clean slate and your own numbers.',
                  onTap: () => setState(() => _mode = _StartMode.fresh),
                ),
                // Sample data exists only in the local (mock) mode.
                if (!ref.watch(remoteModeProvider))
                  LedgerOptionRow(
                    selected: _mode == _StartMode.sample,
                    title: 'Explore with sample data',
                    subtitle: 'Look around with six months of realistic example data first.',
                    onTap: () => setState(() => _mode = _StartMode.sample),
                  ),
              ],
            ),
          ),
          MotionAnimatedSize(
            child: _mode == _StartMode.fresh
                ? Padding(
                    padding: const EdgeInsets.only(top: Sp.xl),
                    child: LedgerAmountField(
                      label: 'Opening balance · bank + cash today',
                      helper: 'Your balance builds from this number.',
                      controller: _balance,
                      errorText: _balanceError,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) {
                        if (_balanceError != null) setState(() => _balanceError = null);
                      },
                    ),
                  )
                : const Padding(
                    padding: EdgeInsets.only(top: Sp.lg),
                    child: LedgerNote(
                      text: 'Sample data is for exploring. You can reset to a clean slate any time from Settings.',
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _IntroView extends StatelessWidget {
  const _IntroView({required this.page});

  final _IntroPage page;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Sp.gutter + Sp.xs, Sp.xl, Sp.gutter + Sp.xs, Sp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(page.title, style: t.title)),
          const SizedBox(height: Sp.sm),
          Text(page.body, style: t.body.copyWith(color: c.inkSoft)),
          const SizedBox(height: Sp.xl),
          LedgerPanel(
            children: [
              for (final text in page.points)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md + 2),
                  child: Text(text, style: t.bodyStrong),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
