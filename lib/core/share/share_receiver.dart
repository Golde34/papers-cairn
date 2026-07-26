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

/// A PDF shared from a file manager — a paper from somewhere other than arXiv.
class SharedPdf extends SharedItem {
  const SharedPdf(this.path, this.suggestedTitle);
  final String path;
  final String suggestedTitle;
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
      // For text and URL shares the payload rides in `path`; for a file share it
      // really is a path.
      final arxivId = extractArxivId(item.path);
      if (arxivId != null) {
        _controller.add(SharedArxivId(arxivId));
        continue;
      }

      if (item.path.toLowerCase().endsWith('.pdf')) {
        _controller.add(SharedPdf(item.path, _titleFrom(item)));
      }
    }
  }

  /// The best guess at a name. The plugin sometimes hands over a temporary file
  /// with a meaningless path, in which case the original name is the only thing
  /// worth showing.
  String _titleFrom(SharedMediaFile item) {
    final name = (item.message?.trim().isNotEmpty ?? false)
        ? item.message!.trim()
        : item.path.split('/').last;
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
