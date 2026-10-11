import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/time/clock.dart';
import '../../../data/local/local_data_store.dart';
import '../../../design_system/design_system.dart';
import '../../settings/domain/financial_profile.dart';

class _IntroPage {
  const _IntroPage(this.icon, this.eyebrow, this.title, this.body, this.points);
  final IconData icon;
  final String eyebrow;
  final String title;
  final String body;
  final List<(IconData, String)> points;
}

const _intro = [
  _IntroPage(
    LucideIcons.sun,
    'CLARITY',
    'See where your money stands',
    'One calm view of what you can spend, what is set aside, and what is coming up.',
    [
      (LucideIcons.wallet, 'Available to spend, explained'),
      (LucideIcons.calendarClock, 'EMIs, renewals and dues ahead of time'),
    ],
  ),
  _IntroPage(
    LucideIcons.target,
    'CONTROL',
    'Plan with intention',
    'Budgets, goals, loans and an emergency fund that work together, not in silos.',
    [
      (LucideIcons.chartPie, 'Budgets that warn before you overspend'),
      (LucideIcons.piggyBank, 'Goals and a safety net that grow steadily'),
    ],
  ),
  _IntroPage(
    LucideIcons.lock,
    'PRIVACY FIRST',
    'Your data stays on this device',
    'No bank logins, no ads, no selling your data. You decide what to record.',
    [
      (LucideIcons.smartphone, 'Stored locally on your phone'),
      (LucideIcons.download, 'Export a copy whenever you like'),
    ],
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
    _pages.animateToPage(index, duration: context.motion.page, curve: Curves2.standard);
  }

  Future<void> _finish() async {
    if (_busy) return;
    final name = _name.text.trim();
    final rawBalance = _balance.text.trim();
    final balance = rawBalance.isEmpty ? Money.zero : AmountField.parse(rawBalance);
    setState(() {
      _nameError = name.isEmpty ? 'Please tell us what to call you' : null;
      _balanceError = _mode == _StartMode.fresh && balance == null ? 'Enter a valid amount, e.g. 25,000' : null;
    });
    if (_nameError != null || _balanceError != null) return;

    setState(() => _busy = true);
    try {
      final repos = ref.read(financeRepositoriesProvider);
      final today = ref.read(clockProvider).today();
      if (_mode == _StartMode.fresh) {
        await ref.read(localDataStoreProvider).reseed(DataScenario.empty, today);
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
    final c = context.colors;
    final onSetup = _page == _setupIndex;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: ResponsiveCenter(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x2, Space.x2, 0),
                child: Row(
                  children: [
                    Text('FiNN', style: context.text.title.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                    const Spacer(),
                    if (!onSetup)
                      TextButton(
                        onPressed: () => _goTo(_setupIndex),
                        style: TextButton.styleFrom(
                          foregroundColor: c.textSecondary,
                          minimumSize: const Size(Dimens.minTouch, Dimens.minTouch),
                        ),
                        child: const Text('Skip'),
                      )
                    else
                      const SizedBox(height: Dimens.minTouch),
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
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x3, Space.gutter, Space.x4),
                child: Column(
                  children: [
                    _PageDots(count: _setupIndex + 1, index: _page),
                    const SizedBox(height: Space.x4),
                    if (onSetup)
                      FinnButton(
                        label: _mode == _StartMode.fresh ? 'Start fresh' : 'Explore with sample data',
                        icon: LucideIcons.arrowRight,
                        size: FinnButtonSize.lg,
                        expand: true,
                        loading: _busy,
                        onPressed: _busy ? null : _finish,
                      )
                    else
                      FinnButton(
                        label: _page == _setupIndex - 1 ? 'Set up FiNN' : 'Continue',
                        icon: LucideIcons.arrowRight,
                        size: FinnButtonSize.lg,
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
    );
  }

  Widget _buildSetup(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x4, Space.gutter, Space.x4),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('LET\'S GET YOU SET UP', style: t.eyebrow),
          const SizedBox(height: Space.x2),
          Text('A few details to begin', style: t.pageTitle),
          const SizedBox(height: Space.x1_5),
          Text('You can change any of this later in Settings.', style: t.caption),
          const SizedBox(height: Space.x6),
          FinnTextField(
            label: 'What should we call you?',
            hint: 'Your first name',
            controller: _name,
            errorText: _nameError,
            prefixIcon: LucideIcons.userRound,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            maxLength: 40,
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
          const SizedBox(height: Space.x5),
          Text('HOW WOULD YOU LIKE TO START?', style: t.eyebrow),
          const SizedBox(height: Space.x2_5),
          _ModeCard(
            selected: _mode == _StartMode.fresh,
            icon: LucideIcons.sprout,
            title: 'Start fresh',
            body: 'Begin with a clean slate and your own numbers.',
            onTap: () => setState(() => _mode = _StartMode.fresh),
          ),
          const SizedBox(height: Space.x2_5),
          _ModeCard(
            selected: _mode == _StartMode.sample,
            icon: LucideIcons.sparkles,
            title: 'Explore with sample data',
            body: 'Look around with six months of realistic example data first.',
            onTap: () => setState(() => _mode = _StartMode.sample),
          ),
          MotionAnimatedSize(
            child: _mode == _StartMode.fresh
                ? Padding(
                    padding: const EdgeInsets.only(top: Space.x5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AmountField(
                          label: 'Opening balance · bank + cash today',
                          controller: _balance,
                          errorText: _balanceError,
                          textInputAction: TextInputAction.done,
                          onChanged: (_) {
                            if (_balanceError != null) setState(() => _balanceError = null);
                          },
                        ),
                        const SizedBox(height: Space.x1_5),
                        Text(
                          'Add up your bank accounts and cash in hand. Your balance builds from this number.',
                          style: t.caption,
                        ),
                      ],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(top: Space.x4),
                    child: InfoBanner(
                      message: 'Sample data is for exploring. You can reset to a clean slate any time from Settings.',
                      icon: LucideIcons.info,
                      tone: FinnTone.info,
                      title: c.isDark ? null : null,
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
    final c = context.colors;
    final t = context.text;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: Space.x6, vertical: Space.x8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(
            icon: page.icon,
            background: c.primary,
            foreground: c.onPrimary,
            size: 64,
            radius: Radii.xxl,
            iconSize: 30,
          ),
          const SizedBox(height: Space.x8),
          Text(page.eyebrow, style: t.eyebrow.copyWith(color: c.attention)),
          const SizedBox(height: Space.x2),
          Semantics(header: true, child: Text(page.title, style: t.display)),
          const SizedBox(height: Space.x3),
          Text(page.body, style: t.body.copyWith(color: c.textSecondary, fontSize: 16)),
          const SizedBox(height: Space.x6),
          for (final (icon, text) in page.points)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.x3),
              child: Row(
                children: [
                  IconTile(
                    icon: icon,
                    background: c.surfaceMuted,
                    foreground: c.textPrimary,
                    size: 36,
                    radius: Radii.lg,
                    iconSize: 17,
                  ),
                  const SizedBox(width: Space.x3),
                  Expanded(child: Text(text, style: t.bodyStrong)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: FinnCard(
        onTap: onTap,
        border: BorderSide(color: selected ? c.primary : c.border, width: selected ? 2 : 1),
        child: Row(
          children: [
            IconTile(
              icon: icon,
              background: selected ? c.primary : c.surfaceMuted,
              foreground: selected ? c.onPrimary : c.textPrimary,
              size: 40,
              radius: Radii.lg,
              iconSize: 19,
            ),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.bodyStrong),
                  const SizedBox(height: Space.x0_5),
                  Text(body, style: t.caption),
                ],
              ),
            ),
            const SizedBox(width: Space.x2),
            Icon(
              selected ? LucideIcons.circleCheck : LucideIcons.circle,
              size: 22,
              color: selected ? c.primary : c.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'Page ${index + 1} of $count',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: context.motion.normal,
              curve: Curves2.standard,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == index ? c.primary : c.borderStrong,
                borderRadius: Radii.rFull,
              ),
            ),
        ],
      ),
    );
  }
}
