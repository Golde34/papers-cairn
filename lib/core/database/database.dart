import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

export 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Papers, Projects, PaperProjects, PaperRelations])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'cairn'));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      // SQLite ignores foreign keys unless this is enabled per connection,
      // which would silently break every onDelete: cascade above.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
