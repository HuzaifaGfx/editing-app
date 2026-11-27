/// One-tap Enhance: local `image`-package pipeline only — no ML, no network,
/// no API key.
///
/// image 4.x has no single `enhance()`/`sharpen()`, so the effect is
/// composed from its primitives: EXIF bake, auto-levels ([img.normalize]),
/// a gentle brightness/contrast/saturation lift ([img.adjustColor]) and an
/// unsharp-mask 3x3 convolution for crispness. Runs in a `compute()` isolate
/// like the other baked pixel ops in filter_matrix.dart.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class EnhanceRequest {
  final String filePath;
  const EnhanceRequest(this.filePath);
}

Future<Uint8List?> enhanceImageOffline(String filePath) {
  return compute(_enhanceIsolate, EnhanceRequest(filePath));
}

Uint8List? _enhanceIsolate(EnhanceRequest req) {
  final file = File(req.filePath);
  if (!file.existsSync()) return null;
  final decoded = img.decodeImage(file.readAsBytesSync());
  if (decoded == null) return null;
  var work = img.bakeOrientation(decoded);
  if (work.width > 2048 || work.height > 2048) {
    work = work.width >= work.height
        ? img.copyResize(work, width: 2048)
        : img.copyResize(work, height: 2048);
  }
  // Auto-levels.
  work = img.normalize(work, min: 0, max: 255);
  // Gentle lift: slightly brighter, punchier, more vivid.
  work = img.adjustColor(
    work,
    brightness: 1.05,
    contrast: 1.15,
    saturation: 1.15,
  );
  // Unsharp mask (kernel sums to 1): crisp edges without halos.
  work = img.convolution(
    work,
    filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0],
  );
  return Uint8List.fromList(img.encodePng(work));
}
