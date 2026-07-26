import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database/database.dart';
import 'network/arxiv_api.dart';
import 'storage/file_service.dart';

/// Infrastructure singletons. Everything above this line is plumbing; features
/// reach it only through a repository.
final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final arxivApiProvider = Provider<ArxivApi>((ref) => ArxivApi());

final fileServiceProvider = Provider<FileService>((ref) => FileService());
