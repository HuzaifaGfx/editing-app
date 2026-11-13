import 'dart:ui';
import '../models/design_project.dart';

ColorFilter buildLayerColorFilter(FilterSettings f) {
  final b = (f.brightness - 1.0) * 255.0;
  final c = f.contrast;
  final t = (1.0 - c) * 128.0;

  // Luminance weights for saturation
  final s = f.saturate;
  final sr = (1 - s) * 0.2126;
  final sg = (1 - s) * 0.7152;
  final sb = (1 - s) * 0.0722;

  final matrix = <double>[
    (sr + s) * c, sg * c, sb * c, 0, b + t,
    sr * c, (sg + s) * c, sb * c, 0, b + t,
    sr * c, sg * c, (sb + s) * c, 0, b + t,
    0, 0, 0, 1, 0,
  ];
  return ColorFilter.matrix(matrix);
}
