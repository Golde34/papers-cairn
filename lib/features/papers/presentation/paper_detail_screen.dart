import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../projects/data/project_repository.dart';
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
            paper.arxivId,
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That file is gone from storage. Download it again.'),
          ),
        );
      }
      return;
    }

    await repository.markOpened(widget.paper.id);
    await OpenFilex.open(file.path);
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
        FilledButton.icon(
          onPressed: downloaded ? _open : _download,
          icon: Icon(downloaded ? Icons.open_in_new : Icons.download),
          label: Text(downloaded ? 'Open PDF' : 'Download PDF'),
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

    return _Section(
      title: 'Related papers',
      action: TextButton.icon(
        icon: const Icon(Icons.add_link, size: 18),
        label: const Text('Link'),
        onPressed: () => _link(context, ref),
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

  Future<void> _link(BuildContext context, WidgetRef ref) async {
    final candidates = (ref.read(allPapersProvider).value ?? [])
        .where((candidate) => candidate.id != paper.id)
        .toList();

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
}) {
  final controller = TextEditingController();
  return showDialog<String>(
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
}
