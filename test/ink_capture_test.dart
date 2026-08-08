import 'package:cairn/core/database/database.dart';
import 'package:cairn/features/boards/presentation/ink_capture.dart';
import 'package:cairn/features/boards/presentation/strokes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _scheme = ColorScheme.fromSeed(seedColor: Colors.green);

DrawnStroke _line(
  Offset from,
  Offset to, {
  int colorValue = defaultInkColorValue,
  double width = 4,
}) => DrawnStroke.from(
  Stroke(
    id: 1,
    boardId: 1,
    pointsJson:
        '[[${from.dx},${from.dy}],[${to.dx},${to.dy}]]',
    colorValue: colorValue,
    width: width,
    createdAt: DateTime(2026, 1, 1),
  ),
  _scheme,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('captureInk', () {
    test('default ink becomes dark, since the capture is on white', () {
      expect(captureInk(defaultInkColorValue).computeLuminance(), lessThan(0.1));
    });

    test('a chosen colour is kept', () {
      expect(captureInk(0xFFF9A825).toARGB32(), 0xFFF9A825);
    });
  });

  group('captureRegion', () {
    test('is null when the box caught nothing', () {
      final strokes = [_line(const Offset(0, 0), const Offset(50, 50))];

      expect(
        captureRegion(strokes, const Rect.fromLTWH(400, 400, 100, 100)),
        isNull,
      );
    });

    test('shrinks a sloppy box to the writing plus a margin', () {
      final strokes = [_line(const Offset(100, 100), const Offset(140, 120))];

      final region = captureRegion(
        strokes,
        const Rect.fromLTWH(0, 0, 1000, 1000),
      )!;

      // The stroke spans 40x20 with a 4-wide nib, so its own bounds are
      // 98..142 by 98..122 before the margin is added.
      expect(region.left, closeTo(98 - captureMargin, 0.01));
      expect(region.right, closeTo(142 + captureMargin, 0.01));
      expect(region.top, closeTo(98 - captureMargin, 0.01));
      expect(region.bottom, closeTo(122 + captureMargin, 0.01));
    });

    test('ignores the part of a stroke outside the box', () {
      // Runs far past the right edge of the selection; only the caught half
      // should count towards the crop.
      final strokes = [_line(const Offset(10, 10), const Offset(900, 10))];

      final region = captureRegion(
        strokes,
        const Rect.fromLTWH(0, 0, 100, 100),
      )!;

      expect(region.right, closeTo(100 + captureMargin, 0.01));
    });

    test('a dot still has an area worth capturing', () {
      final strokes = [_line(const Offset(50, 50), const Offset(50, 50))];

      final region = captureRegion(
        strokes,
        const Rect.fromLTWH(0, 0, 200, 200),
      );

      expect(region, isNotNull);
      expect(region!.isEmpty, isFalse);
    });
  });

  group('captureInkPng', () {
    test('renders a PNG for a box with ink in it', () async {
      final strokes = [_line(const Offset(20, 20), const Offset(80, 60))];

      final png = await captureInkPng(strokes, const Rect.fromLTWH(0, 0, 200, 200));

      expect(png, isNotNull);
      // PNG signature. Cheap, and it catches the case where the format argument
      // is wrong and raw pixels come back instead.
      expect(png!.take(4), [0x89, 0x50, 0x4E, 0x47]);
    });

    test('is null when the box is empty board', () async {
      final strokes = [_line(const Offset(0, 0), const Offset(10, 10))];

      expect(
        await captureInkPng(strokes, const Rect.fromLTWH(500, 500, 100, 100)),
        isNull,
      );
    });
  });
}
