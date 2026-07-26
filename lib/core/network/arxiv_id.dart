/// Pulls an arXiv identifier out of whatever the user threw at us: a share-sheet
/// URL, a pasted abs/pdf link, a bare id, or a `arXiv:1234.56789` citation string.
///
/// Handles both identifier schemes. Papers from April 2007 onwards look like
/// `2103.00020`; older ones carry their archive, e.g. `hep-th/9901001` or
/// `math.GT/0309136`.
library;

const _new = r'\d{4}\.\d{4,5}(?:v\d+)?';
const _old = r'[a-z-]+(?:\.[A-Z]{2})?/\d{7}(?:v\d+)?';

final _patterns = <RegExp>[
  // arxiv.org/abs/... and arxiv.org/pdf/..., with or without a trailing .pdf
  RegExp('arxiv\\.org/(?:abs|pdf)/($_new)', caseSensitive: false),
  RegExp('arxiv\\.org/(?:abs|pdf)/($_old)'),
  // "arXiv:2103.00020" as it appears in citations
  RegExp('arxiv:\\s*($_new)', caseSensitive: false),
  RegExp('arxiv:\\s*($_old)', caseSensitive: false),
  // A bare identifier on its own
  RegExp('^($_new)\$'),
  RegExp('^($_old)\$'),
];

String? extractArxivId(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  for (final pattern in _patterns) {
    final match = pattern.firstMatch(text);
    if (match != null) return match.group(1);
  }
  return null;
}

/// Strips the version suffix: `2103.00020v2` -> `2103.00020`. Used when checking
/// whether a paper is already in the library, so re-sharing a different version
/// of the same paper does not create a duplicate.
String stripVersion(String arxivId) =>
    arxivId.replaceFirst(RegExp(r'v\d+$'), '');
