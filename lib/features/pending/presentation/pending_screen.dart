import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/async_view.dart';
import '../domain/pending_payment.dart';
import 'pending_ui.dart';

/// Money owed between the user and other people. Obligations only — the
/// cash balance changes when an item is settled.
class PendingScreen extends ConsumerStatefulWidget {
  const PendingScreen({super.key});

  @override
  ConsumerState<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends ConsumerState<PendingScreen> {
  PendingFilter _filter = const PendingFilter();

  void _set(PendingFilter f) => setState(() => _filter = f);

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(pendingOverviewProvider);
    return Scaffold(
      appBar: AppBar(
        actions: [
          FinnIconButton(
            icon: LucideIcons.plus,
            tooltip: 'Add money owed',
            variant: FinnIconButtonVariant.filled,
            onPressed: () => context.push(AppRoutes.newPending(owedToMe: _filter.direction == PendingDirection.owedToMe)),
          ),
          const SizedBox(width: Space.x3),
        ],
      ),
      body: AsyncView<PendingOverview>(
        value: overview,
        loading: const _PendingSkeleton(),
        builder: (context, o) => CustomScrollView(
          key: const PageStorageKey('pending-list'),
          slivers: [
            _boxed(StaggeredEntrance(child: _Header(overview: o))),
            _boxed(StaggeredEntrance(index: 1, child: _SummaryRow(overview: o))),
            _boxed(
              Padding(
                padding: const EdgeInsets.only(top: Space.x5),
                child: FinnSearchField(
                  hint: 'Search people or purposes',
                  onChanged: (q) => _set(PendingFilter(tab: _filter.tab, direction: _filter.direction, query: q)),
                ),
              ),
            ),
            _boxed(
              Padding(
                padding: const EdgeInsets.only(top: Space.x4),
                child: SegmentedTabs<PendingTab>(
                  items: [for (final t in PendingTab.values) SegmentItem(t, t.label, count: o.counts[t])],
                  selected: _filter.tab,
                  onChanged: (t) => _set(PendingFilter(tab: t, direction: _filter.direction, query: _filter.query)),
                ),
              ),
            ),
            _boxed(
              Padding(
                padding: const EdgeInsets.only(top: Space.x3, bottom: Space.x2),
                child: FilterChipBar<PendingDirection>(
                  padding: EdgeInsets.zero,
                  items: const [
                    FilterChipItem(PendingDirection.iOwe, 'I owe', icon: LucideIcons.arrowUpRight),
                    FilterChipItem(PendingDirection.owedToMe, 'I will receive', icon: LucideIcons.arrowDownLeft),
                  ],
                  selected: {?_filter.direction},
                  onChanged: (s) {
                    // Two chips act as an optional single filter.
                    final next = s.length == 2 ? s.difference({?_filter.direction}).first : s.firstOrNull;
                    _set(PendingFilter(tab: _filter.tab, direction: next, query: _filter.query));
                  },
                ),
              ),
            ),
            _PendingList(filter: _filter),
            SliverPadding(padding: EdgeInsets.only(bottom: context.bottomClearance)),
          ],
        ),
      ),
    );
  }
}

Widget _boxed(Widget child) => SliverToBoxAdapter(
      child: ResponsiveCenter(padding: const EdgeInsets.symmetric(horizontal: Space.gutter), child: child),
    );

class _Header extends StatelessWidget {
  const _Header({required this.overview});

  final PendingOverview overview;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text('Money owed', style: t.pageTitle)),
          const SizedBox(height: Space.x1),
          Text('What you owe and what others owe you. Not part of your balance until settled.', style: t.caption),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.overview});

  final PendingOverview overview;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final o = overview;
    String count(int n) => n == 0 ? 'Nothing open' : '$n open ${n == 1 ? 'item' : 'items'}';
    final overdueCaption = o.overdueCount == 0
        ? 'All on time'
        : [
            if (o.overdueToPay.isPositive) '${AmountText.formatted(o.overdueToPay)} to pay',
            if (o.overdueToCollect.isPositive) '${AmountText.formatted(o.overdueToCollect)} to collect',
          ].join(' · ');
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: StatTile(
              label: 'To pay · I owe',
              icon: LucideIcons.arrowUpRight,
              accent: c.negative,
              value: AmountText(o.toPay, style: t.amountMedium.copyWith(color: c.negative), fit: true),
              caption: count(o.payCount),
            ),
          ),
          const SizedBox(width: Space.x2),
          Expanded(
            child: StatTile(
              label: 'To collect · I will receive',
              icon: LucideIcons.arrowDownLeft,
              accent: c.positive,
              value: AmountText(o.toCollect, style: t.amountMedium.copyWith(color: c.positive), fit: true),
              caption: count(o.collectCount),
            ),
          ),
          const SizedBox(width: Space.x2),
          Expanded(
            child: StatTile(
              label: 'Overdue',
              icon: LucideIcons.triangleAlert,
              accent: o.overdueCount == 0 ? c.textSecondary : c.attention,
              value: Text('${o.overdueCount}', style: t.amountMedium),
              caption: overdueCaption,
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingList extends ConsumerWidget {
  const _PendingList({required this.filter});

  final PendingFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(pendingEntriesProvider(filter)).value ?? const <PendingEntry>[];
    if (entries.isEmpty) {
      return _boxed(Padding(padding: const EdgeInsets.only(top: Space.x6), child: _Empty(filter: filter)));
    }
    return SliverList.builder(
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        final Widget child = switch (e) {
          PendingPersonHeader() => _PersonHeader(header: e),
          PendingItemEntry(:final view, :final grouped) => Padding(
              key: ValueKey(view.payment.id),
              padding: EdgeInsets.only(top: Space.x2, left: grouped ? Space.x3 : 0),
              child: PendingCard(
                view: view,
                compact: grouped,
                onTap: () => context.push(AppRoutes.pendingItem(view.payment.id)),
                onSettle: () => context.push(AppRoutes.settlePending(view.payment.id)),
              ),
            ),
        };
        return ResponsiveCenter(padding: const EdgeInsets.symmetric(horizontal: Space.gutter), child: child);
      },
    );
  }
}

class _PersonHeader extends StatelessWidget {
  const _PersonHeader({required this.header});

  final PendingPersonHeader header;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final parts = <String>[
      if (header.toPay.isPositive) 'You owe ${AmountText.formatted(header.toPay)}',
      if (header.toCollect.isPositive) 'Owes you ${AmountText.formatted(header.toCollect)}',
    ];
    return Padding(
      key: ValueKey('person-${header.name}'),
      padding: const EdgeInsets.only(top: Space.x4),
      child: Semantics(
        header: true,
        label: '${header.name}, ${header.count} separate items',
        child: Row(
          children: [
            IconTile(icon: LucideIcons.user, background: c.surfaceMuted, foreground: c.textSecondary, size: 28, iconSize: 15),
            const SizedBox(width: Space.x2),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: header.name, style: t.bodyStrong),
                  TextSpan(text: '  ·  ${header.count} separate items', style: t.caption),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (parts.isNotEmpty && !AmountVisibility.hiddenOf(context))
              Text(parts.join(' · '), style: t.micro.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.filter});

  final PendingFilter filter;

  @override
  Widget build(BuildContext context) {
    if (filter.query.trim().isNotEmpty || filter.direction != null) {
      return const EmptyState(
        icon: LucideIcons.searchX,
        title: 'No matches',
        message: 'Try a different name or clear the filters.',
      );
    }
    return switch (filter.tab) {
      PendingTab.active => EmptyState(
          icon: LucideIcons.handshake,
          title: 'All square',
          message: 'Track money you owe or are owed — a shared bill, a loan to a friend, a reimbursement. '
              'Your balance changes only when you settle.',
          actionLabel: 'Add money owed',
          actionIcon: LucideIcons.plus,
          onAction: () => context.push(AppRoutes.newPending()),
        ),
      PendingTab.settled => const EmptyState(
          icon: LucideIcons.circleCheck,
          title: 'Nothing settled yet',
          message: 'Items you settle in full appear here with their history.',
        ),
      PendingTab.writtenOff => const EmptyState(
          icon: LucideIcons.ban,
          title: 'Nothing written off',
          message: 'Items you no longer expect to be paid appear here.',
        ),
    };
  }
}

class _PendingSkeleton extends StatelessWidget {
  const _PendingSkeleton();

  @override
  Widget build(BuildContext context) => const SkeletonPulse(
        child: Padding(
          padding: EdgeInsets.all(Space.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 180, height: 28),
              SizedBox(height: Space.x5),
              Row(children: [
                Expanded(child: CardSkeleton(height: 104)),
                SizedBox(width: Space.x2),
                Expanded(child: CardSkeleton(height: 104)),
                SizedBox(width: Space.x2),
                Expanded(child: CardSkeleton(height: 104)),
              ]),
              SizedBox(height: Space.x5),
              SkeletonBox(height: 44, radius: Radii.full),
              SizedBox(height: Space.x4),
              CardSkeleton(height: 112),
              SizedBox(height: Space.x2),
              CardSkeleton(height: 112),
            ],
          ),
        ),
      );
}

