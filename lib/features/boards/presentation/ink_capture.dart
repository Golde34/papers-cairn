import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'strokes.dart';

/// White space left around the writing.
///
/// A crop that stops at the last pixel of ink reads worse than one with a
/// margin: descenders, accents and the tail of a long division all sit slightly
/// outside the path bounds, and a model given a tight crop tends to guess at
/// what was cut off.
const captureMargin = 24.0;

/// How wide the finished image should be, at most, in pixels.
///
/// Handwriting needs resolution to be legible, but an image costs tokens by
/// area. Around fourteen hundred pixels on the long edge is enough to read a
/// page of maths and well under the point where more pixels stop helping.
const captureTargetEdge = 1400.0;

/// Ink as a reader should see it: dark on white, whatever the board looks like.
///
/// Default ink follows the theme, so on a dark board it is near-white — painted
/// onto the white background this capture uses, it would come out blank. Ink
/// given a real colour keeps it: the palette is mid-toned and stays legible on
/// white, and the colour is often the point (one colour for the working, another
/// for the answer).
Color captureInk(int colorValue) => colorValue == defaultInkColorValue
    ? const Color(0xFF111111)
    : Color(colorValue);

/// The part of [selection] worth turning into an image, or null if the selection
/// caught no ink.
///
/// Shrunk to the writing itself rather than used as drawn. A box dragged in a
/// hurry is mostly empty board, and empty board is pixels the model pays for and
/// learns nothing from.
Rect? captureRegion(Iterable<DrawnStroke> strokes, Rect selection) {
  Rect? bounds;
  for (final stroke in strokes) {
    final box = _boundsOf(stroke);
    if (!box.overlaps(selection)) continue;

    final clipped = box.intersect(selection);
    bounds = bounds == null ? clipped : bounds.expandToInclude(clipped);
  }
  if (bounds == null) return null;
  return bounds.inflate(captureMargin);
}

/// Renders the ink inside [selection] as a PNG, or returns null if there is
/// none.
///
/// Reuses the paths already prepared for the screen instead of decoding the
/// strokes again — the work is done, and a capture is not a reason to redo it.
Future<Uint8List?> captureInkPng(
  List<DrawnStroke> strokes,
  Rect selection,
) async {
  final region = captureRegion(strokes, selection);
  if (region == null || region.isEmpty) return null;

  final longest = math.max(region.width, region.height);
  // Small selections are drawn larger so a short scribble is not a postage
  // stamp; large ones are never blown up past the point of usefulness.
  final ratio = longest <= 0
      ? 1.0
      : (captureTargetEdge / longest).clamp(1.0, 3.0);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(ratio)
    ..translate(-region.left, -region.top)
    ..drawRect(region, Paint()..color = const Color(0xFFFFFFFF));

  for (final stroke in strokes) {
    if (!_boundsOf(stroke).overlaps(region)) continue;
    canvas.drawPath(stroke.path, _capturePaint(stroke));
  }

  final picture = recorder.endRecording();
  // Disposed by hand, both of them. An unreleased picture or image holds native
  // memory the garbage collector cannot see and will not hurry to reclaim.
  try {
    final image = await picture.toImage(
      math.max(1, (region.width * ratio).ceil()),
      math.max(1, (region.height * ratio).ceil()),
    );
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

Rect _boundsOf(DrawnStroke stroke) =>
    stroke.path.getBounds().inflate(stroke.width / 2);

Paint _capturePaint(DrawnStroke stroke) => Paint()
  ..color = captureInk(stroke.colorValue)
  ..strokeWidth = stroke.width
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true;
