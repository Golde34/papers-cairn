import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/boards/presentation/board_screen.dart';
import '../../features/files/presentation/files_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/papers/presentation/paper_detail_screen.dart';
import '../../features/papers/presentation/search_screen.dart';
import '../../features/projects/presentation/project_detail_screen.dart';
import '../../features/reader/presentation/reader_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
    GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
    GoRoute(path: '/files', builder: (_, _) => const FilesScreen()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    GoRoute(
      path: '/paper/:id',
      builder: (_, state) =>
          _withIntId(state, (id) => PaperDetailScreen(paperId: id)),
      routes: [
        GoRoute(
          path: 'read',
          builder: (_, state) =>
              _withIntId(state, (id) => ReaderScreen(paperId: id)),
        ),
      ],
    ),
    GoRoute(
      path: '/project/:id',
      builder: (_, state) =>
          _withIntId(state, (id) => ProjectDetailScreen(projectId: id)),
    ),
    GoRoute(
      path: '/board/:id',
      builder: (_, state) => _withIntId(state, (id) => BoardScreen(boardId: id)),
    ),
  ],
);

Widget _withIntId(GoRouterState state, Widget Function(int id) build) {
  final id = int.tryParse(state.pathParameters['id'] ?? '');
  if (id == null) {
    return const Scaffold(body: Center(child: Text('Not found')));
  }
  return build(id);
}
