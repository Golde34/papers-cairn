import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
import '../../papers/data/paper_repository.dart';
import '../data/board_repository.dart';

/// Accent colours for notes and paper cards.
///
/// Used as a stripe down the edge rather than as the card background: a stored
/// background colour is fixed, and one picked to look right on a dark board turns
/// into a black slab on a light one. The card itself takes its colour from the
/// theme, so it follows the toggle.
const boardItemPalette = <Color>[
  Color(0xFF43A047),
  Color(0xFFF9A825),
  Color(0xFF1E88E5),
  Color(0xFFD81B60),
];

/// A note or a pinned paper sitting on the board.
///
/// Gestures are split so they cannot fight each other or the canvas underneath:
/// a plain tap opens the thing, and moving requires a long press first. Dragging
/// straight from a touch would be ambiguous with panning the board.
class BoardItemView extends ConsumerStatefulWidget {
  const BoardItemView({
    super.key,
    required this.item,
    required this.boardId,
    required this.interactive,
  });

  final BoardItem item;
  final int boardId;

  /// False while a drawing tool is selected, when the whole item layer is behind
  /// an `IgnorePointer` so ink can cross it.
  final bool interactive;

  @override
  ConsumerState<BoardItemView> createState() => _BoardItemViewState();
}

class _BoardItemViewState extends ConsumerState<BoardItemView> {
  Offset _drag = Offset.zero;
  Offset? _panOrigin;
  bool _dragging = false;

  static const _tapSlop = 6.0;

  /// Gap above and right of the card, so the badge has somewhere to sit that is
  /// still inside the hit-testable area.
  static const _badgeGap = 12.0;

  /// Touch target for the delete badge, well above the 22 pixels the visible
  /// circle occupies.
  static const _badgeTarget = 44.0;

  void _onPanStart(DragStartDetails details) {
    _panOrigin = details.localPosition;
    setState(() {
      _dragging = true;
      _drag = Offset.zero;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final origin = _panOrigin;
    if (origin == null) return;
    // localPosition, not delta: delta arrives in screen pixels and would move
    // the item by the wrong amount at any zoom other than 100%. Local positions
    // are already in board units. This only reads correctly because the
    // Transform below has transformHitTests off, leaving the box where it was.
    setState(() => _drag = details.localPosition - origin);
  }

  Future<void> _onPanEnd(DragEndDetails details) {
    _panOrigin = null;
    return _commitDrag();
  }

  Future<void> _commitDrag() async {
    final moved = _drag;
    setState(() {
      _dragging = false;
      _drag = Offset.zero;
    });

    // A press that never moved is just a press; the delete badge is there for
    // removing things.
    if (moved.distance < _tapSlop) return;

    await ref
        .read(boardRepositoryProvider)
        .moveItem(
          widget.item.id,
          Offset(widget.item.x + moved.dx, widget.item.y + moved.dy),
          widget.boardId,
        );
  }

  Future<void> _confirmDelete() async {
    final isPaper = widget.item.kind == BoardItemKind.paper;
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isPaper ? 'Take off the board?' : 'Delete this note?'),
        content: Text(
          isPaper
              ? 'The paper stays in your library.'
              : 'The note and what it says go for good.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(isPaper ? 'Remove' : 'Delete'),
          ),
        ],
      ),
    );

    if (remove != true) return;
    await ref
        .read(boardRepositoryProvider)
        .deleteItem(widget.item.id, widget.boardId);
  }

  Future<void> _onTap() async {
    switch (widget.item.kind) {
      case BoardItemKind.text:
        final text = await showBoardNoteEditor(context, widget.item.body);
        if (text == null) return;
        await ref
            .read(boardRepositoryProvider)
            .setItemText(widget.item.id, text, widget.boardId);
      case BoardItemKind.paper:
        final paperId = widget.item.paperId;
        if (paperId != null && mounted) context.push('/paper/$paperId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Transform.translate(
      offset: _drag,
      // Hit tests stay on the untranslated box so the running drag keeps
      // measuring against where the item started.
      transformHitTests: false,
      child: Stack(
        children: [
          // Space reserved at the top-right for the delete badge. The badge used
          // to hang outside the Stack on negative offsets, where most of it was
          // untappable: a RenderBox rejects a hit outside its own size before it
          // ever asks its children.
          Padding(
            padding: const EdgeInsets.only(top: _badgeGap, right: _badgeGap),
            child: GestureDetector(
              onTap: _onTap,
              // A drag that starts on an item moves the item; one that starts on
              // empty board pans the canvas. The child recognizer wins the arena
              // against the InteractiveViewer above it, so no mode switch and no
              // long press is needed.
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: Opacity(
                opacity: _dragging ? 0.75 : 1,
                child: switch (widget.item.kind) {
                  BoardItemKind.text => _NoteCard(item: widget.item),
                  BoardItemKind.paper => _PaperCard(item: widget.item),
                },
              ),
            ),
          ),
          // Hidden while a drawing tool is up. Shown but inert would be worse
          // than absent: a button that ignores taps reads as broken.
          if (!_dragging && widget.interactive)
            Positioned(
              top: 0,
              right: 0,
              // A finger-sized target around a small glyph. The circle stays
              // discreet; the area that answers it does not.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _confirmDelete,
                child: SizedBox(
                  width: _badgeTarget,
                  height: _badgeTarget,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.surfaceContainerHighest,
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Icon(
                        Icons.close,
                        size: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.item});

  final BoardItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = item.body.trim().isEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: Color(item.colorValue), width: 4),
          top: BorderSide(color: scheme.outlineVariant),
          right: BorderSide(color: scheme.outlineVariant),
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Text(
        empty ? 'Tap to write…' : item.body,
        style: TextStyle(
          height: 1.35,
          color: empty ? scheme.onSurfaceVariant : scheme.onSurface,
          fontStyle: empty ? FontStyle.italic : FontStyle.normal,
        ),
      ),
    );
  }
}

class _PaperCard extends ConsumerWidget {
  const _PaperCard({required this.item});

  final BoardItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final paperId = item.paperId;
    final paper = paperId == null
        ? null
        : ref.watch(paperProvider(paperId)).value;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: Color(item.colorValue), width: 4),
          top: BorderSide(color: scheme.outlineVariant),
          right: BorderSide(color: scheme.outlineVariant),
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.description_outlined, size: 14, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                paper?.arxivId ?? 'missing',
                style: TextStyle(fontSize: 11, color: scheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            // The card holds only a reference, so a paper deleted from the
            // library leaves a card that should say so rather than go blank.
            paper?.title ?? 'This paper is no longer in your library',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w500, height: 1.3),
          ),
          if (paper != null) ...[
            const SizedBox(height: 4),
            Text(
              paper.authors,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// Edits a note in a sheet rather than in place on the canvas. Inline editing
/// inside a zoomed, panned transform puts the caret and the keyboard in the
/// wrong places at anything other than 100%.
Future<String?> showBoardNoteEditor(BuildContext context, String initial) {
  final controller = TextEditingController(text: initial);
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: null,
            minLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'the thing you are trying to work out…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () =>
                Navigator.of(sheetContext).pop(controller.text.trimRight()),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

/// Picks a paper from the library to pin onto the board.
Future<Paper?> showBoardPaperPicker(BuildContext context, WidgetRef ref) {
  final papers = ref.read(allPapersProvider).value ?? const [];

  if (papers.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add a paper to your library first.')),
    );
    return Future.value();
  }

  return showModalBottomSheet<Paper>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final paper in papers)
            ListTile(
              title: Text(
                paper.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                paper.authors,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.of(sheetContext).pop(paper),
            ),
        ],
      ),
    ),
  );
}
