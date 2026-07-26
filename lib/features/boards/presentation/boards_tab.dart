import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../papers/presentation/widgets/paper_tile.dart';
import '../../projects/data/project_repository.dart';
import '../data/board_repository.dart';

class BoardsTab extends ConsumerWidget {
  const BoardsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boards = ref.watch(boardsProvider);
    final projects = ref.watch(projectsProvider).value ?? const [];

    return boards.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (items) => items.isEmpty
          ? const EmptyHint(
              icon: Icons.gesture,
              message:
                  'No boards yet.\nA board is somewhere to think out loud — '
                  'sketch the argument, draw the arrows, work out what connects '
                  'to what.',
            )
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final board = items[index];
                final project = projects
                    .where((p) => p.id == board.projectId)
                    .firstOrNull;

                return ListTile(
                  leading: const Icon(Icons.gesture),
                  title: Text(board.title),
                  subtitle: Text(
                    [
                      if (project != null) project.name,
                      DateFormat.yMMMd().add_jm().format(board.updatedAt),
                    ].join('  ·  '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/board/${board.id}'),
                );
              },
            ),
    );
  }
}

Future<void> showCreateBoardSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _CreateBoardSheet(),
  );
}

class _CreateBoardSheet extends ConsumerStatefulWidget {
  const _CreateBoardSheet();

  @override
  ConsumerState<_CreateBoardSheet> createState() => _CreateBoardSheetState();
}

class _CreateBoardSheetState extends ConsumerState<_CreateBoardSheet> {
  final _controller = TextEditingController();
  int? _projectId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _controller.text.trim();
    final id = await ref
        .read(boardRepositoryProvider)
        .create(
          // An untitled board is still worth having; forcing a name up front
          // just gets in the way of the thought you opened it to capture.
          title: title.isEmpty ? 'Untitled board' : title,
          projectId: _projectId,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
    context.push('/board/$id');
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider).value ?? const [];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New board', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'How contrastive losses fit together',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (projects.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _projectId,
              decoration: const InputDecoration(
                labelText: 'Project (optional)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('No project')),
                for (final project in projects)
                  DropdownMenuItem(
                    value: project.id,
                    child: Text(project.name),
                  ),
              ],
              onChanged: (value) => setState(() => _projectId = value),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: _submit, child: const Text('Create')),
        ],
      ),
    );
  }
}
