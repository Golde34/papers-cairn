import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../network/arxiv_id.dart';

/// Links arriving from the OS share sheet.
///
/// This is the path the app is built around: reading an abstract in the browser,
/// hitting Share, and having the paper filed without typing anything.
///
/// Wired up on Android through the intent filters in AndroidManifest.xml. iOS
/// additionally needs a Share Extension target, which does not exist yet — see
/// docs/ARCHITECTURE.md.
class ShareReceiver {
  final _controller = StreamController<String>.broadcast();
  StreamSubscription<List<SharedMediaFile>>? _subscription;
  bool _started = false;

  Stream<String> get arxivIds => _controller.stream;

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
      // For text and URL shares the payload rides in `path`.
      final id = extractArxivId(item.path);
      if (id != null) _controller.add(id);
    }
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
