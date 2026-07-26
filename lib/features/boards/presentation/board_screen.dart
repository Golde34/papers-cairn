import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
import '../../papers/data/paper_repository.dart';
import '../data/board_repository.dart';
import 'board_items.dart';

enum BoardTool { pan, pen, eraser }

/// Sentinel for ink that follows the theme instead of committing to a colour.
///
/// A fixed neutral cannot work: near-white ink vanishes on a light board, and
/// near-black vanishes on a dark one. Strokes stored with this value resolve to
/// `colorScheme.onSurface` when painted, so a drawing stays readable through a
/// theme change. Zero is safe as a sentinel because a real colour always carries
/// an alpha channel and so is never zero.
const defaultInkColorValue = 0;

/// Mid-toned on purpose — these have to read against both a white board and a
/// near-black one.
const _penColorValues = <int>[
  defaultInkColorValue,
  0xFFF9A825,
  0xFF43A047,
  0xFF1E88E5,
  0xFFD81B60,
];

Color resolveInk(int value, ColorScheme scheme) =>
    value == defaultInkColorValue ? scheme.onSurface : Color(value);

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

  factory _DrawnStroke.from(Stroke stroke, ColorScheme scheme) {
    final points = decodePoints(stroke.pointsJson);
    return _DrawnStroke(
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

  /// Opens on the hand, not the pen. Notes and pinned papers only take taps
  /// while a drawing tool is down, so starting in pen mode meant everything on
  /// the board looked interactive and answered nothing.
  BoardTool _tool = BoardTool.pan;
  int _colorValue = _penColorValues[0];
  double _width = _penWidths[1];
  bool _centred = false;
  Size _viewport = Size.zero;

  List<Stroke>? _cacheSource;
  ColorScheme? _cacheScheme;
  List<_DrawnStroke> _drawn = const [];

  @override
  void dispose() {
    _transform.dispose();
    _live.dispose();
    super.dispose();
  }

  /// Rebuilds the paint cache only when the stream emits a new list, or when the
  /// theme flips and default-ink strokes have to resolve to a new colour.
  void _syncCache(List<Stroke> strokes, ColorScheme scheme) {
    if (identical(strokes, _cacheSource) && scheme == _cacheScheme) return;
    _cacheSource = strokes;
    _cacheScheme = scheme;
    _drawn = strokes
        .map((stroke) => _DrawnStroke.from(stroke, scheme))
        .toList(growable: false);
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
          colorValue: _colorValue,
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

  Future<void> _rename(String current) async {
    final controller = TextEditingController(text: current);
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename board'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    await ref.read(boardRepositoryProvider).rename(widget.boardId, title);
  }

  Future<void> _confirmClearInk() async {
    final confirmed = await _confirm(
      title: 'Erase all ink?',
      body: 'Every stroke on this board goes. Notes and pinned papers stay.',
      action: 'Erase',
    );
    if (!confirmed) return;
    await ref.read(boardRepositoryProvider).clear(widget.boardId);
  }

  Future<void> _confirmDeleteBoard(String? title) async {
    final confirmed = await _confirm(
      title: 'Delete ${title ?? 'this board'}?',
      body:
          'The board, its ink and its notes go for good. Papers pinned to it '
          'stay in your library.',
      action: 'Delete',
    );
    if (!confirmed || !mounted) return;

    await ref.read(boardRepositoryProvider).delete(widget.boardId);
    if (mounted) context.pop();
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
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
    final scheme = Theme.of(context).colorScheme;
    _syncCache(strokes, scheme);

    return Scaffold(
      appBar: AppBar(
        title: Text(board?.title ?? 'Board'),
        actions: [
          IconButton(
            tooltip: 'Add a note',
            icon: const Icon(Icons.sticky_note_2_outlined),
            onPressed: _addNote,
          ),
          IconButton(
            tooltip: 'Pin a paper',
            icon: const Icon(Icons.attach_file),
            onPressed: _addPaper,
          ),
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
          PopupMenuButton<String>(
            onSelected: (value) => switch (value) {
              'rename' => _rename(board?.title ?? ''),
              'clear' => _confirmClearInk(),
              _ => _confirmDeleteBoard(board?.title),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename board')),
              PopupMenuItem(value: 'clear', child: Text('Erase all ink')),
              PopupMenuItem(value: 'delete', child: Text('Delete board')),
            ],
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
                        painter: _GridPainter(
                          transform: _transform,
                          viewport: _viewport,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _StrokesPainter(_drawn),
                        foregroundPainter: _LivePainter(
                          live: _live,
                          color: resolveInk(_colorValue, scheme),
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
                              // A maximum rather than a fixed width, so a note
                              // saying "ok" is the size of the word instead of a
                              // wide empty card with its delete button stranded
                              // at the far corner.
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: item.width,
                                ),
                                child: BoardItemView(
                                  key: ValueKey(item.id),
                                  item: item,
                                  boardId: widget.boardId,
                                  interactive: _tool == BoardTool.pan,
                                ),
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
        colorValue: _colorValue,
        width: _width,
        onTool: (tool) => setState(() => _tool = tool),
        // Picking a colour or a nib means you intend to draw, so both also put
        // the pen back in your hand.
        onColor: (value) => setState(() {
          _colorValue = value;
          _tool = BoardTool.pen;
        }),
        onWidth: (width) => setState(() {
          _width = width;
          _tool = BoardTool.pen;
        }),
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

/// The dot grid that gives an otherwise featureless canvas a sense of place.
///
/// Only the dots actually on screen are drawn. The board is fifty thousand units
/// square, so covering all of it would mean millions of dots for the handful
/// anyone can see.
class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.transform,
    required this.viewport,
    required this.color,
  }) : super(repaint: transform);

  final TransformationController transform;
  final Size viewport;
  final Color color;

  static const _baseSpacing = 40.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (viewport.isEmpty) return;

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

    // Zooming out doubles the spacing rather than crowding the dots into a
    // grey wash; zooming in keeps them from drifting metres apart.
    var spacing = _baseSpacing;
    while (spacing * scale < 18) {
      spacing *= 2;
    }
    while (spacing * scale > 72) {
      spacing /= 2;
    }

    final paint = Paint()..color = color;
    final radius = math.min(1.4 / scale, spacing / 16);

    final firstX = (visible.left / spacing).floorToDouble() * spacing;
    final firstY = (visible.top / spacing).floorToDouble() * spacing;

    for (var x = firstX; x <= visible.right; x += spacing) {
      for (var y = firstY; y <= visible.bottom; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.viewport != viewport || old.color != color;
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
    required this.colorValue,
    required this.width,
    required this.onTool,
    required this.onColor,
    required this.onWidth,
  });

  final BoardTool tool;
  final int colorValue;
  final double width;
  final void Function(BoardTool tool) onTool;
  final void Function(int colorValue) onColor;
  final void Function(double width) onWidth;

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
            for (final option in _penColorValues)
              Center(
                child: GestureDetector(
                  // Opaque, not the default deferToChild: the swatch is smaller
                  // than a fingertip and only its painted circle would take taps.
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onColor(option),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: option == colorValue
                            ? scheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      backgroundColor: resolveInk(option, scheme),
                      radius: 11,
                    ),
                  ),
                ),
              ),
            _Separator(color: scheme.outlineVariant),
            for (final option in _penWidths)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onWidth(option),
                child: SizedBox(
                  width: 44,
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
