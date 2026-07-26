import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/network/arxiv_api.dart';
import '../../../core/network/arxiv_id.dart';
import '../../../core/providers.dart';
import '../../../core/storage/file_service.dart';

/// Papers not yet filed under any project land here.
const inboxFolderName = 'Inbox';

class PaperRepository {
  PaperRepository(this._db, this._api, this._files);

  final AppDatabase _db;
  final ArxivApi _api;
  final FileService _files;

  Stream<List<Paper>> watchAll() =>
      (_db.select(_db.papers)..orderBy([_byRecency])).watch();

  Stream<List<Paper>> watchByStatus(ReadingStatus status) =>
      (_db.select(_db.papers)
            ..where((p) => p.status.equalsValue(status))
            ..orderBy([_byRecency]))
          .watch();

  Stream<Paper?> watchById(int id) =>
      (_db.select(_db.papers)..where((p) => p.id.equals(id)))
          .watchSingleOrNull();

  Stream<List<Paper>> watchByProject(int projectId) {
    final query = _db.select(_db.papers).join([
      innerJoin(
        _db.paperProjects,
        _db.paperProjects.paperId.equalsExp(_db.papers.id),
      ),
    ])..where(_db.paperProjects.projectId.equals(projectId));

    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(_db.papers)).toList(),
    );
  }

  /// Papers filed nowhere yet — the inbox.
  Stream<List<Paper>> watchUnfiled() {
    final filed = _db.selectOnly(_db.paperProjects)
      ..addColumns([_db.paperProjects.paperId]);

    return (_db.select(_db.papers)
          ..where((p) => p.id.isNotInQuery(filed))
          ..orderBy([_byRecency]))
        .watch();
  }

  Stream<List<Paper>> search(String term) {
    final pattern = '%${term.trim()}%';
    return (_db.select(_db.papers)
          ..where(
            (p) =>
                p.title.like(pattern) |
                p.abstractText.like(pattern) |
                p.authors.like(pattern) |
                p.progressNote.like(pattern),
          )
          ..orderBy([_byRecency]))
        .watch();
  }

  /// Most recently touched first, falling back to when it was added for papers
  /// that have never been opened.
  OrderingTerm Function($PapersTable) get _byRecency =>
      (p) => OrderingTerm(
        expression: coalesce([p.lastOpenedAt, p.addedAt]),
        mode: OrderingMode.desc,
      );

  /// Fetches metadata for [idOrUrl] and stores it.
  ///
  /// Returns the existing row if the paper is already in the library, matching
  /// on the version-stripped id so that sharing `v2` of something saved as `v1`
  /// does not create a second copy.
  Future<Paper> addFromArxiv(String idOrUrl, {int? projectId}) async {
    final arxivId = extractArxivId(idOrUrl);
    if (arxivId == null) {
      throw ArxivException('No arXiv id found in "$idOrUrl"');
    }

    final existing = await findByArxivId(arxivId);
    if (existing != null) {
      if (projectId != null) await addToProject(existing.id, projectId);
      return existing;
    }

    final fetched = await _api.fetchById(arxivId);
    final id = await _db
        .into(_db.papers)
        .insert(
          PapersCompanion.insert(
            arxivId: fetched.arxivId,
            title: fetched.title,
            authors: fetched.authors.join('; '),
            abstractText: fetched.abstractText,
            categories: Value(fetched.categories.join('; ')),
            publishedAt: Value(fetched.publishedAt),
            pdfUrl: fetched.pdfUrl,
            addedAt: DateTime.now(),
          ),
        );

    if (projectId != null) await addToProject(id, projectId);
    return (_db.select(_db.papers)..where((p) => p.id.equals(id))).getSingle();
  }

  Future<Paper?> findByArxivId(String arxivId) async {
    final bare = stripVersion(arxivId);
    final candidates = await (_db.select(
      _db.papers,
    )..where((p) => p.arxivId.like('$bare%'))).get();

    return candidates
        .where((p) => stripVersion(p.arxivId) == bare)
        .firstOrNull;
  }

  Future<void> setStatus(int id, ReadingStatus status) =>
      (_db.update(_db.papers)..where((p) => p.id.equals(id)))
          .write(PapersCompanion(status: Value(status)));

  Future<void> setProgressNote(int id, String note) =>
      (_db.update(_db.papers)..where((p) => p.id.equals(id)))
          .write(PapersCompanion(progressNote: Value(note)));

  Future<void> delete(int id) async {
    final paper = await (_db.select(
      _db.papers,
    )..where((p) => p.id.equals(id))).getSingleOrNull();
    final path = paper?.relativePath;
    if (path != null) await _files.delete(path);
    await (_db.delete(_db.papers)..where((p) => p.id.equals(id))).go();
  }

  // --- project membership ---------------------------------------------------

  Future<void> addToProject(int paperId, int projectId, {String note = ''}) =>
      _db
          .into(_db.paperProjects)
          .insertOnConflictUpdate(
            PaperProjectsCompanion.insert(
              paperId: paperId,
              projectId: projectId,
              note: Value(note),
            ),
          );

  Future<void> removeFromProject(int paperId, int projectId) =>
      (_db.delete(_db.paperProjects)..where(
            (pp) => pp.paperId.equals(paperId) & pp.projectId.equals(projectId),
          ))
          .go();

  Stream<List<Project>> watchProjectsOf(int paperId) {
    final query = _db.select(_db.projects).join([
      innerJoin(
        _db.paperProjects,
        _db.paperProjects.projectId.equalsExp(_db.projects.id),
      ),
    ])..where(_db.paperProjects.paperId.equals(paperId));

    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(_db.projects)).toList(),
    );
  }

  // --- relations ------------------------------------------------------------

  Future<void> link(int fromId, int toId, String note) => _db
      .into(_db.paperRelations)
      .insertOnConflictUpdate(
        PaperRelationsCompanion.insert(
          fromId: fromId,
          toId: toId,
          note: Value(note),
        ),
      );

  Future<void> unlink(int fromId, int toId) =>
      (_db.delete(_db.paperRelations)..where(
            (r) =>
                (r.fromId.equals(fromId) & r.toId.equals(toId)) |
                (r.fromId.equals(toId) & r.toId.equals(fromId)),
          ))
          .go();

  /// Related papers with the reason for each link. Relations are stored once but
  /// read in both directions, so a link made from either side shows on both.
  Stream<List<(Paper, String)>> watchRelated(int paperId) {
    final query = _db.select(_db.paperRelations)
      ..where((r) => r.fromId.equals(paperId) | r.toId.equals(paperId));

    return query.watch().asyncMap((relations) async {
      final result = <(Paper, String)>[];
      for (final relation in relations) {
        final otherId = relation.fromId == paperId
            ? relation.toId
            : relation.fromId;
        final other = await (_db.select(
          _db.papers,
        )..where((p) => p.id.equals(otherId))).getSingleOrNull();
        if (other != null) result.add((other, relation.note));
      }
      return result;
    });
  }

  // --- files ----------------------------------------------------------------

  /// Downloads the PDF into the folder of the paper's first project, or the
  /// inbox if it has none. Returns the stored relative path.
  Future<String> downloadPdf(
    int paperId, {
    void Function(int received, int total)? onProgress,
  }) async {
    final paper = await (_db.select(
      _db.papers,
    )..where((p) => p.id.equals(paperId))).getSingle();

    final projects = await watchProjectsOf(paperId).first;
    final folderName = projects.firstOrNull?.folderName ?? inboxFolderName;

    final relativePath = await _files.download(
      url: paper.pdfUrl,
      folderName: folderName,
      fileName: FileService.buildFileName(
        arxivId: paper.arxivId,
        title: paper.title,
        authors: paper.authors.split('; '),
        publishedAt: paper.publishedAt,
      ),
      onProgress: onProgress,
    );

    await (_db.update(_db.papers)..where((p) => p.id.equals(paperId))).write(
      PapersCompanion(relativePath: Value(relativePath)),
    );
    return relativePath;
  }

  /// The downloaded PDF, or null if it is not on disk.
  ///
  /// A file deleted from Files or a file manager leaves the database claiming a
  /// download that is no longer there, so a miss clears the path and the UI
  /// offers to download again rather than failing to open nothing.
  Future<File?> localFile(int paperId) async {
    final paper = await (_db.select(
      _db.papers,
    )..where((p) => p.id.equals(paperId))).getSingleOrNull();
    final path = paper?.relativePath;
    if (path == null) return null;

    final file = await _files.resolve(path);
    if (await file.exists()) return file;

    await (_db.update(_db.papers)..where((p) => p.id.equals(paperId))).write(
      const PapersCompanion(relativePath: Value(null)),
    );
    return null;
  }

  Future<void> markOpened(int paperId) =>
      (_db.update(_db.papers)..where((p) => p.id.equals(paperId))).write(
        PapersCompanion(lastOpenedAt: Value(DateTime.now())),
      );
}

final paperRepositoryProvider = Provider<PaperRepository>(
  (ref) => PaperRepository(
    ref.watch(databaseProvider),
    ref.watch(arxivApiProvider),
    ref.watch(fileServiceProvider),
  ),
);

final allPapersProvider = StreamProvider<List<Paper>>(
  (ref) => ref.watch(paperRepositoryProvider).watchAll(),
);

final unfiledPapersProvider = StreamProvider<List<Paper>>(
  (ref) => ref.watch(paperRepositoryProvider).watchUnfiled(),
);

final readingPapersProvider = StreamProvider<List<Paper>>(
  (ref) =>
      ref.watch(paperRepositoryProvider).watchByStatus(ReadingStatus.reading),
);

final paperProvider = StreamProvider.family<Paper?, int>(
  (ref, id) => ref.watch(paperRepositoryProvider).watchById(id),
);

final papersOfProjectProvider = StreamProvider.family<List<Paper>, int>(
  (ref, projectId) =>
      ref.watch(paperRepositoryProvider).watchByProject(projectId),
);

final projectsOfPaperProvider = StreamProvider.family<List<Project>, int>(
  (ref, paperId) => ref.watch(paperRepositoryProvider).watchProjectsOf(paperId),
);

final relatedPapersProvider =
    StreamProvider.family<List<(Paper, String)>, int>(
      (ref, paperId) => ref.watch(paperRepositoryProvider).watchRelated(paperId),
    );
