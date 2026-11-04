import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/time/clock.dart';
import '../../../data/local/local_data_store.dart';
import '../../../kit/kit.dart';
import '../../accounts/domain/money_account.dart';
import '../../settings/domain/financial_profile.dart';

class _IntroPage {
  const _IntroPage(this.title, this.icon, this.points);
  final String title;
  final IconData icon;

  /// (icon, text) lines on the khata page.
  final List<(IconData, String)> points;
}

const _intro = [
  _IntroPage(
    'See where your money stands',
    LucideIcons.wallet,
    [(LucideIcons.coins, 'Available to spend'), (LucideIcons.calendarClock, 'EMIs, renewals and dues ahead')],
  ),
  _IntroPage(
    'Plan with intention',
    LucideIcons.target,
    [(LucideIcons.chartPie, 'Budgets that warn early'), (LucideIcons.shield, 'Goals and a safety net')],
  ),
  _IntroPage(
    'Your data, kept private',
    LucideIcons.lock,
    [(LucideIcons.ban, 'No bank logins, no ads'), (LucideIcons.download, 'Export or delete anytime')],
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
      await runWithLoader(context, () async {
        final repos = ref.read(financeRepositoriesProvider);
        final today = ref.read(clockProvider).today();
        // Connected: the account is the dataset; only the profile is written
        // (through the `profile.update` action endpoint).
        final remote = ref.read(remoteModeProvider);
        if (_mode == _StartMode.fresh) {
          if (!remote) await ref.read(localDataStoreProvider).reseed(DataScenario.empty, today);
          await repos.profile.set(FinancialProfile(displayName: name, openingBalance: balance!, openingDate: today));
          if (!remote) {
            // The ledger reads the Cash account; the server does this itself.
            final cash = await repos.moneyAccounts.getById(cashAccountId);
            if (cash != null) {
              await repos.moneyAccounts.save(cash.copyWith(
                opening: balance,
                openingDate: today,
                updatedAt: DateTime.now(),
                version: cash.version + 1,
              ));
            }
          }
        } else {
          final existing = repos.profile.current;
          await repos.profile.set(
            existing?.copyWith(displayName: name) ??
                FinancialProfile(displayName: name, openingBalance: Money.zero, openingDate: today),
          );
        }
        await ref.read(settingsProvider.notifier).update((s) => s.copyWith(onboardingComplete: true));
      });
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
                            Expanded(child: LedgerBar(value: (_page + 1) / total, height: 4, color: context.ink.marigold)),
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
                  onTap: () => setState(() => _mode = _StartMode.fresh),
                ),
                // Sample data exists only in the local (mock) mode.
                if (!ref.watch(remoteModeProvider))
                  LedgerOptionRow(
                    selected: _mode == _StartMode.sample,
                    title: 'Explore with sample data',
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
                      controller: _balance,
                      errorText: _balanceError,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) {
                        if (_balanceError != null) setState(() => _balanceError = null);
                      },
                    ),
                  )
                : const SizedBox.shrink(),
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
      padding: const EdgeInsets.fromLTRB(Sp.gutter + Sp.xs, Sp.lg, Sp.gutter + Sp.xs, Sp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Bahi illustration: the page's mark in a marigold seal on the
          // indigo slab.
          ExcludeSemantics(
            child: Container(
              height: 180,
              decoration: BoxDecoration(gradient: c.deepGradient, borderRadius: Rad.rLg),
              child: Center(
                child: Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: c.heroFigure.withValues(alpha: 0.35), width: 10),
                  ),
                  child: Center(
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(color: c.heroFigure, shape: BoxShape.circle),
                      child: Icon(page.icon, size: 32, color: const Color(0xFF2A1A00)),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: Sp.xl),
          Semantics(header: true, child: Text(page.title, style: t.title.wide(114).copyWith(fontSize: 30))),
          const SizedBox(height: Sp.md),
          Container(width: 44, height: 4, decoration: BoxDecoration(color: c.marigold, borderRadius: Rad.pill)),
          const SizedBox(height: Sp.xl),
          LedgerPanel(
            khata: true,
            dividerIndent: 0,
            children: [
              for (final (icon, text) in page.points)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
                  child: Row(
                    children: [
                      IconWell(icon: icon, size: 36, color: c.brand, background: c.surface),
                      const SizedBox(width: Sp.md + 10),
                      Expanded(child: Text(text, style: t.bodyStrong)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
