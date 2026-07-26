import 'package:flutter/material.dart';

import '../database/database.dart';

const seedColor = Color(0xFF4A5D4E);

/// Palette offered when creating a project. Muted on purpose — these are
/// wayfinding marks, and a list of twelve saturated chips is harder to tell
/// apart at a glance than six quiet ones.
const projectPalette = <Color>[
  Color(0xFF4A5D4E),
  Color(0xFF7A5C3E),
  Color(0xFF3E5A7A),
  Color(0xFF7A3E52),
  Color(0xFF5B4A7A),
  Color(0xFF3E7A6E),
];

/// Highlight colours. Saturated rather than muted, unlike [projectPalette]:
/// these are painted translucent over page text, where anything subtle
/// disappears against the paper.
const highlightPalette = <Color>[
  Color(0xFFFFD54F),
  Color(0xFF81C784),
  Color(0xFF64B5F6),
  Color(0xFFF06292),
  Color(0xFFBA68C8),
];

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    listTileTheme: ListTileThemeData(
      // The colour has to be spelled out. Supplying a titleTextStyle replaces
      // ListTile's default wholesale, and a style with a null colour leaves the
      // title painting in whatever the ambient default happens to be — which in
      // light mode is white on white.
      titleTextStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
    ),
  );
}

extension ReadingStatusPresentation on ReadingStatus {
  String get label => switch (this) {
    ReadingStatus.toRead => 'To read',
    ReadingStatus.reading => 'Reading',
    ReadingStatus.done => 'Done',
    ReadingStatus.dropped => 'Dropped',
  };

  IconData get icon => switch (this) {
    ReadingStatus.toRead => Icons.schedule,
    ReadingStatus.reading => Icons.auto_stories,
    ReadingStatus.done => Icons.check_circle_outline,
    ReadingStatus.dropped => Icons.remove_circle_outline,
  };

  Color color(ColorScheme scheme) => switch (this) {
    ReadingStatus.toRead => scheme.outline,
    ReadingStatus.reading => scheme.primary,
    ReadingStatus.done => scheme.tertiary,
    ReadingStatus.dropped => scheme.outlineVariant,
  };
}
