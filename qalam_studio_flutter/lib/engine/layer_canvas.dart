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
        final availW = math.max(1.0, constraints.maxWidth - 32.0);
        final availH = math.max(1.0, constraints.maxHeight - 32.0);
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
                    padding: const EdgeInsets.all(16),
                    child: AspectRatio(
                      aspectRatio: page.width / math.max(1, page.height),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: Container(
                          decoration: widget.forceTransparentBackground
                              ? null
                              : BoxDecoration(
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
                                                        var nextX = layer.x + d.delta.dx / scale;
                                                        var nextY = layer.y + d.delta.dy / scale;
                                                        final cx = nextX + layer.width / 2;
                                                        final cy = nextY + layer.height / 2;
                                                        const snapTol = 8.0;
                                                        final hitX = (cx - page.width / 2).abs() <= snapTol;
                                                        final hitY = (cy - page.height / 2).abs() <= snapTol;
                                                        if (hitX) nextX = page.width / 2 - layer.width / 2;
                                                        if (hitY) nextY = page.height / 2 - layer.height / 2;
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
                                    if (_snapX)
                                      Positioned(
                                        left: page.width / 2 - (1.0 * invScale),
                                        top: 0,
                                        bottom: 0,
                                        width: 2.0 * invScale,
                                        child: IgnorePointer(
                                          child: Container(color: const Color(0xFFF59E0B).withOpacity(0.85)),
                                        ),
                                      ),
                                    if (_snapY)
                                      Positioned(
                                        top: page.height / 2 - (1.0 * invScale),
                                        left: 0,
                                        right: 0,
                                        height: 2.0 * invScale,
                                        child: IgnorePointer(
                                          child: Container(color: const Color(0xFFF59E0B).withOpacity(0.85)),
                                        ),
                                      ),
                                    if (selectedLayer != null && !selectedLayer.locked)
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
                    final nextW = (prevW - localDx).clamp(60.0, 10000.0);
                    final shiftLeft = prevW - nextW;
                    layer.x += shiftLeft * math.cos(rad);
                    layer.y += shiftLeft * math.sin(rad);
                    layer.width = nextW;
                    layer.height = (layer.height + localDy).clamp(40.0, 10000.0);
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

                  if (layer.type == LayerType.image && layer.aspectLocked) {
                    final ratio = layer.width / math.max(1.0, layer.height);
                    final delta = dx.abs() >= (dy * ratio).abs() ? dx : dy * ratio;
                    final nextW = (layer.width + delta).clamp(20.0, 10000.0);
                    final nextH = (nextW / ratio).clamp(20.0, 10000.0);
                    layer.width = nextW;
                    layer.height = nextH;
                  } else if (layer.type == LayerType.text) {
                    final ratio = layer.width / math.max(1.0, layer.height);
                    final delta = dx.abs() >= (dy * ratio).abs() ? dx : dy * ratio;
                    final prevW = math.max(1.0, layer.width);
                    final nextW = (layer.width + delta).clamp(40.0, 10000.0);
                    final nextH = (nextW / ratio).clamp(24.0, 10000.0);
                    layer.fontSize = (layer.fontSize * (nextW / prevW)).clamp(8.0, 600.0);
                    layer.width = nextW;
                    layer.height = nextH;
                  } else {
                    layer.width = (layer.width + dx).clamp(20.0, 10000.0);
                    layer.height = (layer.height + dy).clamp(20.0, 10000.0);
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
