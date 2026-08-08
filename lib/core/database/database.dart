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
    Settings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'cairn'));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 8;

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
      if (from < 5) {
        await m.createTable(settings);
      }
      if (from < 6) {
        // arxivId and pdfUrl become nullable so imported PDFs can be held.
        // SQLite cannot relax NOT NULL in place, so drift rebuilds the table
        // and copies the rows across.
        await m.alterTable(TableMigration(papers));
      }
      if (from < 7) {
        await m.addColumn(boards, boards.background);
      }
      if (from < 8) {
        // The library starts holding documents as well as papers. Everything
        // already in it was added as a paper, which is what the default says.
        await m.addColumn(papers, papers.kind);
      }
    },
    beforeOpen: (details) async {
      // SQLite ignores foreign keys unless this is enabled per connection,
      // which would silently break every onDelete: cascade above.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
