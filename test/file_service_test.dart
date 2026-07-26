import 'package:cairn/core/storage/file_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildFileName', () {
    test('names a file so it explains itself in a file manager', () {
      final name = FileService.buildFileName(
        arxivId: '2103.00020',
        title: 'Learning Transferable Visual Models',
        authors: ['Alec Radford', 'Jong Wook Kim'],
        publishedAt: DateTime(2021, 2, 26),
      );

      expect(
        name,
        '2103.00020 - Learning Transferable Visual Models - Radford 2021.pdf',
      );
    });

    test('strips characters that are illegal in a path', () {
      final name = FileService.buildFileName(
        arxivId: 'hep-th/9901001',
        title: 'Anti/de Sitter: a "review" <of> it?',
        authors: const [],
      );

      expect(name, isNot(contains(':')));
      expect(name, isNot(contains('"')));
      expect(name, isNot(contains('<')));
      expect(name, isNot(contains('?')));
      // The slash inside the old-style id is a path separator too.
      expect(name.split('/'), hasLength(1));
    });

    test('truncates long titles rather than producing an unopenable path', () {
      final name = FileService.buildFileName(
        arxivId: '2103.00020',
        title: 'A ' * 200,
        authors: const ['Someone'],
      );

      expect(name.length, lessThan(150));
      expect(name, endsWith('.pdf'));
    });

    test('copes with a paper that has no authors or date', () {
      final name = FileService.buildFileName(
        arxivId: '2103.00020',
        title: 'Untitled',
        authors: const [],
      );

      expect(name, '2103.00020 - Untitled.pdf');
    });
  });

  test('sanitizeFolderName keeps project folders path-safe', () {
    expect(
      FileService.sanitizeFolderName('Vision/Language  models'),
      'Vision-Language models',
    );
  });
}
