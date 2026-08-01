import 'package:cairn/core/network/arxiv_api.dart';
import 'package:cairn/core/network/arxiv_id.dart';
import 'package:flutter_test/flutter_test.dart';

/// Trimmed from a real response, keeping the shapes that trip the parser up:
/// a title broken across lines, two categories, a versioned id, and a PDF link
/// with no .pdf suffix.
const _sampleFeed = '''
<?xml version='1.0' encoding='UTF-8'?>
<feed xmlns:arxiv="http://arxiv.org/schemas/atom" xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <id>http://arxiv.org/abs/2103.00020v1</id>
    <title>Learning Transferable Visual Models
  From Natural Language Supervision</title>
    <link href="https://arxiv.org/abs/2103.00020v1" rel="alternate" type="text/html"/>
    <link href="https://arxiv.org/pdf/2103.00020v1" rel="related" type="application/pdf" title="pdf"/>
    <summary>State-of-the-art computer vision systems
  are trained to predict a fixed set of categories.</summary>
    <category term="cs.CV" scheme="http://arxiv.org/schemas/atom"/>
    <category term="cs.LG" scheme="http://arxiv.org/schemas/atom"/>
    <published>2021-02-26T19:04:58Z</published>
    <author><name>Alec Radford</name></author>
    <author><name>Jong Wook Kim</name></author>
  </entry>
</feed>
''';

void main() {
  group('extractArxivId', () {
    test('reads modern ids out of abs and pdf urls', () {
      expect(
        extractArxivId('https://arxiv.org/abs/2103.00020'),
        '2103.00020',
      );
      expect(
        extractArxivId('https://arxiv.org/pdf/2103.00020v2'),
        '2103.00020v2',
      );
    });

    test('reads pre-2007 ids, which carry an archive prefix', () {
      expect(extractArxivId('https://arxiv.org/abs/hep-th/9901001'),
          'hep-th/9901001');
      expect(extractArxivId('arXiv:math.GT/0309136'), 'math.GT/0309136');
    });

    test('reads bare ids and citation strings', () {
      expect(extractArxivId('2103.00020'), '2103.00020');
      expect(extractArxivId('arXiv:2103.00020'), '2103.00020');
    });

    test('survives the noise a share sheet adds', () {
      expect(
        extractArxivId('Check this out https://arxiv.org/abs/2103.00020v1 !'),
        '2103.00020v1',
      );
    });

    test('returns null when there is no id to find', () {
      expect(extractArxivId('https://example.com/paper'), isNull);
      expect(extractArxivId(''), isNull);
    });
  });

  group('extractArxivIdFromFileName', () {
    test('reads the id a browser saves an arXiv download under', () {
      expect(
        extractArxivIdFromFileName('/storage/Download/2103.00020v1.pdf'),
        '2103.00020v1',
      );
      expect(extractArxivIdFromFileName('2103.00020.pdf'), '2103.00020');
      expect(extractArxivIdFromFileName('1304.1000v1.PDF'), '1304.1000v1');
    });

    test('still reads a name that spells the id out', () {
      expect(
        extractArxivIdFromFileName('arXiv:2103.00020 - CLIP.pdf'),
        '2103.00020',
      );
    });

    test('returns null for a file that names no paper', () {
      expect(extractArxivIdFromFileName('/Download/thesis-final-v2.pdf'), isNull);
      expect(extractArxivIdFromFileName('scan.pdf'), isNull);
    });

    test('does not mistake a plain version suffix for an id', () {
      expect(extractArxivIdFromFileName('report-v2.pdf'), isNull);
    });
  });

  test('stripVersion drops the version suffix', () {
    expect(stripVersion('2103.00020v3'), '2103.00020');
    expect(stripVersion('2103.00020'), '2103.00020');
    expect(stripVersion('hep-th/9901001v2'), 'hep-th/9901001');
  });

  group('parseFeed', () {
    test('collapses the whitespace arXiv wraps titles and abstracts in', () {
      final paper = ArxivApi().parseFeed(_sampleFeed).single;

      expect(
        paper.title,
        'Learning Transferable Visual Models From Natural Language Supervision',
      );
      expect(paper.abstractText, isNot(contains('\n')));
    });

    test('takes the pdf url from the link rather than building it', () {
      final paper = ArxivApi().parseFeed(_sampleFeed).single;

      expect(paper.pdfUrl, 'https://arxiv.org/pdf/2103.00020v1');
      expect(paper.pdfUrl, isNot(endsWith('.pdf')));
    });

    test('reads id, authors, categories and date', () {
      final paper = ArxivApi().parseFeed(_sampleFeed).single;

      expect(paper.arxivId, '2103.00020v1');
      expect(paper.authors, ['Alec Radford', 'Jong Wook Kim']);
      expect(paper.categories, ['cs.CV', 'cs.LG']);
      expect(paper.publishedAt?.year, 2021);
    });

    test('returns nothing for a feed with no entries', () {
      const empty =
          '<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom"/>';
      expect(ArxivApi().parseFeed(empty), isEmpty);
    });

    test('reports malformed xml instead of throwing raw parser errors', () {
      expect(
        () => ArxivApi().parseFeed('not xml at all'),
        throwsA(isA<ArxivException>()),
      );
    });
  });
}
