import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'filter_matrix.dart';

class BatchJobRequest {
  final List<String> inputPaths;
  final String outputDir;
  final int maxWidth;
  final double brightness;
  final double contrast;
  final double saturation;
  final bool blackAndWhite;
  final bool guilloche;
  final double guillocheContrast;
  final double guillocheBend;
  final double guillocheOpacity;
  final String guillochePattern;
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
    this.guilloche = false,
    this.guillocheContrast = 13.0,
    this.guillocheBend = 3.0,
    this.guillocheOpacity = 88.0,
    this.guillochePattern = 'banknote',
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
      decoded = removeWhiteOnImage(decoded, req.removeWhiteTolerance);
    }
    if (req.guilloche) {
      decoded = applyGuillocheBlendToImage(
        decoded,
        contrastPct: req.guillocheContrast,
        bendPx: req.guillocheBend,
        opacityPct: req.guillocheOpacity,
        pattern: req.guillochePattern,
      );
    } else if (req.blackAndWhite) {
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
    final outName = 'qalamix_${p.basenameWithoutExtension(inputPath)}.$ext';
    final outPath = p.join(req.outputDir, outName);
    final encoded = usePng ? img.encodePng(decoded) : img.encodeJpg(decoded, quality: req.quality);
    File(outPath).writeAsBytesSync(encoded);
    outputs.add(outPath);
  }
  return outputs;
}
