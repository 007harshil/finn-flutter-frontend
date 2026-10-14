import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../design_system/luxe/luxe.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/luxe_async.dart';
import '../application/pending_actions.dart';
import '../domain/pending_payment.dart';
import 'pending_split_ui.dart';
import 'pending_ui.dart';

enum _Menu { edit, remind, writeOff, delete }

/// One pending item: how much is left (and how it was paid down), how
/// long it has waited, the one thing to do next (settle), then the bill
/// it belongs to, the shared view, details and settlement history.
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
    final canDelete = !hasSettlements && !otherCreated;
    final choice = await showLuxeMenu<_Menu>(
      context,
      title: p.purpose,
      eyebrow: p.counterparty,
      items: [
        LuxeMenuItem(
          value: _Menu.edit,
          label: 'Edit details',
          icon: otherCreated ? LucideIcons.lock : LucideIcons.pencil,
          hint: otherCreated ? 'Only $first can — they added it' : null,
        ),
        if (v.status.isActive && !p.direction.isOwe)
          const LuxeMenuItem(
            value: _Menu.remind,
            label: 'Send a reminder',
            icon: LucideIcons.send,
            hint: 'A polite nudge',
          ),
        if (v.status.isActive)
          LuxeMenuItem(
            value: _Menu.writeOff,
            label: 'Write off what is left',
            icon: canWriteOff ? LucideIcons.ban : LucideIcons.lock,
            hint: canWriteOff ? 'You no longer expect it back' : 'Only $first can — they are owed',
          ),
        LuxeMenuItem(
          value: _Menu.delete,
          label: 'Delete',
          icon: canDelete ? LucideIcons.trash2 : LucideIcons.lock,
          destructive: canDelete,
          hint: otherCreated
              ? 'Only $first can'
              : (hasSettlements ? 'Unavailable — settlements exist. Write off the rest instead.' : null),
        ),
      ],
    );
    if (!mounted || choice == null) return;
    final locked = switch (choice) {
      _Menu.edit when otherCreated => '$first added this, so only they can edit it.',
      _Menu.writeOff when !canWriteOff => 'Only $first can write this off, because they are owed.',
      _Menu.delete when !canDelete =>
        otherCreated
            ? 'Only $first can delete this.'
            : 'Items with settlements cannot be deleted. Write off the rest instead.',
      _ => null,
    };
    if (locked != null) {
      FinnToast.info(context, locked);
      return;
    }
    switch (choice) {
      case _Menu.edit:
        context.push(AppRoutes.editPending(v.payment.id));
      case _Menu.remind:
        await sharePendingReminder(context, v);
      case _Menu.writeOff:
        final ok = await showLuxeConfirm(
          context,
          title: 'Write off what is left?',
          message:
              '${maskedPending(context, v.outstanding)} will no longer be expected. '
              'Settlements already recorded stay as they are.',
          confirmLabel: 'Write off',
          icon: LucideIcons.ban,
          destructive: true,
        );
        if (!ok || !mounted) return;
        await runAction(
          context,
          ref,
          action: const CancelPendingAction(),
          input: PendingIdInput(id: v.payment.id),
          idempotencyKey: '$_key-off',
        );
      case _Menu.delete:
        final ok = await showLuxeConfirm(
          context,
          title: 'Delete this item?',
          message: 'It is removed from money owed. This cannot be undone.',
          confirmLabel: 'Delete',
          icon: LucideIcons.trash2,
          destructive: true,
        );
        if (!ok || !mounted) return;
        final done = await runAction(
          context,
          ref,
          action: const DeletePendingAction(),
          input: PendingIdInput(id: v.payment.id),
          idempotencyKey: '$_key-del',
        );
        if (done != null && mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(pendingViewProvider(widget.id));
    final v = value.value;
    return LuxeDetailPage(
      title: v?.payment.counterparty ?? 'Money owed',
      storageKey: 'pending-${widget.id}',
      actions: [
        if (v != null)
          LuxeIconButton(
            icon: LucideIcons.ellipsis,
            tooltip: 'More actions',
            style: LuxeIconStyle.ghost,
            size: 40,
            onPressed: () => _menu(v),
          ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: LuxeAsync<PendingView?>(
            value: value,
            loading: const LuxePageSkeleton(hero: 240, rows: 3, controls: false),
            errorTitle: 'Could not load this item',
            builder: (context, v) {
              if (v == null) {
                return LuxeEmpty(
                  icon: LucideIcons.searchX,
                  title: 'This item no longer exists',
                  message: 'It may have been deleted.',
                  actionLabel: 'Back to money owed',
                  onAction: () => context.go(AppRoutes.pending),
                );
              }
              final split = v.payment.split == null ? null : ref.watch(pendingSplitsProvider)[v.payment.split!.id];
              return _Body(view: v, split: split, onSettle: () => context.push(AppRoutes.settlePending(v.payment.id)));
            },
          ),
        ),
      ],
    );
  }
}

/// Amount in inline copy; masked when balances are hidden.
String maskedPending(BuildContext context, Money m) =>
    AmountVisibility.hiddenOf(context) ? MoneyFormatter.masked : m.format();

class _Body extends StatelessWidget {
  const _Body({required this.view, required this.onSettle, this.split});

  final PendingView view;
  final VoidCallback onSettle;

  /// The bill this item is part of, when it was split between several people.
  final PendingSplitView? split;

  @override
  Widget build(BuildContext context) {
    final lp = context.luxe;
    final t = context.lt;
    final v = view;
    final p = v.payment;
    final active = v.status.isActive;
    var i = 0;
    Widget r(Widget child) => Reveal(index: i++, child: child);
    return ResponsiveCenter(
      padding: const EdgeInsets.symmetric(horizontal: LuxeSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          r(LuxeTitle(eyebrow: p.kind.label, title: p.purpose, subtitle: p.direction.sentence(p.counterparty))),
          const SizedBox(height: 20),
          Reveal(
            index: i++,
            scale: 0.97,
            child: _Hero(view: v),
          ),
          if (active) ...[
            const SizedBox(height: 14),
            r(
              Row(
                children: [
                  Expanded(
                    child: LuxeButton(
                      label: p.direction.isOwe
                          ? 'Settle · I paid ${p.counterparty}'
                          : 'Settle · ${p.counterparty} paid me',
                      icon: LucideIcons.check,
                      expand: true,
                      onPressed: onSettle,
                    ),
                  ),
                  if (!p.direction.isOwe) ...[
                    const SizedBox(width: 8),
                    Builder(
                      builder: (context) => LuxeIconButton(
                        icon: LucideIcons.send,
                        tooltip: 'Send a reminder',
                        size: 52,
                        onPressed: () => sharePendingReminder(context, v),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            r(_WaitingCard(view: v)),
          ],
          if (split case final split?) ...[
            const SizedBox(height: 14),
            r(PendingSplitCard(split: split, currentId: p.id)),
          ],
          if (p.isShared) ...[const SizedBox(height: 14), r(_SharedCard(view: v))],
          const SizedBox(height: LuxeSpace.section),
          r(const LuxeEyebrowHeader(label: 'Details')),
          const SizedBox(height: 12),
          r(_Facts(view: v)),
          const SizedBox(height: LuxeSpace.section),
          LuxeEyebrowHeader(
            label: 'Settlements',
            caption: v.settlements.isEmpty ? null : '${v.settlements.length} recorded',
          ),
          const SizedBox(height: 14),
          if (v.settlements.isEmpty)
            Text(
              active
                  ? 'Nothing settled yet. Record a full or partial settlement when money changes hands.'
                  : 'No settlements were recorded.',
              style: t.bodySoft,
            )
          else
            _SettlementTimeline(view: v),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.info, size: 13, color: lp.inkMute),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Creating this did not change your balance. Settling records the cash movement once.'
                  '${v.settlements.isNotEmpty ? ' Items with settlements cannot be deleted, so your history stays accurate — write off the rest instead.' : ''}',
                  style: t.micro,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context) {
    final lp = context.luxe;
    final t = context.lt;
    final v = view;
    final p = v.payment;
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
      _ => '${maskedPending(context, v.settled)} of ${maskedPending(context, p.originalAmount)} settled · $pct%',
    };
    final (statusColor, statusIcon) = switch (v.status) {
      PendingStatus.open => (lp.gold, LucideIcons.circleDot),
      PendingStatus.partiallySettled => (lp.gold, LucideIcons.hourglass),
      PendingStatus.settled => (lp.isDark ? lp.positive : const Color(0xFF9BD3B5), LucideIcons.circleCheck),
      PendingStatus.cancelled => (lp.onObsidianSoft, LucideIcons.ban),
    };
    return LuxeObsidian(
      semanticLabel:
          '${p.direction.sentence(p.counterparty)}. ${v.status.label}. '
          'Outstanding ${MoneyFormatter.spoken(v.outstanding)} of ${MoneyFormatter.spoken(p.originalAmount)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PendingAvatar(
                name: p.counterparty,
                color: lp.onObsidian,
                progress: v.settledBps / 10000,
                direction: v.status.isActive ? p.direction : null,
                onGradient: true,
                size: 48,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.counterparty,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.heading.c(lp.onObsidian),
                    ),
                    Text(p.direction.isOwe ? 'You pay them' : 'They pay you', style: t.caption.c(lp.onObsidianSoft)),
                  ],
                ),
              ),
              LuxeStatus(label: v.status.label, color: statusColor, icon: statusIcon),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: LuxeAmount(
                  headline,
                  countFromZero: true,
                  style: t.display.copyWith(fontSize: 40, color: lp.onObsidian),
                ),
              ),
              const SizedBox(width: 10),
              Text(suffix, style: t.label.c(lp.onObsidianSoft)),
            ],
          ),
          const SizedBox(height: 4),
          Text(caption, style: t.caption.c(lp.onObsidianSoft)),
          const SizedBox(height: 16),
          _SettlementBar(view: v),
        ],
      ),
    );
  }
}

/// The original amount as a bar, one segment per settlement (oldest first),
/// drawn in payment order so the history reads left to right.
class _SettlementBar extends StatelessWidget {
  const _SettlementBar({required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context) {
    final lp = context.luxe;
    final v = view;
    final whole = v.payment.originalAmount.paise;
    final parts = whole <= 0
        ? const <double>[]
        : [for (final s in v.settlements.reversed) (s.amount.paise / whole).clamp(0.0, 1.0)];
    return ExcludeSemantics(
      child: SizedBox(
        height: 8,
        child: DrawIn(
          value: 1,
          delay: const Duration(milliseconds: 250),
          builder: (context, t) => CustomPaint(
            size: const Size(double.infinity, 8),
            painter: _SegmentsPainter(
              parts: parts,
              progress: t,
              fill: lp.gold,
              track: lp.onObsidian.withValues(alpha: 0.1),
              writtenOff: v.status == PendingStatus.cancelled,
            ),
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
      final paint = Paint()..color = fill.withValues(alpha: i.isEven ? 1 : 0.7);
      canvas.drawRect(Rect.fromLTWH(x, 0, w, h), paint);
      if (i > 0) canvas.drawRect(Rect.fromLTWH(x - 1, 0, 2, h), Paint()..color = const Color(0xFF141311));
      x += w;
      budget -= w;
    }
    if (writtenOff && x < size.width) {
      final stripe = Paint()
        ..color = fill.withValues(alpha: 0.3)
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
      old.parts.length != parts.length;
}

/// How long this has been waiting, said plainly, on an age meter marked at
/// one week and three weeks. There is no deadline — the meter only warms
/// in colour as time passes, so the oldest items stand out.
class _WaitingCard extends StatelessWidget {
  const _WaitingCard({required this.view});

  final PendingView view;

  static const _scaleDays = 60;

  @override
  Widget build(BuildContext context) {
    final lp = context.luxe;
    final t = context.lt;
    final v = view;
    final fresh = PendingAge.of(v) == PendingAge.fresh;
    final accent = fresh ? lp.info : pendingAgeColor(v, lp);
    final last = v.daysSinceLastPayment;
    final hidden = AmountVisibility.hiddenOf(context);
    return LuxeCard(
      semanticLabel: pendingAgeSentence(v),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LuxeIconDisc(icon: LucideIcons.hourglass, color: accent, size: 36),
              const SizedBox(width: 12),
              Expanded(child: Text(pendingAgeSentence(v), style: t.label.w(650).c(lp.ink))),
              const SizedBox(width: 8),
              Text(pendingDays(v.daysOpen), style: t.figure.copyWith(fontSize: 20, color: accent)),
            ],
          ),
          if (last != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Text(
                'Last ${v.payment.direction.isOwe ? 'payment' : 'money back'}'
                '${hidden ? '' : ' (${v.settlements.first.amount.format()})'} '
                '${last == 0 ? 'today' : '$last ${last == 1 ? 'day' : 'days'} ago'}.',
                style: t.caption,
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 16,
            child: DrawIn(
              value: (v.daysOpen / _scaleDays).clamp(0.0, 1.0),
              builder: (context, s) => CustomPaint(
                size: const Size(double.infinity, 16),
                painter: _AgePainter(
                  at: s,
                  marks: const [7 / _scaleDays, PendingView.longPendingDays / _scaleDays],
                  fresh: lp.info,
                  warm: lp.warning,
                  track: lp.sunk,
                  knob: lp.paper,
                  knobColor: accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
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

  final double at;
  final List<double> marks;
  final Color fresh;
  final Color warm;
  final Color track;
  final Color knob;
  final Color knobColor;

  @override
  void paint(Canvas canvas, Size size) {
    const h = 4.0;
    final y = size.height / 2;
    final w = size.width;
    final rect = RRect.fromLTRBR(0, y - h / 2, w, y + h / 2, const Radius.circular(h / 2));
    canvas.drawRRect(rect, Paint()..color = track);
    final x = (at * w).clamp(0.0, w);
    if (x > 0) {
      final fill = Paint()
        ..shader = LinearGradient(
          colors: [fresh, warm],
          stops: [marks.first, marks.last],
        ).createShader(Rect.fromLTWH(0, 0, w, size.height));
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, x, size.height));
      canvas.drawRRect(rect, fill);
      canvas.restore();
    }
    for (final m in marks) {
      final mx = m * w;
      canvas.drawLine(
        Offset(mx, y - 6),
        Offset(mx, y + 6),
        Paint()
          ..color = track
          ..strokeWidth = 2,
      );
    }
    final kx = x.clamp(7.0, w - 7.0);
    canvas.drawCircle(Offset(kx, y), 7, Paint()..color = knobColor.withValues(alpha: 0.18));
    canvas.drawCircle(Offset(kx, y), 5, Paint()..color = knob);
    canvas.drawCircle(
      Offset(kx, y),
      4.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = knobColor,
    );
  }

  @override
  bool shouldRepaint(_AgePainter old) => old.at != at || old.knobColor != knobColor || old.track != track;
}

class _Facts extends StatelessWidget {
  const _Facts({required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context) {
    final lp = context.luxe;
    final t = context.lt;
    final v = view;
    final p = v.payment;
    final notes = p.notes?.trim() ?? '';
    return LuxeFacts(
      facts: [
        LuxeFact('Reason', value: p.kind.label, icon: LucideIcons.tag),
        LuxeFact(
          'Direction',
          icon: p.direction.icon,
          child: Text(p.direction.isOwe ? 'I pay them' : 'They pay me', style: t.label.w(650).c(p.direction.tone(lp))),
        ),
        LuxeFact('Began', value: DateFormats.dayMonthYear.format(p.createdDate), icon: LucideIcons.calendarPlus),
        LuxeFact(
          v.status.isActive ? 'Waiting' : 'Was open',
          icon: LucideIcons.hourglass,
          value: pendingDays(v.status.isActive ? v.daysOpen : daysBetween(p.createdDate, v.settledOn ?? p.updatedAt)),
        ),
      ],
      footer: notes.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.stickyNote, size: 15, color: lp.inkMute),
                  const SizedBox(width: 10),
                  Expanded(child: Text(notes, style: t.body)),
                ],
              ),
            ),
    );
  }
}

/// Settlements newest first on a rail, each with what was left after it.
class _SettlementTimeline extends StatelessWidget {
  const _SettlementTimeline({required this.view});

  final PendingView view;

  @override
  Widget build(BuildContext context) {
    final lp = context.luxe;
    final v = view;
    // Remaining after each settlement, computed oldest first.
    final left = <String, Money>{};
    var remaining = v.payment.originalAmount;
    for (final s in v.settlements.reversed) {
      remaining = Money.max(remaining - s.amount, Money.zero);
      left[s.id] = remaining;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < v.settlements.length; i++)
          Reveal(
            index: i,
            offset: 10,
            blur: 0,
            child: LuxeRailNode(
              color: lp.positive,
              icon: LucideIcons.check,
              first: i == 0,
              last: i == v.settlements.length - 1,
              child: _SettlementRow(
                settlement: v.settlements[i],
                direction: v.payment.direction,
                leftAfter: left[v.settlements[i].id]!,
              ),
            ),
          ),
      ],
    );
  }
}

class _SettlementRow extends StatelessWidget {
  const _SettlementRow({required this.settlement, required this.direction, required this.leftAfter});

  final PendingSettlement settlement;
  final PendingDirection direction;
  final Money leftAfter;

  @override
  Widget build(BuildContext context) {
    final lp = context.luxe;
    final t = context.lt;
    final s = settlement;
    final txId = s.transactionId;
    final meta = [DateFormats.dayMonthYear.format(s.date), if (s.method != null) s.method!.label].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(direction.isOwe ? 'You paid' : 'You received', style: t.label.w(700).c(lp.ink))),
              LuxeAmount(s.amount, fit: false, style: t.number.copyWith(fontSize: 14, color: lp.positive)),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(child: Text(meta, style: t.caption)),
              if (leftAfter.isZero)
                Text('Cleared', style: t.micro.w(750).c(lp.positive))
              else
                Text('${AmountVisibility.hiddenOf(context) ? '' : '${leftAfter.format()} '}left', style: t.micro),
            ],
          ),
          if (s.note != null && s.note!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('“${s.note!}”', style: t.caption.copyWith(fontStyle: FontStyle.italic)),
            ),
          if (txId == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(LucideIcons.circleSlash, size: 12, color: lp.inkMute),
                  const SizedBox(width: 6),
                  Flexible(child: Text('Settled outside your tracked cash', style: t.micro)),
                ],
              ),
            )
          else
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Transform.translate(
                offset: const Offset(-12, 0),
                child: LuxeLink(
                  label: 'View linked transaction',
                  icon: LucideIcons.arrowUpRight,
                  onTap: () => context.push(AppRoutes.transaction(txId)),
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
    final lp = context.luxe;
    final t = context.lt;
    final p = view.payment;
    final link = p.link!;
    final first = p.counterparty.split(' ').first;
    final mirror = ref.watch(mirrorProvider(link));
    final theirs = mirror?.view(view.today);
    final inStep = theirs != null && theirs.outstanding == view.outstanding && theirs.status == view.status;
    return LuxeCard(
      key: const ValueKey('pending-shared-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              LuxeIconDisc(icon: LucideIcons.link2, color: lp.info, size: 36),
              const SizedBox(width: 12),
              Expanded(child: Text('Shared on FiNN · ${link.handle}', style: t.label.w(700).c(lp.ink))),
              LuxeStatus(
                label: link.createdByMe ? 'Added by you' : 'Added by $first',
                color: link.createdByMe ? lp.info : lp.inkSoft,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            link.createdByMe
                ? 'This item is in both accounts. You can edit it; either of you can record a settlement.'
                : '$first added this, so only they can edit it. Either of you can record a settlement.',
            style: t.caption,
          ),
          const LuxeHairline(vertical: 14),
          Text('ON ${first.toUpperCase()}’S FINN', style: t.eyebrow),
          const SizedBox(height: 8),
          if (theirs == null)
            Text('Waiting to sync…', style: t.caption)
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    theirs.payment.direction.sentence(theirs.payment.counterparty),
                    style: t.label.w(700).c(lp.ink),
                  ),
                ),
                LuxeAmount(
                  theirs.outstanding,
                  fit: false,
                  style: t.number.copyWith(fontSize: 14, color: theirs.payment.direction.tone(lp)),
                ),
              ],
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                inStep ? LucideIcons.circleCheck : LucideIcons.refreshCw,
                size: 13,
                color: inStep ? lp.positive : lp.warning,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  inStep ? 'Both sides match' : 'Syncing with $first',
                  style: t.micro.w(750).c(inStep ? lp.positive : lp.warning),
                ),
              ),
              if (theirs != null)
                LuxeLink(
                  key: const ValueKey('pending-their-side'),
                  label: 'See $first’s side',
                  onTap: () => showLuxeSheet<void>(
                    context,
                    builder: (_) => _TheirSideSheet(mirror: mirror!, today: view.today, name: first),
                  ),
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
    final lp = context.luxe;
    final t = context.lt;
    final v = mirror.view(today);
    return LuxeSheet(
      eyebrow: 'Read-only',
      title: '$name’s FiNN',
      description: 'What ${mirror.payment.link!.handle} sees for this item.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: lp.paper,
              borderRadius: BorderRadius.circular(LuxeSpace.rTile),
              border: Border.all(color: lp.line),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(LuxeSpace.rTile),
              child: PendingRow(view: v, onTap: () {}),
            ),
          ),
          const SizedBox(height: 14),
          Text(pendingAgeSentence(v), style: t.caption),
          if (v.settlements.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('SETTLEMENTS ON THEIR SIDE', style: t.eyebrow),
            const SizedBox(height: 6),
            for (final s in v.settlements)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(LucideIcons.circleCheck, size: 14, color: lp.positive),
                    const SizedBox(width: 10),
                    Expanded(child: Text(DateFormats.dayMonthYear.format(s.date), style: t.body)),
                    LuxeAmount(s.amount, fit: false, style: t.number.copyWith(fontSize: 14)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
