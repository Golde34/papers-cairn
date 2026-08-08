import 'package:flutter/material.dart';

import '../../../core/database/database.dart';
import 'board_background.dart';
import 'strokes.dart';

class BoardBackgroundPainter extends CustomPainter {
  BoardBackgroundPainter({
    required this.transform,
    required this.viewport,
    required this.color,
    required this.style,
  }) : super(repaint: transform);

  final TransformationController transform;
  final Size viewport;
  final Color color;
  final BoardBackground style;

  @override
  void paint(Canvas canvas, Size size) {
    if (viewport.isEmpty || style == BoardBackground.blank) return;

    final inverse = Matrix4.copy(transform.value);
    if (inverse.invert() == 0) return;

    final visible = Rect.fromPoints(
      MatrixUtils.transformPoint(inverse, Offset.zero),
      MatrixUtils.transformPoint(
        inverse,
        Offset(viewport.width, viewport.height),
      ),
    );

    final scale = transform.value.getMaxScaleOnAxis();
    if (scale <= 0) return;

    paintBoardPattern(
      canvas: canvas,
      area: visible,
      style: style,
      color: color,
      spacing: adaptiveSpacing(style.baseSpacing, scale),
      // Marks stay one screen pixel wide however far in or out you are.
      strokeScale: 1 / scale,
    );
  }

  @override
  bool shouldRepaint(BoardBackgroundPainter old) =>
      old.viewport != viewport || old.color != color || old.style != style;
}

class StrokesPainter extends CustomPainter {
  const StrokesPainter(this.strokes);

  final List<DrawnStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      canvas.drawPath(stroke.path, stroke.paint);
    }
  }

  @override
  bool shouldRepaint(StrokesPainter old) =>
      !identical(old.strokes, strokes);
}

/// The box being dragged around a piece of writing.
///
/// Drawn in board coordinates like everything else, so [strokeScale] undoes the
/// zoom: without it the outline is hairline when zoomed out and a slab when
/// zoomed in.
class SelectionPainter extends CustomPainter {
  const SelectionPainter({
    required this.selection,
    required this.color,
    required this.strokeScale,
  });

  final Rect? selection;
  final Color color;
  final double strokeScale;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = selection;
    if (rect == null || rect.isEmpty) return;

    canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * strokeScale,
    );
  }

  @override
  bool shouldRepaint(SelectionPainter old) =>
      old.selection != selection ||
      old.color != color ||
      old.strokeScale != strokeScale;
}

class LiveStrokePainter extends CustomPainter {
  LiveStrokePainter({required this.live, required this.color, required this.width})
    : super(repaint: live);

  final LiveStroke live;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    if (!live.isActive) return;
    canvas.drawPath(
      live.path,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(LiveStrokePainter old) =>
      old.color != color || old.width != width || !identical(old.live, live);
}

