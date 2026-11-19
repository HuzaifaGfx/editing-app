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
      final tolNorm = req.removeWhiteTolerance.clamp(1.0, 100.0) / 100.0;
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
      decoded = rgba;
    }

    if (req.blackAndWhite) {
      for (final pixel in decoded) {
        if (decoded.numChannels == 4 && pixel.a == 0) continue;
        final lum = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
        final boosted = ((lum - 128.0) * req.contrast + 128.0 * req.brightness)
            .clamp(0.0, 255.0)
            .round();
        pixel.r = boosted;
        pixel.g = boosted;
        pixel.b = boosted;
      }
    } else if (req.brightness != 1.0 || req.contrast != 1.0 || req.saturation != 1.0) {
      decoded = img.adjustColor(
        decoded,
        brightness: req.brightness,
        contrast: req.contrast,
        saturation: req.saturation,
      );
    }

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
