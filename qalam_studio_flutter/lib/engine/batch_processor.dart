import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

class BatchJobRequest {
  final List<String> inputPaths;
  final String outputDir;
  final int maxWidth;
  final double brightness;
  final double contrast;
  final double saturation;
  final bool blackAndWhite;
  final double removeWhiteTolerance;
  final int quality;

  const BatchJobRequest({
    required this.inputPaths,
    required this.outputDir,
    this.maxWidth = 1600,
    this.brightness = 1.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.blackAndWhite = false,
    this.removeWhiteTolerance = 0.0,
    this.quality = 90,
  });
}

Future<List<String>> runBatchOffline(BatchJobRequest req) {
  return compute(_processImagesIsolate, req);
}

List<String> _processImagesIsolate(BatchJobRequest req) {
  final outputs = <String>[];
  for (final inputPath in req.inputPaths) {
    final bytes = File(inputPath).readAsBytesSync();
    var decoded = img.decodeImage(bytes);
    if (decoded == null) continue;

    if (req.maxWidth > 0 && decoded.width > req.maxWidth) {
      decoded = img.copyResize(decoded, width: req.maxWidth);
    }

    if (req.removeWhiteTolerance > 0) {
      final rgba = decoded.numChannels == 4 ? decoded.clone() : decoded.convert(numChannels: 4);
      final cutoff = (req.removeWhiteTolerance.clamp(1.0, 100.0) / 100.0) * 195.0;
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
          pixel.a = (a * ((dist - featherStart) / featherSpan)).round();
        }
      }
      decoded = rgba;
    }

    if (req.blackAndWhite) {
      decoded = img.grayscale(decoded);
    }

    decoded = img.adjustColor(
      decoded,
      brightness: req.brightness,
      contrast: req.contrast,
      saturation: req.blackAndWhite ? 0.0 : req.saturation,
    );

    final usePng = req.removeWhiteTolerance > 0;
    final ext = usePng ? 'png' : 'jpg';
    final outName = 'qalam_${p.basenameWithoutExtension(inputPath)}.$ext';
    final outPath = p.join(req.outputDir, outName);
    final encoded = usePng ? img.encodePng(decoded) : img.encodeJpg(decoded, quality: req.quality);
    File(outPath).writeAsBytesSync(encoded);
    outputs.add(outPath);
  }
  return outputs;
}
