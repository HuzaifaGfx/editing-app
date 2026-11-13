import 'dart:io';
import 'package:flutter/material.dart';
import '../models/design_project.dart';
import 'filter_matrix.dart';

class LayerCanvas extends StatelessWidget {
  final DocumentPage page;
  final String? selectedLayerId;
  final ValueChanged<String?> onSelectLayer;
  final ValueChanged<DesignLayer> onUpdateLayer;

  const LayerCanvas({
    super.key,
    required this.page,
    required this.selectedLayerId,
    required this.onSelectLayer,
    required this.onUpdateLayer,
  });

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.35,
      maxScale: 4.0,
      boundaryMargin: const EdgeInsets.all(120),
      child: Center(
        child: AspectRatio(
          aspectRatio: page.width / page.height,
          child: Container(
            decoration: BoxDecoration(
              color: page.backgroundColor,
              boxShadow: const [BoxShadow(blurRadius: 32, color: Colors.black54)],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: GestureDetector(onTap: () => onSelectLayer(null)),
                ),
                ...page.layers.where((l) => l.visible).map((layer) {
                  final selected = layer.id == selectedLayerId;
                  return Positioned(
                    left: layer.x,
                    top: layer.y,
                    width: layer.width,
                    height: layer.height,
                    child: Transform.rotate(
                      angle: layer.rotation * 3.14159265 / 180.0,
                      child: GestureDetector(
                        onTap: () => onSelectLayer(layer.id),
                        onPanUpdate: layer.locked
                            ? null
                            : (d) {
                                layer.x += d.delta.dx;
                                layer.y += d.delta.dy;
                                onUpdateLayer(layer);
                              },
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
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLayerContent(DesignLayer layer) {
    if (layer.type == LayerType.image && layer.localImagePath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(layer.borderRadius),
        child: ColorFiltered(
          colorFilter: buildLayerColorFilter(layer.filters),
          child: Image.file(
            File(layer.localImagePath!),
            fit: BoxFit.cover,
            colorBlendMode: layer.blendMode,
          ),
        ),
      );
    }

    if (layer.type == LayerType.text) {
      return Directionality(
        textDirection: layer.isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: Text(
          layer.text,
          textAlign: layer.isRtl ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            fontFamily: layer.fontFamily,
            fontSize: layer.fontSize,
            height: layer.lineHeight,
            color: layer.textColor,
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
        border: Border.all(color: const Color(0xFFF59E0B), width: 2),
      ),
      child: Align(
        alignment: Alignment.bottomRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) {
            layer.width = (layer.width + d.delta.dx).clamp(48, 2000);
            layer.height = (layer.height + d.delta.dy).clamp(48, 2000);
            onUpdateLayer(layer);
          },
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: CircleAvatar(
                radius: 10,
                backgroundColor: Color(0xFFF59E0B),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
