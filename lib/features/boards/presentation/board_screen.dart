import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../papers/data/paper_repository.dart';
import '../data/board_repository.dart';
import 'board_items.dart';

enum BoardTool { pan, pen, eraser }

const _penPalette = <Color>[
  Color(0xFFE8E8E8),
  Color(0xFFFFD54F),
  Color(0xFF81C784),
  Color(0xFF64B5F6),
  Color(0xFFF06292),
];

const _penWidths = <double>[2, 5, 12];

const _toolbarHeight = 56.0;

/// A stroke prepared for painting.
///
/// Built once when the stroke list changes, never inside `paint`. Decoding the
/// JSON and rebuilding the path every frame — which is what the first version
/// did — costs the whole drawing on each of sixty frames a second, and the board
/// gets slower with every line added to it.
class _DrawnStroke {
  _DrawnStroke({
    required this.id,
    required this.points,
    required this.path,
    required this.paint,
  });

  factory _DrawnStroke.from(Stroke stroke) {
    final points = decodePoints(stroke.pointsJson);
    return _DrawnStroke(
      id: stroke.id,
      points: points,
      path: buildStrokePath(points),
      paint: Paint()
        ..color = Color(stroke.colorValue)
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

/// The stroke currently under the finger.
///
/// A [ChangeNotifier] rather than widget state: a pointer move should repaint
/// the ink and nothing else. Calling setState per move rebuilt the whole screen
/// — toolbar, app bar and all — for every sample the touchscreen reported.
class _LiveStroke extends ChangeNotifier {
  final List<Offset> points = [];

  /// Extended segment by segment as the finger moves. Rebuilding the whole path
  /// from every point on each frame makes a stroke cost time proportional to
  /// its own length, so long lines get visibly slower the longer they get.
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
      path.quadraticBezierTo(
        previous.dx,
        previous.dy,
        midpoint.dx,
        midpoint.dy,
      );
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

class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key, required this.boardId});

  final int boardId;

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> {
  final _transform = TransformationController();
  final _live = _LiveStroke();

  BoardTool _tool = BoardTool.pen;
  Color _color = _penPalette[0];
  double _width = _penWidths[1];
  bool _centred = false;
  Size _viewport = Size.zero;

  List<Stroke>? _cacheSource;
  List<_DrawnStroke> _drawn = const [];

  @override
  void dispose() {
    _transform.dispose();
    _live.dispose();
    super.dispose();
  }

  /// Rebuilds the paint cache only when the stream actually emits a new list.
  void _syncCache(List<Stroke> strokes) {
    if (identical(strokes, _cacheSource)) return;
    _cacheSource = strokes;
    _drawn = strokes.map(_DrawnStroke.from).toList(growable: false);
  }

  /// The canvas is a large square rather than a truly infinite plane, so the
  /// view has to start in the middle of it instead of the top-left corner.
  void _centreOnce(Size viewport) {
    if (_centred) return;
    _centred = true;
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        viewport.width / 2 - boardOrigin.dx,
        viewport.height / 2 - boardOrigin.dy,
        0,
        1,
      );
  }

  Offset _toBoard(Offset viewportPoint) {
    final inverse = Matrix4.copy(_transform.value);
    if (inverse.invert() == 0) return viewportPoint;
    return MatrixUtils.transformPoint(inverse, viewportPoint);
  }

  void _onPointerDown(PointerDownEvent event) {
    final point = _toBoard(event.localPosition);
    switch (_tool) {
      case BoardTool.pan:
        return;
      case BoardTool.pen:
        _live.start(point);
      case BoardTool.eraser:
        _eraseAt(point);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    final point = _toBoard(event.localPosition);
    switch (_tool) {
      case BoardTool.pan:
        return;
      case BoardTool.pen:
        if (_live.isActive) _live.extend(point, _minSampleGap);
      case BoardTool.eraser:
        _eraseAt(point);
    }
  }

  /// Roughly one and a half screen pixels, expressed in board units at the
  /// current zoom.
  double get _minSampleGap {
    final scale = _transform.value.getMaxScaleOnAxis();
    return scale <= 0 ? 1.5 : 1.5 / scale;
  }

  Future<void> _onPointerUp(PointerUpEvent event) async {
    if (!_live.isActive) return;
    final points = _live.take();

    // A tap with no movement still deserves a mark — a dot — so single-point
    // strokes are kept rather than discarded.
    await ref
        .read(boardRepositoryProvider)
        .addStroke(
          boardId: widget.boardId,
          points: points.length == 1 ? [points.first, points.first] : points,
          colorValue: _color.toARGB32(),
          width: _width,
        );
  }

  /// New items land in the middle of what you are looking at, which is where
  /// you were looking when you decided to add one.
  Offset get _viewCentre =>
      _toBoard(Offset(_viewport.width / 2, _viewport.height / 2));

  Future<void> _addNote() async {
    final repository = ref.read(boardRepositoryProvider);
    final id = await repository.addText(
      boardId: widget.boardId,
      at: _viewCentre - const Offset(130, 40),
      colorValue: boardItemPalette.first.toARGB32(),
    );
    if (!mounted) return;

    // Straight into the editor: nobody adds an empty note on purpose.
    final text = await showBoardNoteEditor(context, '');
    if (text == null || text.isEmpty) return;
    await repository.setItemText(id, text, widget.boardId);
  }

  Future<void> _addPaper() async {
    final paper = await showBoardPaperPicker(context, ref);
    if (paper == null || !mounted) return;
    await ref
        .read(boardRepositoryProvider)
        .addPaper(
          boardId: widget.boardId,
          paperId: paper.id,
          at: _viewCentre - const Offset(150, 40),
          colorValue: boardItemPalette[2].toARGB32(),
        );
  }

  void _eraseAt(Offset point) {
    // Newest first: the stroke on top is the one the eye expects to lose.
    for (final stroke in _drawn.reversed) {
      if (_hits(stroke.points, point, stroke.width / 2 + 8)) {
        ref
            .read(boardRepositoryProvider)
            .deleteStroke(stroke.id, widget.boardId);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(boardProvider(widget.boardId)).value;
    final strokes = ref.watch(strokesProvider(widget.boardId)).value ?? const [];
    final items = ref.watch(boardItemsProvider(widget.boardId)).value ?? const [];
    // Watched, not merely read when the picker opens: a StreamProvider with no
    // listener has no value yet, and the picker would find the library empty.
    ref.watch(allPapersProvider);
    _syncCache(strokes);

    return Scaffold(
      appBar: AppBar(
        title: Text(board?.title ?? 'Board'),
        actions: [
          IconButton(
            tooltip: 'Undo last stroke',
            icon: const Icon(Icons.undo),
            onPressed: strokes.isEmpty
                ? null
                : () => ref
                      .read(boardRepositoryProvider)
                      .deleteStroke(strokes.last.id, widget.boardId),
          ),
          IconButton(
            tooltip: 'Recentre',
            icon: const Icon(Icons.filter_center_focus),
            onPressed: () => setState(() => _centred = false),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          _viewport = constraints.biggest;
          _centreOnce(constraints.biggest);
          return Listener(
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            child: InteractiveViewer(
              transformationController: _transform,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              minScale: 0.1,
              maxScale: 8,
              // The pen and the eraser both need raw pointer events. Leaving
              // pan and zoom armed would turn every stroke into a drag.
              panEnabled: _tool == BoardTool.pan,
              scaleEnabled: _tool == BoardTool.pan,
              child: SizedBox(
                width: boardExtent,
                height: boardExtent,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _StrokesPainter(_drawn),
                        foregroundPainter: _LivePainter(
                          live: _live,
                          color: _color,
                          width: _width,
                        ),
                      ),
                    ),
                    // Notes and cards stop swallowing touches while a drawing
                    // tool is up, so you can scribble straight across them.
                    IgnorePointer(
                      ignoring: _tool != BoardTool.pan,
                      child: Stack(
                        children: [
                          for (final item in items)
                            Positioned(
                              left: item.x,
                              top: item.y,
                              width: item.width,
                              child: BoardItemView(
                                key: ValueKey(item.id),
                                item: item,
                                boardId: widget.boardId,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: _Toolbar(
        tool: _tool,
        color: _color,
        width: _width,
        onAddNote: _addNote,
        onAddPaper: _addPaper,
        onTool: (tool) => setState(() => _tool = tool),
        onColor: (color) => setState(() {
          _color = color;
          _tool = BoardTool.pen;
        }),
        onWidth: (width) => setState(() => _width = width),
      ),
    );
  }
}

/// Curves through the midpoints of consecutive samples. Joining the samples
/// with straight lines makes a fast stroke look like a polygon.
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

bool _hits(List<Offset> points, Offset probe, double tolerance) {
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

class _StrokesPainter extends CustomPainter {
  const _StrokesPainter(this.strokes);

  final List<_DrawnStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      canvas.drawPath(stroke.path, stroke.paint);
    }
  }

  @override
  bool shouldRepaint(_StrokesPainter old) =>
      !identical(old.strokes, strokes);
}

class _LivePainter extends CustomPainter {
  _LivePainter({required this.live, required this.color, required this.width})
    : super(repaint: live);

  final _LiveStroke live;
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
  bool shouldRepaint(_LivePainter old) =>
      old.color != color || old.width != width || !identical(old.live, live);
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.tool,
    required this.color,
    required this.width,
    required this.onTool,
    required this.onColor,
    required this.onWidth,
    required this.onAddNote,
    required this.onAddPaper,
  });

  final BoardTool tool;
  final Color color;
  final double width;
  final void Function(BoardTool tool) onTool;
  final void Function(Color color) onColor;
  final void Function(double width) onWidth;
  final VoidCallback onAddNote;
  final VoidCallback onAddPaper;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      // Height is pinned. Left to size itself the row grew to fill the loose
      // constraints a bottomNavigationBar hands down, and the controls ended up
      // floating in the middle of the screen.
      child: SizedBox(
        height: _toolbarHeight,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            _ToolButton(
              icon: Icons.pan_tool_outlined,
              selected: tool == BoardTool.pan,
              tooltip: 'Move around',
              onTap: () => onTool(BoardTool.pan),
            ),
            _ToolButton(
              icon: Icons.edit,
              selected: tool == BoardTool.pen,
              tooltip: 'Draw',
              onTap: () => onTool(BoardTool.pen),
            ),
            _ToolButton(
              icon: Icons.cleaning_services_outlined,
              selected: tool == BoardTool.eraser,
              tooltip: 'Erase',
              onTap: () => onTool(BoardTool.eraser),
            ),
            _Separator(color: scheme.outlineVariant),
            for (final option in _penPalette)
              Center(
                child: GestureDetector(
                  onTap: () => onColor(option),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: option == color && tool == BoardTool.pen
                            ? scheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(backgroundColor: option, radius: 11),
                  ),
                ),
              ),
            _Separator(color: scheme.outlineVariant),
            _ToolButton(
              icon: Icons.sticky_note_2_outlined,
              selected: false,
              tooltip: 'Add a note',
              onTap: onAddNote,
            ),
            _ToolButton(
              icon: Icons.attach_file,
              selected: false,
              tooltip: 'Pin a paper',
              onTap: onAddPaper,
            ),
            _Separator(color: scheme.outlineVariant),
            for (final option in _penWidths)
              GestureDetector(
                onTap: () => onWidth(option),
                child: SizedBox(
                  width: 36,
                  child: Center(
                    child: Container(
                      width: math.max(option * 1.6, 6),
                      height: math.max(option * 1.6, 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: option == width
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 1,
      height: 24,
      color: color,
      margin: const EdgeInsets.symmetric(horizontal: 10),
    ),
  );
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon),
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: selected ? scheme.secondaryContainer : null,
          foregroundColor: selected ? scheme.onSecondaryContainer : null,
        ),
      ),
    );
  }
}
