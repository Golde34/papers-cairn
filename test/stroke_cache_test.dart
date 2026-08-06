import 'package:cairn/core/database/database.dart';
import 'package:cairn/features/boards/presentation/strokes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Stroke _stroke(int id, {int colorValue = defaultInkColorValue}) => Stroke(
  id: id,
  boardId: 1,
  pointsJson: '[[0,0],[10,10],[20,5]]',
  colorValue: colorValue,
  width: 5,
  createdAt: DateTime(2026, 1, 1),
);

final _light = ColorScheme.fromSeed(seedColor: Colors.green);
final _dark = ColorScheme.fromSeed(
  seedColor: Colors.green,
  brightness: Brightness.dark,
);

void main() {
  group('StrokeCache', () {
    test('builds each stroke once', () {
      final cache = StrokeCache();
      cache.sync([_stroke(1), _stroke(2)], _light);

      expect(cache.builds, 2);
      expect(cache.drawn, hasLength(2));
    });

    test('adding a stroke builds only the new one', () {
      final cache = StrokeCache();
      cache.sync([_stroke(1), _stroke(2)], _light);
      cache.sync([_stroke(1), _stroke(2), _stroke(3)], _light);

      // Three strokes, three builds. Rebuilding the list wholesale would be
      // five, and the gap widens with every stroke drawn.
      expect(cache.builds, 3);
    });

    test('keeps the very same prepared stroke, not an equal copy', () {
      final cache = StrokeCache();
      cache.sync([_stroke(1)], _light);
      final first = cache.drawn.single;

      cache.sync([_stroke(1), _stroke(2)], _light);

      expect(identical(cache.drawn.first, first), isTrue);
    });

    test('drops what is deleted', () {
      final cache = StrokeCache();
      cache.sync([_stroke(1), _stroke(2)], _light);
      cache.sync([_stroke(2)], _light);

      expect(cache.drawn.map((s) => s.id), [2]);
      expect(cache.builds, 2);
    });

    test('rebuilds everything when the theme flips', () {
      final cache = StrokeCache();
      cache.sync([_stroke(1), _stroke(2)], _light);
      cache.sync([_stroke(1), _stroke(2)], _dark);

      // Default ink resolves to a colour that has just moved, so nothing
      // prepared under the old scheme is still correct.
      expect(cache.builds, 4);
      // Compared as packed ARGB: Flutter stores colour components as floats, and
      // a round trip through Paint leaves the objects unequal while the colour
      // is the same.
      expect(cache.drawn.first.paint.color.toARGB32(), _dark.onSurface.toARGB32());
    });

    test('does no work when nothing changed', () {
      final cache = StrokeCache();
      final strokes = [_stroke(1)];
      cache.sync(strokes, _light);

      expect(cache.sync(strokes, _light), isFalse);
      expect(cache.builds, 1);
    });

    test('a stroke with a real colour ignores the theme', () {
      final cache = StrokeCache();
      cache.sync([_stroke(1, colorValue: 0xFFF9A825)], _light);

      expect(cache.drawn.single.paint.color.toARGB32(), 0xFFF9A825);
    });
  });
}
