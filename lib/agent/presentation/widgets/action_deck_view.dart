import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../design_system/design_system.dart';
import '../../application/action_deck.dart';
import '../../execution/proposals.dart';
import 'action_outcome.dart';
import 'action_visuals.dart';
import 'agent_logo.dart';
import 'agent_visualizer.dart';
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
/// ones are greyed out and stamped, and can be regenerated in place.
/// Regenerated changes are drawn in their own colours.
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
    final duration = context.motion.normal;
    if (duration == Duration.zero || !_pages.hasClients) {
      if (_pages.hasClients) _pages.jumpToPage(page);
      setState(() => _page = page);
    } else {
      _pages.animateToPage(page, duration: duration, curve: Curves2.emphasized);
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
    final c = context.colors;
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
      single: !many,
      canRetry: slots[i].canRetry && !widget.busy,
      onDecide: (d) => _decide(i, d),
      onRetry: () => widget.onRetry(slots[i].key),
      onOpen: widget.onOpen,
    );

    return Semantics(
      container: true,
      label: pending.isNotEmpty ? 'Review proposed changes' : 'Proposed changes',
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.xxl),
          border: Border.all(color: c.agentMid.withValues(alpha: 0.45), width: 1.2),
          boxShadow: Elevation.sm,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DeckHeader(deck: widget.deck, phases: phases, pending: pending),
            const SizedBox(height: Space.x3),
            if (!many)
              Padding(padding: const EdgeInsets.symmetric(horizontal: Space.x3), child: card(0))
            else ...[
              _AdaptivePager(
                controller: _pages,
                count: slots.length,
                onPageChanged: (i) => setState(() => _page = i),
                builder: card,
              ),
              const SizedBox(height: Space.x2),
              _PageDots(
                count: slots.length,
                page: page,
                colors: [for (var i = 0; i < slots.length; i++) _dotColor(slots[i], phases[i], c)],
                onPrevious: page > 0 ? () => _goTo(page - 1) : null,
                onNext: page < slots.length - 1 ? () => _goTo(page + 1) : null,
              ),
            ],
            if (pending.length > 1 && undecided > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x3, Space.x3, Space.x3, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: FinnButton(
                        label: undecided == pending.length ? 'Decline all' : 'Decline rest',
                        variant: FinnButtonVariant.outline,
                        onPressed: () => widget.onDecideRest(CardDecision.declined),
                      ),
                    ),
                    const SizedBox(width: Space.x3),
                    Expanded(
                      child: FinnButton(
                        label: undecided == pending.length ? 'Approve all' : 'Approve rest ($undecided)',
                        icon: LucideIcons.checkCheck,
                        onPressed: () => widget.onDecideRest(CardDecision.approved),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: Space.x3),
          ],
        ),
      ),
    );
  }

  static Color _dotColor(DeckSlot slot, _Phase phase, FinnColors c) => switch (phase) {
    _Phase.deciding => Colors.white,
    _Phase.approved || _Phase.saving => AgentLight.mint,
    _Phase.declined || _Phase.idle => c.textTertiary,
    _Phase.regenerating => AgentLight.magenta,
    _Phase.settled => actionStatusVisual(slot.current.record!, c).$2,
  };
}

/// Title, state and (while reviewing) headline numbers of the deck.
class _DeckHeader extends StatelessWidget {
  const _DeckHeader({required this.deck, required this.phases, required this.pending});

  final ActionDeck deck;
  final List<_Phase> phases;
  final List<DeckAttempt> pending;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final total = deck.slots.length;
    final saved = deck.saved;
    final declined = [
      for (final s in deck.slots)
        if (s.current.record?.status == ActionResultStatus.declined) s,
    ].length;

    final (String title, String subtitle) = switch (phases) {
      _ when pending.isNotEmpty => (
        pending.length == 1 ? 'Review this change' : 'Review ${pending.length} changes',
        pending.length == 1 ? 'Nothing is saved until you approve.' : 'Swipe through them. Nothing is saved until you approve.',
      ),
      _ when phases.contains(_Phase.saving) => (
        'Saving your changes…',
        'Writing what you approved.',
      ),
      _ when phases.contains(_Phase.regenerating) => (
        'Regenerating a change…',
        'Reading your request again.',
      ),
      _ when phases.every((p) => p == _Phase.declined) => ('Declined', 'Nothing was saved.'),
      _ => (
        switch (saved) {
          _ when saved == total => total == 1 ? 'Change saved' : 'All $total changes saved',
          0 => total == 1 ? 'Not saved' : 'No changes saved',
          _ => '$saved of $total changes saved',
        },
        declined > 0 ? 'Tap Retry on a declined change and FiNN will try another way.' : 'Every change below shows what happened.',
      ),
    };

    final movesMoney = pending.where((a) => a.proposal.descriptor.movesMoney).length;
    final permanent = pending.where((a) => !a.proposal.descriptor.reversible).length;
    final modules = {for (final a in pending) actionVisualFor(a.proposal.descriptor.id, c).module}.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, Space.x3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.agentStart.withValues(alpha: 0.16), c.agentEnd.withValues(alpha: 0.10)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const FinnAgentMark(size: 32),
              const SizedBox(width: Space.x3),
              Expanded(
                child: AnimatedSwitcher(
                  duration: context.motion.fast,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previous, ?current],
                  ),
                  child: Column(
                    key: ValueKey(title),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: t.sectionTitle),
                      Text(subtitle, style: t.caption.copyWith(color: c.textSecondary)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (pending.isNotEmpty) ...[
            const SizedBox(height: Space.x3),
            Row(
              children: [
                Expanded(
                  child: ImpactTile(
                    value: '${pending.length}',
                    label: pending.length == 1 ? 'Change' : 'Changes',
                    icon: LucideIcons.listChecks,
                    color: c.agentEnd,
                  ),
                ),
                const SizedBox(width: Space.x2),
                Expanded(
                  child: ImpactTile(value: '$movesMoney', label: 'Move money', icon: LucideIcons.indianRupee, color: c.attention),
                ),
                const SizedBox(width: Space.x2),
                Expanded(
                  child: permanent > 0
                      ? ImpactTile(value: '$permanent', label: 'Permanent', icon: LucideIcons.lock, color: c.negative)
                      : ImpactTile(
                          value: '$modules',
                          label: modules == 1 ? 'Area' : 'Areas',
                          icon: LucideIcons.layers,
                          color: c.agentStart,
                        ),
                ),
              ],
            ),
          ],
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
    required this.single,
    required this.canRetry,
    required this.onDecide,
    required this.onRetry,
    required this.onOpen,
  });

  final DeckSlot slot;
  final _Phase phase;

  /// The only card of the deck (its buttons are the deck's buttons).
  final bool single;
  final bool canRetry;
  final ValueChanged<CardDecision?> onDecide;
  final VoidCallback onRetry;
  final ValueChanged<String> onOpen;

  static const _regenColors = [AgentLight.magenta, AgentLight.violet, Palette.amber400];

  bool get _declined =>
      phase == _Phase.declined || (phase == _Phase.settled && slot.current.record!.status == ActionResultStatus.declined);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final attempt = slot.current;
    final record = attempt.record;
    final regenerated = slot.regenerated;
    final dimmed = _declined || phase == _Phase.saving || phase == _Phase.regenerating || phase == _Phase.idle;

    final Color edge = switch (phase) {
      _Phase.approved || _Phase.saving => AgentLight.mint.withValues(alpha: 0.6),
      _Phase.settled when record!.succeeded => c.positive.withValues(alpha: 0.55),
      _Phase.regenerating => AgentLight.magenta.withValues(alpha: 0.6),
      _ => c.border,
    };

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (regenerated) ...[
          _RegeneratedRibbon(slot: slot),
          const SizedBox(height: Space.x2_5),
        ],
        AnimatedOpacity(
          duration: context.motion.normal,
          opacity: dimmed ? 0.42 : 1,
          child: ChangeDetails(
            proposal: attempt.proposal,
            accent: regenerated ? AgentLight.magenta : null,
            trailing: phase == _Phase.settled && record!.succeeded
                ? Icon(LucideIcons.badgeCheck, size: 22, color: c.positive)
                : null,
          ),
        ),
        if (slot.note case final note?) ...[
          const SizedBox(height: Space.x2_5),
          _AgentNote(text: note),
        ],
        const SizedBox(height: Space.x3),
        _footer(context, c, t),
      ],
    );

    Widget body = AnimatedContainer(
      duration: context.motion.normal,
      padding: const EdgeInsets.all(Space.x3),
      decoration: BoxDecoration(
        color: regenerated ? Color.alphaBlend(AgentLight.magenta.withValues(alpha: 0.07), c.surfaceMuted) : c.surfaceMuted,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: regenerated ? null : Border.all(color: edge, width: 1.2),
      ),
      child: content,
    );
    if (regenerated) {
      // Regenerated changes get their own colours so they read as new.
      body = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.xl + 1.5),
          gradient: const LinearGradient(colors: _regenColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          boxShadow: [BoxShadow(color: AgentLight.magenta.withValues(alpha: 0.22), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: Padding(padding: const EdgeInsets.all(1.5), child: body),
      );
    }

    return Stack(
      children: [
        body,
        if (_declined)
          Positioned(top: regenerated ? Space.x10 : Space.x3, right: Space.x3, child: const _DeclinedStamp()),
        if (phase == _Phase.saving || phase == _Phase.regenerating)
          Positioned.fill(
            child: _CardLoader(
              colors: phase == _Phase.saving ? agentWorkColors(AgentWork.saving) : _regenColors,
              label: phase == _Phase.saving ? 'Saving…' : 'Finding another way…',
            ),
          ),
      ],
    );
  }

  Widget _footer(BuildContext context, FinnColors c, FinnTypography t) {
    final record = slot.current.record;
    switch (phase) {
      case _Phase.deciding:
        return Row(
          children: [
            Expanded(
              child: FinnButton(
                label: 'Decline',
                size: single ? FinnButtonSize.md : FinnButtonSize.sm,
                variant: FinnButtonVariant.outline,
                onPressed: () => onDecide(CardDecision.declined),
              ),
            ),
            const SizedBox(width: Space.x3),
            Expanded(
              child: FinnButton(
                label: 'Approve',
                icon: LucideIcons.check,
                size: single ? FinnButtonSize.md : FinnButtonSize.sm,
                onPressed: () => onDecide(CardDecision.approved),
              ),
            ),
          ],
        );
      case _Phase.approved:
        return _StatusRow(
          pill: const StatusPill(label: 'Approved', color: AgentLight.mint, icon: LucideIcons.check),
          text: 'Saved when you finish reviewing',
          action: _TextAction(label: 'Undo', onTap: () => onDecide(null)),
        );
      case _Phase.declined:
        final reviewing = slot.current.decision == CardDecision.declined && record == null;
        return _StatusRow(
          pill: StatusPill(label: 'Declined', color: c.textTertiary, icon: LucideIcons.circleX),
          text: 'Will not be saved',
          action: reviewing ? _TextAction(label: 'Undo', onTap: () => onDecide(null)) : null,
        );
      case _Phase.saving:
      case _Phase.regenerating:
        // Same height as the settled footer so the card does not jump.
        return const SizedBox(height: 32);
      case _Phase.idle:
        return _StatusRow(
          pill: StatusPill(label: 'Not reviewed', color: c.textTertiary, icon: LucideIcons.circleMinus),
        );
      case _Phase.settled:
        final (icon, color, label) = actionStatusVisual(record!, c);
        final route = actionRecordRoute(record);
        final visual = actionVisualFor(record.proposal.descriptor.id, c);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (record.message != null && !record.succeeded) ...[
              Text(record.message!, style: t.caption.copyWith(color: c.textSecondary)),
              const SizedBox(height: Space.x2),
            ],
            Row(
              children: [
                StatusPill(label: label, color: color, icon: icon),
                const Spacer(),
                if (route != null)
                  RecordViewLink(label: 'View ${visual.module.toLowerCase()} details', onTap: () => onOpen(route)),
                if (canRetry)
                  FinnButton(
                    label: 'Retry',
                    icon: LucideIcons.rotateCcw,
                    size: FinnButtonSize.sm,
                    variant: FinnButtonVariant.secondary,
                    onPressed: onRetry,
                  ),
              ],
            ),
          ],
        );
    }
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.pill, this.text, this.action});

  final Widget pill;
  final String? text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          pill,
          if (text != null) ...[
            const SizedBox(width: Space.x2),
            Expanded(
              child: Text(
                text!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.caption.copyWith(color: context.colors.textSecondary),
              ),
            ),
          ] else
            const Spacer(),
          ?action,
        ],
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        scale: 0.94,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: Space.x1_5),
          child: Text(
            label,
            style: context.text.caption.copyWith(color: AgentLight.cyan, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

/// "Regenerated · try 2", with the change it replaces struck through.
class _RegeneratedRibbon extends StatelessWidget {
  const _RegeneratedRibbon({required this.slot});

  final DeckSlot slot;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final previous = slot.attempts[slot.attempts.length - 2];
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: Space.x0_5 + 1),
          decoration: BoxDecoration(
            borderRadius: Radii.rFull,
            gradient: const LinearGradient(colors: [AgentLight.magenta, AgentLight.violet]),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.sparkles, size: 11, color: Colors.white),
              const SizedBox(width: Space.x1),
              Text(
                'REGENERATED · TRY ${slot.attempts.length}',
                style: t.micro.copyWith(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 0.6),
              ),
            ],
          ),
        ),
        const SizedBox(width: Space.x2),
        Expanded(
          child: Text(
            previous.proposal.preview.summary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.caption.copyWith(
              color: Colors.white.withValues(alpha: 0.45),
              decoration: TextDecoration.lineThrough,
              decorationColor: Colors.white.withValues(alpha: 0.45),
            ),
          ),
        ),
      ],
    );
  }
}

/// What the agent said on this card (e.g. a question after a retry).
class _AgentNote extends StatelessWidget {
  const _AgentNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.x2_5),
      decoration: BoxDecoration(
        color: AgentLight.magenta.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AgentLight.magenta.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FinnAgentMark(size: 18),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Text(
              text,
              style: context.text.caption.copyWith(color: Colors.white.withValues(alpha: 0.9), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rubber-stamp mark on a declined card.
class _DeclinedStamp extends StatelessWidget {
  const _DeclinedStamp();

  @override
  Widget build(BuildContext context) {
    final color = Colors.white.withValues(alpha: 0.78);
    return Semantics(
      label: 'Declined',
      excludeSemantics: true,
      child: Transform.rotate(
        angle: -0.14,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.x2_5, vertical: Space.x1),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1330).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: color, width: 1.6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.ban, size: 13, color: color),
              const SizedBox(width: Space.x1),
              Text(
                'DECLINED',
                style: context.text.micro.copyWith(color: color, fontWeight: FontWeight.w900, letterSpacing: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loader over one card (saving it, or regenerating it).
class _CardLoader extends StatelessWidget {
  const _CardLoader({required this.colors, required this.label});

  final List<Color> colors;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.xl),
          gradient: RadialGradient(
            colors: [const Color(0xFF070E26).withValues(alpha: 0.72), const Color(0xFF070E26).withValues(alpha: 0.2)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OrbitLoader(size: 52, colors: colors),
              const SizedBox(height: Space.x2),
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (r) => LinearGradient(colors: [colors[0], colors[2]]).createShader(r),
                child: Text(label, style: context.text.label.copyWith(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
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
    final t = context.text;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Arrow(icon: LucideIcons.chevronLeft, tooltip: 'Previous change', onTap: onPrevious),
        const SizedBox(width: Space.x2),
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: context.motion.fast,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == page ? 20 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: colors[i].withValues(alpha: i == page ? 1 : 0.55),
              borderRadius: Radii.rFull,
            ),
          ),
        const SizedBox(width: Space.x2),
        Text('${page + 1} / $count', style: t.micro.copyWith(color: Colors.white.withValues(alpha: 0.6))),
        const SizedBox(width: Space.x2),
        _Arrow(icon: LucideIcons.chevronRight, tooltip: 'Next change', onTap: onNext),
      ],
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        excludeSemantics: true,
        child: PressableScale(
          onTap: onTap,
          enabled: enabled,
          scale: 0.9,
          child: SizedBox.square(
            dimension: 40,
            child: Icon(icon, size: 18, color: Colors.white.withValues(alpha: enabled ? 0.85 : 0.25)),
          ),
        ),
      ),
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
        final page = (c.hasClients && c.position.haveDimensions ? c.page ?? fallback : fallback)
            .clamp(0.0, math.max(0, widget.count - 1).toDouble());
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
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: Space.x1), child: widget.builder(i)),
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
