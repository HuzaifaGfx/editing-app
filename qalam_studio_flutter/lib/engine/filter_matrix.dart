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

  // Resize preview safely if enormous while keeping high clarity
  var work = decoded;
  if (work.width > 1600 || work.height > 1600) {
    work = work.width >= work.height
        ? img.copyResize(work, width: 1600)
        : img.copyResize(work, height: 1600);
  }

  final rgba = work.numChannels == 4 ? work.clone() : work.convert(numChannels: 4);
  final cutoff = (req.tolerance.clamp(1.0, 100.0) / 100.0) * 195.0;
  final featherStart = cutoff * 0.68;
  final featherSpan = math.max(1.0, cutoff - featherStart);

  for (final pixel in rgba) {
    final a = pixel.a.toInt();
    if (a == 0) continue;
    final dr = 255 - pixel.r.toInt();
    final dg = 255 - pixel.g.toInt();
    final db = 255 - pixel.b.toInt();
    final dist = math.sqrt(dr * dr + dg * dg + db * db);

    if (dist <= featherStart) {
      pixel.a = 0;
    } else if (dist < cutoff) {
      final factor = (dist - featherStart) / featherSpan;
      pixel.a = (a * factor).round();
    }
  }

  return Uint8List.fromList(img.encodePng(rgba));
}
