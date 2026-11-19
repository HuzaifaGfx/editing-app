import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/design_project.dart';
import 'filter_matrix.dart';

class LayerCanvas extends StatefulWidget {
  final DocumentPage page;
  final String? selectedLayerId;
  final GlobalKey? exportBoundaryKey;
  final bool showSelectionHandles;
  final bool showGuides;
  final bool hideOverlaysForExport;
  final bool forceTransparentBackground;
  final ValueChanged<String?> onSelectLayer;
  final ValueChanged<DesignLayer> onUpdateLayer;
  final VoidCallback? onInteractionStart;

  const LayerCanvas({
    super.key,
    required this.page,
    required this.selectedLayerId,
    this.exportBoundaryKey,
    this.showSelectionHandles = true,
    this.showGuides = true,
    this.hideOverlaysForExport = false,
    this.forceTransparentBackground = false,
    required this.onSelectLayer,
    required this.onUpdateLayer,
    this.onInteractionStart,
  });

  @override
  State<LayerCanvas> createState() => _LayerCanvasState();
}

class _LayerCanvasState extends State<LayerCanvas> {
  final TransformationController _transformController = TransformationController();
  final GlobalKey _canvasStackKey = GlobalKey();

  int _pointerCount = 0;
  bool _isPinching = false;
  double _currentZoom = 1.0;
  DateTime _lastMultiTouchAt = DateTime.fromMillisecondsSinceEpoch(0);

  double _rotateStartAngle = 0.0;
  double _rotateStartDeg = 0.0;
  Offset _rotateCenterGlobal = Offset.zero;
  bool _snapX = false;
  bool _snapY = false;

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

  Offset _layerCenterGlobal(DesignLayer layer) {
    final box = _canvasStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Offset.zero;
    return box.localToGlobal(Offset(layer.x + layer.width / 2, layer.y + layer.height / 2));
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = math.max(1.0, constraints.maxWidth - 12.0);
        final availH = math.max(1.0, constraints.maxHeight - 12.0);
        final fitScale = math.min(
          availW / math.max(1.0, page.width),
          availH / math.max(1.0, page.height),
        );
        final displayScale = (fitScale * _currentZoom).clamp(0.08, 4.0);
        final invScale = (1.0 / displayScale).clamp(0.35, 14.0);

        DesignLayer? selectedLayer;
        if (widget.showSelectionHandles && widget.selectedLayerId != null) {
          for (final l in page.layers) {
            if (l.visible && !l.isCanvasBackground && l.id == widget.selectedLayerId) {
              selectedLayer = l;
              break;
            }
          }
        }

        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _StudioStageDotGridPainter(isDark: isDark),
                ),
              ),
            ),
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
                boundaryMargin: const EdgeInsets.all(140),
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
                    padding: const EdgeInsets.all(6),
                    child: AspectRatio(
                      aspectRatio: page.width / math.max(1, page.height),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: Container(
                          decoration: widget.forceTransparentBackground
                              ? null
                              : BoxDecoration(
                                  border: Border.all(
                                    color: isDark
                                        ? const Color(0xFF2B313D)
                                        : const Color(0xFFCBD5E1),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      blurRadius: 32,
                                      spreadRadius: 2,
                                      offset: const Offset(0, 10),
                                      color: isDark
                                          ? Colors.black.withOpacity(0.65)
                                          : Colors.black.withOpacity(0.18),
                                    ),
                                  ],
                                ),
                          child: RepaintBoundary(
                            key: widget.exportBoundaryKey,
                            child: SizedBox(
                              width: page.width,
                              height: page.height,
                              child: Container(
                                color: widget.forceTransparentBackground
                                    ? Colors.transparent
                                    : page.backgroundColor,
                                child: Stack(
                                  key: _canvasStackKey,
                                  clipBehavior: Clip.none,
                                  children: [
                                    // Strictly clipped artboard surface — zero layer artwork ever escapes canvas bounds
                                    Positioned.fill(
                                      child: ClipRect(
                                        clipBehavior: Clip.hardEdge,
                                        child: Stack(
                                          clipBehavior: Clip.hardEdge,
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
                                              final selected = !widget.hideOverlaysForExport &&
                                                  widget.showSelectionHandles &&
                                                  !layer.isCanvasBackground &&
                                                  layer.id == widget.selectedLayerId;

                                              final layerChild = Transform.rotate(
                                                angle: layer.rotation * math.pi / 180.0,
                                                child: Stack(
                                                  clipBehavior: Clip.none,
                                                  children: [
                                                    Positioned.fill(
                                                      child: _LayerBlendWrapper(
                                                        blendMode: layer.blendMode,
                                                        child: Opacity(
                                                          opacity: layer.opacity.clamp(0.0, 1.0),
                                                          child: _buildLayerContent(layer),
                                                        ),
                                                      ),
                                                    ),
                                                    if (selected)
                                                      IgnorePointer(
                                                        child: Container(
                                                          decoration: BoxDecoration(
                                                            border: Border.all(
                                                              color: const Color(0xFFF59E0B),
                                                              width: (2.5 * invScale).clamp(2.0, 20.0),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
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
                                                          if (!layer.locked) widget.onInteractionStart?.call();
                                                        },
                                                        onPanUpdate: layer.locked
                                                            ? null
                                                            : (d) {
                                                                if (_blockLayerInteraction) return;
                                                                final scale = _transformController.value
                                                                    .getMaxScaleOnAxis()
                                                                    .clamp(0.5, 4.0);
                                                                final maxX = math.max(0.0, page.width - layer.width);
                                                                final maxY = math.max(0.0, page.height - layer.height);
                                                                var nextX = (layer.x + d.delta.dx / scale).clamp(0.0, maxX).toDouble();
                                                                var nextY = (layer.y + d.delta.dy / scale).clamp(0.0, maxY).toDouble();
                                                                final cx = nextX + layer.width / 2;
                                                                final cy = nextY + layer.height / 2;
                                                                const snapTol = 8.0;
                                                                final hitX = (cx - page.width / 2).abs() <= snapTol;
                                                                final hitY = (cy - page.height / 2).abs() <= snapTol;
                                                                if (hitX) nextX = (page.width / 2 - layer.width / 2).clamp(0.0, maxX).toDouble();
                                                                if (hitY) nextY = (page.height / 2 - layer.height / 2).clamp(0.0, maxY).toDouble();
                                                                layer.x = nextX;
                                                                layer.y = nextY;
                                                                if (_snapX != hitX || _snapY != hitY) {
                                                                  setState(() {
                                                                    _snapX = hitX;
                                                                    _snapY = hitY;
                                                                  });
                                                                }
                                                                widget.onUpdateLayer(layer);
                                                              },
                                                        onPanEnd: (_) {
                                                          if (_snapX || _snapY) {
                                                            setState(() {
                                                              _snapX = false;
                                                              _snapY = false;
                                                            });
                                                          }
                                                        },
                                                        child: layerChild,
                                                      ),
                                              );
                                            }),
                                            if (widget.showGuides && !widget.hideOverlaysForExport)
                                              Positioned.fill(
                                                child: IgnorePointer(
                                                  child: CustomPaint(
                                                    painter: _MarginGuidesPainter(invScale: invScale),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (_snapX && !widget.hideOverlaysForExport)
                                      Positioned(
                                        left: page.width / 2 - (1.0 * invScale),
                                        top: 0,
                                        bottom: 0,
                                        width: 2.0 * invScale,
                                        child: IgnorePointer(
                                          child: Container(color: const Color(0xFFF59E0B).withOpacity(0.85)),
                                        ),
                                      ),
                                    if (_snapY && !widget.hideOverlaysForExport)
                                      Positioned(
                                        top: page.height / 2 - (1.0 * invScale),
                                        left: 0,
                                        right: 0,
                                        height: 2.0 * invScale,
                                        child: IgnorePointer(
                                          child: Container(color: const Color(0xFFF59E0B).withOpacity(0.85)),
                                        ),
                                      ),
                                    if (!widget.hideOverlaysForExport && selectedLayer != null && !selectedLayer.locked)
                                      _buildSelectionHandlesOverlay(selectedLayer, invScale),
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
            ),
            if (selectedLayer != null && !selectedLayer.locked)
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: (isDark ? const Color(0xFF1A1E26) : Colors.white).withOpacity(0.92),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark ? const Color(0xFF2D3340) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFF59E0B), shape: BoxShape.circle)),
                          const SizedBox(width: 4),
                          Text('Scale', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black87)),
                          const SizedBox(width: 10),
                          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF0EA5E9), shape: BoxShape.circle)),
                          const SizedBox(width: 4),
                          Text('Rotate', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black87)),
                          const SizedBox(width: 10),
                          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                          const SizedBox(width: 4),
                          Text('Box Width', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black87)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 12,
              bottom: 12,
              child: Material(
                elevation: isDark ? 6 : 3,
                shadowColor: Colors.black.withOpacity(0.28),
                borderRadius: BorderRadius.circular(10),
                color: isDark
                    ? const Color(0xFF1A1E26).withOpacity(0.94)
                    : Colors.white.withOpacity(0.96),
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? const Color(0xFF2D3340) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _zoomStepBtn(
                        icon: Icons.remove_rounded,
                        tooltip: 'Zoom Out',
                        isDark: isDark,
                        onTap: () => _setZoomAroundCenter(
                          _currentZoom - 0.25,
                          constraints.maxWidth,
                          constraints.maxHeight,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 18,
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),
                      InkWell(
                        onTap: _resetZoom,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            '${(_currentZoom * 100).round()}%',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 18,
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),
                      _zoomStepBtn(
                        icon: Icons.add_rounded,
                        tooltip: 'Zoom In',
                        isDark: isDark,
                        onTap: () => _setZoomAroundCenter(
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

  Widget _zoomStepBtn({
    required IconData icon,
    required String tooltip,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(
            icon,
            size: 17,
            color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
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
        child: Transform.flip(
          flipX: layer.flipX,
          flipY: layer.flipY,
          child: ColorFiltered(
            colorFilter: buildLayerColorFilter(layer.filters),
            child: imgWidget,
          ),
        ),
      );
    }

    if (layer.type == LayerType.text) {
      final weightIndex = ((layer.fontWeight / 100).round() - 1).clamp(0, 8);
      final effectiveAlign =
          layer.textAlign ?? (layer.isRtl ? TextAlign.right : TextAlign.left);
      final alignBox = effectiveAlign == TextAlign.center
          ? Alignment.topCenter
          : (effectiveAlign == TextAlign.right ? Alignment.topRight : Alignment.topLeft);
      final hasBg = layer.textBgColor.alpha > 0;
      return Directionality(
        textDirection: layer.isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: Container(
          padding: hasBg ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8) : EdgeInsets.zero,
          decoration: hasBg
              ? BoxDecoration(
                  color: layer.textBgColor,
                  borderRadius: BorderRadius.circular(layer.borderRadius > 0 ? layer.borderRadius : 12),
                )
              : null,
          child: Align(
            alignment: alignBox,
            child: Text(
              layer.text,
              textAlign: effectiveAlign,
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

  Widget _buildSelectionHandlesOverlay(DesignLayer layer, double invScale) {
    final page = widget.page;
    final hitSize = 58.0 * invScale;
    final badgeSize = 40.0 * invScale;
    final iconSize = 22.0 * invScale;
    final ringWidth = 2.8 * invScale;
    final pad = hitSize * 0.52;

    return Positioned(
      left: layer.x - pad,
      top: layer.y - pad,
      width: layer.width + pad * 2,
      height: layer.height + pad * 2,
      child: Transform.rotate(
        angle: layer.rotation * math.pi / 180.0,
        alignment: Alignment.center,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 1. TOP-RIGHT: Big Rotate Handle (Text, Image & Shape)
            Align(
              alignment: Alignment.topRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) {
                  if (_blockLayerInteraction) return;
                  widget.onInteractionStart?.call();
                  _rotateCenterGlobal = _layerCenterGlobal(layer);
                  _rotateStartAngle = math.atan2(
                    d.globalPosition.dy - _rotateCenterGlobal.dy,
                    d.globalPosition.dx - _rotateCenterGlobal.dx,
                  );
                  _rotateStartDeg = layer.rotation;
                },
                onPanUpdate: (d) {
                  if (_blockLayerInteraction) return;
                  final curAngle = math.atan2(
                    d.globalPosition.dy - _rotateCenterGlobal.dy,
                    d.globalPosition.dx - _rotateCenterGlobal.dx,
                  );
                  var deg = _rotateStartDeg + (curAngle - _rotateStartAngle) * 180.0 / math.pi;
                  while (deg > 180.0) {
                    deg -= 360.0;
                  }
                  while (deg < -180.0) {
                    deg += 360.0;
                  }
                  final nearest90 = (deg / 90.0).round() * 90.0;
                  if ((deg - nearest90).abs() <= 3.0) {
                    deg = nearest90;
                  }
                  layer.rotation = deg;
                  widget.onUpdateLayer(layer);
                },
                child: SizedBox(
                  width: hitSize,
                  height: hitSize,
                  child: Center(
                    child: Container(
                      width: badgeSize,
                      height: badgeSize,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0EA5E9),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: ringWidth),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 6.0 * invScale,
                            offset: Offset(0, 2.0 * invScale),
                            color: Colors.black38,
                          ),
                        ],
                      ),
                      child: Icon(Icons.rotate_right_rounded, size: iconSize, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),

            // 2. BOTTOM-LEFT: Big Text Box Resize Handle (adjust W & H without scaling font size)
            if (layer.type == LayerType.text)
              Align(
                alignment: Alignment.bottomLeft,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) {
                    if (!_blockLayerInteraction) widget.onInteractionStart?.call();
                  },
                  onPanUpdate: (d) {
                    if (_blockLayerInteraction) return;
                    final scale = _transformController.value.getMaxScaleOnAxis().clamp(0.5, 4.0);
                    final rawDx = d.delta.dx / scale;
                    final rawDy = d.delta.dy / scale;
                    final rad = layer.rotation * math.pi / 180.0;
                    final localDx = rawDx * math.cos(-rad) - rawDy * math.sin(-rad);
                    final localDy = rawDx * math.sin(-rad) + rawDy * math.cos(-rad);

                    final prevW = layer.width;
                    final nextW = (prevW - localDx).clamp(60.0, math.max(60.0, page.width)).toDouble();
                    final shiftLeft = prevW - nextW;
                    final maxH = math.max(40.0, page.height - layer.y);
                    layer.x = (layer.x + shiftLeft * math.cos(rad)).clamp(0.0, math.max(0.0, page.width - nextW)).toDouble();
                    layer.y = (layer.y + shiftLeft * math.sin(rad)).clamp(0.0, math.max(0.0, page.height - 40.0)).toDouble();
                    layer.width = nextW.clamp(60.0, math.max(60.0, page.width - layer.x)).toDouble();
                    layer.height = (layer.height + localDy).clamp(40.0, math.max(40.0, page.height - layer.y)).toDouble();
                    if (layer.height > maxH) layer.height = maxH;
                    widget.onUpdateLayer(layer);
                  },
                  child: SizedBox(
                    width: hitSize,
                    height: hitSize,
                    child: Center(
                      child: Container(
                        width: badgeSize,
                        height: badgeSize,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: ringWidth),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 6.0 * invScale,
                              offset: Offset(0, 2.0 * invScale),
                              color: Colors.black38,
                            ),
                          ],
                        ),
                        child: Icon(Icons.aspect_ratio_rounded, size: iconSize * 0.92, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),

            // 3. BOTTOM-RIGHT: Big Proportional Scale Size (+/-) Handle
            Align(
              alignment: Alignment.bottomRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) {
                  if (_blockLayerInteraction) return;
                  final scale = _transformController.value.getMaxScaleOnAxis().clamp(0.5, 4.0);
                  final rawDx = d.delta.dx / scale;
                  final rawDy = d.delta.dy / scale;
                  final rad = -layer.rotation * math.pi / 180.0;
                  final dx = rawDx * math.cos(rad) - rawDy * math.sin(rad);
                  final dy = rawDx * math.sin(rad) + rawDy * math.cos(rad);

                  final availW = math.max(40.0, page.width - layer.x);
                  final availH = math.max(24.0, page.height - layer.y);
                  if (layer.type == LayerType.image && layer.aspectLocked) {
                    final ratio = layer.width / math.max(1.0, layer.height);
                    final delta = dx.abs() >= (dy * ratio).abs() ? dx : dy * ratio;
                    final maxW = math.min(availW, availH * ratio);
                    final nextW = (layer.width + delta).clamp(20.0, math.max(20.0, maxW)).toDouble();
                    final nextH = (nextW / ratio).clamp(20.0, math.max(20.0, availH)).toDouble();
                    layer.width = nextW;
                    layer.height = nextH;
                  } else if (layer.type == LayerType.text) {
                    final ratio = layer.width / math.max(1.0, layer.height);
                    final delta = dx.abs() >= (dy * ratio).abs() ? dx : dy * ratio;
                    final prevW = math.max(1.0, layer.width);
                    final maxW = math.min(availW, availH * ratio);
                    final nextW = (layer.width + delta).clamp(40.0, math.max(40.0, maxW)).toDouble();
                    final nextH = (nextW / ratio).clamp(24.0, math.max(24.0, availH)).toDouble();
                    layer.fontSize = (layer.fontSize * (nextW / prevW)).clamp(8.0, 600.0).toDouble();
                    layer.width = nextW;
                    layer.height = nextH;
                  } else {
                    layer.width = (layer.width + dx).clamp(20.0, availW).toDouble();
                    layer.height = (layer.height + dy).clamp(20.0, availH).toDouble();
                  }
                  widget.onUpdateLayer(layer);
                },
                child: SizedBox(
                  width: hitSize,
                  height: hitSize,
                  child: Center(
                    child: Container(
                      width: badgeSize,
                      height: badgeSize,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: ringWidth),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 6.0 * invScale,
                            offset: Offset(0, 2.0 * invScale),
                            color: Colors.black38,
                          ),
                        ],
                      ),
                      child: Icon(Icons.open_in_full_rounded, size: iconSize * 0.92, color: Colors.black),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LayerBlendWrapper extends SingleChildRenderObjectWidget {
  final BlendMode blendMode;
  const _LayerBlendWrapper({required this.blendMode, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLayerBlend(blendMode);

  @override
  void updateRenderObject(BuildContext context, covariant _RenderLayerBlend renderObject) {
    renderObject.blendMode = blendMode;
  }
}

class _RenderLayerBlend extends RenderProxyBox {
  BlendMode _blendMode;
  _RenderLayerBlend(this._blendMode);

  set blendMode(BlendMode value) {
    if (_blendMode == value) return;
    _blendMode = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    if (_blendMode == BlendMode.srcOver) {
      context.paintChild(child!, offset);
      return;
    }
    context.canvas.saveLayer(offset & size, Paint()..blendMode = _blendMode);
    context.paintChild(child!, offset);
    context.canvas.restore();
  }
}


class _StudioStageDotGridPainter extends CustomPainter {
  final bool isDark;
  const _StudioStageDotGridPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isDark
          ? const Color(0xFF94A3B8).withOpacity(0.12)
          : const Color(0xFF64748B).withOpacity(0.20);
    const step = 20.0;
    for (double y = step / 2; y < size.height; y += step) {
      for (double x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StudioStageDotGridPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}


class _MarginGuidesPainter extends CustomPainter {
  final double invScale;
  const _MarginGuidesPainter({required this.invScale});

  @override
  void paint(Canvas canvas, Size size) {
    final margin = math.min(size.width, size.height) * 0.06;
    if (margin <= 2) return;
    final strokeW = (1.15 * invScale).clamp(0.75, 2.5);
    final paint = Paint()
      ..color = const Color(0xFF06B6D4).withOpacity(0.55)
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke;

    final rect = Rect.fromLTWH(
      margin,
      margin,
      size.width - margin * 2,
      size.height - margin * 2,
    );

    final dash = 8.0 * invScale.clamp(0.5, 2.5);
    final gap = 6.0 * invScale.clamp(0.5, 2.5);
    _drawDashedLine(canvas, rect.topLeft, rect.topRight, paint, dash, gap);
    _drawDashedLine(canvas, rect.topRight, rect.bottomRight, paint, dash, gap);
    _drawDashedLine(canvas, rect.bottomRight, rect.bottomLeft, paint, dash, gap);
    _drawDashedLine(canvas, rect.bottomLeft, rect.topLeft, paint, dash, gap);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint, double dash, double gap) {
    final delta = end - start;
    final dist = delta.distance;
    if (dist <= 0) return;
    final dir = delta / dist;
    double d = 0;
    while (d < dist) {
      final segEnd = math.min(dist, d + dash);
      canvas.drawLine(start + dir * d, start + dir * segEnd, paint);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _MarginGuidesPainter oldDelegate) =>
      oldDelegate.invScale != invScale;
}
