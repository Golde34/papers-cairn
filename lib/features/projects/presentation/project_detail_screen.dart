import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../papers/data/paper_repository.dart';
import '../../papers/presentation/add_paper_sheet.dart';
import '../../papers/presentation/widgets/paper_tile.dart';
import '../data/project_repository.dart';

class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({super.key, required this.projectId});

  final int projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider).value ?? [];
    final project = projects.where((p) => p.id == projectId).firstOrNull;
    final papers = ref.watch(papersOfProjectProvider(projectId));

    return Scaffold(
      appBar: AppBar(
        title: Text(project?.name ?? 'Project'),
        actions: [
          IconButton(
            tooltip: 'Delete project',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref, project?.name),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddPaperSheet(context, projectId: projectId),
        icon: const Icon(Icons.add),
        label: const Text('Add paper'),
      ),
      body: PaperListView(
        papers: papers,
        emptyIcon: Icons.description_outlined,
        emptyMessage:
            'No papers here yet.\nAdd one, or share an arXiv link into Cairn.',
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String? name,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${name ?? 'this project'}?'),
        content: const Text(
          'The papers stay in your library and downloaded PDFs stay on disk. '
          'Only the project and its filing notes go away.',
        ),
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

    if (confirmed != true || !context.mounted) return;
    await ref.read(projectRepositoryProvider).delete(projectId);
    if (context.mounted) context.pop();
  }
}
