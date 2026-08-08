import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/database.dart';
import '../../../core/providers.dart';
import '../../../core/storage/file_service.dart';

/// What a file on disk turned out to be.
enum FileKind {
  /// A paper in the library points at it.
  library,

  /// Nothing in the database mentions it. Either it was put there by hand, or
  /// the paper that owned it was deleted while the file stayed.
  loose,

  /// The database itself. Cairn's own bookkeeping, not a document.
  appData,
}

class StoredFile {
  const StoredFile({
    required this.relativePath,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.kind,
    this.paper,
  });

  final String relativePath;
  final int sizeBytes;
  final DateTime modifiedAt;
  final FileKind kind;

  /// The paper that claims this file, when one does.
  final Paper? paper;

  String get name => p.basename(relativePath);
  String get folder => p.dirname(relativePath);
}

/// A paper whose file is not where the database says it is.
///
/// The case that started this screen: a PDF deleted from a file manager leaves
/// the library holding a path to nothing, and until you try to open it nothing
/// says so.
class MissingFile {
  const MissingFile({required this.paper, required this.relativePath});

  final Paper paper;
  final String relativePath;
}

class FileReport {
  const FileReport({
    required this.rootPath,
    required this.files,
    required this.missing,
  });

  final String rootPath;
  final List<StoredFile> files;
  final List<MissingFile> missing;

  List<StoredFile> ofKind(FileKind kind) =>
      files.where((file) => file.kind == kind).toList();

  int get totalBytes =>
      files.fold(0, (total, file) => total + file.sizeBytes);
}

/// Reads what is actually on disk and holds it against what the database
/// believes.
///
/// Deliberately not a cached view of the library: the whole point is to catch
/// the places where the two have drifted apart.
class FileInventory {
  FileInventory(this._db, this._files);

  final AppDatabase _db;
  final FileService _files;

  Future<FileReport> scan() async {
    final papers = await _db.select(_db.papers).get();
    final root = await _files.root();

    final onDisk = <ScannedFile>[];
    for (final path in await _files.list()) {
      final stat = await File(p.join(root.path, path)).stat();
      onDisk.add((
        relativePath: path,
        sizeBytes: stat.size,
        modifiedAt: stat.modified,
      ));
    }

    return reconcile(rootPath: root.path, papers: papers, onDisk: onDisk);
  }
}

/// A file as the filesystem described it, before anything is known about what
/// it means to the app.
typedef ScannedFile = ({
  String relativePath,
  int sizeBytes,
  DateTime modifiedAt,
});

/// Matches what is on disk against what the database claims, in both
/// directions.
///
/// Kept apart from the scanning so it can be tested without a filesystem: the
/// interesting cases here are files nothing claims and claims with no file, and
/// neither needs a real directory to reproduce.
FileReport reconcile({
  required String rootPath,
  required List<Paper> papers,
  required List<ScannedFile> onDisk,
}) {
  final claimed = <String, Paper>{
    for (final paper in papers)
      if (paper.relativePath != null) paper.relativePath!: paper,
  };

  final files = [
    for (final scanned in onDisk)
      StoredFile(
        relativePath: scanned.relativePath,
        sizeBytes: scanned.sizeBytes,
        modifiedAt: scanned.modifiedAt,
        kind: _isAppData(scanned.relativePath)
            ? FileKind.appData
            : claimed.containsKey(scanned.relativePath)
            ? FileKind.library
            : FileKind.loose,
        paper: claimed[scanned.relativePath],
      ),
  ];

  final present = {for (final scanned in onDisk) scanned.relativePath};
  final missing = [
    for (final paper in papers)
      if (paper.relativePath != null && !present.contains(paper.relativePath))
        MissingFile(paper: paper, relativePath: paper.relativePath!),
  ];

  // Biggest first. Someone opening this screen is usually asking where the space
  // went, and that answer belongs at the top.
  files.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
  return FileReport(rootPath: rootPath, files: files, missing: missing);
}

/// The drift database and the journal files it keeps beside itself. They sit in
/// the same directory as the documents and are emphatically not documents.
bool _isAppData(String relativePath) =>
    p.dirname(relativePath) == '.' &&
    p.basename(relativePath).startsWith('cairn.sqlite');

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

final fileInventoryProvider = Provider<FileInventory>(
  (ref) => FileInventory(
    ref.watch(databaseProvider),
    ref.watch(fileServiceProvider),
  ),
);

/// Re-read rather than watched. A directory listing is not a stream, and the
/// screen invalidates this itself after anything it does changes the answer.
final fileReportProvider = FutureProvider<FileReport>(
  (ref) => ref.watch(fileInventoryProvider).scan(),
);
