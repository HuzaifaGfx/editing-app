import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/design_project.dart';
import 'filter_matrix.dart';

class LayerCanvas extends StatefulWidget {
  final DocumentPage page;
  final String? selectedLayerId;
  final GlobalKey? exportBoundaryKey;
  final bool showSelectionHandles;
  final bool forceTransparentBackground;
  final ValueChanged<String?> onSelectLayer;
  final ValueChanged<DesignLayer> onUpdateLayer;

  const LayerCanvas({
    super.key,
    required this.page,
    required this.selectedLayerId,
    this.exportBoundaryKey,
    this.showSelectionHandles = true,
    this.forceTransparentBackground = false,
    required this.onSelectLayer,
    required this.onUpdateLayer,
  });

  @override
  State<LayerCanvas> createState() => _LayerCanvasState();
}

class _LayerCanvasState extends State<LayerCanvas> {
  final TransformationController _transformController = TransformationController();
  int _pointerCount = 0;
  bool _isPinching = false;
  double _currentZoom = 1.0;
  DateTime _lastMultiTouchAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _blockLayerInteraction =>
      _pointerCount > 1 ||
      _isPinching ||
      DateTime.now().difference(_lastMultiTouchAt).inMilliseconds < 320;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _setZoomAroundCenter(double nextZoom, double vw, double vh) {
    final clamped = nextZoom.clamp(0.5, 3.5).toDouble();
    final cur = _transformController.value.clone();
    final curScale = cur.getMaxScaleOnAxis();
    final ratio = clamped / (curScale <= 0 ? 1.0 : curScale);
    final cx = vw / 2.0;
    final cy = vh / 2.0;
    final nextMatrix = Matrix4.identity()
      ..translate(cx, cy)
      ..scale(ratio)
      ..translate(-cx, -cy)
      ..multiply(cur);
    setState(() {
      _currentZoom = clamped;
      _transformController.value = nextMatrix;
    });
  }

  void _resetZoom() {
    setState(() {
      _currentZoom = 1.0;
      _transformController.value = Matrix4.identity();
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                _pointerCount++;
                if (_pointerCount > 1) {
                  setState(() {
                    _isPinching = true;
                    _lastMultiTouchAt = DateTime.now();
                  });
                }
              },
              onPointerUp: (_) {
                _pointerCount = math.max(0, _pointerCount - 1);
                if (_pointerCount <= 1 && _isPinching) {
                  setState(() {
                    _lastMultiTouchAt = DateTime.now();
                    _isPinching = false;
                  });
                }
              },
              onPointerCancel: (_) {
                _pointerCount = math.max(0, _pointerCount - 1);
                if (_pointerCount <= 1 && _isPinching) {
                  setState(() {
                    _lastMultiTouchAt = DateTime.now();
                    _isPinching = false;
                  });
                }
              },
              child: InteractiveViewer(
                transformationController: _transformController,
                panEnabled: _pointerCount > 1 || _currentZoom > 1.02,
                scaleEnabled: true,
                minScale: 0.5,
                maxScale: 3.5,
                boundaryMargin: EdgeInsets.zero,
                onInteractionStart: (details) {
                  if (details.pointerCount > 1) {
                    setState(() {
                      _isPinching = true;
                      _lastMultiTouchAt = DateTime.now();
                    });
                  }
                },
                onInteractionUpdate: (_) {
                  final nextZoom = _transformController.value.getMaxScaleOnAxis();
                  if ((nextZoom - _currentZoom).abs() > 0.02) {
                    setState(() => _currentZoom = nextZoom);
                  }
                },
                onInteractionEnd: (_) {
                  final nextZoom = _transformController.value.getMaxScaleOnAxis();
                  setState(() {
                    _currentZoom = nextZoom;
                    if (_isPinching) {
                      _lastMultiTouchAt = DateTime.now();
                      _isPinching = false;
                    }
                  });
                },
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: AspectRatio(
                      aspectRatio: page.width / math.max(1, page.height),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: RepaintBoundary(
                          key: widget.exportBoundaryKey,
                          child: SizedBox(
                            width: page.width,
                            height: page.height,
                            child: Container(
                              decoration: BoxDecoration(
                                color: widget.forceTransparentBackground
                                    ? Colors.transparent
                                    : page.backgroundColor,
                                boxShadow: widget.forceTransparentBackground
                                    ? null
                                    : const [BoxShadow(blurRadius: 24, color: Colors.black54)],
                              ),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: () {
                                if (_blockLayerInteraction) return;
                                widget.onSelectLayer(null);
                              },
                            ),
                          ),
                          ...page.layers.where((l) => l.visible).map((layer) {
                            final selected = widget.showSelectionHandles &&
                                !layer.isCanvasBackground &&
                                layer.id == widget.selectedLayerId;

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
                                      onTap: () {
                                        if (_blockLayerInteraction) return;
                                        widget.onSelectLayer(layer.id);
                                      },
                                      onPanStart: (_) {
                                        if (_blockLayerInteraction) return;
                                        widget.onSelectLayer(layer.id);
                                      },
                                      onPanUpdate: layer.locked
                                          ? null
                                          : (d) {
                                              if (_blockLayerInteraction) return;
                                              final scale = _transformController.value
                                                  .getMaxScaleOnAxis()
                                                  .clamp(0.5, 4.0);
                                              layer.x += d.delta.dx / scale;
                                              layer.y += d.delta.dy / scale;
                                              widget.onUpdateLayer(layer);
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
      ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                color: isDark
                    ? const Color(0xFF16191E).withOpacity(0.92)
                    : Colors.white.withOpacity(0.95),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Zoom Out',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.zoom_out_rounded, size: 19),
                        onPressed: () => _setZoomAroundCenter(
                          _currentZoom - 0.25,
                          constraints.maxWidth,
                          constraints.maxHeight,
                        ),
                      ),
                      InkWell(
                        onTap: _resetZoom,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                          child: Text(
                            '${(_currentZoom * 100).round()}%',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Zoom In',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.zoom_in_rounded, size: 19),
                        onPressed: () => _setZoomAroundCenter(
                          _currentZoom + 0.25,
                          constraints.maxWidth,
                          constraints.maxHeight,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
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
      final weightIndex = ((layer.fontWeight / 100).round() - 1).clamp(0, 8);
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
              fontWeight: FontWeight.values[weightIndex],
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
                  if (_blockLayerInteraction) return;
                  final scale = _transformController.value.getMaxScaleOnAxis().clamp(0.5, 4.0);
                  final dx = d.delta.dx / scale;
                  final dy = d.delta.dy / scale;
                  if (layer.type == LayerType.image && layer.aspectLocked) {
                    final ratio = layer.width / math.max(1.0, layer.height);
                    final delta = dx.abs() >= (dy * ratio).abs() ? dx : dy * ratio;
                    final nextW = (layer.width + delta).clamp(4.0, 10000.0);
                    final nextH = (nextW / ratio).clamp(4.0, 10000.0);
                    layer.width = nextW;
                    layer.height = nextH;
                  } else if (layer.type == LayerType.text) {
                    final ratio = layer.width / math.max(1.0, layer.height);
                    final delta = dx.abs() >= (dy * ratio).abs() ? dx : dy * ratio;
                    final prevW = math.max(1.0, layer.width);
                    final nextW = (layer.width + delta).clamp(4.0, 10000.0);
                    final nextH = (nextW / ratio).clamp(4.0, 10000.0);
                    layer.fontSize = (layer.fontSize * (nextW / prevW)).clamp(4.0, 800.0);
                    layer.width = nextW;
                    layer.height = nextH;
                  } else {
                    layer.width = (layer.width + dx).clamp(4.0, 10000.0);
                    layer.height = (layer.height + dy).clamp(4.0, 10000.0);
                  }
                  widget.onUpdateLayer(layer);
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
