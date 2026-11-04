import 'package:flutter/material.dart';

import '../tokens.dart';
import 'surfaces.dart';

/// One row's share of a [LedgerPanel], for long lazy lists (a
/// `SliverList` cannot hold one panel around hundreds of rows). Consecutive
/// slices from [first] to [last] read as a single panel: same surface,
/// hairline edge, corner radius and inset dividers between rows.
class LedgerPanelSlice extends StatelessWidget {
  const LedgerPanelSlice({
    super.key,
    required this.child,
    this.first = false,
    this.last = false,
    this.dividerIndent = Sp.lg,
    this.khata = false,
  });

  final Widget child;

  /// Bahi ledger paper: warm fill, ruled edges and the red double margin
  /// line at [khataMargin] (between the icon column and the text).
  final bool khata;
  static const khataMargin = 60.0;

  /// Opens the panel: rounded top edge, no divider above.
  final bool first;

  /// Closes the panel: rounded bottom edge.
  final bool last;

  /// Left inset of the hairline above this row (unless [first]).
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    const r = Radius.circular(Rad.lg);
    final radius = BorderRadius.vertical(top: first ? r : Radius.zero, bottom: last ? r : Radius.zero);
    return CustomPaint(
      // Dark mode separates panels by tone alone, like [LedgerPanel].
      painter: _SlicePainter(
        first: first,
        last: last,
        fill: khata ? c.khata : c.surface,
        line: khata ? c.khataRule : c.line,
        margin: khata ? c.khataMargin : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!first)
                Padding(
                  padding: EdgeInsetsDirectional.only(start: dividerIndent),
                  child: Container(height: 1, color: khata ? c.khataRule : c.line),
                ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _SlicePainter extends CustomPainter {
  _SlicePainter({required this.first, required this.last, required this.fill, this.line, this.margin});

  final bool first;
  final bool last;
  final Color fill;
  final Color? line;
  final Color? margin;

  @override
  void paint(Canvas canvas, Size size) {
    const r = Radius.circular(Rad.lg);
    const inner = Radius.circular(Rad.lg - 0.5);
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        rect,
        topLeft: first ? r : Radius.zero,
        topRight: first ? r : Radius.zero,
        bottomLeft: last ? r : Radius.zero,
        bottomRight: last ? r : Radius.zero,
      ),
      Paint()..color = fill,
    );
    final m = margin;
    if (m != null) {
      final p = Paint()
        ..color = m
        ..strokeWidth = 1.2;
      const x = LedgerPanelSlice.khataMargin;
      canvas.drawLine(Offset(x, first ? 6 : 0), Offset(x, last ? size.height - 6 : size.height), p);
      canvas.drawLine(Offset(x + 3, first ? 6 : 0), Offset(x + 3, last ? size.height - 6 : size.height), p);
    }
    final stroke = line;
    if (stroke == null) return;
    // Stroke a rounded rect that runs past the open ends, clipped to this
    // slice, so only the edges this slice owns are drawn.
    canvas.save();
    canvas.clipRect(rect);
    final edge = Rect.fromLTRB(0.5, first ? 0.5 : -2, size.width - 0.5, last ? size.height - 0.5 : size.height + 2);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        edge,
        topLeft: first ? inner : Radius.zero,
        topRight: first ? inner : Radius.zero,
        bottomLeft: last ? inner : Radius.zero,
        bottomRight: last ? inner : Radius.zero,
      ),
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SlicePainter old) =>
      old.first != first || old.last != last || old.fill != fill || old.line != line || old.margin != margin;
}
