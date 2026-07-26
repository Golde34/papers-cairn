import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/providers.dart';
import '../../../core/storage/file_service.dart';

class ProjectRepository {
  ProjectRepository(this._db);

  final AppDatabase _db;

  Stream<List<Project>> watchAll() =>
      (_db.select(_db.projects)..orderBy([
            (p) => OrderingTerm(expression: p.createdAt, mode: OrderingMode.desc),
          ]))
          .watch();

  Future<Project?> findById(int id) =>
      (_db.select(_db.projects)..where((p) => p.id.equals(id)))
          .getSingleOrNull();

  Future<Project> create({required String name, required int colorValue}) async {
    final trimmed = name.trim();
    final id = await _db
        .into(_db.projects)
        .insert(
          ProjectsCompanion.insert(
            name: trimmed,
            // Frozen at creation. Renaming a project later must not move or
            // orphan PDFs already sitting on disk under the old folder.
            folderName: FileService.sanitizeFolderName(trimmed),
            colorValue: colorValue,
            createdAt: DateTime.now(),
          ),
        );
    return (await findById(id))!;
  }

  Future<void> rename(int id, String name) =>
      (_db.update(_db.projects)..where((p) => p.id.equals(id))).write(
        ProjectsCompanion(name: Value(name.trim())),
      );

  /// Removes the project and its memberships. Papers survive, and so do any
  /// PDFs already on disk — deleting a folder of downloaded reading because a
  /// project was tidied away would be a nasty surprise.
  Future<void> delete(int id) =>
      (_db.delete(_db.projects)..where((p) => p.id.equals(id))).go();

  /// Number of papers filed under each project, keyed by project id.
  Stream<Map<int, int>> watchPaperCounts() {
    final count = _db.paperProjects.paperId.count();
    final query = _db.selectOnly(_db.paperProjects)
      ..addColumns([_db.paperProjects.projectId, count])
      ..groupBy([_db.paperProjects.projectId]);

    return query.watch().map(
      (rows) => {
        for (final row in rows)
          row.read(_db.paperProjects.projectId)!: row.read(count) ?? 0,
      },
    );
  }
}

final projectRepositoryProvider = Provider<ProjectRepository>(
  (ref) => ProjectRepository(ref.watch(databaseProvider)),
);

final projectsProvider = StreamProvider<List<Project>>(
  (ref) => ref.watch(projectRepositoryProvider).watchAll(),
);

final projectPaperCountsProvider = StreamProvider<Map<int, int>>(
  (ref) => ref.watch(projectRepositoryProvider).watchPaperCounts(),
);
