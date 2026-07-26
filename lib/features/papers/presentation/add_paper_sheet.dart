import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../data/paper_repository.dart';

/// Adds a paper from a pasted id, URL, or citation string.
///
/// [projectId] files it on arrival; leaving it null drops the paper in the inbox.
Future<Paper?> showAddPaperSheet(
  BuildContext context, {
  int? projectId,
  String? initialValue,
}) {
  return showModalBottomSheet<Paper>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _AddPaperSheet(projectId: projectId, initialValue: initialValue),
  );
}

class _AddPaperSheet extends ConsumerStatefulWidget {
  const _AddPaperSheet({this.projectId, this.initialValue});

  final int? projectId;
  final String? initialValue;

  @override
  ConsumerState<_AddPaperSheet> createState() => _AddPaperSheetState();
}

class _AddPaperSheetState extends ConsumerState<_AddPaperSheet> {
  late final _controller = TextEditingController(text: widget.initialValue);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final input = _controller.text.trim();
    if (input.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final paper = await ref
          .read(paperRepositoryProvider)
          .addFromArxiv(input, projectId: widget.projectId);
      if (mounted) Navigator.of(context).pop(paper);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add a paper', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: 'arXiv link or id',
              hintText: '2103.00020',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Fetch from arXiv'),
          ),
        ],
      ),
    );
  }
}
