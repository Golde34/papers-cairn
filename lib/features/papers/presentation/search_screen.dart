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
  String _term = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search titles, authors, abstracts, notes',
            border: InputBorder.none,
          ),
          onChanged: (value) => setState(() => _term = value.trim()),
        ),
      ),
      body: _term.isEmpty
          ? const EmptyHint(
              icon: Icons.search,
              message: 'Your own notes are searchable too, not just abstracts.',
            )
          : StreamBuilder<List<Paper>>(
              stream: ref.read(paperRepositoryProvider).search(_term),
              builder: (context, snapshot) {
                final results = snapshot.data;
                if (results == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (results.isEmpty) {
                  return EmptyHint(
                    icon: Icons.search_off,
                    message: 'Nothing matches "$_term".',
                  );
                }
                return ListView.separated(
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) => PaperTile(paper: results[index]),
                );
              },
            ),
    );
  }
}
