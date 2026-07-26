import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/database.dart';
import '../../../../core/theme/app_theme.dart';

class PaperTile extends StatelessWidget {
  const PaperTile({super.key, required this.paper, this.unfiled = false});

  final Paper paper;

  /// Marks a paper that belongs to no project. Only the library shows this;
  /// inside a project every paper is filed by definition.
  final bool unfiled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = paper.progressNote.isNotEmpty
        ? paper.progressNote
        : paper.authors;

    return ListTile(
      onTap: () => context.push('/paper/${paper.id}'),
      leading: Icon(paper.status.icon, color: paper.status.color(scheme)),
      title: Text(paper.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: paper.progressNote.isNotEmpty
              ? scheme.primary
              : scheme.onSurfaceVariant,
          fontStyle: paper.progressNote.isNotEmpty
              ? FontStyle.italic
              : FontStyle.normal,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (unfiled)
            Tooltip(
              message: 'Not filed under any project',
              child: Icon(
                Icons.inbox_outlined,
                size: 18,
                color: scheme.outline,
              ),
            ),
          if (unfiled && paper.relativePath != null) const SizedBox(width: 10),
          if (paper.relativePath != null)
            Icon(Icons.picture_as_pdf, size: 18, color: scheme.outline),
        ],
      ),
    );
  }
}

/// Shared empty state, so every list explains what to do rather than showing a
/// blank screen.
class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: scheme.outlineVariant),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders a stream-backed list, collapsing the loading and error cases that
/// every screen here would otherwise repeat.
class PaperListView extends StatelessWidget {
  const PaperListView({
    super.key,
    required this.papers,
    required this.emptyIcon,
    required this.emptyMessage,
  });

  final AsyncValue<List<Paper>> papers;
  final IconData emptyIcon;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return papers.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => EmptyHint(
        icon: Icons.error_outline,
        message: 'Something went wrong: $error',
      ),
      data: (items) => items.isEmpty
          ? EmptyHint(icon: emptyIcon, message: emptyMessage)
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) => PaperTile(paper: items[index]),
            ),
    );
  }
}
