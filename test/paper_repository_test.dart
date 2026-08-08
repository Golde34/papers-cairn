import 'package:cairn/core/database/database.dart';
import 'package:cairn/core/network/arxiv_api.dart';
import 'package:cairn/core/storage/file_service.dart';
import 'package:cairn/features/papers/data/paper_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises the queries against a real SQLite database rather than a stand-in.
/// These are joins; the only way to know one is right is to run it.
void main() {
  late AppDatabase db;
  late PaperRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = PaperRepository(db, ArxivApi(), FileService());
  });

  tearDown(() => db.close());

  Future<int> addPaper(String title) => db
      .into(db.papers)
      .insert(
        PapersCompanion.insert(
          title: title,
          authors: 'Someone',
          abstractText: '',
          addedAt: DateTime(2026, 1, 1),
        ),
      );

  Future<int> addProject(String name) => db
      .into(db.projects)
      .insert(
        ProjectsCompanion.insert(
          name: name,
          folderName: name,
          colorValue: 0xFF000000,
          createdAt: DateTime(2026, 1, 1),
        ),
      );

  group('watchRelated', () {
    test('finds papers linked from either end, with their reasons', () async {
      final a = await addPaper('A');
      final b = await addPaper('B');
      final c = await addPaper('C');

      // A -> B, and C -> A. Both are relations *of* A, from opposite sides.
      await repository.link(a, b, 'extends the loss');
      await repository.link(c, a, 'where the trick comes from');

      final related = await repository.watchRelated(a).first;

      expect(
        {for (final (paper, note) in related) paper.id: note},
        {b: 'extends the loss', c: 'where the trick comes from'},
      );
    });

    test('does not report a paper as related to itself', () async {
      final a = await addPaper('A');
      final b = await addPaper('B');
      await repository.link(a, b, 'why');

      final related = await repository.watchRelated(a).first;

      expect(related.map((r) => r.$1.id), [b]);
    });

    test('is empty for a paper nothing links to', () async {
      final a = await addPaper('A');
      await addPaper('B');

      expect(await repository.watchRelated(a).first, isEmpty);
    });

    test('a removed link stops being reported', () async {
      final a = await addPaper('A');
      final b = await addPaper('B');
      await repository.link(a, b, 'why');
      await repository.unlink(a, b);

      expect(await repository.watchRelated(a).first, isEmpty);
    });
  });

  group('projectsOf', () {
    test('agrees with the watching version', () async {
      final paper = await addPaper('A');
      final gaia = await addProject('Gaia');
      final other = await addProject('Other');
      await repository.addToProject(paper, gaia);
      await repository.addToProject(paper, other);

      final once = await repository.projectsOf(paper);
      final watched = await repository.watchProjectsOf(paper).first;

      expect(once.map((p) => p.id).toSet(), {gaia, other});
      expect(once.map((p) => p.id), watched.map((p) => p.id));
    });

    test('is empty for an unfiled paper', () async {
      final paper = await addPaper('A');
      expect(await repository.projectsOf(paper), isEmpty);
    });
  });

  group('adoptExisting', () {
    test('claims the file where it already is, as a document', () async {
      final paper = await repository.adoptExisting(
        relativePath: 'papers/9/handout.pdf',
        title: 'Lecture 3 handout',
      );

      expect(paper.relativePath, 'papers/9/handout.pdf');
      expect(paper.kind, EntryKind.document);
      // Nothing was invented on its behalf.
      expect(paper.authors, isEmpty);
      expect(paper.arxivId, isNull);
    });
  });

  group('forgetFile', () {
    test('drops the path and keeps everything else', () async {
      final paper = await repository.adoptExisting(
        relativePath: 'papers/9/gone.pdf',
        title: 'Gone',
      );

      await repository.forgetFile(paper.id);
      final after = await repository.watchById(paper.id).first;

      expect(after?.relativePath, isNull);
      expect(after?.title, 'Gone');
    });
  });

  group('watchUnfiled', () {
    test('lists only papers belonging to no project', () async {
      final filed = await addPaper('Filed');
      final loose = await addPaper('Loose');
      final project = await addProject('Gaia');
      await repository.addToProject(filed, project);

      final unfiled = await repository.watchUnfiled().first;

      expect(unfiled.map((p) => p.id), [loose]);
    });
  });
}
