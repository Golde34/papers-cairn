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
    required this.colorValue,
    required this.points,
    required this.path,
    required this.paint,
  });

  factory DrawnStroke.from(Stroke stroke, ColorScheme scheme) {
    final points = decodePoints(stroke.pointsJson);
    return DrawnStroke(
      id: stroke.id,
      colorValue: stroke.colorValue,
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

  /// The colour as stored, before the theme had its say. Kept because painting
  /// is not the only thing a stroke is for: an export has to know that ink was
  /// left to follow the theme rather than told to be this particular near-white.
  final int colorValue;

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

/// The stroke currently under the finger.
///
/// A [ChangeNotifier] rather than widget state: a pointer move should repaint
/// the ink and nothing else. Calling setState per move rebuilt the whole screen
/// — toolbar, app bar and all — for every sample the touchscreen reported.
class LiveStroke extends ChangeNotifier {
  final List<Offset> points = [];

  /// Extended segment by segment as the finger moves. Rebuilding the whole path
  /// from every point on each frame makes a stroke cost time proportional to its
  /// own length, so long lines get visibly slower the longer they get.
  Path path = Path();

  bool get isActive => points.isNotEmpty;

  void start(Offset point) {
    points
      ..clear()
      ..add(point);
    path = Path()..moveTo(point.dx, point.dy);
    notifyListeners();
  }

  /// [minGap] is in board units, so it has to come from the caller: the same
  /// screen distance is a different board distance at every zoom level.
  void extend(Offset point, double minGap) {
    final last = points.last;
    // A touchscreen reports far more samples than the line needs. Dropping the
    // ones a fraction of a pixel apart costs nothing visible and keeps the path
    // short.
    if ((point - last).distance < minGap) return;

    points.add(point);
    if (points.length >= 3) {
      final previous = points[points.length - 2];
      final midpoint = (previous + point) / 2;
      path.quadraticBezierTo(previous.dx, previous.dy, midpoint.dx, midpoint.dy);
    } else {
      path.lineTo(point.dx, point.dy);
    }
    notifyListeners();
  }

  List<Offset> take() {
    final taken = List<Offset>.of(points);
    points.clear();
    path = Path();
    notifyListeners();
    return taken;
  }
}

/// Whether [probe] falls within [tolerance] of the line through [points].
///
/// Used by the eraser, which has to decide what a fingertip landed on. Testing
/// the bounding box instead would erase strokes the finger never touched — a
/// long diagonal covers a lot of board it does not actually cross.
bool strokeHits(List<Offset> points, Offset probe, double tolerance) {
  for (var i = 0; i < points.length - 1; i++) {
    if (_distanceToSegment(probe, points[i], points[i + 1]) <= tolerance) {
      return true;
    }
  }
  return false;
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared == 0) return (p - a).distance;

  final t = (((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / lengthSquared).clamp(
    0.0,
    1.0,
  );
  return (p - Offset(a.dx + t * dx, a.dy + t * dy)).distance;
}
