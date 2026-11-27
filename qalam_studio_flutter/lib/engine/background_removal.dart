/// On-device AI background removal (Google ML Kit selfie segmentation).
///
/// The ML Kit model is bundled with the app
/// (`com.google.mlkit:segmentation-selfie`, ~4.5 MB in the APK) — no
/// download, no network, no API key. Segmentation only detects *people*, so
/// this is a portrait feature, not a general object cut-out; the UI labels
/// it "Remove BG (Person)" for exactly that reason.
///
/// Threading: the ML Kit call is a platform-channel call, and platform
/// channels do not work inside a `compute()` isolate, so segmentation runs
/// on the main isolate (behind the saving HUD). All heavy pixel work
/// (decode / EXIF bake / resize / mask compositing) runs in `compute()`
/// isolates, mirroring `removeWhiteBackgroundOffline` in filter_matrix.dart.
///
/// EXIF: the segmenter sees a temporary copy of the source that has already
/// been orientation-baked and capped at 1024 px, and the mask is applied to
/// the same baked full-resolution image — so the mask can never be rotated
/// out of sync with the pixels, whatever EXIF rotation the camera wrote.
/// The temporary segmentation file is deleted right after the call.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Segmentation input is capped at this longest side for speed; the mask is
/// then upscaled back onto the full-resolution image.
const int kSegmentationMaxSide = 1024;

/// Foreground is kept when confidence is above this; [kMaskFeather] is the
/// half-width of the smooth edge band around it.
const double kMaskThreshold = 0.5;
const double kMaskFeather = 0.15;

/// Below this foreground fraction the photo is treated as "no person found".
const double kMinForegroundFraction = 0.005;

class BackgroundRemovalResult {
  /// Transparent-background PNG, or null when no person was found.
  final Uint8List? pngBytes;

  /// Fraction of mask pixels with foreground confidence above 0.5.
  final double foregroundFraction;

  /// True when the image was processed but contained no detectable person.
  final bool noPersonDetected;

  const BackgroundRemovalResult({
    required this.pngBytes,
    required this.foregroundFraction,
    required this.noPersonDetected,
  });
}

class _SegmentationPrepRequest {
  final String filePath;
  const _SegmentationPrepRequest(this.filePath);
}

class _PreparedSegmentationInput {
  /// Orientation-baked, full resolution.
  final Uint8List fullPngBytes;

  /// Orientation-baked, longest side capped at [kSegmentationMaxSide].
  final Uint8List cappedPngBytes;

  const _PreparedSegmentationInput(this.fullPngBytes, this.cappedPngBytes);
}

_PreparedSegmentationInput? _prepareSegmentationInput(
  _SegmentationPrepRequest req,
) {
  final file = File(req.filePath);
  if (!file.existsSync()) return null;
  final decoded = img.decodeImage(file.readAsBytesSync());
  if (decoded == null) return null;
  final baked = img.bakeOrientation(decoded);
  final full = Uint8List.fromList(img.encodePng(baked));
  final capped = (baked.width > kSegmentationMaxSide ||
          baked.height > kSegmentationMaxSide)
      ? (baked.width >= baked.height
          ? img.copyResize(baked, width: kSegmentationMaxSide)
          : img.copyResize(baked, height: kSegmentationMaxSide))
      : baked;
  final cappedBytes = Uint8List.fromList(img.encodePng(capped));
  return _PreparedSegmentationInput(full, cappedBytes);
}

class _MaskApplyRequest {
  final Uint8List fullPngBytes;
  final int maskWidth;
  final int maskHeight;
  final List<double> confidences;
  final double threshold;
  final double feather;

  const _MaskApplyRequest({
    required this.fullPngBytes,
    required this.maskWidth,
    required this.maskHeight,
    required this.confidences,
    required this.threshold,
    required this.feather,
  });
}

Uint8List? _applyMaskIsolate(_MaskApplyRequest req) {
  final decoded = img.decodeImage(req.fullPngBytes);
  if (decoded == null) return null;
  final rgba = decoded.numChannels == 4
      ? decoded.clone()
      : decoded.convert(numChannels: 4);
  final w = rgba.width;
  final h = rgba.height;
  final mw = req.maskWidth;
  final mh = req.maskHeight;
  final conf = req.confidences;
  if (w == 0 || h == 0 || mw <= 0 || mh <= 0 || conf.length < mw * mh) {
    return null;
  }
  // With enableRawSizeMask the mask is the model's raw size (e.g. 256x256),
  // usually smaller than the image — bilinear-upscale it onto the pixels.
  final lo = req.threshold - req.feather;
  final span = req.feather * 2.0;
  for (int y = 0; y < h; y++) {
    final fy = h <= 1 ? 0.0 : y * (mh - 1) / (h - 1);
    final y0 = fy.floor().clamp(0, mh - 1);
    final y1 = math.min(mh - 1, y0 + 1);
    final ty = fy - y0;
    for (int x = 0; x < w; x++) {
      final fx = w <= 1 ? 0.0 : x * (mw - 1) / (w - 1);
      final x0 = fx.floor().clamp(0, mw - 1);
      final x1 = math.min(mw - 1, x0 + 1);
      final tx = fx - x0;
      final c00 = conf[y0 * mw + x0];
      final c10 = conf[y0 * mw + x1];
      final c01 = conf[y1 * mw + x0];
      final c11 = conf[y1 * mw + x1];
      final c = (c00 * (1.0 - tx) + c10 * tx) * (1.0 - ty) +
          (c01 * (1.0 - tx) + c11 * tx) * ty;
      final t = ((c - lo) / span).clamp(0.0, 1.0);
      final smooth = t * t * (3.0 - 2.0 * t);
      final px = rgba.getPixel(x, y);
      px.a = (px.a.toInt() * smooth).round();
    }
  }
  return Uint8List.fromList(img.encodePng(rgba));
}

/// Segments the person out of [filePath] and returns a transparent PNG.
///
/// Returns null only on a hard failure (unreadable file, decode failure,
/// segmentation error). A processed image with no detectable person returns
/// a result with [BackgroundRemovalResult.noPersonDetected] true and
/// [BackgroundRemovalResult.pngBytes] null, so the caller can show a
/// friendly message instead of crashing.
Future<BackgroundRemovalResult?> removeBackgroundOffline(
  String filePath, {
  double threshold = kMaskThreshold,
  double feather = kMaskFeather,
}) async {
  final prepared = await compute(
    _prepareSegmentationInput,
    _SegmentationPrepRequest(filePath),
  );
  if (prepared == null) return null;

  // Segmentation itself runs on the main isolate: ML Kit is a
  // platform-channel plugin and cannot run inside a compute() isolate.
  final tmpDir = await getTemporaryDirectory();
  final segPath = p.join(
    tmpDir.path,
    'qalamix_seg_${DateTime.now().microsecondsSinceEpoch}.png',
  );
  SegmentationMask? mask;
  final segmenter = SelfieSegmenter(
    mode: SegmenterMode.single,
    enableRawSizeMask: true,
  );
  try {
    await File(segPath).writeAsBytes(prepared.cappedPngBytes);
    mask = await segmenter.processImage(InputImage.fromFilePath(segPath));
  } catch (_) {
    mask = null;
  } finally {
    await segmenter.close();
    try {
      await File(segPath).delete();
    } catch (_) {}
  }
  if (mask == null) return null;

  var fgCount = 0;
  for (final c in mask.confidences) {
    if (c > 0.5) fgCount++;
  }
  final fraction =
      mask.confidences.isEmpty ? 0.0 : fgCount / mask.confidences.length;
  if (fraction < kMinForegroundFraction) {
    return BackgroundRemovalResult(
      pngBytes: null,
      foregroundFraction: fraction,
      noPersonDetected: true,
    );
  }

  final out = await compute(
    _applyMaskIsolate,
    _MaskApplyRequest(
      fullPngBytes: prepared.fullPngBytes,
      maskWidth: mask.width,
      maskHeight: mask.height,
      confidences: mask.confidences,
      threshold: threshold,
      feather: feather,
    ),
  );
  if (out == null) return null;
  return BackgroundRemovalResult(
    pngBytes: out,
    foregroundFraction: fraction,
    noPersonDetected: false,
  );
}
