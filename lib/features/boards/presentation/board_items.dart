import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
import '../../papers/data/paper_repository.dart';
import '../data/board_repository.dart';

/// Backgrounds for notes and paper cards. Dim enough that ink drawn across them
/// still reads, since the whole point is being able to scribble over the lot.
const boardItemPalette = <Color>[
  Color(0xFF2E3A30),
  Color(0xFF3A3227),
  Color(0xFF27333A),
  Color(0xFF3A2B31),
];

/// A note or a pinned paper sitting on the board.
///
/// Gestures are split so they cannot fight each other or the canvas underneath:
/// a plain tap opens the thing, and moving requires a long press first. Dragging
/// straight from a touch would be ambiguous with panning the board.
class BoardItemView extends ConsumerStatefulWidget {
  const BoardItemView({super.key, required this.item, required this.boardId});

  final BoardItem item;
  final int boardId;

  @override
  ConsumerState<BoardItemView> createState() => _BoardItemViewState();
}

class _BoardItemViewState extends ConsumerState<BoardItemView> {
  Offset _drag = Offset.zero;
  bool _dragging = false;

  static const _tapSlop = 6.0;

  void _onLongPressStart(LongPressStartDetails details) {
    setState(() {
      _dragging = true;
      _drag = Offset.zero;
    });
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    // Local rather than global: this widget sits inside the board's transform,
    // so the local offset is already in board units at any zoom.
    setState(() => _drag = details.localOffsetFromOrigin);
  }

  Future<void> _onLongPressEnd(LongPressEndDetails details) async {
    final moved = _drag;
    setState(() {
      _dragging = false;
      _drag = Offset.zero;
    });

    if (moved.distance < _tapSlop) {
      await _showItemMenu();
      return;
    }

    await ref
        .read(boardRepositoryProvider)
        .moveItem(
          widget.item.id,
          Offset(widget.item.x + moved.dx, widget.item.y + moved.dy),
          widget.boardId,
        );
  }

  Future<void> _showItemMenu() async {
    final remove = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(
                widget.item.kind == BoardItemKind.paper
                    ? 'Take off the board'
                    : 'Delete this note',
              ),
              subtitle: widget.item.kind == BoardItemKind.paper
                  ? const Text('The paper stays in your library')
                  : null,
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
          ],
        ),
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
        final text = await showBoardNoteEditor(context, widget.item.text);
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
    return Transform.translate(
      offset: _drag,
      child: GestureDetector(
        onTap: _onTap,
        onLongPressStart: _onLongPressStart,
        onLongPressMoveUpdate: _onLongPressMoveUpdate,
        onLongPressEnd: _onLongPressEnd,
        child: Opacity(
          opacity: _dragging ? 0.75 : 1,
          child: switch (widget.item.kind) {
            BoardItemKind.text => _NoteCard(item: widget.item),
            BoardItemKind.paper => _PaperCard(item: widget.item),
          },
        ),
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
    final empty = item.text.trim().isEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color(item.colorValue),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Text(
        empty ? 'Tap to write…' : item.text,
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
        color: Color(item.colorValue),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: scheme.primary, width: 3),
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          right: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
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
