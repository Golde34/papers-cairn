import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

/// One paper as arXiv describes it, before it becomes a database row.
class ArxivPaper {
  const ArxivPaper({
    required this.arxivId,
    required this.title,
    required this.authors,
    required this.abstractText,
    required this.categories,
    required this.pdfUrl,
    this.publishedAt,
  });

  final String arxivId;
  final String title;
  final List<String> authors;
  final String abstractText;
  final List<String> categories;
  final String pdfUrl;
  final DateTime? publishedAt;
}

class ArxivException implements Exception {
  ArxivException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ArxivApi {
  ArxivApi({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              // Plain http://export.arxiv.org answers 301 to https, and a
              // redirect that drops the query string is a confusing failure.
              baseUrl: 'https://export.arxiv.org',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              responseType: ResponseType.plain,
            ),
          );

  final Dio _dio;

  /// arXiv asks callers for one request every three seconds. Exceeding it earns
  /// a block, so requests queue here rather than racing.
  static const _minInterval = Duration(seconds: 3);
  DateTime? _lastRequest;
  Future<void> _pending = Future.value();

  Future<T> _throttled<T>(Future<T> Function() action) {
    final result = _pending.then((_) async {
      final last = _lastRequest;
      if (last != null) {
        final elapsed = DateTime.now().difference(last);
        if (elapsed < _minInterval) await Future.delayed(_minInterval - elapsed);
      }
      _lastRequest = DateTime.now();
      return action();
    });
    // Keep the chain alive even when one call throws, or every later request
    // would inherit the same error.
    _pending = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<ArxivPaper> fetchById(String arxivId) async {
    final papers = await _query({'id_list': arxivId, 'max_results': '1'});
    if (papers.isEmpty) {
      throw ArxivException('arXiv has no paper with id $arxivId');
    }
    return papers.first;
  }

  Future<List<ArxivPaper>> search(String query, {int maxResults = 25}) {
    return _query({
      'search_query': 'all:$query',
      'max_results': '$maxResults',
      'sortBy': 'relevance',
    });
  }

  Future<List<ArxivPaper>> _query(Map<String, String> params) {
    return _throttled(() async {
      final Response<String> response;
      try {
        response = await _dio.get<String>(
          '/api/query',
          queryParameters: params,
        );
      } on DioException catch (e) {
        throw ArxivException('Could not reach arXiv: ${e.message}');
      }

      final body = response.data;
      if (body == null || body.isEmpty) {
        throw ArxivException('arXiv returned an empty response');
      }
      return parseFeed(body);
    });
  }

  /// Public so the parser can be tested against a captured response without
  /// standing up an HTTP mock. This is the part most likely to break when arXiv
  /// changes its output.
  List<ArxivPaper> parseFeed(String body) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(body);
    } on XmlException catch (e) {
      throw ArxivException('arXiv returned malformed XML: ${e.message}');
    }

    return document
        .findAllElements('entry')
        .map(_parseEntry)
        .nonNulls
        .toList(growable: false);
  }

  ArxivPaper? _parseEntry(XmlElement entry) {
    // <id> is a URL: http://arxiv.org/abs/2103.00020v1
    final idUrl = _text(entry, 'id');
    if (idUrl == null) return null;
    final arxivId = idUrl.split('/abs/').last;
    if (arxivId.isEmpty || arxivId == idUrl) return null;

    final title = _text(entry, 'title');
    if (title == null || title.isEmpty) return null;

    // The PDF href carries no .pdf suffix and its version can differ from the
    // one in <id>, so it is read rather than reconstructed.
    final pdfUrl = entry
        .findElements('link')
        .where((link) => link.getAttribute('title') == 'pdf')
        .map((link) => link.getAttribute('href'))
        .nonNulls
        .firstOrNull;
    if (pdfUrl == null) return null;

    return ArxivPaper(
      arxivId: arxivId,
      title: title,
      authors: entry
          .findElements('author')
          .map((author) => _text(author, 'name'))
          .nonNulls
          .toList(growable: false),
      abstractText: _text(entry, 'summary') ?? '',
      categories: entry
          .findElements('category')
          .map((category) => category.getAttribute('term'))
          .nonNulls
          .toList(growable: false),
      pdfUrl: pdfUrl,
      publishedAt: DateTime.tryParse(_text(entry, 'published') ?? ''),
    );
  }

  /// Titles and abstracts arrive wrapped across lines and indented to match the
  /// surrounding XML. Left alone, every list row renders with ragged gaps.
  String? _text(XmlElement parent, String name) {
    final element = parent.findElements(name).firstOrNull;
    if (element == null) return null;
    return element.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
