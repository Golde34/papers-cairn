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

/// What arXiv says about a paper, alongside the library's own copy if it has
/// one. Shown before anything is written so the paper can be checked first.
class PaperPreview {
  const PaperPreview({required this.fetched, required this.existing});

  final ArxivPaper fetched;
  final Paper? existing;

  bool get alreadySaved => existing != null;
}

class PaperRepository {
  PaperRepository(this._db, this._api, this._files);

  final AppDatabase _db;
  final ArxivApi _api;
  final FileService _files;

  Stream<List<Paper>> watchAll() =>
      (_db.select(_db.papers)..orderBy([_byRecency])).watch();

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

    // Highlights and their notes are searchable too. Finding a paper by
    // something you wrote in the margin is the whole reason the annotations
    // live in this database instead of inside the PDF.
    final annotated = _db.selectOnly(_db.annotations)
      ..addColumns([_db.annotations.paperId])
      ..where(
        _db.annotations.quotedText.like(pattern) |
            _db.annotations.note.like(pattern),
      );

    return (_db.select(_db.papers)
          ..where(
            (p) =>
                p.title.like(pattern) |
                p.abstractText.like(pattern) |
                p.authors.like(pattern) |
                p.progressNote.like(pattern) |
                p.id.isInQuery(annotated),
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

  /// Looks a paper up on arXiv without storing anything.
  ///
  /// Nothing is written until [save] is called, so a mistyped id costs a lookup
  /// rather than a row that has to be found and deleted again.
  Future<PaperPreview> preview(String idOrUrl) async {
    final arxivId = extractArxivId(idOrUrl);
    if (arxivId == null) {
      throw ArxivException('No arXiv id found in "$idOrUrl"');
    }

    return PaperPreview(
      fetched: await _api.fetchById(arxivId),
      existing: await findByArxivId(arxivId),
    );
  }

  /// Stores a previewed paper.
  ///
  /// Returns the existing row if the library already has it, matching on the
  /// version-stripped id so that saving `v2` of something stored as `v1` files
  /// the copy already there instead of creating a duplicate.
  Future<Paper> save(ArxivPaper fetched, {int? projectId}) async {
    final existing = await findByArxivId(fetched.arxivId);
    if (existing != null) {
      if (projectId != null) await addToProject(existing.id, projectId);
      return existing;
    }

    final id = await _db
        .into(_db.papers)
        .insert(
          PapersCompanion.insert(
            arxivId: Value(fetched.arxivId),
            title: fetched.title,
            authors: fetched.authors.join('; '),
            abstractText: fetched.abstractText,
            categories: Value(fetched.categories.join('; ')),
            publishedAt: Value(fetched.publishedAt),
            pdfUrl: Value(fetched.pdfUrl),
            addedAt: DateTime.now(),
          ),
        );

    if (projectId != null) await addToProject(id, projectId);
    return (_db.select(_db.papers)..where((p) => p.id.equals(id))).getSingle();
  }

  /// Looks up and stores in one step.
  ///
  /// Used by the share sheet, where the whole point is capturing a paper in one
  /// tap. Papers arriving this way land in the inbox, which is itself the review
  /// queue, so there is nothing for a confirmation step to protect.
  Future<Paper> addFromArxiv(String idOrUrl, {int? projectId}) async {
    final result = await preview(idOrUrl);
    return save(result.fetched, projectId: projectId);
  }

  Future<Paper?> findByArxivId(String arxivId) async {
    final bare = stripVersion(arxivId);
    final candidates = await (_db.select(
      _db.papers,
    )..where((p) => p.arxivId.like('$bare%'))).get();

    return candidates
        .where((p) => p.arxivId != null && stripVersion(p.arxivId!) == bare)
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

  Stream<List<Project>> watchProjectsOf(int paperId) =>
      _projectsOfQuery(paperId).watch().map(_readProjects);

  /// The same thing read once, for callers that just need an answer now.
  ///
  /// Taking `.first` off the watching version instead built a live query, opened
  /// a subscription, read one value and tore it all down again — work with a
  /// stream's cost and none of its point.
  Future<List<Project>> projectsOf(int paperId) =>
      _projectsOfQuery(paperId).get().then(_readProjects);

  JoinedSelectStatement<HasResultSet, dynamic> _projectsOfQuery(int paperId) =>
      _db.select(_db.projects).join([
        innerJoin(
          _db.paperProjects,
          _db.paperProjects.projectId.equalsExp(_db.projects.id),
        ),
      ])..where(_db.paperProjects.paperId.equals(paperId));

  List<Project> _readProjects(List<TypedResult> rows) =>
      [for (final row in rows) row.readTable(_db.projects)];

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
    // One join rather than a query per relation. Fetching each related paper in
    // its own round trip meant a paper with ten links cost eleven queries, and
    // every one of them ran again each time the relations table changed.
    //
    // A relation is stored once but read from either end, so the join matches
    // the paper on whichever side of it is not this one.
    final query = _db.select(_db.paperRelations).join([
      innerJoin(
        _db.papers,
        (_db.paperRelations.fromId.equals(paperId) &
                _db.papers.id.equalsExp(_db.paperRelations.toId)) |
            (_db.paperRelations.toId.equals(paperId) &
                _db.papers.id.equalsExp(_db.paperRelations.fromId)),
      ),
    ])..where(
      _db.paperRelations.fromId.equals(paperId) |
          _db.paperRelations.toId.equals(paperId),
    );

    return query.watch().map(
      (rows) => [
        for (final row in rows)
          (row.readTable(_db.papers), row.readTable(_db.paperRelations).note),
      ],
    );
  }

  /// Adopts a PDF already on the device — a paper from somewhere other than
  /// arXiv, downloaded by hand.
  ///
  /// The file is taken into Cairn's own storage, because a path into the
  /// device's downloads is not something the app can rely on still being there.
  Future<Paper> importPdf({
    required File source,
    required String title,
    int? projectId,
  }) async {
    final id = await _db
        .into(_db.papers)
        .insert(
          PapersCompanion.insert(
            title: title,
            // Nothing is known beyond the file itself; these are the paper's to
            // fill in later rather than the importer's to invent.
            authors: '',
            abstractText: '',
            addedAt: DateTime.now(),
          ),
        );

    if (projectId != null) await addToProject(id, projectId);

    final relativePath = await _files.adopt(
      source: source,
      folderName: await _folderFor(id),
      fileName: FileService.buildFileName(title: title, authors: const []),
    );

    await (_db.update(_db.papers)..where((p) => p.id.equals(id))).write(
      PapersCompanion(relativePath: Value(relativePath)),
    );
    return (_db.select(_db.papers)..where((p) => p.id.equals(id))).getSingle();
  }

  /// Gives a paper a PDF that is already on the device, instead of downloading
  /// one.
  ///
  /// The paper's own metadata names the file, so a copy grabbed by a browser
  /// under some opaque name lands in Cairn under the same readable name every
  /// other paper gets.
  Future<void> attachFile(int paperId, File source) async {
    final paper = await (_db.select(
      _db.papers,
    )..where((p) => p.id.equals(paperId))).getSingle();

    // Replace rather than accumulate: a paper has one PDF, and leaving the old
    // one behind would orphan a file nothing points at.
    final previous = paper.relativePath;
    if (previous != null) await _files.delete(previous);

    final relativePath = await _files.adopt(
      source: source,
      folderName: await _folderFor(paperId),
      fileName: FileService.buildFileName(
        arxivId: paper.arxivId,
        title: paper.title,
        authors: paper.authors.split('; '),
        publishedAt: paper.publishedAt,
      ),
    );

    await (_db.update(_db.papers)..where((p) => p.id.equals(paperId))).write(
      PapersCompanion(relativePath: Value(relativePath)),
    );
  }

  /// Saves an arXiv paper using a PDF the device already has.
  ///
  /// The metadata still comes from arXiv — a file name is not a paper — but the
  /// bytes come from the file, so downloading a second copy of something already
  /// sitting in the downloads folder is avoided.
  Future<Paper> addFromArxivWithFile({
    required String arxivId,
    required File source,
    int? projectId,
  }) async {
    final existing = await findByArxivId(arxivId);
    final paper =
        existing ?? await save((await preview(arxivId)).fetched, projectId: projectId);

    if (existing != null && projectId != null) {
      await addToProject(paper.id, projectId);
    }

    await attachFile(paper.id, source);
    return (_db.select(_db.papers)..where((p) => p.id.equals(paper.id)))
        .getSingle();
  }

  /// The folder a paper's file belongs in: its first project, or the inbox.
  Future<String> _folderFor(int paperId) async =>
      (await projectsOf(paperId)).firstOrNull?.folderName ?? inboxFolderName;

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

    final url = paper.pdfUrl;
    if (url == null) {
      // An imported paper has no origin. Its only copy is the one on disk, so
      // there is nothing to re-download and losing that file is unrecoverable.
      throw StateError('This paper was imported and has nowhere to download from');
    }

    final relativePath = await _files.download(
      url: url,
      folderName: await _folderFor(paperId),
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

  /// Remembers the page the reader was left on so the next open resumes there.
  Future<void> setLastPage(int paperId, int page) =>
      (_db.update(_db.papers)..where((p) => p.id.equals(paperId)))
          .write(PapersCompanion(lastPage: Value(page)));
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

// Every family provider below is auto-disposing. Riverpod keeps one instance per
// argument and, left alone, keeps it for the life of the app — so each paper
// ever opened would hold an open database query forever, and drift re-runs every
// live query on the table whenever anything writes to it. Auto-dispose closes
// them when the last widget looks away.

final paperProvider = StreamProvider.family<Paper?, int>(
  (ref, id) => ref.watch(paperRepositoryProvider).watchById(id),
  isAutoDispose: true,
);

final papersOfProjectProvider = StreamProvider.family<List<Paper>, int>(
  (ref, projectId) =>
      ref.watch(paperRepositoryProvider).watchByProject(projectId),
  isAutoDispose: true,
);

final projectsOfPaperProvider = StreamProvider.family<List<Project>, int>(
  (ref, paperId) => ref.watch(paperRepositoryProvider).watchProjectsOf(paperId),
  isAutoDispose: true,
);

final relatedPapersProvider = StreamProvider.family<List<(Paper, String)>, int>(
  (ref, paperId) => ref.watch(paperRepositoryProvider).watchRelated(paperId),
  isAutoDispose: true,
);
