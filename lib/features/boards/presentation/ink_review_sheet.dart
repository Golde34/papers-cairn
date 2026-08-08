import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Shows what the selection actually captured.
///
/// A step of its own on purpose. What gets sent is a crop of your board, and
/// seeing it first is the difference between "the reading was wrong" and "I
/// selected the wrong half of the page".
Future<void> showInkReviewSheet(BuildContext context, Uint8List png) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _InkReviewSheet(png: png),
  );
}

class _InkReviewSheet extends StatelessWidget {
  const _InkReviewSheet({required this.png});

  final Uint8List png;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Selected writing', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.5,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  // Always on white: the capture is rendered dark-on-white so it
                  // stays readable, and a dark sheet behind a transparent gap
                  // would misrepresent what is being sent.
                  child: Container(
                    color: Colors.white,
                    width: double.infinity,
                    child: Image.memory(png, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${(png.lengthInBytes / 1024).toStringAsFixed(0)} KB',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
