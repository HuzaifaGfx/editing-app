import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FontVariation;
import 'package:flutter/material.dart';
import '../models/design_project.dart';
import 'filter_matrix.dart';

class LayerCanvas extends StatelessWidget {
  final DocumentPage page;
  final String? selectedLayerId;
  final GlobalKey? exportBoundaryKey;
  final bool showSelectionHandles;
  final ValueChanged<String?> onSelectLayer;
  final ValueChanged<DesignLayer> onUpdateLayer;

  const LayerCanvas({
    super.key,
    required this.page,
    required this.selectedLayerId,
    this.exportBoundaryKey,
    this.showSelectionHandles = true,
    required this.onSelectLayer,
    required this.onUpdateLayer,
  });

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      panEnabled: false,
      scaleEnabled: true,
      minScale: 0.85,
      maxScale: 3.0,
      boundaryMargin: EdgeInsets.zero,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: AspectRatio(
            aspectRatio: page.width / math.max(1, page.height),
            child: FittedBox(
              fit: BoxFit.contain,
              child: RepaintBoundary(
                key: exportBoundaryKey,
                child: SizedBox(
                  width: page.width,
                  height: page.height,
                  child: Container(
                    decoration: BoxDecoration(
                      color: page.backgroundColor,
                      boxShadow: const [BoxShadow(blurRadius: 24, color: Colors.black54)],
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () => onSelectLayer(null),
                          ),
                        ),
                        ...page.layers.where((l) => l.visible).map((layer) {
                          final selected = showSelectionHandles &&
                              !layer.isCanvasBackground &&
                              layer.id == selectedLayerId;

                          final layerChild = Transform.rotate(
                            angle: layer.rotation * math.pi / 180.0,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned.fill(
                                  child: Opacity(
                                    opacity: layer.opacity.clamp(0.0, 1.0),
                                    child: _buildLayerContent(layer),
                                  ),
                                ),
                                if (selected) _buildTouchHandles(layer),
                              ],
                            ),
                          );

                          return Positioned(
                            left: layer.x,
                            top: layer.y,
                            width: layer.width,
                            height: layer.height,
                            child: layer.isCanvasBackground
                                ? IgnorePointer(ignoring: true, child: layerChild)
                                : GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => onSelectLayer(layer.id),
                                    onPanStart: (_) => onSelectLayer(layer.id),
                                    onPanUpdate: layer.locked
                                        ? null
                                        : (d) {
                                            layer.x += d.delta.dx;
                                            layer.y += d.delta.dy;
                                            onUpdateLayer(layer);
                                          },
                                    child: layerChild,
                                  ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLayerContent(DesignLayer layer) {
    if (layer.type == LayerType.image) {
      Widget? imgWidget;
      final fit = layer.aspectLocked ? layer.objectFit : BoxFit.fill;

      if (layer.processedWhiteRemovedBytes != null) {
        imgWidget = Image.memory(
          layer.processedWhiteRemovedBytes!,
          fit: fit,
          colorBlendMode: layer.blendMode,
          gaplessPlayback: true,
        );
      } else if (layer.localImagePath != null && File(layer.localImagePath!).existsSync()) {
        imgWidget = Image.file(
          File(layer.localImagePath!),
          fit: fit,
          colorBlendMode: layer.blendMode,
        );
      }

      if (imgWidget == null) {
        return Container(
          color: const Color(0xFF262B35),
          child: const Center(child: Icon(Icons.image_outlined, size: 48, color: Colors.white54)),
        );
      }

      return ClipRRect(
        borderRadius: BorderRadius.circular(layer.borderRadius),
        child: ColorFiltered(
          colorFilter: buildLayerColorFilter(layer.filters),
          child: imgWidget,
        ),
      );
    }

    if (layer.type == LayerType.text) {
      return Directionality(
        textDirection: layer.isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: Align(
          alignment: layer.isRtl ? Alignment.topRight : Alignment.topLeft,
          child: Text(
            layer.text,
            textAlign: layer.isRtl ? TextAlign.right : TextAlign.left,
            style: TextStyle(
              fontFamily: layer.fontFamily,
              fontSize: layer.fontSize,
              fontWeight: FontWeight.values[((layer.fontWeight / 100).round() - 1).clamp(0, 8)],
              fontVariations: [FontVariation('wght', layer.fontWeight.toDouble())],
              height: layer.lineHeight,
              color: layer.textColor,
              shadows: const [],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: layer.textColor,
        borderRadius: BorderRadius.circular(layer.borderRadius),
      ),
    );
  }

  Widget _buildTouchHandles(DesignLayer layer) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFF59E0B), width: 3),
      ),
      child: layer.locked
          ? const SizedBox.shrink()
          : Align(
              alignment: Alignment.bottomRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) {
                  if (layer.type == LayerType.image && layer.aspectLocked) {
                    final ratio = layer.width / math.max(1.0, layer.height);
                    final delta = d.delta.dx.abs() >= (d.delta.dy * ratio).abs()
                        ? d.delta.dx
                        : d.delta.dy * ratio;
                    final nextW = (layer.width + delta).clamp(48.0, 4000.0);
                    final nextH = (nextW / ratio).clamp(48.0, 4000.0);
                    layer.width = nextW;
                    layer.height = nextH;
                  } else if (layer.type == LayerType.text) {
                    final ratio = layer.width / math.max(1.0, layer.height);
                    final delta = d.delta.dx.abs() >= (d.delta.dy * ratio).abs()
                        ? d.delta.dx
                        : d.delta.dy * ratio;
                    final prevW = math.max(1.0, layer.width);
                    final nextW = (layer.width + delta).clamp(60.0, 4000.0);
                    final nextH = (nextW / ratio).clamp(36.0, 4000.0);
                    layer.fontSize = (layer.fontSize * (nextW / prevW)).clamp(10.0, 220.0);
                    layer.width = nextW;
                    layer.height = nextH;
                  } else {
                    layer.width = (layer.width + d.delta.dx).clamp(48.0, 4000.0);
                    layer.height = (layer.height + d.delta.dy).clamp(48.0, 4000.0);
                  }
                  onUpdateLayer(layer);
                },
                child: const SizedBox(
                  width: 56,
                  height: 56,
                  child: Center(
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: Color(0xFFF59E0B),
                      child: Icon(Icons.open_in_full, size: 14, color: Colors.black),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
