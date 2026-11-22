import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
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


bool filtersHaveVisualEffect(FilterSettings f) {
  return (f.brightness - 1.0).abs() >= 0.005 ||
      (f.contrast - 1.0).abs() >= 0.005 ||
      (f.saturate - 1.0).abs() >= 0.005 ||
      f.sepia >= 0.005 ||
      f.grayscale >= 0.005 ||
      f.blackAndWhite ||
      f.softGlow > 0.5 ||
      f.rosyTint > 0.5 ||
      f.skinSmooth > 0.5 ||
      f.portraitBlur > 0.5;
}

Widget buildOpticalFilteredImageWidget({
  required FilterSettings filters,
  required Widget Function() childBuilder,
}) {
  final hasColorGrade = (filters.brightness - 1.0).abs() >= 0.005 ||
      (filters.contrast - 1.0).abs() >= 0.005 ||
      (filters.saturate - 1.0).abs() >= 0.005 ||
      filters.sepia >= 0.005 ||
      filters.grayscale >= 0.005 ||
      filters.blackAndWhite;

  Widget gradedChild() {
    final base = childBuilder();
    return hasColorGrade
        ? ColorFiltered(
            colorFilter: buildLayerColorFilter(filters),
            child: base,
          )
        : base;
  }

  final pBlur = filters.guilloche ? 0.0 : filters.portraitBlur.clamp(0.0, 100.0);
  final skinSmooth = filters.guilloche ? 0.0 : filters.skinSmooth.clamp(0.0, 100.0);
  final softGlow = filters.guilloche ? 0.0 : filters.softGlow.clamp(0.0, 100.0);
  final rosyTint = filters.guilloche ? 0.0 : filters.rosyTint.clamp(0.0, 100.0);

  if (pBlur <= 0.5 && skinSmooth <= 0.5 && softGlow <= 0.5 && rosyTint <= 0.5) {
    return gradedChild();
  }

  return ClipRect(
    child: Stack(
      fit: StackFit.expand,
      children: [
        gradedChild(),
        if (pBlur > 0.5)
          IgnorePointer(
            child: ShaderMask(
              blendMode: ui.BlendMode.dstOut,
              shaderCallback: (Rect bounds) => RadialGradient(
                center: const Alignment(0.0, -0.16),
                radius: 0.72,
                colors: [
                  Colors.black,
                  Colors.black.withOpacity(0.86),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.44, 0.94],
              ).createShader(bounds),
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: (pBlur / 100.0) * 12.0,
                  sigmaY: (pBlur / 100.0) * 12.0,
                  tileMode: TileMode.clamp,
                ),
                child: gradedChild(),
              ),
            ),
          ),
        if (skinSmooth > 0.5)
          IgnorePointer(
            child: Opacity(
              opacity: (skinSmooth / 100.0) * 0.36,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: (skinSmooth / 100.0) * 3.8,
                  sigmaY: (skinSmooth / 100.0) * 3.8,
                  tileMode: TileMode.clamp,
                ),
                child: gradedChild(),
              ),
            ),
          ),
        if (softGlow > 0.5)
          IgnorePointer(
            child: Opacity(
              opacity: (softGlow / 100.0) * 0.32,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: 3.0 + (softGlow / 100.0) * 9.0,
                  sigmaY: 3.0 + (softGlow / 100.0) * 9.0,
                  tileMode: TileMode.clamp,
                ),
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.white.withOpacity(0.24),
                    ui.BlendMode.plus,
                  ),
                  child: gradedChild(),
                ),
              ),
            ),
          ),
        if (rosyTint > 0.5)
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFFFB6CE).withOpacity((rosyTint / 100.0) * 0.24),
                    const Color(0xFFFCA5C0).withOpacity((rosyTint / 100.0) * 0.18),
                    const Color(0xFFFED7AA).withOpacity((rosyTint / 100.0) * 0.16),
                  ],
                ),
              ),
            ),
          ),
        if (rosyTint > 0.5)
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.10),
                  radius: 0.65,
                  colors: [
                    const Color(0xFFF47298).withOpacity((rosyTint / 100.0) * 0.14),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class WhiteRemovalRequest {
  final String filePath;
  final double tolerance;
  const WhiteRemovalRequest(this.filePath, this.tolerance);
}

class GuillocheRequest {
  final String filePath;
  final double contrastPct;
  final double bendPx;
  final double opacityPct;
  final String pattern;
  final double removeWhiteTolerance;

  const GuillocheRequest({
    required this.filePath,
    this.contrastPct = 13.0,
    this.bendPx = 3.0,
    this.opacityPct = 88.0,
    this.pattern = 'banknote',
    this.removeWhiteTolerance = 0.0,
  });
}

img.Image removeWhiteOnImage(img.Image src, double tolerance) {
  final rgba = src.numChannels == 4 ? src.clone() : src.convert(numChannels: 4);
  final tolNorm = tolerance.clamp(1.0, 100.0) / 100.0;
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
  return rgba;
}

/// Evaluates continuous procedural Guilloche linework security intensity in [0..1]
/// (1.0 = archival cream paper, 0.32..0.55 = finely engraved security wave/rosette ink).
double _evaluateGuillocheIntensity(double u, double v, int width, int height, String pattern) {
  final scale = math.max(1.0, math.min(width, height) / 420.0);
  final sx = u / scale;
  final sy = v / scale;

  double ridge = 1.0;
  if (pattern == 'rosette') {
    final cx = width / (2.0 * scale);
    final cy = height / (2.0 * scale);
    final dx = sx - cx;
    final dy = sy - cy;
    final rad = math.sqrt(dx * dx + dy * dy);
    final ang = math.atan2(dy, dx);
    final w1 = math.sin(rad * 0.58 + math.sin(ang * 12.0) * 1.9);
    final w2 = math.sin(rad * 0.58 - math.sin(ang * 12.0 + 1.1) * 1.9);
    final w3 = math.cos(sx * 0.32 + math.sin(sy * 0.085) * 3.2);
    final line1 = 1.0 - (1.0 - w1.abs()).clamp(0.0, 1.0);
    final line2 = 1.0 - (1.0 - w2.abs()).clamp(0.0, 1.0);
    final line3 = 1.0 - (1.0 - w3.abs()).clamp(0.0, 1.0);
    final crest = math.min(math.pow(line1, 5.5), math.pow(line2, 5.5)).toDouble();
    final wave = math.pow(line3, 6.0).toDouble();
    ridge = 1.0 - (1.0 - crest) * 0.42 - (1.0 - wave) * 0.16;
  } else if (pattern == 'mesh') {
    final d1 = math.sin((sx + sy) * 0.48 + math.sin((sx - sy) * 0.09) * 2.2);
    final d2 = math.sin((sx - sy) * 0.48 + math.cos((sx + sy) * 0.09) * 2.2);
    final l1 = math.pow((1.0 - d1.abs()).clamp(0.0, 1.0), 4.5).toDouble();
    final l2 = math.pow((1.0 - d2.abs()).clamp(0.0, 1.0), 4.5).toDouble();
    final ink = math.max(l1, l2);
    ridge = 1.0 - ink * 0.46;
  } else {
    // Classic Banknote Security Engraving (interlocking dual-phase sine waves + micro rosette)
    final p1 = math.sin(sy * 0.55 + math.sin(sx * 0.065) * 4.4 + math.cos(sx * 0.025) * 2.4);
    final p2 = math.sin(sy * 0.55 - math.sin(sx * 0.065 + 0.9) * 4.4 + math.sin(sx * 0.03) * 2.0);
    final p3 = math.sin((sx * 0.28 + sy * 0.14) + math.cos(sy * 0.05) * 2.8);
    final l1 = math.pow((1.0 - p1.abs()).clamp(0.0, 1.0), 5.0).toDouble();
    final l2 = math.pow((1.0 - p2.abs()).clamp(0.0, 1.0), 5.0).toDouble();
    final l3 = math.pow((1.0 - p3.abs()).clamp(0.0, 1.0), 6.0).toDouble();
    final ink = (math.max(l1, l2) * 0.84 + l3 * 0.34).clamp(0.0, 1.0);
    ridge = 1.0 - ink * 0.48;
  }
  return ridge.clamp(0.45, 1.0);
}

/// Applies the 4-stage Security Guilloche Blend effect:
/// 1. Grayscale + Contrast Boost (+10%..+15%)
/// 2. Subtle UV Contour Displacement (2..4 px) from portrait luminance
/// 3. Multiply Blend Mode: Result = (P * B) / 255
/// 4. Luminance Opacity (85%..90%) over warm banknote cream paper (#F6EED0)
img.Image applyGuillocheBlendToImage(
  img.Image src, {
  double contrastPct = 13.0,
  double bendPx = 3.0,
  double opacityPct = 88.0,
  String pattern = 'banknote',
}) {
  final rgba = src.numChannels == 4 ? src.clone() : src.convert(numChannels: 4);
  final w = rgba.width;
  final h = rgba.height;
  final total = w * h;
  if (w == 0 || h == 0) return rgba;

  final lumGrid = Float64List(total);
  final contrastFactor = 1.0 + contrastPct.clamp(0.0, 35.0) / 100.0;

  // Stage 1: Grayscale + Contrast Boost
  for (int y = 0; y < h; y++) {
    final rowOffset = y * w;
    for (int x = 0; x < w; x++) {
      final px = rgba.getPixel(x, y);
      final lum = 0.299 * px.r + 0.587 * px.g + 0.114 * px.b;
      final boosted = ((lum - 128.0) * contrastFactor + 128.0).clamp(0.0, 255.0);
      lumGrid[rowOffset + x] = boosted;
    }
  }

  final skinOp = opacityPct.clamp(65.0, 100.0) / 100.0;
  final invOp = 1.0 - skinOp;
  final bend = bendPx.clamp(0.0, 8.0);

  // Archival yellowish-cream banknote base tint (#F6EED0)
  const double paperR = 246.0;
  const double paperG = 238.0;
  const double paperB = 208.0;

  // Stages 2, 3 & 4
  for (int y = 0; y < h; y++) {
    final rowOffset = y * w;
    final yUp = y > 0 ? y - 1 : 0;
    final yDn = y + 1 < h ? y + 1 : h - 1;
    for (int x = 0; x < w; x++) {
      final px = rgba.getPixel(x, y);
      final a = px.a.toInt();
      if (a == 0) continue;

      final pLum = lumGrid[rowOffset + x];
      final lumNorm = pLum / 255.0;

      // Stage 2: Subtle UV displacement / contour bend (2..4 px)
      final xLt = x > 0 ? x - 1 : 0;
      final xRt = x + 1 < w ? x + 1 : w - 1;
      final gx = (lumGrid[rowOffset + xRt] - lumGrid[rowOffset + xLt]) / 255.0;
      final gy = (lumGrid[yDn * w + x] - lumGrid[yUp * w + x]) / 255.0;
      final u = x + gx * bend * 1.45 + (lumNorm - 0.5) * bend;
      final v = y + gy * bend * 1.45 + (lumNorm - 0.5) * bend;

      // Background Security Texture pixel B at displaced (u, v)
      final intensity = _evaluateGuillocheIntensity(u, v, w, h, pattern);
      final bR = paperR * intensity;
      final bG = paperG * intensity;
      final bB = paperB * intensity;

      // Stage 3: Multiply Blend Mode: Result = (P * B) / 255
      final multR = (pLum * bR) / 255.0;
      final multG = (pLum * bG) / 255.0;
      final multB = (pLum * bB) / 255.0;

      // Stage 4: Luminance Opacity (85%..90%) letting warm paper show through skin
      final outR = (multR * skinOp + paperR * invOp).clamp(0.0, 255.0).round();
      final outG = (multG * skinOp + paperG * invOp).clamp(0.0, 255.0).round();
      final outB = (multB * skinOp + paperB * invOp).clamp(0.0, 255.0).round();

      px.r = outR;
      px.g = outG;
      px.b = outB;
    }
  }
  return rgba;
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
  final rgba = removeWhiteOnImage(work, req.tolerance);
  return Uint8List.fromList(img.encodePng(rgba));
}

Future<Uint8List?> applyGuillocheBlendOffline(GuillocheRequest req) {
  return compute(_guillocheIsolate, req);
}

Uint8List? _guillocheIsolate(GuillocheRequest req) {
  final bytes = File(req.filePath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var work = decoded;
  if (work.width > 1800 || work.height > 1800) {
    work = work.width >= work.height
        ? img.copyResize(work, width: 1800)
        : img.copyResize(work, height: 1800);
  }
  if (req.removeWhiteTolerance > 0) {
    work = removeWhiteOnImage(work, req.removeWhiteTolerance);
  }
  final result = applyGuillocheBlendToImage(
    work,
    contrastPct: req.contrastPct,
    bendPx: req.bendPx,
    opacityPct: req.opacityPct,
    pattern: req.pattern,
  );
  return Uint8List.fromList(img.encodePng(result));
}

class ScanSignatureRequest {
  final String filePath;
  final double sensitivity; // 15..95
  final int? recolorArgb; // null = preserve original ink hue
  final bool autoTrim;
  final bool transparentBg;

  const ScanSignatureRequest({
    required this.filePath,
    this.sensitivity = 56.0,
    this.recolorArgb,
    this.autoTrim = true,
    this.transparentBg = true,
  });
}

Future<Uint8List?> extractScannedSignatureOffline(ScanSignatureRequest req) {
  return compute(_scanSignatureIsolate, req);
}

Uint8List? _scanSignatureIsolate(ScanSignatureRequest req) {
  final file = File(req.filePath);
  if (!file.existsSync()) return null;
  final bytes = file.readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  var work = decoded;
  if (work.width > 1500 || work.height > 1500) {
    work = work.width >= work.height
        ? img.copyResize(work, width: 1500)
        : img.copyResize(work, height: 1500);
  }
  final rgba = work.numChannels == 4 ? work.clone() : work.convert(numChannels: 4);
  final w = rgba.width;
  final h = rgba.height;
  if (w == 0 || h == 0) return null;

  // Stage 1: Coarse 18x18 block background illumination field (shadows removed cleanly)
  const gx = 18;
  const gy = 18;
  final blockMax = Float64List(gx * gy);
  final blockW = w / gx;
  final blockH = h / gy;

  for (int by = 0; by < gy; by++) {
    final y0 = (by * blockH).floor();
    final y1 = math.min(h, ((by + 1) * blockH).floor());
    for (int bx = 0; bx < gx; bx++) {
      final x0 = (bx * blockW).floor();
      final x1 = math.min(w, ((bx + 1) * blockW).floor());
      final stepY = math.max(1, (y1 - y0) ~/ 6);
      final stepX = math.max(1, (x1 - x0) ~/ 6);
      final samples = <double>[];
      for (int py = y0; py < y1; py += stepY) {
        for (int px = x0; px < x1; px += stepX) {
          final p = rgba.getPixel(px, py);
          samples.add(0.299 * p.r + 0.587 * p.g + 0.114 * p.b);
        }
      }
      double topLum = 235.0;
      if (samples.isNotEmpty) {
        samples.sort();
        final idx = math.min(samples.length - 1, (samples.length * 0.85).floor());
        topLum = samples[idx];
      }
      blockMax[by * gx + bx] = math.max(115.0, topLum);
    }
  }

  final smoothField = Float64List(gx * gy);
  double globalSum = 0.0;
  for (int by = 0; by < gy; by++) {
    for (int bx = 0; bx < gx; bx++) {
      double acc = 0.0;
      int cnt = 0;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          final ny = (by + dy).clamp(0, gy - 1);
          final nx = (bx + dx).clamp(0, gx - 1);
          acc += blockMax[ny * gx + nx];
          cnt++;
        }
      }
      final val = acc / cnt;
      smoothField[by * gx + bx] = val;
      globalSum += val;
    }
  }
  final minSafePaper = math.max(110.0, (globalSum / (gx * gy)) * 0.72);
  for (int i = 0; i < smoothField.length; i++) {
    if (smoothField[i] < minSafePaper) smoothField[i] = minSafePaper;
  }

  // Stage 2: Adaptive paper removal + optional recolor + bounding-box scan
  final sensNorm = req.sensitivity.clamp(15.0, 95.0) / 100.0;
  final paperThreshold = 0.91 - sensNorm * 0.28;
  final softWidth = 0.16 + sensNorm * 0.08;
  final tintArgb = req.recolorArgb;
  final tintR = tintArgb != null ? ((tintArgb >> 16) & 0xFF) : 0;
  final tintG = tintArgb != null ? ((tintArgb >> 8) & 0xFF) : 0;
  final tintB = tintArgb != null ? (tintArgb & 0xFF) : 0;

  int minX = w;
  int minY = h;
  int maxX = -1;
  int maxY = -1;

  for (int py = 0; py < h; py++) {
    final fy = (py / math.max(1, h)) * (gy - 1);
    final yA = fy.floor();
    final yB = math.min(gy - 1, yA + 1);
    final ty = fy - yA;

    for (int px = 0; px < w; px++) {
      final fx = (px / math.max(1, w)) * (gx - 1);
      final xA = fx.floor();
      final xB = math.min(gx - 1, xA + 1);
      final tx = fx - xA;

      final p00 = smoothField[yA * gx + xA];
      final p10 = smoothField[yA * gx + xB];
      final p01 = smoothField[yB * gx + xA];
      final p11 = smoothField[yB * gx + xB];
      final localPaper =
          (p00 * (1.0 - tx) + p10 * tx) * (1.0 - ty) +
          (p01 * (1.0 - tx) + p11 * tx) * ty;

      final p = rgba.getPixel(px, py);
      final r = p.r.toDouble();
      final g = p.g.toDouble();
      final b = p.b.toDouble();
      final lum = 0.299 * r + 0.587 * g + 0.114 * b;

      final maxC = math.max(r, math.max(g, b));
      final minC = math.min(r, math.min(g, b));
      final chroma = maxC - minC;
      final relLum = lum / math.max(90.0, localPaper) -
          (chroma > 28.0 ? (chroma - 28.0) / 280.0 : 0.0);

      int alpha = 0;
      if (relLum >= paperThreshold) {
        alpha = 0;
      } else if (relLum > paperThreshold - softWidth) {
        final u = ((paperThreshold - relLum) / softWidth).clamp(0.0, 1.0);
        final smooth = u * u * (3.0 - 2.0 * u);
        alpha = (smooth * 255.0).round();
      } else {
        alpha = 255;
      }

      if (alpha < 10) {
        p.a = 0;
      } else {
        p.a = alpha;
        if (tintArgb != null) {
          p.r = tintR;
          p.g = tintG;
          p.b = tintB;
        } else {
          final normScale = 250.0 / math.max(120.0, localPaper);
          p.r = (r * normScale * 0.9).clamp(0.0, 255.0).round();
          p.g = (g * normScale * 0.9).clamp(0.0, 255.0).round();
          p.b = (b * normScale * 0.9).clamp(0.0, 255.0).round();
        }
        if (alpha > 22) {
          if (px < minX) minX = px;
          if (px > maxX) maxX = px;
          if (py < minY) minY = py;
          if (py > maxY) maxY = py;
        }
      }
    }
  }

  // Stage 3: Auto-Trim crop + optional white-paper flattening
  final hasInk = maxX > minX && maxY > minY;
  final pad = math.max(20, (math.min(w, h) * 0.04).round());
  img.Image out = rgba;
  if (req.autoTrim && hasInk) {
    final sx = math.max(0, minX - pad);
    final sy = math.max(0, minY - pad);
    final sw = math.min(w - sx, (maxX - minX) + pad * 2);
    final sh = math.min(h - sy, (maxY - minY) + pad * 2);
    if (sw > 0 && sh > 0) {
      out = img.copyCrop(rgba, x: sx, y: sy, width: sw, height: sh);
    }
  }

  if (!req.transparentBg) {
    for (final px in out) {
      final a = px.a.toInt();
      if (a == 0) {
        px.r = 255;
        px.g = 255;
        px.b = 255;
        px.a = 255;
      } else if (a < 255) {
        final af = a / 255.0;
        final inv = 1.0 - af;
        px.r = (px.r * af + 255.0 * inv).round().clamp(0, 255);
        px.g = (px.g * af + 255.0 * inv).round().clamp(0, 255);
        px.b = (px.b * af + 255.0 * inv).round().clamp(0, 255);
        px.a = 255;
      }
    }
  }

  return Uint8List.fromList(img.encodePng(out));
}
