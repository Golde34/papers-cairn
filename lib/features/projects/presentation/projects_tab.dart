import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../papers/presentation/widgets/paper_tile.dart';
import '../data/project_repository.dart';

class ProjectsTab extends ConsumerWidget {
  const ProjectsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);
    final counts = ref.watch(projectPaperCountsProvider).value ?? {};

    return projects.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (items) => items.isEmpty
          ? const EmptyHint(
              icon: Icons.folder_outlined,
              message:
                  'No projects yet.\nA project is one line of enquiry — the '
                  'papers you are reading for a single question.',
            )
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final project = items[index];
                final count = counts[project.id] ?? 0;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Color(project.colorValue),
                    radius: 12,
                  ),
                  title: Text(project.name),
                  subtitle: Text(count == 1 ? '1 paper' : '$count papers'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/project/${project.id}'),
                );
              },
            ),
    );
  }
}

Future<void> showCreateProjectSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _CreateProjectSheet(),
  );
}

class _CreateProjectSheet extends ConsumerStatefulWidget {
  const _CreateProjectSheet();

  @override
  ConsumerState<_CreateProjectSheet> createState() =>
      _CreateProjectSheetState();
}

class _CreateProjectSheetState extends ConsumerState<_CreateProjectSheet> {
  final _controller = TextEditingController();
  late Color _color = projectPalette[Random().nextInt(projectPalette.length)];
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give it a name');
      return;
    }

    try {
      await ref
          .read(projectRepositoryProvider)
          .create(name: name, colorValue: _color.toARGB32());
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      // The name column is unique; anything else here would be a bug worth
      // seeing rather than swallowing.
      if (mounted) setState(() => _error = 'A project already has that name');
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New project', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Name',
              hintText: 'Contrastive pretraining',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            children: projectPalette
                .map(
                  (color) => GestureDetector(
                    onTap: () => setState(() => _color = color),
                    child: CircleAvatar(
                      backgroundColor: color,
                      radius: 16,
                      child: _color == color
                          ? const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _submit, child: const Text('Create')),
        ],
      ),
    );
  }
}
