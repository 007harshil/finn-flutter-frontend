import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../ui/ui.dart';
import '../../application/action_deck.dart';
import '../../execution/proposals.dart';
import 'action_outcome.dart';
import 'action_visuals.dart';
import 'agent_progress.dart';
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

/// The changes the agent proposed for one message, as one panel: a
/// swipeable carousel when there are several, one card otherwise. Each
/// card is approved or declined on its own (or all at once) and stays with
/// its outcome: saved cards link to their record, declined ones are dimmed
/// and can be regenerated in place.
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

  /// A turn is running (regenerating is not possible meanwhile).
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
    final duration = UiMotion.of(context).normal;
    if (duration == Duration.zero || !_pages.hasClients) {
      if (_pages.hasClients) _pages.jumpToPage(page);
      setState(() => _page = page);
    } else {
      _pages.animateToPage(page, duration: duration, curve: UiMotion.ease);
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
    final t = UiType.of(context);
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
      framed: many,
      canRetry: slots[i].canRetry && !widget.busy,
      onDecide: (d) => _decide(i, d),
      onRetry: () => widget.onRetry(slots[i].key),
      onOpen: widget.onOpen,
    );

    return Semantics(
      container: true,
      label: pending.isNotEmpty ? 'Review proposed changes' : 'Proposed changes',
      child: UiPanel(
        padding: const EdgeInsets.symmetric(vertical: UiSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: UiSpace.lg),
              child: _DeckHeader(deck: widget.deck, phases: phases, pending: pending),
            ),
            const SizedBox(height: UiSpace.lg),
            if (!many)
              Padding(padding: const EdgeInsets.symmetric(horizontal: UiSpace.lg), child: card(0))
            else ...[
              _AdaptivePager(
                controller: _pages,
                count: slots.length,
                onPageChanged: (i) => setState(() => _page = i),
                builder: card,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  UiStepButton(
                    icon: LucideIcons.chevronLeft,
                    tooltip: 'Previous change',
                    onPressed: page > 0 ? () => _goTo(page - 1) : null,
                  ),
                  Semantics(liveRegion: true, child: Text('${page + 1} / ${slots.length}', style: t.small)),
                  UiStepButton(
                    icon: LucideIcons.chevronRight,
                    tooltip: 'Next change',
                    onPressed: page < slots.length - 1 ? () => _goTo(page + 1) : null,
                  ),
                ],
              ),
            ],
            if (pending.length > 1 && undecided > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: UiSpace.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    UiTextButton(
                      label: undecided == pending.length ? 'Decline all' : 'Decline rest',
                      onTap: () => widget.onDecideRest(CardDecision.declined),
                    ),
                    UiChipButton(
                      label: undecided == pending.length ? 'Approve all' : 'Approve rest ($undecided)',
                      trailingIcon: LucideIcons.checkCheck,
                      selected: true,
                      onTap: () => widget.onDecideRest(CardDecision.approved),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What the deck is waiting for, or what happened to it.
class _DeckHeader extends StatelessWidget {
  const _DeckHeader({required this.deck, required this.phases, required this.pending});

  final ActionDeck deck;
  final List<_Phase> phases;
  final List<DeckAttempt> pending;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    final total = deck.slots.length;
    final saved = deck.saved;
    final declined = [
      for (final s in deck.slots)
        if (s.current.record?.status == ActionResultStatus.declined) s,
    ].length;

    final (String title, String? subtitle) = switch (phases) {
      _ when pending.isNotEmpty => (
        pending.length == 1 ? 'Review this change' : 'Review ${pending.length} changes',
        'Nothing is saved until you approve.',
      ),
      _ when phases.contains(_Phase.saving) => ('Saving your changes…', null),
      _ when phases.contains(_Phase.regenerating) => ('Regenerating a change…', null),
      _ when phases.every((p) => p == _Phase.declined) => ('Nothing saved', null),
      _ => (
        switch (saved) {
          _ when saved == total => total == 1 ? 'Change saved' : 'All $total changes saved',
          0 => total == 1 ? 'Not saved' : 'No changes saved',
          _ => '$saved of $total changes saved',
        },
        declined > 0 ? 'Retry a declined change and FiNN will try another way.' : null,
      ),
    };

    return AnimatedSwitcher(
      duration: UiMotion.of(context).quick,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, ?current],
      ),
      child: Column(
        key: ValueKey(title),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(title, style: t.section)),
          if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle, style: t.small)],
        ],
      ),
    );
  }
}

/// One change of the deck, drawn for its [phase]. In a carousel each card
/// gets a hairline frame so neighbours read as separate.
class _DeckCard extends StatelessWidget {
  const _DeckCard({
    required this.slot,
    required this.phase,
    required this.framed,
    required this.canRetry,
    required this.onDecide,
    required this.onRetry,
    required this.onOpen,
  });

  final DeckSlot slot;
  final _Phase phase;
  final bool framed;
  final bool canRetry;
  final ValueChanged<CardDecision?> onDecide;
  final VoidCallback onRetry;
  final ValueChanged<String> onOpen;

  bool get _declined =>
      phase == _Phase.declined || (phase == _Phase.settled && slot.current.record!.status == ActionResultStatus.declined);

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final attempt = slot.current;
    final record = attempt.record;
    final dimmed = _declined || phase == _Phase.saving || phase == _Phase.regenerating || phase == _Phase.idle;
    final Widget? status = switch (phase) {
      _ when _declined => _Tag(icon: LucideIcons.circleX, label: 'Declined', color: c.inkSoft),
      _Phase.settled when record!.succeeded => Icon(LucideIcons.badgeCheck, size: 20, color: c.positive),
      _ => null,
    };

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (slot.regenerated) ...[
          _Tag(icon: LucideIcons.rotateCcw, label: 'Regenerated · try ${slot.attempts.length}', color: c.info),
          const SizedBox(height: UiSpace.sm),
        ],
        AnimatedOpacity(
          duration: UiMotion.of(context).normal,
          opacity: dimmed ? 0.45 : 1,
          child: ChangeDetails(proposal: attempt.proposal, trailing: status),
        ),
        if (slot.note case final note?) UiNotice(icon: LucideIcons.messageSquare, text: note),
        const SizedBox(height: UiSpace.md),
        _footer(context, c, t),
      ],
    );
    if (!framed) return content;
    return Container(
      padding: const EdgeInsets.all(UiSpace.md + 2),
      decoration: BoxDecoration(
        borderRadius: UiRadius.control,
        border: Border.all(color: slot.regenerated ? c.info.withValues(alpha: 0.5) : c.hairline),
      ),
      child: content,
    );
  }

  Widget _footer(BuildContext context, UiColors c, UiType t) {
    final record = slot.current.record;
    switch (phase) {
      case _Phase.deciding:
        return Row(
          children: [
            Expanded(
              child: UiSecondaryButton(label: 'Decline', onPressed: () => onDecide(CardDecision.declined)),
            ),
            const SizedBox(width: UiSpace.md),
            Expanded(
              child: UiPrimaryButton(
                label: 'Approve',
                icon: LucideIcons.check,
                onPressed: () => onDecide(CardDecision.approved),
              ),
            ),
          ],
        );
      case _Phase.approved:
        return _StatusLine(
          icon: LucideIcons.check,
          color: c.positive,
          text: 'Approved · saved when you finish',
          action: UiTextButton(label: 'Undo', onTap: () => onDecide(null)),
        );
      case _Phase.declined:
        final reviewing = slot.current.decision == CardDecision.declined && record == null;
        return _StatusLine(
          icon: LucideIcons.circleX,
          color: c.inkSoft,
          text: 'Will not be saved',
          action: reviewing ? UiTextButton(label: 'Undo', onTap: () => onDecide(null)) : null,
        );
      case _Phase.saving:
      case _Phase.regenerating:
        return SizedBox(
          height: UiSpace.touch,
          child: Row(
            children: [
              const AgentSpinner(),
              const SizedBox(width: UiSpace.md),
              Text(phase == _Phase.saving ? 'Saving…' : 'Finding another way…', style: t.label),
            ],
          ),
        );
      case _Phase.idle:
        return _StatusLine(icon: LucideIcons.circleMinus, color: c.inkSoft, text: 'Not reviewed');
      case _Phase.settled:
        final (icon, color, label) = actionStatusVisual(record!, c);
        final route = actionRecordRoute(record);
        final visual = actionVisualFor(record.proposal.descriptor.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (record.message != null && !record.succeeded) ...[
              Text(record.message!, style: t.small),
              const SizedBox(height: UiSpace.xs),
            ],
            _StatusLine(
              icon: icon,
              color: color,
              text: label,
              action: route != null
                  ? RecordViewLink(label: 'View ${visual.module.toLowerCase()} details', onTap: () => onOpen(route))
                  : canRetry
                  ? UiChipButton(label: 'Retry', trailingIcon: LucideIcons.rotateCcw, onTap: onRetry)
                  : null,
            ),
          ],
        );
    }
  }
}

/// Icon + short status, with an optional action at the end.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.icon, required this.color, required this.text, this.action});

  final IconData icon;
  final Color color;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: UiSpace.touch),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: UiSpace.sm),
          Expanded(
            child: Text(text, style: t.label.copyWith(color: color == UiColors.of(context).inkSoft ? null : color)),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Small icon + word ("Declined", "Regenerated · try 2").
class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label, style: t.small.copyWith(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// A [PageView] whose height follows the page on screen (cards differ in
/// height), easing between neighbours while swiping.
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
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: UiSpace.xs), child: widget.builder(i)),
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
