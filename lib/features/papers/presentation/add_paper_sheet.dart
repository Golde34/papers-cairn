import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/database/database.dart';
import '../../../core/network/arxiv_api.dart';
import '../data/paper_repository.dart';

/// Adds a paper from a pasted id, URL, or citation string.
///
/// Looking a paper up and keeping it are two separate steps: the sheet shows
/// what arXiv returned and waits for Save. An id off by one digit is a real
/// paper about something else entirely, and noticing that before it is filed is
/// cheaper than finding and deleting it afterwards.
///
/// [projectId] files the paper on arrival; leaving it null drops it in the inbox.
Future<Paper?> showAddPaperSheet(
  BuildContext context, {
  int? projectId,
  String? initialValue,
}) {
  return showModalBottomSheet<Paper>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _AddPaperSheet(projectId: projectId, initialValue: initialValue),
  );
}

class _AddPaperSheet extends ConsumerStatefulWidget {
  const _AddPaperSheet({this.projectId, this.initialValue});

  final int? projectId;
  final String? initialValue;

  @override
  ConsumerState<_AddPaperSheet> createState() => _AddPaperSheetState();
}

class _AddPaperSheetState extends ConsumerState<_AddPaperSheet> {
  late final _controller = TextEditingController(text: widget.initialValue);
  bool _busy = false;
  String? _error;
  PaperPreview? _preview;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final input = _controller.text.trim();
    if (input.isEmpty || _busy) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final preview = await ref.read(paperRepositoryProvider).preview(input);
      if (mounted) {
        setState(() {
          _busy = false;
          _preview = preview;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _save() async {
    final preview = _preview;
    if (preview == null || _busy) return;

    setState(() => _busy = true);
    try {
      final paper = await ref
          .read(paperRepositoryProvider)
          .save(preview.fetched, projectId: widget.projectId);
      if (mounted) Navigator.of(context).pop(paper);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: _preview == null ? _buildInput(context) : _buildPreview(context),
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Add a paper', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          autofocus: true,
          enabled: !_busy,
          decoration: InputDecoration(
            labelText: 'arXiv link or id',
            hintText: '2103.00020',
            border: const OutlineInputBorder(),
            errorText: _error,
          ),
          onSubmitted: (_) => _fetch(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _fetch,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Look up on arXiv'),
        ),
      ],
    );
  }

  Widget _buildPreview(BuildContext context) {
    final preview = _preview!;
    final paper = preview.fetched;
    final scheme = Theme.of(context).colorScheme;
    final published = paper.publishedAt;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Try a different id',
              icon: const Icon(Icons.arrow_back),
              onPressed: _busy ? null : () => setState(() => _preview = null),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Is this the right paper?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        if (preview.alreadySaved) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: scheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.projectId == null
                        ? 'Already in your library. Saving changes nothing.'
                        : 'Already in your library. Saving files it here too.',
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(paper.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  paper.authors.join(', '),
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    paper.arxivId,
                    if (published != null) DateFormat.yMMM().format(published),
                    if (paper.categories.isNotEmpty) paper.categories.join(', '),
                  ].join('  ·  '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Text(
                  paper.abstractText,
                  style: const TextStyle(height: 1.4),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: scheme.error)),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openPdf(paper),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Read PDF'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Opens the PDF straight from arXiv, before anything has been saved or
  /// downloaded, so the paper can be skimmed before deciding to keep it.
  ///
  /// Safe from bouncing back into Cairn because the arxiv.org intent filter is
  /// scoped to /abs. A Custom Tab is deliberately not used here: it cannot
  /// download, and answers a PDF URL with "Can't download link".
  Future<void> _openPdf(ArxivPaper paper) async {
    final opened = await launchUrl(
      Uri.parse(paper.pdfUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing on this device opens PDFs.')),
      );
    }
  }
}
