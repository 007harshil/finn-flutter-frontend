import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../kit/kit.dart';
import '../../application/action_deck.dart';
import '../../execution/proposals.dart';
import 'action_outcome.dart';
import 'action_visuals.dart';
import 'agent_working.dart';
import 'change_review.dart';

/// Where one card stands.
enum _Phase {
  /// Waiting for the user's call.
  deciding,

  /// Approved; saved once the review is submitted.
  approved,

  /// Declined (before or while the review is being closed).
  declined,

  /// Approved and being written.
  saving,

  /// Has a confirmed outcome.
  settled,

  /// The agent is regenerating it.
  regenerating,

  /// Not reviewed (the turn stopped before it got there).
  idle,
}

/// The changes the agent proposed for one message, as a deck of cards: a
/// swipeable carousel when there are several, one card otherwise. Each
/// card is approved or declined on its own (or all at once) and stays on
/// the deck with its outcome: saved cards link to their record, declined
/// ones are muted and labelled, and can be retried in place ("Try 2").
class ActionDeckView extends StatefulWidget {
  const ActionDeckView({
    super.key,
    required this.deck,
    required this.reviewing,
    required this.active,
    required this.executing,
    required this.busy,
    required this.onDecide,
    required this.onDecideRest,
    required this.onRetry,
    required this.onOpen,
  });

  final ActionDeck deck;

  /// Whether a proposal waits for the user's decision.
  final bool Function(String proposalId) reviewing;

  /// The running turn works on this deck.
  final bool active;

  /// Approved changes are being written.
  final bool executing;

  /// A turn is running (retrying is not possible meanwhile).
  final bool busy;

  final void Function(String proposalId, CardDecision? decision) onDecide;

  /// Gives every undecided card [CardDecision] and submits the review.
  final ValueChanged<CardDecision> onDecideRest;
  final ValueChanged<String> onRetry;

  /// Opens a saved record's screen.
  final ValueChanged<String> onOpen;

  @override
  State<ActionDeckView> createState() => _ActionDeckViewState();
}

class _ActionDeckViewState extends State<ActionDeckView> {
  late final PageController _pages = PageController(viewportFraction: 0.94);
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  _Phase _phaseOf(DeckSlot slot) {
    if (slot.retrying) return _Phase.regenerating;
    final a = slot.current;
    if (a.record != null) return _Phase.settled;
    if (widget.reviewing(a.proposal.id)) {
      return switch (a.decision) {
        null => _Phase.deciding,
        CardDecision.approved => _Phase.approved,
        CardDecision.declined => _Phase.declined,
      };
    }
    if (widget.active) return a.decision == CardDecision.approved && widget.executing ? _Phase.saving : _Phase.declined;
    return _Phase.idle;
  }

  void _goTo(int page) {
    final duration = context.motion.normal;
    if (duration == Duration.zero || !_pages.hasClients) {
      if (_pages.hasClients) _pages.jumpToPage(page);
      setState(() => _page = page);
    } else {
      _pages.animateToPage(page, duration: duration, curve: context.motion.standard);
    }
  }

  void _decide(int index, CardDecision? decision) {
    final slots = widget.deck.slots;
    widget.onDecide(slots[index].current.proposal.id, decision);
    if (decision == null || slots.length < 2) return;
    // Move on to the next change that still needs a decision.
    for (var step = 1; step < slots.length; step++) {
      final i = (index + step) % slots.length;
      if (_phaseOf(slots[i]) == _Phase.deciding) {
        _goTo(i);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final slots = widget.deck.slots;
    final phases = [for (final s in slots) _phaseOf(s)];
    final pending = [
      for (final s in slots)
        if (widget.reviewing(s.current.proposal.id)) s.current,
    ];
    final undecided = pending.where((a) => a.decision == null).length;
    final many = slots.length > 1;
    final page = _page.clamp(0, slots.length - 1);

    Widget card(int i) => _DeckCard(
      slot: slots[i],
      phase: phases[i],
      canRetry: slots[i].canRetry && !widget.busy,
      onDecide: (d) => _decide(i, d),
      onRetry: () => widget.onRetry(slots[i].key),
      onOpen: widget.onOpen,
    );

    return Semantics(
      container: true,
      label: pending.isNotEmpty ? 'Review proposed changes' : 'Proposed changes',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DeckHeader(deck: widget.deck, phases: phases, pending: pending),
          const SizedBox(height: Sp.md),
          if (!many)
            card(0)
          else ...[
            _AdaptivePager(
              controller: _pages,
              count: slots.length,
              onPageChanged: (i) => setState(() => _page = i),
              builder: card,
            ),
            const SizedBox(height: Sp.xs),
            _PageDots(
              count: slots.length,
              page: page,
              colors: [for (var i = 0; i < slots.length; i++) _dotColor(slots[i], phases[i], c)],
              onPrevious: page > 0 ? () => _goTo(page - 1) : null,
              onNext: page < slots.length - 1 ? () => _goTo(page + 1) : null,
            ),
          ],
          if (pending.length > 1 && undecided > 0) ...[
            const SizedBox(height: Sp.sm),
            Row(
              children: [
                Expanded(
                  child: LedgerButton(
                    label: undecided == pending.length ? 'Decline all' : 'Decline rest',
                    variant: LedgerButtonVariant.secondary,
                    expand: true,
                    onPressed: () => widget.onDecideRest(CardDecision.declined),
                  ),
                ),
                const SizedBox(width: Sp.md),
                Expanded(
                  child: LedgerButton(
                    label: undecided == pending.length ? 'Approve all' : 'Approve rest ($undecided)',
                    icon: LucideIcons.checkCheck,
                    expand: true,
                    onPressed: () => widget.onDecideRest(CardDecision.approved),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static Color _dotColor(DeckSlot slot, _Phase phase, LedgerColors c) => switch (phase) {
    _Phase.deciding => c.ink,
    _Phase.approved || _Phase.saving => c.green,
    _Phase.declined || _Phase.idle => c.lineStrong,
    _Phase.regenerating => c.inkSoft,
    _Phase.settled => actionStatusVisual(slot.current.record!, c).$2,
  };
}

/// Title and state of the deck.
class _DeckHeader extends StatelessWidget {
  const _DeckHeader({required this.deck, required this.phases, required this.pending});

  final ActionDeck deck;
  final List<_Phase> phases;
  final List<DeckAttempt> pending;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final total = deck.slots.length;
    final saved = deck.saved;
    final declined = [
      for (final s in deck.slots)
        if (s.current.record?.status == ActionResultStatus.declined) s,
    ].length;

    final (String title, String subtitle) = switch (phases) {
      _ when pending.isNotEmpty => (
        pending.length == 1 ? 'Review this change' : 'Review ${pending.length} changes',
        pending.length == 1
            ? 'Nothing is saved until you approve.'
            : 'Swipe through them. Nothing is saved until you approve.',
      ),
      _ when phases.contains(_Phase.saving) => ('Saving your changes', 'Writing what you approved.'),
      _ when phases.contains(_Phase.regenerating) => ('Trying another way', 'Reading your request again.'),
      _ when phases.every((p) => p == _Phase.declined) => ('Nothing saved', 'You declined every change.'),
      _ => (
        switch (saved) {
          _ when saved == total => total == 1 ? 'Change saved' : 'All $total changes saved',
          0 => total == 1 ? 'Not saved' : 'No changes saved',
          _ => '$saved of $total changes saved',
        },
        declined > 0 ? 'Retry a declined change and FiNN will try another way.' : 'Each change shows what happened.',
      ),
    };

    return AnimatedSwitcher(
      duration: context.motion.fast,
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
      child: Column(
        key: ValueKey(title),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(title, style: t.heading)),
          const SizedBox(height: 2),
          Text(subtitle, style: t.label),
        ],
      ),
    );
  }
}

/// One change of the deck, drawn for its [phase].
class _DeckCard extends StatelessWidget {
  const _DeckCard({
    required this.slot,
    required this.phase,
    required this.canRetry,
    required this.onDecide,
    required this.onRetry,
    required this.onOpen,
  });

  final DeckSlot slot;
  final _Phase phase;
  final bool canRetry;
  final ValueChanged<CardDecision?> onDecide;
  final VoidCallback onRetry;
  final ValueChanged<String> onOpen;

  bool get _declined =>
      phase == _Phase.declined ||
      (phase == _Phase.settled && slot.current.record!.status == ActionResultStatus.declined);

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final attempt = slot.current;
    final record = attempt.record;
    final muted = _declined || phase == _Phase.saving || phase == _Phase.regenerating || phase == _Phase.idle;

    final rows = changeDetailRows(
      context,
      attempt.proposal,
      tag: slot.regenerated ? Text('Try ${slot.attempts.length}', style: t.small) : null,
      trailing: phase == _Phase.settled && record!.succeeded
          ? Semantics(
              label: 'Saved',
              excludeSemantics: true,
              child: Icon(LucideIcons.circleCheck, size: 20, color: c.green),
            )
          : null,
    );

    return LedgerPanel(
      children: [
        for (final r in rows) AnimatedOpacity(duration: context.motion.normal, opacity: muted ? 0.5 : 1, child: r),
        if (slot.note case final note?)
          Padding(
            padding: const EdgeInsets.all(Sp.md),
            child: LedgerNote(text: note, icon: LucideIcons.messageCircle),
          ),
        Padding(padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.md, Sp.md), child: _footer(context, c, t)),
      ],
    );
  }

  Widget _footer(BuildContext context, LedgerColors c, LedgerType t) {
    final record = slot.current.record;
    switch (phase) {
      case _Phase.deciding:
        return Padding(
          padding: const EdgeInsets.only(right: Sp.xs),
          child: Row(
            children: [
              Expanded(
                child: LedgerButton(
                  label: 'Decline',
                  variant: LedgerButtonVariant.secondary,
                  expand: true,
                  onPressed: () => onDecide(CardDecision.declined),
                ),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: LedgerButton(
                  label: 'Approve',
                  icon: LucideIcons.check,
                  expand: true,
                  onPressed: () => onDecide(CardDecision.approved),
                ),
              ),
            ],
          ),
        );
      case _Phase.approved:
        return _Status(
          icon: LucideIcons.check,
          color: c.green,
          label: 'Approved',
          text: 'Saved when you finish reviewing',
          action: LedgerButton(label: 'Undo', variant: LedgerButtonVariant.quiet, onPressed: () => onDecide(null)),
        );
      case _Phase.declined:
        final reviewing = slot.current.decision == CardDecision.declined && record == null;
        return _Status(
          icon: LucideIcons.circleSlash,
          color: c.inkSoft,
          label: 'Declined',
          text: 'Will not be saved',
          action: reviewing
              ? LedgerButton(label: 'Undo', variant: LedgerButtonVariant.quiet, onPressed: () => onDecide(null))
              : null,
        );
      case _Phase.saving:
      case _Phase.regenerating:
        final label = phase == _Phase.saving ? 'Saving…' : 'Finding another way…';
        return Semantics(
          liveRegion: true,
          label: label,
          excludeSemantics: true,
          child: SizedBox(
            height: 48,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(label, style: t.label),
                const SizedBox(height: Sp.sm),
                const Padding(
                  padding: EdgeInsets.only(right: Sp.xs),
                  child: AgentProgressLine(),
                ),
              ],
            ),
          ),
        );
      case _Phase.idle:
        return _Status(icon: LucideIcons.circleMinus, color: c.inkSoft, label: 'Not reviewed');
      case _Phase.settled:
        final (icon, color, label) = actionStatusVisual(record!, c);
        final route = actionRecordRoute(record);
        final visual = actionVisualFor(record.proposal.descriptor.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (record.message != null && !record.succeeded) ...[
              Padding(
                padding: const EdgeInsets.only(right: Sp.xs),
                child: Text(record.message!, style: t.label),
              ),
              const SizedBox(height: Sp.xs),
            ],
            _Status(
              icon: icon,
              color: color,
              label: label,
              action: route != null
                  ? RecordViewLink(label: 'View ${visual.module.toLowerCase()} details', onTap: () => onOpen(route))
                  : canRetry
                  ? LedgerButton(
                      label: 'Retry',
                      icon: LucideIcons.rotateCcw,
                      variant: LedgerButtonVariant.secondary,
                      small: true,
                      onPressed: onRetry,
                    )
                  : null,
            ),
          ],
        );
    }
  }
}

/// Status line of a card: icon and label (coloured only for meaning), an
/// optional note and one action on the right.
class _Status extends StatelessWidget {
  const _Status({required this.icon, required this.color, required this.label, this.text, this.action});

  final IconData icon;
  final Color color;
  final String label;
  final String? text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final note = text;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: Sp.sm),
          Text(label, style: t.labelStrong.copyWith(color: color)),
          if (note != null) ...[
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.small),
            ),
          ] else
            const Spacer(),
          ?action,
        ],
      ),
    );
  }
}

/// Dots (coloured by each change's state) with previous / next buttons.
class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.count,
    required this.page,
    required this.colors,
    required this.onPrevious,
    required this.onNext,
  });

  final int count;
  final int page;
  final List<Color> colors;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        LedgerIconButton(icon: LucideIcons.chevronLeft, tooltip: 'Previous change', onPressed: onPrevious),
        const SizedBox(width: Sp.xs),
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: context.motion.fast,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == page ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(color: colors[i], borderRadius: Rad.pill),
          ),
        const SizedBox(width: Sp.sm),
        Text('${page + 1} / $count', style: t.small),
        const SizedBox(width: Sp.xs),
        LedgerIconButton(icon: LucideIcons.chevronRight, tooltip: 'Next change', onPressed: onNext),
      ],
    );
  }
}

/// A page view whose height follows its pages: each page is measured and
/// the height blends between neighbours while swiping.
class _AdaptivePager extends StatefulWidget {
  const _AdaptivePager({
    required this.controller,
    required this.count,
    required this.builder,
    required this.onPageChanged,
  });

  final PageController controller;
  final int count;
  final Widget Function(int index) builder;
  final ValueChanged<int> onPageChanged;

  @override
  State<_AdaptivePager> createState() => _AdaptivePagerState();
}

class _AdaptivePagerState extends State<_AdaptivePager> {
  final _heights = <int, double>{};

  void _measured(int index, double height) {
    if (_heights[index] == height) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _heights[index] != height) setState(() => _heights[index] = height);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        final c = widget.controller;
        final fallback = c.initialPage.toDouble();
        final page = (c.hasClients && c.position.haveDimensions ? c.page ?? fallback : fallback).clamp(
          0.0,
          math.max(0, widget.count - 1).toDouble(),
        );
        final lo = page.floor();
        final hi = page.ceil();
        final known = _heights[lo] ?? _heights.values.firstOrNull ?? 320;
        final height = lerpDouble(known, _heights[hi] ?? known, page - lo)!;
        return SizedBox(height: height, child: child);
      },
      child: PageView.builder(
        controller: widget.controller,
        itemCount: widget.count,
        onPageChanged: widget.onPageChanged,
        itemBuilder: (context, i) => OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: double.infinity,
          child: _SizeReporter(
            onHeight: (h) => _measured(i, h),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.xs),
              child: widget.builder(i),
            ),
          ),
        ),
      ),
    );
  }
}

class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSizeReporter(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderSizeReporter renderObject) => renderObject.onHeight = onHeight;
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onHeight);

  ValueChanged<double> onHeight;

  @override
  void performLayout() {
    super.performLayout();
    onHeight(size.height);
  }
}
