import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../providers.dart';

const _themeKey = 'themeMode';

class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  /// Defaults to following the system. Someone who has never touched the toggle
  /// wants whatever the rest of their device is doing.
  Stream<ThemeMode> watchThemeMode() =>
      (_db.select(_db.settings)..where((s) => s.key.equals(_themeKey)))
          .watchSingleOrNull()
          .map(
            (row) => switch (row?.value) {
              'light' => ThemeMode.light,
              'dark' => ThemeMode.dark,
              _ => ThemeMode.system,
            },
          );

  Future<void> setThemeMode(ThemeMode mode) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(key: _themeKey, value: mode.name),
      );
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);

final themeModeProvider = StreamProvider<ThemeMode>(
  (ref) => ref.watch(settingsRepositoryProvider).watchThemeMode(),
);
