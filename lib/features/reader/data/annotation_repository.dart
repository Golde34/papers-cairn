import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/providers.dart';

/// One line of a highlight, in PDF page coordinates: origin bottom-left, y
/// increasing upward, so [top] is above [bottom] numerically.
///
/// Page coordinates rather than screen ones. A highlight recorded at one zoom
/// level has to land in the same place at another, on a different screen, on a
/// different device.
class HighlightRect {
  const HighlightRect(this.left, this.top, this.right, this.bottom);

  factory HighlightRect.fromJson(List<dynamic> json) => HighlightRect(
    (json[0] as num).toDouble(),
    (json[1] as num).toDouble(),
    (json[2] as num).toDouble(),
    (json[3] as num).toDouble(),
  );

  final double left;
  final double top;
  final double right;
  final double bottom;

  List<double> toJson() => [left, top, right, bottom];
}

List<HighlightRect> decodeRects(String json) => (jsonDecode(json) as List)
    .map((entry) => HighlightRect.fromJson(entry as List))
    .toList(growable: false);

String encodeRects(List<HighlightRect> rects) =>
    jsonEncode(rects.map((rect) => rect.toJson()).toList());

class AnnotationRepository {
  AnnotationRepository(this._db);

  final AppDatabase _db;

  Stream<List<Annotation>> watchForPaper(int paperId) =>
      (_db.select(_db.annotations)
            ..where((a) => a.paperId.equals(paperId))
            ..orderBy([
              (a) => OrderingTerm(expression: a.pageNumber),
              (a) => OrderingTerm(expression: a.createdAt),
            ]))
          .watch();

  Future<int> add({
    required int paperId,
    required int pageNumber,
    required String quotedText,
    required List<HighlightRect> rects,
    required int colorValue,
    String note = '',
  }) => _db
      .into(_db.annotations)
      .insert(
        AnnotationsCompanion.insert(
          paperId: paperId,
          pageNumber: pageNumber,
          quotedText: quotedText,
          rectsJson: encodeRects(rects),
          colorValue: colorValue,
          note: Value(note),
          createdAt: DateTime.now(),
        ),
      );

  Future<void> setNote(int id, String note) =>
      (_db.update(_db.annotations)..where((a) => a.id.equals(id)))
          .write(AnnotationsCompanion(note: Value(note)));

  Future<void> delete(int id) =>
      (_db.delete(_db.annotations)..where((a) => a.id.equals(id))).go();
}

final annotationRepositoryProvider = Provider<AnnotationRepository>(
  (ref) => AnnotationRepository(ref.watch(databaseProvider)),
);

/// Auto-disposing: a paper closed should stop watching its own highlights.
final annotationsProvider = StreamProvider.family<List<Annotation>, int>(
  (ref, paperId) =>
      ref.watch(annotationRepositoryProvider).watchForPaper(paperId),
  isAutoDispose: true,
);
