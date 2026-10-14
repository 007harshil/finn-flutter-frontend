import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/async_view.dart';
import '../../alerts/presentation/alert_visuals.dart' show MaybeAnimate;
import '../application/pending_actions.dart';
import '../domain/pending_payment.dart';
import 'pending_split_ui.dart';
import 'pending_ui.dart';

enum _Menu { edit, remind, writeOff, delete }

/// One pending item: how much is left, how far along it is (money and
/// time), what to do next, then the details and settlement history.
class PendingDetailScreen extends ConsumerStatefulWidget {
  const PendingDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<PendingDetailScreen> createState() => _PendingDetailScreenState();
}

class _PendingDetailScreenState extends ConsumerState<PendingDetailScreen> {
  final _key = newIdempotencyKey();

  Future<void> _menu(PendingView v) async {
    final hasSettlements = v.settlements.isNotEmpty;
    final p = v.payment;
    final first = p.counterparty.split(' ').first;
    // Shared items: only the creator edits or deletes; only the person who
    // is owed can write it off.
    final otherCreated = p.link != null && !p.link!.createdByMe;
    final canWriteOff = !(p.isShared && p.direction.isOwe);
    final choice = await showFinnActionMenu<_Menu>(
      context,
      title: p.purpose,
      items: [
        FinnMenuItem(
          value: _Menu.edit,
          label: otherCreated ? 'Edit — only $first can, they added it' : 'Edit details',
          icon: LucideIcons.pencil,
          enabled: !otherCreated,
        ),
        if (v.status.isActive && !p.direction.isOwe)
          const FinnMenuItem(value: _Menu.remind, label: 'Send a reminder', icon: LucideIcons.send),
        if (v.status.isActive)
          FinnMenuItem(
            value: _Menu.writeOff,
            label: canWriteOff ? 'Write off what is left' : 'Write off — only $first can, they are owed',
            icon: LucideIcons.ban,
            enabled: canWriteOff,
          ),
        FinnMenuItem(
          value: _Menu.delete,
          label: otherCreated
              ? 'Delete — only $first can'
              : (hasSettlements ? 'Delete — unavailable, settlements exist' : 'Delete'),
          icon: LucideIcons.trash2,
          destructive: true,
          enabled: !hasSettlements && !otherCreated,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _Menu.edit:
        context.push(AppRoutes.editPending(v.payment.id));
      case _Menu.remind:
        await sharePendingReminder(context, v);
      case _Menu.writeOff:
        await runAction(context, ref,
            action: const CancelPendingAction(), input: PendingIdInput(id: v.payment.id), idempotencyKey: '$_key-off');
      case _Menu.delete:
        final done = await runAction(context, ref,
            action: const DeletePendingAction(), input: PendingIdInput(id: v.payment.id), idempotencyKey: '$_key-del');
        if (done != null && mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(pendingViewProvider(widget.id));
    final v = value.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(v?.payment.counterparty ?? 'Money owed'),
        actions: [
          if (v != null)
            FinnIconButton(icon: LucideIcons.ellipsisVertical, tooltip: 'More actions', onPressed: () => _menu(v)),
          const SizedBox(width: Space.x2),
        ],
      ),
      body: AsyncView<PendingView?>(
        value: value,
        loading: const SkeletonPulse(
          child: Padding(
            padding: EdgeInsets.all(Space.gutter),
            child: Column(children: [CardSkeleton(height: 200), SizedBox(height: Space.x4), CardSkeleton(height: 120)]),
          ),
        ),
        builder: (context, v) {
          if (v == null) {
            return Center(
              child: EmptyState(
                icon: LucideIcons.searchX,
                title: 'This item no longer exists',
                message: 'It may have been deleted.',
                actionLabel: 'Back to money owed',
                onAction: () => context.go(AppRoutes.pending),
              ),
            );
          }
          final split = v.payment.split == null ? null : ref.watch(pendingSplitsProvider)[v.payment.split!.id];
          return _Body(view: v, split: split, onSettle: () => context.push(AppRoutes.settlePending(v.payment.id)));
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.view, required this.onSettle, this.split});

  final PendingView view;
  final VoidCallback onSettle;

  /// The bill this item is part of, when it was split between several people.
  final PendingSplitView? split;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final v = view;
    final p = v.payment;
    final active = v.status.isActive;
    final sections = <Widget>[
      _Hero(view: v),
      if (active) ...[
        const SizedBox(height: Space.x3),
        _WaitingCard(view: v),
        const SizedBox(height: Space.x3),
        Row(
          children: [
            Expanded(
              child: FinnButton(
                label: p.direction.isOwe ? 'Settle · I paid ${p.counterparty}' : 'Settle · ${p.counterparty} paid me',
                icon: LucideIcons.circleCheck,
                expand: true,
                size: FinnButtonSize.lg,
                onPressed: onSettle,
              ),
            ),
            if (!p.direction.isOwe) ...[
              const SizedBox(width: Space.x2),
              Builder(
                builder: (context) => FinnIconButton(
                  icon: LucideIcons.send,
                  tooltip: 'Send a reminder',
                  variant: FinnIconButtonVariant.outline,
                  size: FinnButtonSize.lg,
                  onPressed: () => sharePendingReminder(context, v),
                ),
              ),
            ],
          ],
        ),
      ],
      if (split case final split?) ...[
        const SizedBox(height: Space.x3),
        PendingSplitCard(split: split, currentId: p.id),
      ],
      if (p.isShared) ...[
        const SizedBox(height: Space.x3),
        _SharedCard(view: v),
      ],
      const SizedBox(height: Space.x6),
      SectionHeader(icon: LucideIcons.fileText, title: 'Details', tileColor: c.accentPending),
      const SizedBox(height: Space.x2),
      _Facts(view: v),
      const SizedBox(height: Space.x6),
      SectionHeader(
        icon: LucideIcons.history,
        title: 'Settlements',
        subtitle: v.settlements.isEmpty ? null : '${v.settlements.length} recorded',
        tileColor: c.positive,
      ),
      const SizedBox(height: Space.x2),
      if (v.settlements.isEmpty)
        FinnCard(
          variant: FinnCardVariant.muted,
          padding: const EdgeInsets.all(Space.x3),
          child: Text(
            active
                ? 'Nothing settled yet. Record a full or partial settlement when money changes hands.'
                : 'No settlements were recorded.',
            style: t.caption,
          ),
        )
      else
        _SettlementTimeline(view: v),
      const SizedBox(height: Space.x4),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, size: 13, color: c.textTertiary),
          const SizedBox(width: Space.x1_5),
          Expanded(
            child: Text(
              'Creating this did not change your balance. Settling records the cash movement once.'
              '${v.settlements.isNotEmpty ? ' Items with settlements cannot be deleted, so your history stays accurate — write off the rest instead.' : ''}',
              style: t.micro,
            ),
          ),
        ],
      ),
    ];
    return ListView(
      key: PageStorageKey('pending-${p.id}'),
      padding: EdgeInsets.fromLTRB(0, Space.x2, 0, context.bottomClearance),
      children: [
        for (var i = 0; i < sections.length; i++)
          ResponsiveCenter(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: i == 0 ? StaggeredEntrance(child: sections[i]) : sections[i],
          ),
      ],
    );
  }
}
class _Hero extends StatelessWidget {
  const _Hero({required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final v = view;
    final p = v.payment;
    final white70 = Colors.white.withValues(alpha: 0.75);
    final pct = v.settledBps ~/ 100;
    final (Money headline, String suffix) = switch (v.status) {
      PendingStatus.settled => (p.originalAmount, 'settled in full'),
      PendingStatus.cancelled => (v.payment.originalAmount - v.settled, 'written off'),
      _ => (v.outstanding, 'left'),
    };
    final caption = switch (v.status) {
      PendingStatus.settled when v.settledOn != null =>
        'Closed ${DateFormats.dayMonthYear.format(v.settledOn!)} · ${daysBetween(p.createdDate, v.settledOn!)} days after it began',
      PendingStatus.open => 'Nothing settled yet',
      _ => '${v.settled.format()} of ${p.originalAmount.format()} settled · $pct%',
    };
    return GradientHeroCard(
      watermark: LucideIcons.handshake,
      padding: const EdgeInsets.all(Space.x4),
      semanticLabel: '${p.direction.sentence(p.counterparty)}. ${v.status.label}. '
          'Outstanding ${MoneyFormatter.spoken(v.outstanding)} of ${MoneyFormatter.spoken(p.originalAmount)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PendingAvatar(
                name: p.counterparty,
                color: Colors.white,
                progress: v.settledBps / 10000,
                direction: v.status.isActive ? p.direction : null,
                onGradient: true,
                size: 44,
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.direction.sentence(p.counterparty),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyStrong.copyWith(color: Colors.white)),
                    Text('${p.purpose} · ${p.kind.label}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: t.caption.copyWith(color: white70)),
                  ],
                ),
              ),
              const SizedBox(width: Space.x2),
              _StatusValue(view: v, onGradient: true),
            ],
          ),
          const SizedBox(height: Space.x4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: AnimatedAmount(
                  headline,
                  animateOnMount: true,
                  style: t.amountHero.copyWith(color: Colors.white),
                  fit: true,
                ),
              ),
              const SizedBox(width: Space.x2),
              Text(suffix, style: t.bodyStrong.copyWith(color: white70)),
            ],
          ),
          const SizedBox(height: 2),
          Text(caption, style: t.caption.copyWith(color: white70)),
          const SizedBox(height: Space.x3),
          _SettlementBar(view: v),
        ],
      ),
    );
  }
}

/// The original amount as a bar, one segment per settlement (oldest first),
/// filled in payment order so the history reads left to right.
class _SettlementBar extends StatelessWidget {
  const _SettlementBar({required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context) {
    final v = view;
    final whole = v.payment.originalAmount.paise;
    final parts = whole <= 0
        ? const <double>[]
        : [for (final s in v.settlements.reversed) (s.amount.paise / whole).clamp(0.0, 1.0)];
    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 900),
        curve: Curves2.emphasized,
        builder: (context, t, _) => CustomPaint(
          size: const Size(double.infinity, 10),
          painter: _SegmentsPainter(
            parts: parts,
            progress: t,
            fill: Colors.white,
            track: Colors.white.withValues(alpha: 0.18),
            writtenOff: v.status == PendingStatus.cancelled,
          ),
        ),
      ),
    );
  }
}

class _SegmentsPainter extends CustomPainter {
  const _SegmentsPainter({
    required this.parts,
    required this.progress,
    required this.fill,
    required this.track,
    required this.writtenOff,
  });

  final List<double> parts;
  final double progress;
  final Color fill;
  final Color track;

  /// Hatch the unpaid rest instead of leaving it empty.
  final bool writtenOff;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final r = Radius.circular(h / 2);
    final bar = RRect.fromRectAndRadius(Offset.zero & size, r);
    canvas.drawRRect(bar, Paint()..color = track);
    canvas.save();
    canvas.clipRRect(bar);
    final total = parts.fold<double>(0, (a, b) => a + b);
    var x = 0.0;
    var budget = total * progress * size.width;
    for (var i = 0; i < parts.length && budget > 0; i++) {
      final w = (parts[i] * size.width).clamp(0.0, budget);
      // Alternate opacity so neighbouring payments stay distinguishable.
      final paint = Paint()..color = fill.withValues(alpha: i.isEven ? 1 : 0.78);
      canvas.drawRect(Rect.fromLTWH(x, 0, w, h), paint);
      if (i > 0) {
        canvas.drawRect(Rect.fromLTWH(x - 1, 0, 2, h), Paint()..color = track.withValues(alpha: 0.9));
      }
      x += w;
      budget -= w;
    }
    if (writtenOff && x < size.width) {
      final stripe = Paint()
        ..color = fill.withValues(alpha: 0.35)
        ..strokeWidth = 1.5;
      for (var sx = x - h; sx < size.width; sx += 5) {
        canvas.drawLine(Offset(sx, h), Offset(sx + h, 0), stripe);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SegmentsPainter old) =>
      old.progress != progress ||
      old.fill != fill ||
      old.track != track ||
      old.writtenOff != writtenOff ||
      old.parts.length != parts.length ||
      !Iterable.generate(parts.length).every((i) => old.parts[i] == parts[i]);
}

/// How long this has been waiting, said plainly ("Priya has not returned
/// your money yet. 20 days have passed."), with an age meter marked at one
/// week, three weeks and two months. There is no deadline — the meter only
/// warms in colour as time passes, so the oldest items stand out.
class _WaitingCard extends StatelessWidget {
  const _WaitingCard({required this.view});

  final PendingView view;

  static const _scaleDays = 60;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final v = view;
    final tone = pendingAgeColor(v, c);
    final accent = PendingAge.of(v) == PendingAge.fresh ? c.info : tone;
    final last = v.daysSinceLastPayment;
    final hidden = AmountVisibility.hiddenOf(context);
    return FinnCard(
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x3),
      semanticLabel: pendingAgeSentence(v),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.hourglass, size: 16, color: accent),
              const SizedBox(width: Space.x2),
              Expanded(child: Text(pendingAgeSentence(v), style: t.bodyStrong)),
              const SizedBox(width: Space.x2),
              Text(pendingDays(v.daysOpen), style: t.amountSmall.copyWith(color: accent)),
            ],
          ),
          if (last != null) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 16 + Space.x2),
              child: Text(
                'Last ${v.payment.direction.isOwe ? 'payment' : 'money back'}'
                '${hidden ? '' : ' (${v.settlements.first.amount.format()})'} '
                '${last == 0 ? 'today' : '$last ${last == 1 ? 'day' : 'days'} ago'}.',
                style: t.caption,
              ),
            ),
          ],
          const SizedBox(height: Space.x3),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (v.daysOpen / _scaleDays).clamp(0.0, 1.0)),
            duration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 900),
            curve: Curves2.emphasized,
            builder: (context, s, _) => CustomPaint(
              size: const Size(double.infinity, 14),
              painter: _AgePainter(
                at: s,
                marks: const [7 / _scaleDays, PendingView.longPendingDays / _scaleDays],
                fresh: c.info,
                warm: c.warning,
                track: c.surfaceMuted,
                knob: c.surface,
                knobColor: accent,
              ),
            ),
          ),
          const SizedBox(height: Space.x1),
          Row(
            children: [
              Text('Began ${DateFormats.dayMonth.format(v.payment.createdDate)}', style: t.micro),
              const Spacer(),
              Text(v.daysOpen > _scaleDays ? '2 months+' : '2 months', style: t.micro),
            ],
          ),
        ],
      ),
    );
  }
}

class _AgePainter extends CustomPainter {
  const _AgePainter({
    required this.at,
    required this.marks,
    required this.fresh,
    required this.warm,
    required this.track,
    required this.knob,
    required this.knobColor,
  });

  /// Position of today on the 0..1 scale.
  final double at;
  final List<double> marks;
  final Color fresh;
  final Color warm;
  final Color track;
  final Color knob;
  final Color knobColor;

  @override
  void paint(Canvas canvas, Size size) {
    const h = 6.0;
    final y = size.height / 2;
    final w = size.width;
    final rect = RRect.fromLTRBR(0, y - h / 2, w, y + h / 2, const Radius.circular(h / 2));
    canvas.drawRRect(rect, Paint()..color = track);
    final x = (at * w).clamp(0.0, w);
    if (x > 0) {
      // Warms from blue to amber as the wait grows.
      final fill = Paint()
        ..shader = LinearGradient(colors: [fresh, warm], stops: [marks.first, marks.last])
            .createShader(Rect.fromLTWH(0, 0, w, size.height));
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, x, size.height));
      canvas.drawRRect(rect, fill);
      canvas.restore();
    }
    final tick = Paint()
      ..color = track
      ..strokeWidth = 2;
    for (final m in marks) {
      final mx = m * w;
      canvas.drawLine(Offset(mx, y - 6), Offset(mx, y + 6), tick);
      canvas.drawCircle(Offset(mx, y), 1.5, Paint()..color = warm.withValues(alpha: 0.6));
    }
    final kx = x.clamp(6.0, w - 6.0);
    canvas.drawCircle(Offset(kx, y), 6.5, Paint()..color = knob);
    canvas.drawCircle(
      Offset(kx, y),
      5.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = knobColor,
    );
  }

  @override
  bool shouldRepaint(_AgePainter old) =>
      old.at != at ||
      old.fresh != fresh ||
      old.warm != warm ||
      old.track != track ||
      old.knob != knob ||
      old.knobColor != knobColor;
}

/// Details as compact tiles instead of a long label/value list.
class _Facts extends StatelessWidget {
  const _Facts({required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final v = view;
    final p = v.payment;
    final notes = p.notes?.trim() ?? '';
    final tiles = <(IconData, String, String, Color?)>[
      (LucideIcons.tag, 'Reason', p.kind.label, null),
      (p.direction.icon, 'Direction', p.direction.isOwe ? 'I pay them' : 'They pay me', p.direction.color(c)),
      (LucideIcons.calendarPlus, 'Began', DateFormats.dayMonthYear.format(p.createdDate), null),
      (
        LucideIcons.hourglass,
        v.status.isActive ? 'Waiting' : 'Was open',
        pendingDays(v.status.isActive ? v.daysOpen : daysBetween(p.createdDate, v.settledOn ?? p.updatedAt)),
        v.status.isActive ? pendingAgeColor(v, c) : null,
      ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final w = (box.maxWidth - Space.x2) / 2;
        return Wrap(
          spacing: Space.x2,
          runSpacing: Space.x2,
          children: [
            for (final (icon, label, value, color) in tiles)
              SizedBox(
                width: w,
                child: MergeSemantics(
                  child: Container(
                    padding: const EdgeInsets.all(Space.x3),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: Radii.rLg,
                      border: Border.all(color: c.border),
                    ),
                    child: Row(
                      children: [
                        Icon(icon, size: 16, color: color ?? c.textTertiary),
                        const SizedBox(width: Space.x2),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label.toUpperCase(), style: t.eyebrow),
                              Text(value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.label.copyWith(color: color ?? c.textPrimary, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (notes.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Space.x3),
                decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.rLg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(LucideIcons.stickyNote, size: 16, color: c.textTertiary),
                    const SizedBox(width: Space.x2),
                    Expanded(child: Text(notes, style: t.body)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatusValue extends StatelessWidget {
  const _StatusValue({required this.view, this.onGradient = false});

  final PendingView view;
  final bool onGradient;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (color, icon) = switch (view.status) {
      PendingStatus.open => (c.info, LucideIcons.circleDot),
      PendingStatus.partiallySettled => (c.warning, LucideIcons.hourglass),
      PendingStatus.settled => (c.positive, LucideIcons.circleCheck),
      PendingStatus.cancelled => (c.textSecondary, LucideIcons.ban),
    };
    if (onGradient) {
      return StatusPill(label: view.status.label, color: Colors.white, icon: icon);
    }
    return StatusPill(label: view.status.label, color: color, icon: icon);
  }
}

/// Settlements newest first on a rail, each with what was left after it.
class _SettlementTimeline extends StatelessWidget {
  const _SettlementTimeline({required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context) {
    final v = view;
    // Remaining after each settlement, computed oldest first.
    final chronological = v.settlements.reversed.toList();
    final left = <String, Money>{};
    var remaining = v.payment.originalAmount;
    for (final s in chronological) {
      remaining = Money.max(remaining - s.amount, Money.zero);
      left[s.id] = remaining;
    }
    return FinnCard(
      padding: const EdgeInsets.fromLTRB(Space.x3, Space.x3, Space.x3, Space.x1),
      child: Column(
        children: [
          for (var i = 0; i < v.settlements.length; i++)
            _SettlementRow(
              settlement: v.settlements[i],
              direction: v.payment.direction,
              leftAfter: left[v.settlements[i].id]!,
              last: i == v.settlements.length - 1,
            ).maybeAnimate(
              context,
              (a) => a
                  .fadeIn(delay: 120.ms + 60.ms * i, duration: 280.ms)
                  .slideX(begin: 0.06, end: 0, delay: 120.ms + 60.ms * i, duration: 360.ms, curve: Curves.easeOutCubic),
            ),
        ],
      ),
    );
  }
}

class _SettlementRow extends StatelessWidget {
  const _SettlementRow({
    required this.settlement,
    required this.direction,
    required this.leftAfter,
    required this.last,
  });

  final PendingSettlement settlement;
  final PendingDirection direction;
  final Money leftAfter;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final s = settlement;
    final txId = s.transactionId;
    final meta = [
      DateFormats.dayMonthYear.format(s.date),
      if (s.method != null) s.method!.label,
    ].join(' · ');
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                const SizedBox(height: 3),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.positiveSoft,
                    border: Border.all(color: c.positive, width: 2.5),
                  ),
                ),
                if (!last) Expanded(child: Container(width: 2, color: c.border)),
              ],
            ),
          ),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: Space.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(direction.isOwe ? 'You paid' : 'You received', style: t.bodyStrong)),
                      AmountText(s.amount, style: t.amountSmall.copyWith(color: c.positive)),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: Text(meta, style: t.caption)),
                      if (leftAfter.isZero)
                        Text('Cleared', style: t.micro.copyWith(color: c.positive, fontWeight: FontWeight.w800))
                      else
                        Text('${AmountVisibility.hiddenOf(context) ? '' : '${leftAfter.format()} '}left',
                            style: t.micro),
                    ],
                  ),
                  if (s.note != null && s.note!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('“${s.note!}”', style: t.caption.copyWith(fontStyle: FontStyle.italic)),
                    ),
                  if (txId == null)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.x1),
                      child: Row(children: [
                        Icon(LucideIcons.circleSlash, size: 12, color: c.textTertiary),
                        const SizedBox(width: Space.x1),
                        Flexible(child: Text('Settled outside your tracked cash', style: t.micro)),
                      ]),
                    )
                  else
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: () => context.push(AppRoutes.transaction(txId)),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(Dimens.minTouch, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: c.info,
                          textStyle: t.micro.copyWith(fontWeight: FontWeight.w800),
                        ),
                        icon: const Icon(LucideIcons.link2, size: 13),
                        label: const Text('View linked transaction'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Double entry made visible: who added the shared item and what the other
/// person's FiNN shows right now, with a check that both sides agree.
class _SharedCard extends ConsumerWidget {
  const _SharedCard({required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.text;
    final p = view.payment;
    final link = p.link!;
    final first = p.counterparty.split(' ').first;
    final mirror = ref.watch(mirrorProvider(link));
    final theirs = mirror?.view(view.today);
    final inStep = theirs != null && theirs.outstanding == view.outstanding && theirs.status == view.status;
    return FinnCard(
      key: const ValueKey('pending-shared-card'),
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.link2, size: 16, color: c.info),
              const SizedBox(width: Space.x2),
              Expanded(child: Text('Shared on FiNN · ${link.handle}', style: t.bodyStrong)),
              StatusPill(
                label: link.createdByMe ? 'Added by you' : 'Added by $first',
                color: link.createdByMe ? c.info : c.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: Space.x1),
          Text(
            link.createdByMe
                ? 'This item is in both accounts. You can edit it; either of you can record a settlement.'
                : '$first added this, so only they can edit it. Either of you can record a settlement.',
            style: t.caption,
          ),
          const SizedBox(height: Space.x3),
          Text('ON ${first.toUpperCase()}’S FINN', style: t.eyebrow),
          const SizedBox(height: Space.x1),
          if (theirs == null)
            Text('Waiting to sync…', style: t.caption)
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    theirs.payment.direction.sentence(theirs.payment.counterparty),
                    style: t.body.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                AmountText(theirs.outstanding, style: t.amountSmall.copyWith(color: theirs.payment.direction.color(c))),
              ],
            ),
          Row(
            children: [
              Icon(inStep ? LucideIcons.circleCheck : LucideIcons.refreshCw,
                  size: 13, color: inStep ? c.positive : c.warning),
              const SizedBox(width: Space.x1),
              Expanded(
                child: Text(
                  inStep ? 'Both sides match' : 'Syncing with $first',
                  style: t.micro.copyWith(color: inStep ? c.positive : c.warning, fontWeight: FontWeight.w800),
                ),
              ),
              if (theirs != null)
                TextButton(
                  key: const ValueKey('pending-their-side'),
                  onPressed: () => showFinnSheet<void>(
                    context,
                    builder: (_) => _TheirSideSheet(mirror: mirror!, today: view.today, name: first),
                  ),
                  child: Text('See $first’s side'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Read-only view of the mirrored entry, as the other person sees it.
class _TheirSideSheet extends StatelessWidget {
  const _TheirSideSheet({required this.mirror, required this.today, required this.name});

  final MirrorEntry mirror;
  final DateTime today;
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final v = mirror.view(today);
    return FinnSheetScaffold(
      title: '$name’s FiNN',
      description: 'What ${mirror.payment.link!.handle} sees for this item. Read-only.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: Radii.rXl,
              border: Border.all(color: c.border),
            ),
            child: ClipRRect(borderRadius: Radii.rXl, child: PendingRow(view: v, onTap: () {})),
          ),
          const SizedBox(height: Space.x3),
          Text(pendingAgeSentence(v), style: t.caption),
          if (v.settlements.isNotEmpty) ...[
            const SizedBox(height: Space.x4),
            Text('SETTLEMENTS ON THEIR SIDE', style: t.eyebrow),
            const SizedBox(height: Space.x1),
            for (final s in v.settlements)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.x1),
                child: Row(
                  children: [
                    Icon(LucideIcons.circleCheck, size: 14, color: c.positive),
                    const SizedBox(width: Space.x2),
                    Expanded(child: Text(DateFormats.dayMonthYear.format(s.date), style: t.body)),
                    AmountText(s.amount, style: t.amountSmall),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
