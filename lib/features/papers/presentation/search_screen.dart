import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../data/paper_repository.dart';
import 'widgets/paper_tile.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  String _term = '';

  /// Held rather than built in `build`.
  ///
  /// Creating the stream inline meant a fresh database query on every rebuild —
  /// once per keystroke, and again whenever anything unrelated redrew the
  /// screen, each time dropping back to a loading spinner. Kept here, the query
  /// is made once per search and the results stay on screen while you type.
  Stream<List<Paper>>? _results;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Waits for a pause before searching. Every keystroke is not a question; the
  /// word you are halfway through typing is rarely one worth scanning for.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(value));
  }

  void _search(String value) {
    final term = value.trim();
    if (term == _term) return;

    setState(() {
      _term = term;
      _results = term.isEmpty
          ? null
          : ref.read(paperRepositoryProvider).search(term);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search titles, authors, abstracts, notes',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
          // Submitting should not wait out the pause.
          onSubmitted: _search,
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final results = _results;
    if (results == null) {
      return const EmptyHint(
        icon: Icons.search,
        message: 'Your own notes and highlights are searchable too, not just '
            'abstracts.',
      );
    }

    return StreamBuilder<List<Paper>>(
      stream: results,
      builder: (context, snapshot) {
        final papers = snapshot.data;
        if (papers == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (papers.isEmpty) {
          return EmptyHint(
            icon: Icons.search_off,
            message: 'Nothing matches "$_term".',
          );
        }
        return ListView.separated(
          itemCount: papers.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, index) => PaperTile(paper: papers[index]),
        );
      },
    );
  }
}
