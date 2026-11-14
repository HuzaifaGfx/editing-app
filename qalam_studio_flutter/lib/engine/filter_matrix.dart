import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../models/design_project.dart';

ColorFilter buildLayerColorFilter(FilterSettings f) {
  final b = (f.brightness - 1.0) * 255.0;
  final c = f.contrast;
  final t = (1.0 - c) * 128.0;

  final s = f.blackAndWhite ? 0.0 : (f.saturate * (1.0 - f.grayscale));
  final sr = (1.0 - s) * 0.2126;
  final sg = (1.0 - s) * 0.7152;
  final sb = (1.0 - s) * 0.0722;

  final matrix = <double>[
    (sr + s) * c, sg * c, sb * c, 0, b + t,
    sr * c, (sg + s) * c, sb * c, 0, b + t,
    sr * c, sg * c, (sb + s) * c, 0, b + t,
    0, 0, 0, 1, 0,
  ];
  return ColorFilter.matrix(matrix);
}

class WhiteRemovalRequest {
  final String filePath;
  final double tolerance;
  const WhiteRemovalRequest(this.filePath, this.tolerance);
}

Future<Uint8List?> removeWhiteBackgroundOffline(String filePath, double tolerance) {
  return compute(_removeWhiteIsolate, WhiteRemovalRequest(filePath, tolerance));
}

Uint8List? _removeWhiteIsolate(WhiteRemovalRequest req) {
  final bytes = File(req.filePath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  var work = decoded;
  if (work.width > 2048 || work.height > 2048) {
    work = work.width >= work.height
        ? img.copyResize(work, width: 2048)
        : img.copyResize(work, height: 2048);
  }

  final rgba = work.numChannels == 4 ? work.clone() : work.convert(numChannels: 4);
  final tolNorm = req.tolerance.clamp(1.0, 100.0) / 100.0;
  final hardMinLum = 248.0 - tolNorm * 95.0;
  final softRange = 28.0 + tolNorm * 34.0;
  final maxChromaForWhite = 18.0 + tolNorm * 46.0;

  for (final pixel in rgba) {
    final a = pixel.a.toInt();
    if (a == 0) continue;
    final r = pixel.r.toInt();
    final g = pixel.g.toInt();
    final b = pixel.b.toInt();

    final maxC = math.max(r, math.max(g, b));
    final minC = math.min(r, math.min(g, b));
    final chroma = maxC - minC;
    final lum = 0.299 * r + 0.587 * g + 0.114 * b;
    final chromaPenalty = chroma > maxChromaForWhite ? (chroma - maxChromaForWhite) * 2.1 : 0.0;
    final effectiveWhiteness = math.min(lum, minC + 14.0) - chromaPenalty;

    if (effectiveWhiteness >= hardMinLum) {
      pixel.a = 0;
    } else if (effectiveWhiteness > hardMinLum - softRange) {
      final t = ((hardMinLum - effectiveWhiteness) / softRange).clamp(0.0, 1.0);
      final smooth = t * t * (3.0 - 2.0 * t);
      final nextAlpha = (a * smooth).round();
      pixel.a = nextAlpha;

      if (nextAlpha > 8 && nextAlpha < 248) {
        final af = nextAlpha / 255.0;
        pixel.r = ((r - 255.0 * (1.0 - af)) / af).clamp(0.0, 255.0).round();
        pixel.g = ((g - 255.0 * (1.0 - af)) / af).clamp(0.0, 255.0).round();
        pixel.b = ((b - 255.0 * (1.0 - af)) / af).clamp(0.0, 255.0).round();
      }
    }
  }

  return Uint8List.fromList(img.encodePng(rgba));
}
