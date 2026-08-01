import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../network/arxiv_id.dart';

/// Something shared into Cairn from another app.
sealed class SharedItem {
  const SharedItem();
}

/// An arXiv link or citation, shared from a browser.
class SharedArxivId extends SharedItem {
  const SharedArxivId(this.arxivId);
  final String arxivId;
}

/// A PDF shared from a file manager.
///
/// [arxivId] is set when the file name gives the paper away — a browser saves an
/// arXiv download as `2103.00020v1.pdf`. That turns a file share into "here is
/// the PDF for this paper" rather than "here is some paper", which is what lets
/// it join a paper already in the library instead of duplicating it.
class SharedPdf extends SharedItem {
  const SharedPdf({
    required this.path,
    required this.suggestedTitle,
    this.arxivId,
  });

  final String path;
  final String suggestedTitle;
  final String? arxivId;
}

/// Something arrived that Cairn cannot use. Reported rather than discarded, so
/// the app never appears to swallow a share without explanation.
class SharedUnrecognised extends SharedItem {
  const SharedUnrecognised(this.payload);
  final String payload;
}

/// Everything arriving from the OS share sheet.
///
/// This is the path the app is built around: reading an abstract in the browser,
/// hitting Share, and having the paper filed without typing anything. It doubles
/// as the way non-arXiv papers get in — share the downloaded PDF from a file
/// manager.
///
/// Wired up on Android through the intent filters in AndroidManifest.xml. iOS
/// additionally needs a Share Extension target, which does not exist yet — see
/// docs/ARCHITECTURE.md.
class ShareReceiver {
  final _controller = StreamController<SharedItem>.broadcast();
  StreamSubscription<List<SharedMediaFile>>? _subscription;
  bool _started = false;

  Stream<SharedItem> get items => _controller.stream;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Shares that launched the app from cold.
    _emit(await ReceiveSharingIntent.instance.getInitialMedia());
    // Tells the plugin not to hand back the same payload after a hot restart.
    ReceiveSharingIntent.instance.reset();

    // Shares arriving while the app is already running.
    _subscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      _emit,
      onError: (_) {},
    );
  }

  void _emit(List<SharedMediaFile> shared) {
    for (final item in shared) {
      // Type first, not the file extension. The plugin copies every shared file
      // into a cache folder and the copy's name is not guaranteed to keep the
      // `.pdf` on the end — an extension check drops those on the floor, and a
      // share that vanishes without a word looks like the app aborted.
      if (item.type == SharedMediaType.file) {
        _controller.add(
          SharedPdf(
            path: item.path,
            suggestedTitle: _titleFrom(item),
            arxivId: extractArxivIdFromFileName(item.path),
          ),
        );
        continue;
      }

      // Text and URL shares carry the payload in `path`.
      final arxivId = extractArxivId(item.path);
      if (arxivId != null) {
        _controller.add(SharedArxivId(arxivId));
        continue;
      }

      // Deliberately not silent. Whatever arrives, the app says something about
      // it rather than appearing to do nothing.
      _controller.add(SharedUnrecognised(item.path));
    }
  }

  /// The best guess at a name, from the file name alone.
  ///
  /// `message` is not consulted: the plugin documents it as iOS-only, so on
  /// Android it is always null and reading it first just hid the real source.
  String _titleFrom(SharedMediaFile item) {
    final name = item.path.split('/').last;
    return name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '').trim();
  }

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}

final shareReceiverProvider = Provider<ShareReceiver>((ref) {
  final receiver = ShareReceiver();
  ref.onDispose(receiver.dispose);
  return receiver;
});
