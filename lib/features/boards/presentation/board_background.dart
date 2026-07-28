import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/database/database.dart';

/// How the ruling is drawn, shared by the board itself and the little previews
/// in the picker, so what you choose is exactly what you get.
void paintBoardPattern({
  required Canvas canvas,
  required Rect area,
  required BoardBackground style,
  required Color color,
  required double spacing,
  required double strokeScale,
}) {
  if (style == BoardBackground.blank) return;

  final paint = Paint()..color = color;
  final firstX = (area.left / spacing).floorToDouble() * spacing;
  final firstY = (area.top / spacing).floorToDouble() * spacing;

  switch (style) {
    case BoardBackground.blank:
      return;

    case BoardBackground.dots:
      final radius = math.min(1.4 * strokeScale, spacing / 16);
      for (var x = firstX; x <= area.right; x += spacing) {
        for (var y = firstY; y <= area.bottom; y += spacing) {
          canvas.drawCircle(Offset(x, y), radius, paint);
        }
      }

    case BoardBackground.lines:
      // Horizontal only, like a writing pad. Vertical rules would fight the
      // handwriting rather than guide it.
      paint
        ..strokeWidth = strokeScale
        ..style = PaintingStyle.stroke;
      for (var y = firstY; y <= area.bottom; y += spacing) {
        canvas.drawLine(Offset(area.left, y), Offset(area.right, y), paint);
      }

    case BoardBackground.grid:
      paint
        ..strokeWidth = strokeScale
        ..style = PaintingStyle.stroke;
      for (var y = firstY; y <= area.bottom; y += spacing) {
        canvas.drawLine(Offset(area.left, y), Offset(area.right, y), paint);
      }
      for (var x = firstX; x <= area.right; x += spacing) {
        canvas.drawLine(Offset(x, area.top), Offset(x, area.bottom), paint);
      }
  }
}

/// Keeps the ruling legible at any zoom: doubling when it would crowd into a
/// grey wash, halving when the marks would drift too far apart to guide the eye.
double adaptiveSpacing(double base, double scale) {
  var spacing = base;
  while (spacing * scale < 18) {
    spacing *= 2;
  }
  while (spacing * scale > 72) {
    spacing /= 2;
  }
  return spacing;
}

extension BoardBackgroundPresentation on BoardBackground {
  String get label => switch (this) {
    BoardBackground.dots => 'Dots',
    BoardBackground.lines => 'Lined',
    BoardBackground.grid => 'Squared',
    BoardBackground.blank => 'Blank',
  };

  /// Line spacing is wider than dot spacing on purpose — handwriting needs room
  /// between rules, whereas dots are only a hint of alignment.
  double get baseSpacing => switch (this) {
    BoardBackground.dots => 40,
    BoardBackground.lines => 64,
    BoardBackground.grid => 48,
    BoardBackground.blank => 40,
  };
}

/// A swatch of what a ruling looks like, drawn with the same code as the board.
class BoardBackgroundPreview extends StatelessWidget {
  const BoardBackgroundPreview({
    super.key,
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final BoardBackground style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 74,
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 2.5 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: CustomPaint(
              painter: _PreviewPainter(
                style: style,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            style.label,
            style: TextStyle(
              fontSize: 12,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  const _PreviewPainter({required this.style, required this.color});

  final BoardBackground style;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    paintBoardPattern(
      canvas: canvas,
      area: Offset.zero & size,
      style: style,
      color: color,
      // Fixed, not adaptive: a preview should show the pattern's character at a
      // readable density rather than whatever the last zoom level happened to be.
      spacing: style == BoardBackground.lines ? 16 : 12,
      strokeScale: 1,
    );
  }

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      old.style != style || old.color != color;
}
