import 'package:cairn/core/database/database.dart';
import 'package:cairn/features/files/data/file_inventory.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The database is real rather than stubbed because [Paper] is a generated row
/// class, and inserting one is less work than hand-building every column.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<Paper> addPaper(String title, {String? relativePath}) async {
    final id = await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            title: title,
            authors: '',
            abstractText: '',
            addedAt: DateTime(2026, 1, 1),
            relativePath: Value(relativePath),
          ),
        );
    return (db.select(db.papers)..where((p) => p.id.equals(id))).getSingle();
  }

  ScannedFile file(String path, {int size = 1000}) => (
    relativePath: path,
    sizeBytes: size,
    modifiedAt: DateTime(2026, 1, 1),
  );

  group('reconcile', () {
    test('a file a paper points at counts as library', () async {
      final paper = await addPaper('A', relativePath: 'papers/1/a.pdf');

      final report = reconcile(
        rootPath: '/root',
        papers: [paper],
        onDisk: [file('papers/1/a.pdf')],
      );

      expect(report.ofKind(FileKind.library).single.paper?.id, paper.id);
      expect(report.missing, isEmpty);
    });

    test('a file nothing points at is loose', () async {
      final paper = await addPaper('A', relativePath: 'papers/1/a.pdf');

      final report = reconcile(
        rootPath: '/root',
        papers: [paper],
        onDisk: [file('papers/1/a.pdf'), file('papers/9/stray.pdf')],
      );

      expect(
        report.ofKind(FileKind.loose).single.relativePath,
        'papers/9/stray.pdf',
      );
    });

    test('a paper whose file is gone is reported missing', () async {
      final paper = await addPaper('A', relativePath: 'papers/1/a.pdf');

      final report = reconcile(
        rootPath: '/root',
        papers: [paper],
        onDisk: const [],
      );

      expect(report.missing.single.paper.id, paper.id);
      expect(report.missing.single.relativePath, 'papers/1/a.pdf');
    });

    test('a paper that never had a file is not missing', () async {
      final paper = await addPaper('A');

      final report = reconcile(
        rootPath: '/root',
        papers: [paper],
        onDisk: const [],
      );

      expect(report.missing, isEmpty);
    });

    test('the database is app data, not a loose document', () {
      final report = reconcile(
        rootPath: '/root',
        papers: const [],
        onDisk: [
          file('cairn.sqlite'),
          file('cairn.sqlite-wal'),
          file('papers/1/a.pdf'),
        ],
      );

      expect(
        report.ofKind(FileKind.appData).map((f) => f.name),
        ['cairn.sqlite', 'cairn.sqlite-wal'],
      );
      expect(report.ofKind(FileKind.loose), hasLength(1));
    });

    test('a PDF that merely happens to be named like the database is not', () {
      // Only the file sitting at the top level is bookkeeping. One filed under
      // a paper's folder is a document whatever it is called.
      final report = reconcile(
        rootPath: '/root',
        papers: const [],
        onDisk: [file('papers/1/cairn.sqlite.pdf')],
      );

      expect(report.ofKind(FileKind.appData), isEmpty);
      expect(report.ofKind(FileKind.loose), hasLength(1));
    });

    test('biggest file first, and the total adds up', () {
      final report = reconcile(
        rootPath: '/root',
        papers: const [],
        onDisk: [
          file('small.pdf', size: 100),
          file('big.pdf', size: 5000),
          file('middling.pdf', size: 900),
        ],
      );

      expect(report.files.map((f) => f.name), [
        'big.pdf',
        'middling.pdf',
        'small.pdf',
      ]);
      expect(report.totalBytes, 6000);
    });
  });

  group('formatBytes', () {
    test('reads as a person would say it', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2 KB');
      expect(formatBytes(3 * 1024 * 1024), '3.0 MB');
    });
  });
}
