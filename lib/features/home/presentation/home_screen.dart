import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'dart:async';
import 'dart:io';

import '../../../core/database/database.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/share/share_receiver.dart';
import '../../boards/presentation/boards_tab.dart';
import '../../papers/data/paper_repository.dart';
import '../../papers/presentation/add_paper_sheet.dart';
import '../../papers/presentation/widgets/paper_tile.dart';
import '../../projects/presentation/projects_tab.dart';
import 'app_drawer.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;

  /// Held so it can be cancelled. An uncancelled subscription keeps this State —
  /// and the BuildContext it closes over — alive after the widget is gone, and
  /// every hot restart used to stack another listener on top of the last.
  StreamSubscription<SharedItem>? _shares;

  static const _titles = ['Library', 'Projects', 'Boards'];

  @override
  void initState() {
    super.initState();
    _listenForShares();
  }

  @override
  void dispose() {
    _shares?.cancel();
    super.dispose();
  }

  /// Papers shared from the browser are fetched immediately and land in the
  /// library unfiled. Filing them is a separate, later decision — interrupting
  /// with a project picker at share time defeats the point of a one-tap capture.
  void _listenForShares() {
    final receiver = ref.read(shareReceiverProvider);
    _shares = receiver.items.listen((item) async {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final repository = ref.read(paperRepositoryProvider);

      try {
        final (paper, note) = switch (item) {
          SharedArxivId(:final arxivId) => (
            await repository.addFromArxiv(arxivId),
            'Saved',
          ),

          // The file name gave the paper away. Its metadata comes from arXiv,
          // its bytes from the file you already have — no second download, and
          // no second copy of a paper the library is already holding.
          SharedPdf(:final path, arxivId: final String id) =>
            await _adoptSharedArxivPdf(repository, id, path),

          // Nothing identifies it, so the one thing that matters — what to call
          // it — is asked before anything is written.
          SharedPdf(:final path, :final suggestedTitle) => (
            await _importShared(repository, path, suggestedTitle),
            'Imported',
          ),

          SharedUnrecognised() => (null, ''),
        };

        if (item is SharedUnrecognised) {
          if (!mounted) return;
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Cairn takes arXiv links and PDF files.'),
            ),
          );
          return;
        }

        if (!mounted || paper == null) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text('$note: ${paper.title}'),
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

  /// Whether the paper was already held has to be settled before saving, or the
  /// answer is always "yes" and the message always says the wrong thing.
  Future<(Paper?, String)> _adoptSharedArxivPdf(
    PaperRepository repository,
    String arxivId,
    String path,
  ) async {
    final held = await repository.findByArxivId(arxivId) != null;
    final paper = await repository.addFromArxivWithFile(
      arxivId: arxivId,
      source: File(path),
    );
    return (paper, held ? 'Attached your file to' : 'Saved with your file');
  }

  Future<Paper?> _importShared(
    PaperRepository repository,
    String path,
    String suggestedTitle,
  ) async {
    final choice = await showImportTitleDialog(context, suggestedTitle);
    if (choice == null || choice.title.isEmpty) return null;
    return repository.importPdf(
      source: File(path),
      title: choice.title,
      kind: choice.kind,
    );
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
      drawer: AppDrawer(
        tab: _tab,
        onTab: (index) => setState(() => _tab = index),
      ),
      body: IndexedStack(
        index: _tab,
        children: const [_LibraryTab(), ProjectsTab(), BoardsTab()],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => switch (_tab) {
          1 => showCreateProjectSheet(context),
          2 => showCreateBoardSheet(context),
          _ => showAddPaperSheet(context),
        },
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
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

/// What the library is currently narrowed to.
///
/// Replaced a separate Reading tab. One list you can narrow beats two lists you
/// have to switch between, and it leaves somewhere obvious to look for a paper
/// that is neither in progress nor top of mind.
enum _LibraryFilter {
  all('All'),
  papers('Papers'),
  documents('Documents'),
  toRead('To read'),
  reading('Reading'),
  done('Done'),
  unfiled('Unfiled');

  const _LibraryFilter(this.label);

  final String label;

  bool matches(Paper paper, Set<int> unfiledIds) => switch (this) {
    _LibraryFilter.all => true,
    _LibraryFilter.papers => paper.kind == EntryKind.paper,
    _LibraryFilter.documents => paper.kind == EntryKind.document,
    _LibraryFilter.toRead => paper.status == ReadingStatus.toRead,
    _LibraryFilter.reading => paper.status == ReadingStatus.reading,
    _LibraryFilter.done => paper.status == ReadingStatus.done,
    _LibraryFilter.unfiled => unfiledIds.contains(paper.id),
  };
}

/// Every paper, with the unfiled ones marked.
///
/// This replaced an inbox that only listed unfiled papers. The inbox stayed
/// empty for anyone who picks a project while adding, and meanwhile there was
/// nowhere at all to see the whole library — a filed paper you were not
/// currently reading could only be reached through its project or by searching.
class _LibraryTab extends ConsumerStatefulWidget {
  const _LibraryTab();

  @override
  ConsumerState<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends ConsumerState<_LibraryTab> {
  _LibraryFilter _filter = _LibraryFilter.all;

  @override
  Widget build(BuildContext context) {
    final papers = ref.watch(allPapersProvider);
    final unfiled = <int>{
      for (final paper
          in ref.watch(unfiledPapersProvider).value ?? const <Paper>[])
        paper.id,
    };

    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final option in _LibraryFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    child: FilterChip(
                      label: Text(option.label),
                      selected: _filter == option,
                      onSelected: (_) => setState(() => _filter = option),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: papers.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => EmptyHint(
              icon: Icons.error_outline,
              message: 'Something went wrong: $error',
            ),
            data: (all) {
              final items = all
                  .where((paper) => _filter.matches(paper, unfiled))
                  .toList();

              if (items.isEmpty) {
                return EmptyHint(
                  icon: Icons.library_books_outlined,
                  message: _filter == _LibraryFilter.all
                      ? 'Nothing here yet.\nAdd a paper, or share an arXiv link '
                            'into Cairn from your browser.'
                      : 'No papers under "${_filter.label}".',
                );
              }

              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, index) => PaperTile(
                  paper: items[index],
                  unfiled: unfiled.contains(items[index].id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
