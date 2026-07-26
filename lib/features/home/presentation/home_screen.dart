import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/settings/settings_repository.dart';
import '../../../core/share/share_receiver.dart';
import '../../boards/presentation/boards_tab.dart';
import '../../papers/data/paper_repository.dart';
import '../../papers/presentation/add_paper_sheet.dart';
import '../../papers/presentation/widgets/paper_tile.dart';
import '../../projects/presentation/projects_tab.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;

  static const _titles = ['Reading', 'Library', 'Projects', 'Boards'];

  @override
  void initState() {
    super.initState();
    _listenForShares();
  }

  /// Papers shared from the browser are fetched immediately and land in the
  /// inbox. Filing them is a separate, later decision — interrupting with a
  /// project picker at share time defeats the point of a one-tap capture.
  void _listenForShares() {
    final receiver = ref.read(shareReceiverProvider);
    receiver.arxivIds.listen((arxivId) async {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      try {
        final paper = await ref
            .read(paperRepositoryProvider)
            .addFromArxiv(arxivId);
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text('Saved: ${paper.title}'),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => context.push('/paper/${paper.id}'),
            ),
          ),
        );
      } catch (error) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(content: Text('$error')));
      }
    });
    receiver.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          const _ThemeToggle(),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: const [
          _ReadingTab(),
          _LibraryTab(),
          ProjectsTab(),
          BoardsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => switch (_tab) {
          2 => showCreateProjectSheet(context),
          3 => showCreateBoardSheet(context),
          _ => showAddPaperSheet(context),
        },
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories),
            label: 'Reading',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Projects',
          ),
          NavigationDestination(
            icon: Icon(Icons.gesture_outlined),
            selectedIcon: Icon(Icons.gesture),
            label: 'Boards',
          ),
        ],
      ),
    );
  }
}

/// Cycles system → light → dark. Three states rather than a plain switch,
/// because "follow the device" is a real preference and losing it to a toggle
/// would be a downgrade for anyone who had it.
class _ThemeToggle extends ConsumerWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider).value ?? ThemeMode.system;

    final (icon, label, next) = switch (mode) {
      ThemeMode.system => (
        Icons.brightness_auto,
        'Following the device',
        ThemeMode.light,
      ),
      ThemeMode.light => (Icons.light_mode, 'Light', ThemeMode.dark),
      ThemeMode.dark => (Icons.dark_mode, 'Dark', ThemeMode.system),
    };

    return IconButton(
      icon: Icon(icon),
      tooltip: label,
      onPressed: () =>
          ref.read(settingsRepositoryProvider).setThemeMode(next),
    );
  }
}

class _ReadingTab extends ConsumerWidget {
  const _ReadingTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PaperListView(
      papers: ref.watch(readingPapersProvider),
      emptyIcon: Icons.auto_stories_outlined,
      emptyMessage:
          'Nothing in progress.\nMark a paper as Reading and it shows up here, '
          'most recently opened first.',
    );
  }
}

class _InboxTab extends ConsumerWidget {
  const _InboxTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PaperListView(
      papers: ref.watch(unfiledPapersProvider),
      emptyIcon: Icons.inbox_outlined,
      emptyMessage:
          'Inbox is empty.\nPapers shared from the browser land here until you '
          'file them under a project.',
    );
  }
}
