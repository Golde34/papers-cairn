import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../papers/data/paper_repository.dart';
import '../data/annotation_repository.dart';

/// Reads a downloaded PDF, with highlights kept in Cairn's own database.
///
/// The point of reading inside the app rather than handing the file to another
/// reader: a highlight made here is searchable next to the paper's notes,
/// survives re-downloading the PDF, and can be exported later. In a foreign
/// reader it is locked away where Cairn cannot see it.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.paperId});

  final int paperId;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final _controller = PdfViewerController();
  late final Future<_ReaderTarget?> _target = _resolve();

  _PendingSelection? _pending;
  List<Annotation> _annotations = const [];
  Timer? _pageSaveTimer;

  @override
  void dispose() {
    _pageSaveTimer?.cancel();
    super.dispose();
  }

  Future<_ReaderTarget?> _resolve() async {
    final repository = ref.read(paperRepositoryProvider);
    final paper = await repository.watchById(widget.paperId).first;
    if (paper == null) return null;

    final file = await repository.localFile(widget.paperId);
    if (file == null) return null;

    await repository.markOpened(widget.paperId);
    return _ReaderTarget(paper: paper, file: file);
  }

  @override
  Widget build(BuildContext context) {
    // Held in a field as well as watched, because the page paint callback runs
    // synchronously during rendering and cannot read a provider.
    _annotations = ref.watch(annotationsProvider(widget.paperId)).value ?? const [];

    return FutureBuilder<_ReaderTarget?>(
      future: _target,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final target = snapshot.data;
        if (target == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'The PDF is not on this device. Download it first.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        return _buildReader(context, target);
      },
    );
  }

  Widget _buildReader(BuildContext context, _ReaderTarget target) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          target.paper.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: 'Highlights',
            icon: Badge(
              isLabelVisible: _annotations.isNotEmpty,
              label: Text('${_annotations.length}'),
              child: const Icon(Icons.format_quote),
            ),
            onPressed: () => _showHighlights(context),
          ),
        ],
      ),
      bottomNavigationBar: _pending == null
          ? null
          : _SelectionBar(
              onColor: (color) => _saveHighlight(color, withNote: false),
              onNote: () =>
                  _saveHighlight(highlightPalette.first, withNote: true),
              onCancel: _clearSelection,
            ),
      body: PdfViewer.file(
        target.file.path,
        controller: _controller,
        initialPageNumber: target.paper.lastPage ?? 1,
        params: PdfViewerParams(
          pagePaintCallbacks: [_paintHighlights],
          onPageChanged: _rememberPage,
          textSelectionParams: PdfTextSelectionParams(
            onTextSelectionChange: _onSelectionChange,
          ),
        ),
      ),
    );
  }

  /// Draws saved highlights underneath nothing in particular — the callback runs
  /// after the page is rendered, so the colour is translucent to keep the text
  /// underneath readable.
  void _paintHighlights(Canvas canvas, Rect pageRect, PdfPage page) {
    final scaleX = pageRect.width / page.width;
    final scaleY = pageRect.height / page.height;

    for (final annotation in _annotations) {
      if (annotation.pageNumber != page.pageNumber) continue;
      final paint = Paint()
        ..color = Color(annotation.colorValue).withValues(alpha: 0.35);

      for (final rect in decodeRects(annotation.rectsJson)) {
        canvas.drawRect(
          Rect.fromLTRB(
            pageRect.left + rect.left * scaleX,
            // PDF y grows upward from the bottom of the page; Flutter's grows
            // downward from the top, so every y has to be flipped.
            pageRect.top + (page.height - rect.top) * scaleY,
            pageRect.left + rect.right * scaleX,
            pageRect.top + (page.height - rect.bottom) * scaleY,
          ),
          paint,
        );
      }
    }
  }

  void _rememberPage(int? pageNumber) {
    if (pageNumber == null) return;
    // Debounced: flicking through twenty pages should cost one write, not twenty.
    _pageSaveTimer?.cancel();
    _pageSaveTimer = Timer(const Duration(seconds: 1), () {
      ref.read(paperRepositoryProvider).setLastPage(widget.paperId, pageNumber);
    });
  }

  /// pdfrx hands this a [PdfTextSelection] synchronously; reading the selected
  /// text is asynchronous, so the work is kicked off and not awaited.
  void _onSelectionChange(PdfTextSelection selection) {
    unawaited(_handleSelection(selection));
  }

  Future<void> _handleSelection(PdfTextSelection selection) async {
    if (!selection.hasSelectedText) {
      if (_pending != null && mounted) setState(() => _pending = null);
      return;
    }

    final ranges = await selection.getSelectedTextRanges();
    if (ranges.isEmpty) return;
    final text = (await selection.getSelectedText()).trim();
    if (text.isEmpty) return;

    // A selection dragged across a page break is rare and awkward to store as
    // one highlight; the first page's worth is kept.
    final pageNumber = ranges.first.pageNumber;
    final rects = [
      for (final range in ranges)
        if (range.pageNumber == pageNumber) ..._lineRects(range),
    ];
    if (rects.isEmpty) return;

    if (!mounted) return;
    setState(() {
      _pending = _PendingSelection(
        pageNumber: pageNumber,
        text: text,
        rects: rects,
      );
    });
  }

  Future<void> _clearSelection() async {
    if (_controller.isReady) {
      await _controller.textSelectionDelegate.clearTextSelection();
    }
    if (mounted) setState(() => _pending = null);
  }

  Future<void> _saveHighlight(Color color, {required bool withNote}) async {
    final pending = _pending;
    if (pending == null) return;

    final id = await ref
        .read(annotationRepositoryProvider)
        .add(
          paperId: widget.paperId,
          pageNumber: pending.pageNumber,
          quotedText: pending.text,
          rects: pending.rects,
          colorValue: color.toARGB32(),
        );

    await _clearSelection();
    if (!mounted || !withNote) return;
    final note = await _askForNote(context, pending.text);
    if (note == null || note.isEmpty) return;
    await ref.read(annotationRepositoryProvider).setNote(id, note);
  }

  Future<void> _showHighlights(BuildContext context) async {
    final annotation = await showModalBottomSheet<Annotation>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _HighlightList(
        annotations: _annotations,
        onDelete: (id) => ref.read(annotationRepositoryProvider).delete(id),
      ),
    );
    if (annotation == null) return;
    await _controller.goToPage(pageNumber: annotation.pageNumber);
  }
}

/// Groups the characters of a selection into one rectangle per line.
///
/// Without this a selection running across three lines would paint a single box
/// covering the whole paragraph, including the text to the left of where the
/// selection started and to the right of where it ended.
List<HighlightRect> _lineRects(PdfPageTextRange range) {
  final chars = range.pageText.charRects;
  if (chars.isEmpty) return const [];

  final start = range.start.clamp(0, chars.length);
  final end = range.end.clamp(start, chars.length);

  final lines = <HighlightRect>[];
  PdfRect? current;

  for (final rect in chars.sublist(start, end)) {
    // Whitespace carries a degenerate rect that would stretch the line box.
    if (rect.left >= rect.right || rect.top <= rect.bottom) continue;

    if (current == null) {
      current = rect;
      continue;
    }

    // Same line if the baselines are within most of a line height of each
    // other. Comparing exactly fails on subscripts, superscripts and inline
    // maths, which papers are full of.
    final lineHeight = math.max(current.top - current.bottom, 1.0);
    if ((rect.top - current.top).abs() < lineHeight * 0.6) {
      current = current.merge(rect);
    } else {
      lines.add(_toHighlight(current));
      current = rect;
    }
  }

  if (current != null) lines.add(_toHighlight(current));
  return lines;
}

HighlightRect _toHighlight(PdfRect rect) =>
    HighlightRect(rect.left, rect.top, rect.right, rect.bottom);

class _ReaderTarget {
  const _ReaderTarget({required this.paper, required this.file});

  final Paper paper;
  final File file;
}

class _PendingSelection {
  const _PendingSelection({
    required this.pageNumber,
    required this.text,
    required this.rects,
  });

  final int pageNumber;
  final String text;
  final List<HighlightRect> rects;
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.onColor,
    required this.onNote,
    required this.onCancel,
  });

  final void Function(Color color) onColor;
  final VoidCallback onNote;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            for (final color in highlightPalette)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  onTap: () => onColor(color),
                  child: CircleAvatar(backgroundColor: color, radius: 14),
                ),
              ),
            const Spacer(),
            IconButton(
              tooltip: 'Highlight and add a note',
              icon: const Icon(Icons.edit_note),
              onPressed: onNote,
            ),
            IconButton(
              tooltip: 'Cancel',
              icon: const Icon(Icons.close),
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightList extends StatelessWidget {
  const _HighlightList({required this.annotations, required this.onDelete});

  final List<Annotation> annotations;
  final void Function(int id) onDelete;

  @override
  Widget build(BuildContext context) {
    if (annotations.isEmpty) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No highlights yet. Select some text to make one.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return SafeArea(
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: annotations.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final annotation = annotations[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Color(annotation.colorValue),
              radius: 8,
            ),
            title: Text(
              annotation.quotedText,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              annotation.note.isEmpty
                  ? 'Page ${annotation.pageNumber}'
                  : 'Page ${annotation.pageNumber} · ${annotation.note}',
            ),
            onTap: () => Navigator.of(context).pop(annotation),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => onDelete(annotation.id),
            ),
          );
        },
      ),
    );
  }
}

Future<String?> _askForNote(BuildContext context, String quoted) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Note on this highlight'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            quoted,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontStyle: FontStyle.italic,
              color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: null,
            decoration: const InputDecoration(
              hintText: 'why this matters, what it contradicts…',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Skip'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
