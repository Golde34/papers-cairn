import 'package:flutter/material.dart';

import '../../../core/database/database.dart';
import '../data/board_repository.dart';

/// Sentinel for ink that follows the theme instead of committing to a colour.
///
/// A fixed neutral cannot work: near-white ink vanishes on a light board, and
/// near-black vanishes on a dark one. Strokes stored with this value resolve to
/// `colorScheme.onSurface` when painted, so a drawing stays readable through a
/// theme change. Zero is safe as a sentinel because a real colour always carries
/// an alpha channel and so is never zero.
const defaultInkColorValue = 0;

Color resolveInk(int value, ColorScheme scheme) =>
    value == defaultInkColorValue ? scheme.onSurface : Color(value);

/// Curves through the midpoints of consecutive samples. Joining the samples with
/// straight lines makes a fast stroke look like a polygon.
Path buildStrokePath(List<Offset> points) {
  final path = Path();
  if (points.isEmpty) return path;

  path.moveTo(points.first.dx, points.first.dy);
  if (points.length < 3) {
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  for (var i = 1; i < points.length - 1; i++) {
    final midpoint = (points[i] + points[i + 1]) / 2;
    path.quadraticBezierTo(points[i].dx, points[i].dy, midpoint.dx, midpoint.dy);
  }
  path.lineTo(points.last.dx, points.last.dy);
  return path;
}

/// A stroke prepared for painting.
///
/// Built once and kept, never rebuilt inside `paint`. Decoding the JSON and
/// rebuilding the path every frame costs the whole drawing on each of sixty
/// frames a second.
class DrawnStroke {
  DrawnStroke({
    required this.id,
    required this.points,
    required this.path,
    required this.paint,
  });

  factory DrawnStroke.from(Stroke stroke, ColorScheme scheme) {
    final points = decodePoints(stroke.pointsJson);
    return DrawnStroke(
      id: stroke.id,
      points: points,
      path: buildStrokePath(points),
      paint: Paint()
        ..color = resolveInk(stroke.colorValue, scheme)
        ..strokeWidth = stroke.width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  final int id;
  final List<Offset> points;
  final Path path;
  final Paint paint;

  double get width => paint.strokeWidth;
}

/// Keeps the painted form of a board's strokes in step with the database.
///
/// Strokes are immutable once written — only inserted and deleted — so anything
/// already prepared under the same theme is still correct and is kept by id.
/// Rebuilding the whole list on every change, which is what this did at first,
/// made each new stroke re-decode and re-path every stroke before it: the two
/// hundredth line on a board cost two hundred rebuilds, and the board grew
/// slower the more was drawn on it.
class StrokeCache {
  Map<int, DrawnStroke> _byId = const {};
  List<Stroke>? _source;
  ColorScheme? _scheme;

  List<DrawnStroke> _drawn = const [];
  List<DrawnStroke> get drawn => _drawn;

  /// Number of strokes actually built, across the cache's life. Cheap to keep
  /// and the only direct evidence that reuse is happening at all.
  int builds = 0;

  /// Returns whether anything changed, so a caller can skip repainting.
  bool sync(List<Stroke> strokes, ColorScheme scheme) {
    if (identical(strokes, _source) && scheme == _scheme) return false;

    // A theme change is the one case where nothing can be reused: strokes drawn
    // in default ink resolve to a colour that has just moved.
    final reusable = scheme == _scheme ? _byId : const <int, DrawnStroke>{};
    final next = <int, DrawnStroke>{};

    _drawn = [
      for (final stroke in strokes)
        next[stroke.id] = reusable[stroke.id] ?? _build(stroke, scheme),
    ];

    _byId = next;
    _source = strokes;
    _scheme = scheme;
    return true;
  }

  DrawnStroke _build(Stroke stroke, ColorScheme scheme) {
    builds++;
    return DrawnStroke.from(stroke, scheme);
  }
}
