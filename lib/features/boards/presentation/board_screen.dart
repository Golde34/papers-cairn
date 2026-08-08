import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
import '../../papers/data/paper_repository.dart';
import '../data/board_repository.dart';
import 'board_background.dart';
import 'board_items.dart';
import 'board_painters.dart';
import 'board_toolbar.dart';
import 'ink_capture.dart';
import 'ink_review_sheet.dart';
import 'strokes.dart';

class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key, required this.boardId});

  final int boardId;

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> {
  final _transform = TransformationController();
  final _live = LiveStroke();

  /// Opens on the hand, not the pen. Notes and pinned papers only take taps
  /// while a drawing tool is down, so starting in pen mode meant everything on
  /// the board looked interactive and answered nothing.
  BoardTool _tool = BoardTool.pan;
  int _colorValue = penColorValues[0];
  double _width = penWidths[1];
  bool _centred = false;
  Size _viewport = Size.zero;

  /// Where the selection drag began, and the box it has reached, both in board
  /// coordinates so they survive a zoom.
  Offset? _selectAnchor;
  Rect? _selection;

  final _strokes = StrokeCache();

  @override
  void dispose() {
    _transform.dispose();
    _live.dispose();
    super.dispose();
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
      case BoardTool.select:
        setState(() {
          _selectAnchor = point;
          _selection = null;
        });
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
      case BoardTool.select:
        final anchor = _selectAnchor;
        if (anchor != null) {
          setState(() => _selection = Rect.fromPoints(anchor, point));
        }
    }
  }

  /// Board units to screen pixels. Guarded against zero because dividing by the
  /// zoom is the whole reason anything asks for it.
  double get _scale {
    final scale = _transform.value.getMaxScaleOnAxis();
    return scale <= 0 ? 1 : scale;
  }

  /// Roughly one and a half screen pixels, expressed in board units at the
  /// current zoom.
  double get _minSampleGap => 1.5 / _scale;

  /// Smaller than this, in board units, and the drag was a tap that missed.
  /// Capturing on every stray touch would open the sheet constantly.
  static const _minSelection = 24.0;

  Future<void> _onPointerUp(PointerUpEvent event) async {
    if (_tool == BoardTool.select) return _finishSelection();
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

  /// Turns the box just dragged into an image of whatever it caught.
  ///
  /// The box itself is thrown away either way: it marked what to capture, and
  /// leaving it on the board afterwards only invites you to wonder whether it
  /// still means something.
  Future<void> _finishSelection() async {
    final selection = _selection;
    setState(() {
      _selectAnchor = null;
      _selection = null;
    });

    if (selection == null ||
        selection.width < _minSelection ||
        selection.height < _minSelection) {
      return;
    }

    final png = await captureInkPng(_strokes.drawn, selection);
    if (!mounted) return;

    if (png == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No ink inside that box.')),
      );
      return;
    }
    await showInkReviewSheet(context, png);
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

  /// Applies each choice on the spot rather than behind an OK button. Ruling is
  /// something you judge by looking at it, and the sheet leaves the board visible
  /// while you do.
  Future<void> _chooseBackground(BoardBackground current) async {
    var selected = current;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paper style',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final option in BoardBackground.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: BoardBackgroundPreview(
                            style: option,
                            selected: option == selected,
                            onTap: () {
                              setSheetState(() => selected = option);
                              ref
                                  .read(boardRepositoryProvider)
                                  .setBackground(widget.boardId, option);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _rename(String current) async {
    final controller = TextEditingController(text: current);
    final String? title;
    try {
      title = await showDialog<String>(
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
    } finally {
      controller.dispose();
    }
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
    for (final stroke in _strokes.drawn.reversed) {
      if (strokeHits(stroke.points, point, stroke.width / 2 + 8)) {
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
    _strokes.sync(strokes, scheme);

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
              'paper' => _chooseBackground(
                board?.background ?? BoardBackground.dots,
              ),
              'rename' => _rename(board?.title ?? ''),
              'clear' => _confirmClearInk(),
              _ => _confirmDeleteBoard(board?.title),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'paper', child: Text('Paper style')),
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
                        painter: BoardBackgroundPainter(
                          transform: _transform,
                          viewport: _viewport,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                          style: board?.background ?? BoardBackground.dots,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: StrokesPainter(_strokes.drawn),
                        foregroundPainter: LiveStrokePainter(
                          live: _live,
                          color: resolveInk(_colorValue, scheme),
                          width: _width,
                        ),
                      ),
                    ),
                    if (_selection != null)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: SelectionPainter(
                            selection: _selection,
                            color: scheme.primary,
                            strokeScale: 1 / _scale,
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
      bottomNavigationBar: BoardToolbar(
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
