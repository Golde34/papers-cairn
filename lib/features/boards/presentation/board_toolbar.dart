import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'strokes.dart';

/// What a touch on the board does.
enum BoardTool { pan, pen, eraser, select }

/// Mid-toned on purpose — these have to read against both a white board and a
/// near-black one.
const penColorValues = <int>[
  defaultInkColorValue,
  0xFFF9A825,
  0xFF43A047,
  0xFF1E88E5,
  0xFFD81B60,
];

const penWidths = <double>[2, 5, 12];

const _height = 56.0;

class BoardToolbar extends StatelessWidget {
  const BoardToolbar({
    super.key,
    required this.tool,
    required this.colorValue,
    required this.width,
    required this.onTool,
    required this.onColor,
    required this.onWidth,
  });

  final BoardTool tool;
  final int colorValue;
  final double width;
  final void Function(BoardTool tool) onTool;
  final void Function(int colorValue) onColor;
  final void Function(double width) onWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      // Height is pinned. Left to size itself the row grew to fill the loose
      // constraints a bottomNavigationBar hands down, and the controls ended up
      // floating in the middle of the screen.
      child: SizedBox(
        height: _height,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            _ToolButton(
              icon: Icons.pan_tool_outlined,
              selected: tool == BoardTool.pan,
              tooltip: 'Move around',
              onTap: () => onTool(BoardTool.pan),
            ),
            _ToolButton(
              icon: Icons.edit,
              selected: tool == BoardTool.pen,
              tooltip: 'Draw',
              onTap: () => onTool(BoardTool.pen),
            ),
            _ToolButton(
              icon: Icons.cleaning_services_outlined,
              selected: tool == BoardTool.eraser,
              tooltip: 'Erase',
              onTap: () => onTool(BoardTool.eraser),
            ),
            _ToolButton(
              icon: Icons.auto_awesome_outlined,
              selected: tool == BoardTool.select,
              tooltip: 'Select handwriting',
              onTap: () => onTool(BoardTool.select),
            ),
            _Separator(color: scheme.outlineVariant),
            for (final option in penColorValues)
              Center(
                child: GestureDetector(
                  // Opaque, not the default deferToChild: the swatch is smaller
                  // than a fingertip and only its painted circle would take taps.
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onColor(option),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: option == colorValue
                            ? scheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      backgroundColor: resolveInk(option, scheme),
                      radius: 11,
                    ),
                  ),
                ),
              ),
            _Separator(color: scheme.outlineVariant),
            for (final option in penWidths)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onWidth(option),
                child: SizedBox(
                  width: 48,
                  child: Center(
                    // The nib is shown by a filled disc behind it, not by
                    // recolouring the dot. Dark green against near-black told
                    // you almost nothing about which size was selected.
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: option == width
                            ? scheme.secondaryContainer
                            : Colors.transparent,
                      ),
                      child: Center(
                        child: Container(
                          width: math.max(option * 1.6, 6),
                          height: math.max(option * 1.6, 6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: option == width
                                ? scheme.onSecondaryContainer
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 1,
      height: 24,
      color: color,
      margin: const EdgeInsets.symmetric(horizontal: 10),
    ),
  );
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon),
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: selected ? scheme.secondaryContainer : null,
          foregroundColor: selected ? scheme.onSecondaryContainer : null,
        ),
      ),
    );
  }
}
