import 'dart:io';
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
  final int quality;

  const BatchJobRequest({
    required this.inputPaths,
    required this.outputDir,
    this.maxWidth = 1920,
    this.brightness = 1.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
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

    decoded = img.adjustColor(
      decoded,
      brightness: req.brightness,
      contrast: req.contrast,
      saturation: req.saturation,
    );

    final outName = 'qalam_${p.basenameWithoutExtension(inputPath)}.jpg';
    final outPath = p.join(req.outputDir, outName);
    File(outPath).writeAsBytesSync(img.encodeJpg(decoded, quality: req.quality));
    outputs.add(outPath);
  }
  return outputs;
}
