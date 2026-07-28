import 'dart:convert';
import 'dart:ui';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/providers.dart';

/// Board coordinates are unbounded in principle. In practice the canvas is a
/// very large finite square and the view starts in the middle of it, which
/// behaves identically unless somebody draws for several kilometres.
const boardExtent = 50000.0;
const boardOrigin = Offset(boardExtent / 2, boardExtent / 2);

List<Offset> decodePoints(String json) => [
  for (final point in jsonDecode(json) as List)
    Offset(
      ((point as List)[0] as num).toDouble(),
      (point[1] as num).toDouble(),
    ),
];

String encodePoints(List<Offset> points) => jsonEncode([
  // Rounded to a tenth of a unit: a pen samples far more precision than a
  // finger actually carries, and the full doubles triple the stored size.
  for (final point in points)
    [
      (point.dx * 10).roundToDouble() / 10,
      (point.dy * 10).roundToDouble() / 10,
    ],
]);

class BoardRepository {
  BoardRepository(this._db);

  final AppDatabase _db;

  Stream<List<Board>> watchAll() =>
      (_db.select(_db.boards)..orderBy([
            (b) => OrderingTerm(expression: b.updatedAt, mode: OrderingMode.desc),
          ]))
          .watch();

  Stream<Board?> watchById(int id) =>
      (_db.select(_db.boards)..where((b) => b.id.equals(id)))
          .watchSingleOrNull();

  Future<int> create({required String title, int? projectId}) {
    final now = DateTime.now();
    return _db
        .into(_db.boards)
        .insert(
          BoardsCompanion.insert(
            title: title.trim(),
            projectId: Value(projectId),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> setBackground(int id, BoardBackground background) =>
      (_db.update(_db.boards)..where((b) => b.id.equals(id))).write(
        BoardsCompanion(
          background: Value(background),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> rename(int id, String title) =>
      (_db.update(_db.boards)..where((b) => b.id.equals(id))).write(
        BoardsCompanion(
          title: Value(title.trim()),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> delete(int id) =>
      (_db.delete(_db.boards)..where((b) => b.id.equals(id))).go();

  Stream<List<Stroke>> watchStrokes(int boardId) =>
      (_db.select(_db.strokes)
            ..where((s) => s.boardId.equals(boardId))
            ..orderBy([(s) => OrderingTerm(expression: s.createdAt)]))
          .watch();

  Future<void> addStroke({
    required int boardId,
    required List<Offset> points,
    required int colorValue,
    required double width,
  }) async {
    await _db
        .into(_db.strokes)
        .insert(
          StrokesCompanion.insert(
            boardId: boardId,
            pointsJson: encodePoints(points),
            colorValue: colorValue,
            width: width,
            createdAt: DateTime.now(),
          ),
        );
    await _touch(boardId);
  }

  Future<void> deleteStroke(int id, int boardId) async {
    await (_db.delete(_db.strokes)..where((s) => s.id.equals(id))).go();
    await _touch(boardId);
  }

  Future<void> clear(int boardId) async {
    await (_db.delete(_db.strokes)..where((s) => s.boardId.equals(boardId)))
        .go();
    await _touch(boardId);
  }

  // --- items ----------------------------------------------------------------

  Stream<List<BoardItem>> watchItems(int boardId) =>
      (_db.select(_db.boardItems)
            ..where((i) => i.boardId.equals(boardId))
            ..orderBy([(i) => OrderingTerm(expression: i.createdAt)]))
          .watch();

  Future<int> addText({
    required int boardId,
    required Offset at,
    required int colorValue,
    String text = '',
  }) async {
    final id = await _db
        .into(_db.boardItems)
        .insert(
          BoardItemsCompanion.insert(
            boardId: boardId,
            kind: BoardItemKind.text,
            x: at.dx,
            y: at.dy,
            width: 260,
            body: Value(text),
            colorValue: colorValue,
            createdAt: DateTime.now(),
          ),
        );
    await _touch(boardId);
    return id;
  }

  Future<int> addPaper({
    required int boardId,
    required int paperId,
    required Offset at,
    required int colorValue,
  }) async {
    final id = await _db
        .into(_db.boardItems)
        .insert(
          BoardItemsCompanion.insert(
            boardId: boardId,
            kind: BoardItemKind.paper,
            x: at.dx,
            y: at.dy,
            width: 300,
            paperId: Value(paperId),
            colorValue: colorValue,
            createdAt: DateTime.now(),
          ),
        );
    await _touch(boardId);
    return id;
  }

  /// Position is written on drag end rather than continuously — a drag produces
  /// a write per frame otherwise, and every one of them wakes every stream
  /// watching the table.
  Future<void> moveItem(int id, Offset to, int boardId) async {
    await (_db.update(_db.boardItems)..where((i) => i.id.equals(id))).write(
      BoardItemsCompanion(x: Value(to.dx), y: Value(to.dy)),
    );
    await _touch(boardId);
  }

  Future<void> setItemText(int id, String text, int boardId) async {
    await (_db.update(_db.boardItems)..where((i) => i.id.equals(id)))
        .write(BoardItemsCompanion(body: Value(text)));
    await _touch(boardId);
  }

  Future<void> deleteItem(int id, int boardId) async {
    await (_db.delete(_db.boardItems)..where((i) => i.id.equals(id))).go();
    await _touch(boardId);
  }

  /// Boards are listed most-recently-worked-on first, which only means anything
  /// if drawing on one counts as working on it.
  Future<void> _touch(int boardId) =>
      (_db.update(_db.boards)..where((b) => b.id.equals(boardId)))
          .write(BoardsCompanion(updatedAt: Value(DateTime.now())));
}

final boardRepositoryProvider = Provider<BoardRepository>(
  (ref) => BoardRepository(ref.watch(databaseProvider)),
);

final boardsProvider = StreamProvider<List<Board>>(
  (ref) => ref.watch(boardRepositoryProvider).watchAll(),
);

final boardProvider = StreamProvider.family<Board?, int>(
  (ref, id) => ref.watch(boardRepositoryProvider).watchById(id),
);

final strokesProvider = StreamProvider.family<List<Stroke>, int>(
  (ref, boardId) => ref.watch(boardRepositoryProvider).watchStrokes(boardId),
);

final boardItemsProvider = StreamProvider.family<List<BoardItem>, int>(
  (ref, boardId) => ref.watch(boardRepositoryProvider).watchItems(boardId),
);
