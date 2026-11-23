import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageCropResult {
  final String filePath;
  final int width;
  final int height;

  const ImageCropResult({
    required this.filePath,
    required this.width,
    required this.height,
  });
}

Future<ImageCropResult?> showImageCropSheet(
  BuildContext context, {
  required String imagePath,
}) {
  return showModalBottomSheet<ImageCropResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ImageCropSheet(imagePath: imagePath),
  );
}

class _CropIsolateArgs {
  final Uint8List rawBytes;
  final String sourceExt;
  final int quarterTurns;
  final double nx;
  final double ny;
  final double nw;
  final double nh;

  const _CropIsolateArgs({
    required this.rawBytes,
    required this.sourceExt,
    required this.quarterTurns,
    required this.nx,
    required this.ny,
    required this.nw,
    required this.nh,
  });
}

class _CropIsolateOutput {
  final Uint8List bytes;
  final String ext;
  final int width;
  final int height;

  const _CropIsolateOutput({
    required this.bytes,
    required this.ext,
    required this.width,
    required this.height,
  });
}

_CropIsolateOutput? _applyCropRotateIsolate(_CropIsolateArgs args) {
  var decoded = img.decodeImage(args.rawBytes);
  if (decoded == null) return null;
  decoded = img.bakeOrientation(decoded);
  final turns = args.quarterTurns % 4;
  if (turns != 0) {
    decoded = img.copyRotate(decoded, angle: turns * 90);
  }
  final srcW = math.max(1, decoded.width);
  final srcH = math.max(1, decoded.height);
  final x = (args.nx.clamp(0.0, 0.98) * srcW).round().clamp(0, srcW - 1);
  final y = (args.ny.clamp(0.0, 0.98) * srcH).round().clamp(0, srcH - 1);
  final w = (args.nw.clamp(0.02, 1.0) * srcW).round().clamp(1, srcW - x);
  final h = (args.nh.clamp(0.02, 1.0) * srcH).round().clamp(1, srcH - y);

  final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
  final preferPng = args.sourceExt == '.png' || cropped.numChannels == 4;
  final outBytes = preferPng
      ? Uint8List.fromList(img.encodePng(cropped))
      : Uint8List.fromList(img.encodeJpg(cropped, quality: 94));
  return _CropIsolateOutput(
    bytes: outBytes,
    ext: preferPng ? '.png' : '.jpg',
    width: cropped.width,
    height: cropped.height,
  );
}

class _ImageCropSheet extends StatefulWidget {
  final String imagePath;

  const _ImageCropSheet({required this.imagePath});

  @override
  State<_ImageCropSheet> createState() => _ImageCropSheetState();
}

class _ImageCropSheetState extends State<_ImageCropSheet> {
  ui.Image? _decodedPreview;
  bool _loading = true;
  bool _applying = false;
  int _quarterTurns = 0;
  double? _aspectRatio; // null = free, 1.0 = 1:1, 0.8 = 4:5
  Rect _normCrop = const Rect.fromLTWH(0.06, 0.06, 0.88, 0.88);
  String? _dragMode; // 'move', 'tl', 'tr', 'bl', 'br'
  Offset _dragStartLocal = Offset.zero;
  Rect _dragStartCrop = Rect.zero;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void dispose() {
    _decodedPreview?.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    try {
      final f = File(widget.imagePath);
      if (!f.existsSync()) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final bytes = await f.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1080);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _decodedPreview = frame.image;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Size get _effectiveImageSize {
    final im = _decodedPreview;
    if (im == null) return const Size(1, 1);
    final w = im.width.toDouble();
    final h = im.height.toDouble();
    return _quarterTurns.isOdd ? Size(h, w) : Size(w, h);
  }

  void _setAspect(double? ratio) {
    setState(() {
      _aspectRatio = ratio;
      if (ratio == null) return;
      final imgSize = _effectiveImageSize;
      final imgAspect = imgSize.width / math.max(1.0, imgSize.height);
      final normTarget = ratio / imgAspect;
      double nw = 0.84;
      double nh = nw / math.max(0.05, normTarget);
      if (nh > 0.88) {
        nh = 0.88;
        nw = nh * normTarget;
      }
      nw = nw.clamp(0.15, 0.96);
      nh = nh.clamp(0.15, 0.96);
      _normCrop = Rect.fromCenter(
        center: const Offset(0.5, 0.5),
        width: nw,
        height: nh,
      );
    });
  }

  void _rotate90() {
    setState(() {
      _quarterTurns = (_quarterTurns + 1) % 4;
      _normCrop = const Rect.fromLTWH(0.06, 0.06, 0.88, 0.88);
    });
    if (_aspectRatio != null) {
      _setAspect(_aspectRatio);
    }
  }

  void _handleDragStart(Offset localPos, Rect imageRect) {
    final cropRect = Rect.fromLTWH(
      imageRect.left + _normCrop.left * imageRect.width,
      imageRect.top + _normCrop.top * imageRect.height,
      _normCrop.width * imageRect.width,
      _normCrop.height * imageRect.height,
    );
    const hitR = 28.0;
    if ((localPos - cropRect.topLeft).distance <= hitR) {
      _dragMode = 'tl';
    } else if ((localPos - cropRect.topRight).distance <= hitR) {
      _dragMode = 'tr';
    } else if ((localPos - cropRect.bottomLeft).distance <= hitR) {
      _dragMode = 'bl';
    } else if ((localPos - cropRect.bottomRight).distance <= hitR) {
      _dragMode = 'br';
    } else if (cropRect.contains(localPos)) {
      _dragMode = 'move';
    } else {
      _dragMode = null;
    }
    _dragStartLocal = localPos;
    _dragStartCrop = _normCrop;
  }

  void _handleDragUpdate(Offset localPos, Rect imageRect) {
    if (_dragMode == null || imageRect.width <= 1 || imageRect.height <= 1) {
      return;
    }
    final dx = (localPos.dx - _dragStartLocal.dx) / imageRect.width;
    final dy = (localPos.dy - _dragStartLocal.dy) / imageRect.height;
    const minSize = 0.14;
    final start = _dragStartCrop;

    if (_dragMode == 'move') {
      final nl = (start.left + dx).clamp(0.0, 1.0 - start.width);
      final nt = (start.top + dy).clamp(0.0, 1.0 - start.height);
      setState(() {
        _normCrop = Rect.fromLTWH(nl, nt, start.width, start.height);
      });
      return;
    }

    double left = start.left;
    double top = start.top;
    double right = start.right;
    double bottom = start.bottom;

    if (_dragMode == 'tl' || _dragMode == 'bl') {
      left = (start.left + dx).clamp(0.0, right - minSize);
    }
    if (_dragMode == 'tr' || _dragMode == 'br') {
      right = (start.right + dx).clamp(left + minSize, 1.0);
    }
    if (_dragMode == 'tl' || _dragMode == 'tr') {
      top = (start.top + dy).clamp(0.0, bottom - minSize);
    }
    if (_dragMode == 'bl' || _dragMode == 'br') {
      bottom = (start.bottom + dy).clamp(top + minSize, 1.0);
    }

    if (_aspectRatio != null) {
      final imgSize = _effectiveImageSize;
      final imgAspect = imgSize.width / math.max(1.0, imgSize.height);
      final normTarget = _aspectRatio! / imgAspect;
      double w = right - left;
      double h = w / math.max(0.05, normTarget);
      if (h < minSize) {
        h = minSize;
        w = h * normTarget;
      }
      if (_dragMode == 'tl' || _dragMode == 'tr') {
        if (bottom - h < 0) {
          h = bottom;
          w = h * normTarget;
        }
        top = bottom - h;
      } else {
        if (top + h > 1.0) {
          h = 1.0 - top;
          w = h * normTarget;
        }
        bottom = top + h;
      }
      if (_dragMode == 'tl' || _dragMode == 'bl') {
        if (right - w < 0) {
          w = right;
          h = w / normTarget;
          if (_dragMode == 'tl') top = bottom - h;
        }
        left = right - w;
      } else {
        if (left + w > 1.0) {
          w = 1.0 - left;
          h = w / normTarget;
          if (_dragMode == 'tr') top = bottom - h;
        }
        right = left + w;
      }
    }

    setState(() {
      _normCrop = Rect.fromLTRB(
        left.clamp(0.0, 1.0 - minSize),
        top.clamp(0.0, 1.0 - minSize),
        right.clamp(minSize, 1.0),
        bottom.clamp(minSize, 1.0),
      );
    });
  }

  Future<void> _apply() async {
    if (_applying) return;
    setState(() => _applying = true);
    try {
      final rawBytes = await File(widget.imagePath).readAsBytes();
      final out = await compute(
        _applyCropRotateIsolate,
        _CropIsolateArgs(
          rawBytes: rawBytes,
          sourceExt: p.extension(widget.imagePath).toLowerCase(),
          quarterTurns: _quarterTurns,
          nx: _normCrop.left,
          ny: _normCrop.top,
          nw: _normCrop.width,
          nh: _normCrop.height,
        ),
      );
      if (out == null) {
        if (mounted) Navigator.pop(context);
        return;
      }
      final docsDir = await getApplicationDocumentsDirectory();
      final imgDir = Directory(p.join(docsDir.path, 'qalamix_images'));
      if (!imgDir.existsSync()) imgDir.createSync(recursive: true);
      final outPath = p.join(
        imgDir.path,
        'crop_${DateTime.now().microsecondsSinceEpoch}${out.ext}',
      );
      await File(outPath).writeAsBytes(out.bytes);
      if (!mounted) return;
      Navigator.pop(
        context,
        ImageCropResult(
          filePath: outPath,
          width: out.width,
          height: out.height,
        ),
      );
    } catch (_) {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF1E222B) : Colors.white;
    final stageBg = isDark ? const Color(0xFF12141A) : const Color(0xFFE6E1D6);
    final border = isDark ? const Color(0xFF2C313C) : const Color(0xFFE7E2D8);
    final sub = isDark ? const Color(0xFF94A3B8) : const Color(0xFF57534E);
    final chipBg = isDark ? const Color(0xFF262B36) : const Color(0xFFF3F0E9);
    final selChipBg = isDark ? const Color(0xFFF59E0B).withOpacity(0.18) : const Color(0xFFFFF6E0);
    final selChipBorder = isDark ? const Color(0xFFFBBF24) : const Color(0xFFF59E0B);
    final selChipFg = isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
    const amber = Color(0xFFF59E0B);
    const onAmber = Color(0xFF1C1917);

    Widget aspectBtn(String label, double? ratio) {
      final sel = (_aspectRatio == null && ratio == null) ||
          (_aspectRatio != null && ratio != null && (_aspectRatio! - ratio).abs() < 0.01);
      return InkWell(
        onTap: () => _setAspect(ratio),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: sel ? selChipBg : chipBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? selChipBorder : border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: sel ? selChipFg : (isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1C1917)),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: sub.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Crop & Rotate Image',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _applying ? null : _rotate90,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: border),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.rotate_90_degrees_cw_rounded, size: 17),
                    label: const Text('Rotate 90°', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                height: math.min(360, MediaQuery.of(context).size.height * 0.44),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: stageBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border),
                ),
                clipBehavior: Clip.antiAlias,
                child: _loading || _decodedPreview == null
                    ? const Center(child: CircularProgressIndicator(color: amber))
                    : LayoutBuilder(
                        builder: (ctx, box) {
                          final eff = _effectiveImageSize;
                          const pad = 14.0;
                          final availW = math.max(1.0, box.maxWidth - pad * 2);
                          final availH = math.max(1.0, box.maxHeight - pad * 2);
                          final scale = math.min(availW / eff.width, availH / eff.height);
                          final drawW = eff.width * scale;
                          final drawH = eff.height * scale;
                          final imageRect = Rect.fromLTWH(
                            (box.maxWidth - drawW) / 2,
                            (box.maxHeight - drawH) / 2,
                            drawW,
                            drawH,
                          );
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (d) => _handleDragStart(d.localPosition, imageRect),
                            onPanUpdate: (d) => _handleDragUpdate(d.localPosition, imageRect),
                            onPanEnd: (_) => _dragMode = null,
                            child: CustomPaint(
                              painter: _CropPreviewPainter(
                                image: _decodedPreview!,
                                quarterTurns: _quarterTurns,
                                imageRect: imageRect,
                                normCrop: _normCrop,
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  aspectBtn('Free', null),
                  const SizedBox(width: 8),
                  aspectBtn('1:1', 1.0),
                  const SizedBox(width: 8),
                  aspectBtn('4:5', 0.8),
                  const Spacer(),
                  Text(
                    'Drag corners to crop',
                    style: TextStyle(fontSize: 11.5, color: sub),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _applying ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: BorderSide(color: border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _applying || _decodedPreview == null ? null : _apply,
                      style: FilledButton.styleFrom(
                        backgroundColor: amber,
                        foregroundColor: onAmber,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _applying
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: onAmber),
                            )
                          : const Icon(Icons.check_rounded, size: 18, color: onAmber),
                      label: Text(
                        _applying ? 'Applying...' : 'Apply Crop',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CropPreviewPainter extends CustomPainter {
  final ui.Image image;
  final int quarterTurns;
  final Rect imageRect;
  final Rect normCrop;

  const _CropPreviewPainter({
    required this.image,
    required this.quarterTurns,
    required this.imageRect,
    required this.normCrop,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = imageRect.center;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(quarterTurns * math.pi / 2);
    final rawW = quarterTurns.isOdd ? imageRect.height : imageRect.width;
    final rawH = quarterTurns.isOdd ? imageRect.width : imageRect.height;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(-rawW / 2, -rawH / 2, rawW, rawH),
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();

    final crop = Rect.fromLTWH(
      imageRect.left + normCrop.left * imageRect.width,
      imageRect.top + normCrop.top * imageRect.height,
      normCrop.width * imageRect.width,
      normCrop.height * imageRect.height,
    );

    final scrimPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(imageRect)
      ..addRect(crop);
    canvas.drawPath(scrimPath, Paint()..color = Colors.black.withOpacity(0.56));

    // Rule-of-thirds grid
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.32)
      ..strokeWidth = 0.8;
    for (int i = 1; i <= 2; i++) {
      final gx = crop.left + crop.width * (i / 3.0);
      final gy = crop.top + crop.height * (i / 3.0);
      canvas.drawLine(Offset(gx, crop.top), Offset(gx, crop.bottom), gridPaint);
      canvas.drawLine(Offset(crop.left, gy), Offset(crop.right, gy), gridPaint);
    }

    canvas.drawRect(
      crop,
      Paint()
        ..color = const Color(0xFFF59E0B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    final handlePaint = Paint()..color = const Color(0xFFF59E0B);
    final handleStroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    for (final pt in [crop.topLeft, crop.topRight, crop.bottomLeft, crop.bottomRight]) {
      canvas.drawCircle(pt, 7.5, handlePaint);
      canvas.drawCircle(pt, 7.5, handleStroke);
    }
  }

  @override
  bool shouldRepaint(covariant _CropPreviewPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.quarterTurns != quarterTurns ||
      oldDelegate.imageRect != imageRect ||
      oldDelegate.normCrop != normCrop;
}
