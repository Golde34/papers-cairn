import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

export 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Papers,
    Projects,
    PaperProjects,
    PaperRelations,
    Annotations,
    Boards,
    Strokes,
    BoardItems,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'cairn'));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Reading moved in-app: highlights need somewhere to live, and papers
        // need to remember the page you stopped on.
        await m.createTable(annotations);
        await m.addColumn(papers, papers.lastPage);
      }
      if (from < 3) {
        await m.createTable(boards);
        await m.createTable(strokes);
      }
      if (from < 4) {
        await m.createTable(boardItems);
      }
    },
    beforeOpen: (details) async {
      // SQLite ignores foreign keys unless this is enabled per connection,
      // which would silently break every onDelete: cascade above.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
