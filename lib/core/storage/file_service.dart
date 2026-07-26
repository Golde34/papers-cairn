import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Owns the one directory the app writes into.
///
/// iOS has no equivalent of Android's Storage Access Framework, so rather than
/// writing into a folder the user picks, the app keeps its own and exposes it —
/// visible in Files on iOS via `UIFileSharingEnabled`, and browsable with any
/// file manager on Android.
class FileService {
  FileService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  Directory? _cachedRoot;

  Future<Directory> _root() async =>
      _cachedRoot ??= await getApplicationDocumentsDirectory();

  /// Absolute path for a path stored in the database.
  ///
  /// Only ever call this at the moment of use. iOS rewrites the container path
  /// on every app update, so an absolute path that is correct today is a dangling
  /// one after the next release — which is why only relative paths are stored.
  Future<File> resolve(String relativePath) async =>
      File(p.join((await _root()).path, relativePath));

  Future<bool> exists(String relativePath) async =>
      (await resolve(relativePath)).exists();

  /// Downloads [url] into `<documents>/<folderName>/<fileName>` and returns the
  /// path relative to the documents directory.
  Future<String> download({
    required String url,
    required String folderName,
    required String fileName,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final root = await _root();
    final directory = Directory(p.join(root.path, folderName));
    await directory.create(recursive: true);

    final relativePath = p.join(folderName, fileName);
    final target = File(p.join(root.path, relativePath));

    // Download beside the target, then rename. A connection dropped mid-transfer
    // would otherwise leave a truncated file that looks perfectly valid until it
    // is opened.
    final partial = File('${target.path}.part');
    try {
      await _dio.download(
        url,
        partial.path,
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
      );
      await partial.rename(target.path);
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    }

    return relativePath;
  }

  Future<void> delete(String relativePath) async {
    final file = await resolve(relativePath);
    if (await file.exists()) await file.delete();
  }

  /// Builds a name that explains itself in a file manager, where the app's
  /// database is not around to help:
  /// `2103.00020 - Learning Transferable Visual Models - Radford 2021.pdf`
  static String buildFileName({
    required String arxivId,
    required String title,
    required List<String> authors,
    DateTime? publishedAt,
  }) {
    final parts = <String>[
      // Pre-2007 ids carry their archive and a slash, e.g. `hep-th/9901001`.
      // Left alone that slash makes this a path, not a file name.
      _sanitize(arxivId),
      _truncate(_sanitize(title), 80),
      if (authors.isNotEmpty)
        [
          _sanitize(authors.first.split(' ').last),
          if (publishedAt != null) '${publishedAt.year}',
        ].join(' '),
    ].where((part) => part.isNotEmpty);

    return '${parts.join(' - ')}.pdf';
  }

  static String sanitizeFolderName(String name) =>
      _truncate(_sanitize(name), 60);

  static String _sanitize(String value) => value
      .replaceAll(RegExp(r'[/\\:*?"<>|]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _truncate(String value, int max) =>
      value.length <= max ? value : value.substring(0, max).trim();
}
