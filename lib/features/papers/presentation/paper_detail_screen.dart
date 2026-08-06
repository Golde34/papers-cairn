import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../projects/data/project_repository.dart';
import '../../reader/data/annotation_repository.dart';
import '../data/paper_repository.dart';

class PaperDetailScreen extends ConsumerWidget {
  const PaperDetailScreen({super.key, required this.paperId});

  final int paperId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paper = ref.watch(paperProvider(paperId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paper'),
        actions: [
          IconButton(
            tooltip: 'Remove from library',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: paper.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (value) => value == null
            ? const Center(child: Text('This paper is no longer in the library'))
            : _Body(paper: value),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this paper?'),
        content: const Text(
          'The downloaded PDF is deleted too. Notes, project links, and '
          'relations for this paper are lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    await ref.read(paperRepositoryProvider).delete(paperId);
    if (context.mounted) context.pop();
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.paper});

  final Paper paper;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final published = paper.publishedAt;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(paper.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          paper.authors,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(
          [
            // An imported paper has no arXiv id; the row should shrink rather
            // than print the word "null".
            ?paper.arxivId,
            if (published != null) DateFormat.yMMM().format(published),
            if (paper.categories.isNotEmpty) paper.categories,
          ].join('  ·  '),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        _PdfSection(paper: paper),
        const Divider(height: 32),
        _StatusSelector(paper: paper),
        const SizedBox(height: 16),
        _ProgressNoteField(paper: paper),
        const Divider(height: 32),
        _HighlightsSection(paper: paper),
        const Divider(height: 32),
        _ProjectsSection(paper: paper),
        const Divider(height: 32),
        _RelationsSection(paper: paper),
        const Divider(height: 32),
        _Section(
          title: 'Abstract',
          child: Text(paper.abstractText, style: const TextStyle(height: 1.4)),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.action});

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            ?action,
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _PdfSection extends ConsumerStatefulWidget {
  const _PdfSection({required this.paper});

  final Paper paper;

  @override
  ConsumerState<_PdfSection> createState() => _PdfSectionState();
}

class _PdfSectionState extends ConsumerState<_PdfSection> {
  double? _progress;
  String? _error;

  Future<void> _download() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      await ref
          .read(paperRepositoryProvider)
          .downloadPdf(
            widget.paper.id,
            onProgress: (received, total) {
              if (total > 0 && mounted) {
                setState(() => _progress = received / total);
              }
            },
          );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _open() async {
    final repository = ref.read(paperRepositoryProvider);
    final file = await repository.localFile(widget.paper.id);

    if (file == null) {
      // localFile has already cleared the stale path, so the button below has
      // flipped back to Download by the time this message is read.
      _tell('That file is gone from storage. Download it again.');
      return;
    }

    await repository.markOpened(widget.paper.id);

    final result = await OpenFilex.open(file.path);
    if (result.type == ResultType.done) return;

    // Nothing on the device claims application/pdf. The download is fine and
    // still on disk; there is simply no reader. Hand the arXiv copy to a full
    // browser as a stopgap.
    //
    // externalApplication, not inAppBrowserView: a Custom Tab is a stripped
    // Chrome that cannot download, so it answers a PDF URL with "Can't download
    // link". This is safe from bouncing back into Cairn because the arxiv.org
    // intent filter is scoped to /abs.
    // An imported paper has no URL to fall back to — the file on disk is the
    // only copy there has ever been.
    final url = widget.paper.pdfUrl;
    if (url == null) {
      _tell('Install a PDF reader to open this file.');
      return;
    }

    _tell('No PDF reader installed. Trying the browser instead.');
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      _tell('Install a PDF reader to open downloaded papers.');
    }
  }

  void _tell(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_progress != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(value: _progress == 0 ? null : _progress),
          const SizedBox(height: 8),
          Text(
            'Downloading… ${((_progress ?? 0) * 100).round()}%',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }

    final downloaded = widget.paper.relativePath != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!downloaded)
          FilledButton.icon(
            onPressed: _download,
            icon: const Icon(Icons.download),
            label: const Text('Download PDF'),
          )
        else
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () =>
                      context.push('/paper/${widget.paper.id}/read'),
                  icon: const Icon(Icons.chrome_reader_mode_outlined),
                  label: const Text('Read'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Open in another app',
                icon: const Icon(Icons.open_in_new),
                onPressed: _open,
              ),
            ],
          ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class _StatusSelector extends ConsumerWidget {
  const _StatusSelector({required this.paper});

  final Paper paper;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Section(
      title: 'Status',
      child: SegmentedButton<ReadingStatus>(
        segments: ReadingStatus.values
            .map(
              (status) => ButtonSegment(
                value: status,
                icon: Icon(status.icon),
                tooltip: status.label,
              ),
            )
            .toList(),
        selected: {paper.status},
        showSelectedIcon: false,
        onSelectionChanged: (selection) => ref
            .read(paperRepositoryProvider)
            .setStatus(paper.id, selection.first),
      ),
    );
  }
}

class _ProgressNoteField extends ConsumerStatefulWidget {
  const _ProgressNoteField({required this.paper});

  final Paper paper;

  @override
  ConsumerState<_ProgressNoteField> createState() => _ProgressNoteFieldState();
}

class _ProgressNoteFieldState extends ConsumerState<_ProgressNoteField> {
  late final _controller = TextEditingController(
    text: widget.paper.progressNote,
  );
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Saving on every keystroke would rewrite the row the stream is feeding
    // this field from, so the note is committed when the field loses focus.
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _save();
    });
  }

  void _save() {
    final text = _controller.text;
    if (text == widget.paper.progressNote) return;
    ref.read(paperRepositoryProvider).setProgressNote(widget.paper.id, text);
  }

  @override
  void dispose() {
    _save();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Where you stopped',
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        maxLines: null,
        textInputAction: TextInputAction.newline,
        decoration: const InputDecoration(
          hintText: 'Read up to section 4.2, stuck on the proof of Lemma 3',
          border: OutlineInputBorder(),
        ),
      ),
    );
  }
}

/// Highlights made in the reader, shown here so the paper's page is one place
/// for everything thought about it rather than a launcher for the PDF.
class _HighlightsSection extends ConsumerWidget {
  const _HighlightsSection({required this.paper});

  final Paper paper;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final annotations = ref.watch(annotationsProvider(paper.id));
    final scheme = Theme.of(context).colorScheme;

    return _Section(
      title: 'Highlights',
      child: annotations.when(
        loading: () => const SizedBox(height: 24),
        error: (error, _) => Text('$error'),
        data: (items) => items.isEmpty
            ? Text(
                paper.relativePath == null
                    ? 'Download the paper to start highlighting.'
                    : 'None yet. Select text while reading to make one.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            : Column(
                children: [
                  for (final annotation in items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 4,
                        height: 36,
                        color: Color(annotation.colorValue),
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
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      onTap: () => context.push('/paper/${paper.id}/read'),
                    ),
                ],
              ),
      ),
    );
  }
}

class _ProjectsSection extends ConsumerWidget {
  const _ProjectsSection({required this.paper});

  final Paper paper;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filed = ref.watch(projectsOfPaperProvider(paper.id));
    final all = ref.watch(projectsProvider);

    return _Section(
      title: 'Projects',
      action: TextButton.icon(
        icon: const Icon(Icons.add, size: 18),
        label: const Text('File'),
        onPressed: () => _pickProject(context, ref, all.value ?? []),
      ),
      child: filed.when(
        loading: () => const SizedBox(height: 24),
        error: (error, _) => Text('$error'),
        data: (projects) => projects.isEmpty
            ? Text(
                'Not filed anywhere yet.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: projects
                    .map(
                      (project) => InputChip(
                        label: Text(project.name),
                        avatar: CircleAvatar(
                          backgroundColor: Color(project.colorValue),
                          radius: 6,
                        ),
                        onPressed: () => context.push('/project/${project.id}'),
                        onDeleted: () => ref
                            .read(paperRepositoryProvider)
                            .removeFromProject(paper.id, project.id),
                      ),
                    )
                    .toList(),
              ),
      ),
    );
  }

  Future<void> _pickProject(
    BuildContext context,
    WidgetRef ref,
    List<Project> projects,
  ) async {
    if (projects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a project first.')),
      );
      return;
    }

    final selected = await showModalBottomSheet<Project>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: projects
              .map(
                (project) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Color(project.colorValue),
                    radius: 10,
                  ),
                  title: Text(project.name),
                  onTap: () => Navigator.of(sheetContext).pop(project),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (selected == null || !context.mounted) return;

    final note = await _askForReason(
      context,
      title: 'Why does this belong in ${selected.name}?',
      hint: 'baseline we compare against',
    );
    if (note == null) return;

    await ref
        .read(paperRepositoryProvider)
        .addToProject(paper.id, selected.id, note: note);
  }
}

class _RelationsSection extends ConsumerWidget {
  const _RelationsSection({required this.paper});

  final Paper paper;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final related = ref.watch(relatedPapersProvider(paper.id));
    // Watched, not read inside the handler. A StreamProvider nobody is
    // listening to has no value yet, so reading it on the first tap always came
    // back empty and the button claimed there was nothing to link to.
    final candidates = (ref.watch(allPapersProvider).value ?? [])
        .where((candidate) => candidate.id != paper.id)
        .toList();

    return _Section(
      title: 'Related papers',
      action: TextButton.icon(
        icon: const Icon(Icons.add_link, size: 18),
        label: const Text('Link'),
        onPressed: () => _link(context, ref, candidates),
      ),
      child: related.when(
        loading: () => const SizedBox(height: 24),
        error: (error, _) => Text('$error'),
        data: (items) => items.isEmpty
            ? Text(
                'No links yet.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            : Column(
                children: items
                    .map(
                      (entry) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          entry.$1.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: entry.$2.isEmpty ? null : Text(entry.$2),
                        onTap: () => context.push('/paper/${entry.$1.id}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.link_off, size: 18),
                          onPressed: () => ref
                              .read(paperRepositoryProvider)
                              .unlink(paper.id, entry.$1.id),
                        ),
                      ),
                    )
                    .toList(),
              ),
      ),
    );
  }

  Future<void> _link(
    BuildContext context,
    WidgetRef ref,
    List<Paper> candidates,
  ) async {
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add another paper first.')),
      );
      return;
    }

    final target = await showModalBottomSheet<Paper>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: candidates
              .map(
                (candidate) => ListTile(
                  title: Text(
                    candidate.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.of(sheetContext).pop(candidate),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (target == null || !context.mounted) return;

    final note = await _askForReason(
      context,
      title: 'How are these two connected?',
      hint: 'extends the loss from section 3',
    );
    if (note == null) return;

    await ref.read(paperRepositoryProvider).link(paper.id, target.id, note);
  }
}

/// Prompts for the reason behind a link.
///
/// Returns null when cancelled, so an empty string stays a valid answer for
/// anyone who really does not want to explain themselves.
Future<String?> _askForReason(
  BuildContext context, {
  required String title,
  required String hint,
}) async {
  final controller = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}
