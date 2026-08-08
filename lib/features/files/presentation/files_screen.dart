import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../../../core/providers.dart';
import '../../papers/data/paper_repository.dart';
import '../data/file_inventory.dart';

/// Everything Cairn is actually holding on disk, next to what the library
/// thinks it holds.
///
/// The library lists papers; this lists files. They are not the same thing, and
/// the gaps between them — a PDF whose paper was deleted, a paper whose PDF was
/// deleted from a file manager — are the whole reason this screen exists.
class FilesScreen extends ConsumerWidget {
  const FilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(fileReportProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Files'),
        actions: [
          IconButton(
            tooltip: 'Rescan',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(fileReportProvider),
          ),
        ],
      ),
      body: report.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not read storage.\n$error')),
        data: (data) => _FileList(report: data),
      ),
    );
  }
}

class _FileList extends ConsumerWidget {
  const _FileList({required this.report});

  final FileReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final library = report.ofKind(FileKind.library);
    final loose = report.ofKind(FileKind.loose);
    final appData = report.ofKind(FileKind.appData);

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${report.files.length} files · ${formatBytes(report.totalBytes)}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              // Shown in full because on Android this is the only place the
              // path appears, and it is the answer to "where did my file go".
              SelectableText(
                report.rootPath,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),

        // Problems first. Everything else on this screen is fine as it is.
        if (report.missing.isNotEmpty) ...[
          _Heading('Missing on disk', count: report.missing.length),
          for (final entry in report.missing)
            _MissingTile(entry: entry, onChanged: () => _rescan(ref)),
        ],

        if (loose.isNotEmpty) ...[
          _Heading('Not in the library', count: loose.length),
          for (final file in loose)
            _LooseTile(file: file, onChanged: () => _rescan(ref)),
        ],

        if (library.isNotEmpty) ...[
          _Heading('In the library', count: library.length),
          for (final file in library) _LibraryTile(file: file),
        ],

        if (appData.isNotEmpty) ...[
          _Heading('App data', count: appData.length),
          for (final file in appData)
            ListTile(
              leading: const Icon(Icons.storage_outlined),
              title: Text(file.name),
              subtitle: Text(formatBytes(file.sizeBytes)),
              enabled: false,
            ),
        ],

        if (report.files.isEmpty && report.missing.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Nothing stored yet.')),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  void _rescan(WidgetRef ref) => ref.invalidate(fileReportProvider);
}

class _LibraryTile extends ConsumerWidget {
  const _LibraryTile({required this.file});

  final StoredFile file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paper = file.paper!;
    return ListTile(
      leading: const Icon(Icons.picture_as_pdf_outlined),
      title: Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('${paper.title} · ${formatBytes(file.sizeBytes)}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/paper/${paper.id}'),
    );
  }
}

class _LooseTile extends ConsumerWidget {
  const _LooseTile({required this.file, required this.onChanged});

  final StoredFile file;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.help_outline),
      title: Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (file.folder != '.') file.folder,
          formatBytes(file.sizeBytes),
        ].join(' · '),
      ),
      onTap: () => _open(context, ref, file.relativePath),
      trailing: PopupMenuButton<String>(
        onSelected: (value) => switch (value) {
          'open' => _open(context, ref, file.relativePath),
          'add' => _addToLibrary(context, ref),
          _ => _delete(context, ref),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'open', child: Text('Open')),
          PopupMenuItem(value: 'add', child: Text('Add to library')),
          PopupMenuItem(value: 'delete', child: Text('Delete file')),
        ],
      ),
    );
  }

  Future<void> _addToLibrary(BuildContext context, WidgetRef ref) async {
    // The file name is nearly always the best title available, and for anything
    // Cairn downloaded itself it is exactly the right one.
    final title = await _askTitle(
      context,
      p.basenameWithoutExtension(file.name),
    );
    if (title == null || title.isEmpty) return;

    await ref
        .read(paperRepositoryProvider)
        .adoptExisting(relativePath: file.relativePath, title: title);
    onChanged();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      title: 'Delete ${file.name}?',
      body: 'The file goes for good. Nothing in the library points at it.',
    );
    if (!confirmed) return;

    await ref.read(fileServiceProvider).delete(file.relativePath);
    onChanged();
  }
}

class _MissingTile extends ConsumerWidget {
  const _MissingTile({required this.entry, required this.onChanged});

  final MissingFile entry;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.link_off, color: scheme.error),
      title: Text(entry.paper.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(entry.relativePath),
      trailing: TextButton(
        onPressed: () async {
          await ref.read(paperRepositoryProvider).forgetFile(entry.paper.id);
          onChanged();
        },
        child: const Text('Forget'),
      ),
      onTap: () => context.push('/paper/${entry.paper.id}'),
    );
  }
}

Future<void> _open(
  BuildContext context,
  WidgetRef ref,
  String relativePath,
) async {
  final file = await ref.read(fileServiceProvider).resolve(relativePath);
  final result = await OpenFilex.open(file.path);
  if (result.type == ResultType.done || !context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Could not open it: ${result.message}')),
  );
}

Future<String?> _askTitle(BuildContext context, String initial) async {
  final controller = TextEditingController(text: initial);
  try {
    return await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add to library'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
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
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return result ?? false;
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {required this.count});

  final String text;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        '$text · $count',
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
