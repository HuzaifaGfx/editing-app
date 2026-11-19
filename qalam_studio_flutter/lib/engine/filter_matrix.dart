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

  var m00 = sr + s, m01 = sg, m02 = sb;
  var m10 = sr, m11 = sg + s, m12 = sb;
  var m20 = sr, m21 = sg, m22 = sb + s;

  final sp = f.sepia.clamp(0.0, 1.0);
  if (sp > 0.0 && !f.blackAndWhite) {
    final inv = 1.0 - sp;
    final nm00 = m00 * (inv + sp * 0.393) + m10 * (sp * 0.769) + m20 * (sp * 0.189);
    final nm01 = m01 * (inv + sp * 0.393) + m11 * (sp * 0.769) + m21 * (sp * 0.189);
    final nm02 = m02 * (inv + sp * 0.393) + m12 * (sp * 0.769) + m22 * (sp * 0.189);
    final nm10 = m00 * (sp * 0.349) + m10 * (inv + sp * 0.686) + m20 * (sp * 0.168);
    final nm11 = m01 * (sp * 0.349) + m11 * (inv + sp * 0.686) + m21 * (sp * 0.168);
    final nm12 = m02 * (sp * 0.349) + m12 * (inv + sp * 0.686) + m22 * (sp * 0.168);
    final nm20 = m00 * (sp * 0.272) + m10 * (sp * 0.534) + m20 * (inv + sp * 0.131);
    final nm21 = m01 * (sp * 0.272) + m11 * (sp * 0.534) + m21 * (inv + sp * 0.131);
    final nm22 = m02 * (sp * 0.272) + m12 * (sp * 0.534) + m22 * (inv + sp * 0.131);
    m00 = nm00; m01 = nm01; m02 = nm02;
    m10 = nm10; m11 = nm11; m12 = nm12;
    m20 = nm20; m21 = nm21; m22 = nm22;
  }

  final matrix = <double>[
    m00 * c, m01 * c, m02 * c, 0, b + t,
    m10 * c, m11 * c, m12 * c, 0, b + t,
    m20 * c, m21 * c, m22 * c, 0, b + t,
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
