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

  final Map<int, Offset> _activePointers = {};
  bool _isPinching = false;
  double _currentZoom = 1.0;
  DateTime _lastMultiTouchAt = DateTime.fromMillisecondsSinceEpoch(0);
  double _pinchStartDistance = 1.0;
  Offset _pinchStartFocal = Offset.zero;
  Matrix4 _pinchStartMatrix = Matrix4.identity();

  DesignLayer? _preDragLayer;
  double _preDragX = 0.0;
  double _preDragY = 0.0;
  double _preDragW = 0.0;
  double _preDragH = 0.0;
  double _preDragFontSize = 0.0;
  double _preDragRot = 0.0;
  DateTime _preDragAt = DateTime.fromMillisecondsSinceEpoch(0);

  double _rotateStartAngle = 0.0;
  double _rotateStartDeg = 0.0;
  Offset _rotateCenterGlobal = Offset.zero;
  Offset _panStartCanvas = Offset.zero;
  bool _snapX = false;
  bool _snapY = false;

  Offset _globalToCanvas(Offset globalPos) {
    final box = _canvasStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    return box.globalToLocal(globalPos);
  }

  bool get _blockLayerInteraction =>
      _activePointers.length > 1 ||
      _isPinching ||
      DateTime.now().difference(_lastMultiTouchAt).inMilliseconds < 300;

  void _capturePreDrag(DesignLayer layer) {
    _preDragLayer = layer;
    _preDragX = layer.x;
    _preDragY = layer.y;
    _preDragW = layer.width;
    _preDragH = layer.height;
    _preDragFontSize = layer.fontSize;
    _preDragRot = layer.rotation;
    _preDragAt = DateTime.now();
  }

  void _restorePreDragIfRecent() {
    final l = _preDragLayer;
    if (l != null && DateTime.now().difference(_preDragAt).inMilliseconds < 420) {
      l.x = _preDragX;
      l.y = _preDragY;
      l.width = _preDragW;
      l.height = _preDragH;
      l.fontSize = _preDragFontSize;
      l.rotation = _preDragRot;
      widget.onUpdateLayer(l);
    }
    _preDragLayer = null;
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _setZoomAroundCenter(double nextZoom, double vw, double vh) {
    final clamped = nextZoom.clamp(0.4, 4.0).toDouble();
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
              onPointerDown: (e) {
                _activePointers[e.pointer] = e.localPosition;
                if (_activePointers.length >= 2) {
                  _restorePreDragIfRecent();
                  final pts = _activePointers.values.take(2).toList();
                  _pinchStartDistance = math.max(12.0, (pts[1] - pts[0]).distance);
                  _pinchStartFocal = (pts[0] + pts[1]) / 2.0;
                  _pinchStartMatrix = _transformController.value.clone();
                  setState(() {
                    _isPinching = true;
                    _lastMultiTouchAt = DateTime.now();
                  });
                }
              },
              onPointerMove: (e) {
                if (!_activePointers.containsKey(e.pointer)) return;
                _activePointers[e.pointer] = e.localPosition;
                if (_activePointers.length >= 2 && _isPinching) {
                  final pts = _activePointers.values.take(2).toList();
                  final dist = math.max(12.0, (pts[1] - pts[0]).distance);
                  final focal = (pts[0] + pts[1]) / 2.0;
                  final startScale = _pinchStartMatrix.getMaxScaleOnAxis();
                  final safeStartScale = startScale <= 0 ? 1.0 : startScale;
                  final targetScale = (safeStartScale * (dist / _pinchStartDistance)).clamp(0.4, 4.0).toDouble();
                  final appliedRatio = targetScale / safeStartScale;
                  final nextMatrix = Matrix4.identity()
                    ..translate(focal.dx, focal.dy)
                    ..scale(appliedRatio)
                    ..translate(-_pinchStartFocal.dx, -_pinchStartFocal.dy)
                    ..multiply(_pinchStartMatrix);
                  _transformController.value = nextMatrix;
                  _lastMultiTouchAt = DateTime.now();
                  if ((targetScale - _currentZoom).abs() > 0.01) {
                    setState(() => _currentZoom = targetScale);
                  }
                }
              },
              onPointerUp: (e) {
                _activePointers.remove(e.pointer);
                if (_activePointers.length <= 1 && _isPinching) {
                  setState(() {
                    _lastMultiTouchAt = DateTime.now();
                    _isPinching = false;
                  });
                }
              },
              onPointerCancel: (e) {
                _activePointers.remove(e.pointer);
                if (_activePointers.length <= 1 && _isPinching) {
                  setState(() {
                    _lastMultiTouchAt = DateTime.now();
                    _isPinching = false;
                  });
                }
              },
              child: InteractiveViewer(
                transformationController: _transformController,
                panEnabled: _activePointers.length <= 1 && !_isPinching && _currentZoom > 1.02,
                scaleEnabled: false,
                minScale: 0.4,
                maxScale: 4.0,
                boundaryMargin: const EdgeInsets.all(220),
                onInteractionUpdate: (_) {
                  if (_isPinching) return;
                  final nextZoom = _transformController.value.getMaxScaleOnAxis();
                  if ((nextZoom - _currentZoom).abs() > 0.02) {
                    setState(() => _currentZoom = nextZoom);
                  }
                },
                onInteractionEnd: (_) {
                  final nextZoom = _transformController.value.getMaxScaleOnAxis();
                  setState(() {
                    _currentZoom = nextZoom;
                    if (_isPinching && _activePointers.length <= 1) {
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
                                                        opacity: layer.opacity.clamp(0.0, 1.0),
                                                        child: _buildLayerContent(layer),
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
                                                        onPanStart: (d) {
                                                          if (_blockLayerInteraction) return;
                                                          _capturePreDrag(layer);
                                                          _panStartCanvas = _globalToCanvas(d.globalPosition);
                                                          widget.onSelectLayer(layer.id);
                                                          if (!layer.locked) widget.onInteractionStart?.call();
                                                        },
                                                        onPanUpdate: layer.locked
                                                            ? null
                                                            : (d) {
                                                                if (_blockLayerInteraction) return;
                                                                final curCanvas = _globalToCanvas(d.globalPosition);
                                                                final totalDelta = curCanvas - _panStartCanvas;
                                                                const minOverlap = 24.0;
                                                                final minX = -(layer.width - minOverlap);
                                                                final maxX = page.width - minOverlap;
                                                                final minY = -(layer.height - minOverlap);
                                                                final maxY = page.height - minOverlap;
                                                                var nextX = (_preDragX + totalDelta.dx).clamp(minX, maxX).toDouble();
                                                                var nextY = (_preDragY + totalDelta.dy).clamp(minY, maxY).toDouble();
                                                                final cx = nextX + layer.width / 2;
                                                                final cy = nextY + layer.height / 2;
                                                                const snapTol = 10.0;
                                                                final hitX = (cx - page.width / 2).abs() <= snapTol;
                                                                final hitY = (cy - page.height / 2).abs() <= snapTol;
                                                                if (hitX) nextX = (page.width / 2 - layer.width / 2).clamp(minX, maxX).toDouble();
                                                                if (hitY) nextY = (page.height / 2 - layer.height / 2).clamp(minY, maxY).toDouble();
                                                                setState(() {
                                                                  layer.x = nextX;
                                                                  layer.y = nextY;
                                                                  _snapX = hitX;
                                                                  _snapY = hitY;
                                                                });
                                                              },
                                                        onPanEnd: (_) {
                                                          if (_snapX || _snapY) {
                                                            setState(() {
                                                              _snapX = false;
                                                              _snapY = false;
                                                            });
                                                          }
                                                          widget.onUpdateLayer(layer);
                                                        },
                                                        onPanCancel: () {
                                                          if (_snapX || _snapY) {
                                                            setState(() {
                                                              _snapX = false;
                                                              _snapY = false;
                                                            });
                                                          }
                                                          widget.onUpdateLayer(layer);
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
          gaplessPlayback: true,
        );
      } else if (layer.localImagePath != null && File(layer.localImagePath!).existsSync()) {
        imgWidget = Image.file(
          File(layer.localImagePath!),
          fit: fit,
          gaplessPlayback: true,
        );
      }

      if (imgWidget == null) {
        return Container(
          color: const Color(0xFF262B35),
          child: const Center(child: Icon(Icons.image_outlined, size: 48, color: Colors.white54)),
        );
      }

      final hasCustomFilter = !_filtersAreNeutral(layer.filters);
      final Widget filteredImg = hasCustomFilter
          ? _LayerColorFilter(
              colorFilter: buildLayerColorFilter(layer.filters),
              child: imgWidget,
            )
          : imgWidget;
      final Widget flippedImg = (layer.flipX || layer.flipY)
          ? Transform.flip(
              flipX: layer.flipX,
              flipY: layer.flipY,
              child: filteredImg,
            )
          : filteredImg;
      return layer.borderRadius > 0
          ? ClipRRect(
              borderRadius: BorderRadius.circular(layer.borderRadius),
              child: flippedImg,
            )
          : flippedImg;
    }

    if (layer.type == LayerType.text) {
      final weightIndex = ((layer.fontWeight / 100).round() - 1).clamp(0, 8);
      final effectiveAlign =
          layer.textAlign ?? (layer.isRtl ? TextAlign.right : TextAlign.left);
      final alignBox = effectiveAlign == TextAlign.center
          ? Alignment.topCenter
          : (effectiveAlign == TextAlign.right ||
                  (effectiveAlign == TextAlign.justify && layer.isRtl)
              ? Alignment.topRight
              : Alignment.topLeft);
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
            child: SizedBox(
              width: double.infinity,
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
        ),
      );
    }

    return CustomPaint(
      size: Size(layer.width, layer.height),
      painter: _ShapeLayerPainter(
        shapeKind: layer.shapeKind,
        fillColor: layer.textColor,
        strokeColor: layer.shapeStrokeColor,
        strokeWidth: layer.shapeStrokeWidth,
        borderRadius: layer.borderRadius,
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

    final isUnrotated = (layer.rotation % 360).abs() < 0.01;
    const minVis = 24.0;
    final visLeft = isUnrotated
        ? layer.x.clamp(0.0, math.max(0.0, page.width - minVis)).toDouble()
        : layer.x.clamp(-page.width * 0.35, page.width - minVis).toDouble();
    final visTop = isUnrotated
        ? layer.y.clamp(0.0, math.max(0.0, page.height - minVis)).toDouble()
        : layer.y.clamp(-page.height * 0.35, page.height - minVis).toDouble();
    final visRight = isUnrotated
        ? (layer.x + layer.width).clamp(visLeft + minVis, page.width).toDouble()
        : (layer.x + layer.width).clamp(visLeft + minVis, page.width * 1.35).toDouble();
    final visBottom = isUnrotated
        ? (layer.y + layer.height).clamp(visTop + minVis, page.height).toDouble()
        : (layer.y + layer.height).clamp(visTop + minVis, page.height * 1.35).toDouble();
    final visW = math.max(minVis, visRight - visLeft);
    final visH = math.max(minVis, visBottom - visTop);

    return Positioned(
      left: visLeft - pad,
      top: visTop - pad,
      width: visW + pad * 2,
      height: visH + pad * 2,
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
                  _capturePreDrag(layer);
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
                  setState(() => layer.rotation = deg);
                },
                onPanEnd: (_) => widget.onUpdateLayer(layer),
                onPanCancel: () => widget.onUpdateLayer(layer),
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
                  onPanStart: (d) {
                    if (_blockLayerInteraction) return;
                    _capturePreDrag(layer);
                    _panStartCanvas = _globalToCanvas(d.globalPosition);
                    widget.onInteractionStart?.call();
                  },
                  onPanUpdate: (d) {
                    if (_blockLayerInteraction) return;
                    final total = _globalToCanvas(d.globalPosition) - _panStartCanvas;
                    final rad = _preDragRot * math.pi / 180.0;
                    final localDx = total.dx * math.cos(-rad) - total.dy * math.sin(-rad);
                    final localDy = total.dx * math.sin(-rad) + total.dy * math.cos(-rad);

                    final nextW = (_preDragW - localDx).clamp(60.0, page.width * 2.5).toDouble();
                    final nextH = (_preDragH + localDy).clamp(40.0, page.height * 2.5).toDouble();
                    final shiftLeft = _preDragW - nextW;
                    const minOverlap = 24.0;
                    setState(() {
                      layer.x = (_preDragX + shiftLeft * math.cos(rad))
                          .clamp(-(nextW - minOverlap), page.width - minOverlap)
                          .toDouble();
                      layer.y = (_preDragY + shiftLeft * math.sin(rad))
                          .clamp(-(nextH - minOverlap), page.height - minOverlap)
                          .toDouble();
                      layer.width = nextW;
                      layer.height = nextH;
                    });
                  },
                  onPanEnd: (_) => widget.onUpdateLayer(layer),
                  onPanCancel: () => widget.onUpdateLayer(layer),
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
                onPanStart: (d) {
                  if (_blockLayerInteraction) return;
                  _capturePreDrag(layer);
                  _panStartCanvas = _globalToCanvas(d.globalPosition);
                  widget.onInteractionStart?.call();
                },
                onPanUpdate: (d) {
                  if (_blockLayerInteraction) return;
                  final total = _globalToCanvas(d.globalPosition) - _panStartCanvas;
                  final rad = -_preDragRot * math.pi / 180.0;
                  final dx = total.dx * math.cos(rad) - total.dy * math.sin(rad);
                  final dy = total.dx * math.sin(rad) + total.dy * math.cos(rad);

                  final availW = page.width * 3.0;
                  final availH = page.height * 3.0;
                  setState(() {
                    if (layer.type == LayerType.image && layer.aspectLocked) {
                      final ratio = _preDragW / math.max(1.0, _preDragH);
                      final delta = dx.abs() >= (dy * ratio).abs() ? dx : dy * ratio;
                      final maxW = math.min(availW, availH * ratio);
                      final nextW = (_preDragW + delta).clamp(20.0, math.max(20.0, maxW)).toDouble();
                      final nextH = (nextW / ratio).clamp(20.0, math.max(20.0, availH)).toDouble();
                      layer.width = nextW;
                      layer.height = nextH;
                    } else if (layer.type == LayerType.text) {
                      final ratio = _preDragW / math.max(1.0, _preDragH);
                      final delta = dx.abs() >= (dy * ratio).abs() ? dx : dy * ratio;
                      final prevW = math.max(1.0, _preDragW);
                      final maxW = math.min(availW, availH * ratio);
                      final nextW = (_preDragW + delta).clamp(40.0, math.max(40.0, maxW)).toDouble();
                      final nextH = (nextW / ratio).clamp(24.0, math.max(24.0, availH)).toDouble();
                      layer.fontSize = (_preDragFontSize * (nextW / prevW)).clamp(8.0, 600.0).toDouble();
                      layer.width = nextW;
                      layer.height = nextH;
                    } else {
                      layer.width = (_preDragW + dx).clamp(20.0, availW).toDouble();
                      layer.height = (_preDragH + dy).clamp(20.0, availH).toDouble();
                    }
                  });
                },
                onPanEnd: (_) => widget.onUpdateLayer(layer),
                onPanCancel: () => widget.onUpdateLayer(layer),
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
  final double opacity;
  const _LayerBlendWrapper({
    required this.blendMode,
    this.opacity = 1.0,
    super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLayerBlend(blendMode, opacity);

  @override
  void updateRenderObject(BuildContext context, covariant _RenderLayerBlend renderObject) {
    renderObject
      ..blendMode = blendMode
      ..opacity = opacity;
  }
}

class _RenderLayerBlend extends RenderProxyBox {
  BlendMode _blendMode;
  double _opacity;
  _RenderLayerBlend(this._blendMode, this._opacity);

  set blendMode(BlendMode value) {
    if (_blendMode == value) return;
    _blendMode = value;
    markNeedsPaint();
  }

  set opacity(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    if ((_opacity - clamped).abs() < 0.001) return;
    _opacity = clamped;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || _opacity <= 0.001) return;
    if (_blendMode == BlendMode.srcOver && _opacity >= 0.999) {
      context.paintChild(child!, offset);
      return;
    }
    final alpha = (_opacity * 255).round().clamp(0, 255);
    final paint = Paint()
      ..blendMode = _blendMode
      ..color = Color.fromARGB(alpha, 255, 255, 255);
    context.canvas.saveLayer(offset & size, paint);
    context.paintChild(child!, offset);
    context.canvas.restore();
  }
}

bool _filtersAreNeutral(FilterSettings f) {
  return (f.brightness - 1.0).abs() < 0.005 &&
      (f.contrast - 1.0).abs() < 0.005 &&
      (f.saturate - 1.0).abs() < 0.005 &&
      f.sepia < 0.005 &&
      f.grayscale < 0.005 &&
      !f.blackAndWhite;
}

class _LayerColorFilter extends SingleChildRenderObjectWidget {
  final ColorFilter colorFilter;
  const _LayerColorFilter({
    required this.colorFilter,
    super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLayerColorFilter(colorFilter);

  @override
  void updateRenderObject(
      BuildContext context, covariant _RenderLayerColorFilter renderObject) {
    renderObject.colorFilter = colorFilter;
  }
}

class _RenderLayerColorFilter extends RenderProxyBox {
  ColorFilter _colorFilter;
  _RenderLayerColorFilter(this._colorFilter);

  set colorFilter(ColorFilter value) {
    if (_colorFilter == value) return;
    _colorFilter = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    context.canvas.saveLayer(offset & size, Paint()..colorFilter = _colorFilter);
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

    final thirdsPaint = Paint()
      ..color = const Color(0xFF06B6D4).withOpacity(0.18)
      ..strokeWidth = (0.85 * invScale).clamp(0.5, 1.8)
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(size.width / 3, 0), Offset(size.width / 3, size.height), thirdsPaint);
    canvas.drawLine(Offset(size.width * 2 / 3, 0), Offset(size.width * 2 / 3, size.height), thirdsPaint);
    canvas.drawLine(Offset(0, size.height / 3), Offset(size.width, size.height / 3), thirdsPaint);
    canvas.drawLine(Offset(0, size.height * 2 / 3), Offset(size.width, size.height * 2 / 3), thirdsPaint);

    final crossPaint = Paint()
      ..color = const Color(0xFFF59E0B).withOpacity(0.45)
      ..strokeWidth = (1.1 * invScale).clamp(0.7, 2.2);
    final cx = size.width / 2;
    final cy = size.height / 2;
    final tick = 10.0 * invScale.clamp(0.6, 2.4);
    canvas.drawLine(Offset(cx - tick, cy), Offset(cx + tick, cy), crossPaint);
    canvas.drawLine(Offset(cx, cy - tick), Offset(cx, cy + tick), crossPaint);
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


class _ShapeLayerPainter extends CustomPainter {
  final String shapeKind;
  final Color fillColor;
  final Color strokeColor;
  final double strokeWidth;
  final double borderRadius;

  const _ShapeLayerPainter({
    required this.shapeKind,
    required this.fillColor,
    required this.strokeColor,
    required this.strokeWidth,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = math.max(2.0, size.width);
    final h = math.max(2.0, size.height);
    final path = Path();

    if (shapeKind == 'circle') {
      path.addOval(Rect.fromLTWH(0, 0, w, h));
    } else if (shapeKind == 'arrow') {
      final headW = math.min(w * 0.44, h * 0.85);
      final sx = w - headW;
      path
        ..moveTo(0, h * 0.28)
        ..lineTo(sx, h * 0.28)
        ..lineTo(sx, 0)
        ..lineTo(w, h / 2)
        ..lineTo(sx, h)
        ..lineTo(sx, h * 0.72)
        ..lineTo(0, h * 0.72)
        ..close();
    } else if (shapeKind == 'double_arrow') {
      final headW = math.min(w * 0.3, h * 0.65);
      final lx = headW;
      final rx = w - headW;
      path
        ..moveTo(0, h / 2)
        ..lineTo(lx, 0)
        ..lineTo(lx, h * 0.30)
        ..lineTo(rx, h * 0.30)
        ..lineTo(rx, 0)
        ..lineTo(w, h / 2)
        ..lineTo(rx, h)
        ..lineTo(rx, h * 0.70)
        ..lineTo(lx, h * 0.70)
        ..lineTo(lx, h)
        ..close();
    } else if (shapeKind == 'triangle') {
      path
        ..moveTo(w / 2, 0)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
    } else if (shapeKind == 'star') {
      final cx = w / 2;
      final cy = h / 2;
      final ox = w / 2;
      final oy = h / 2;
      final ix = ox * 0.42;
      final iy = oy * 0.42;
      for (int i = 0; i < 10; i++) {
        final a = -math.pi / 2 + (i * math.pi) / 5;
        final rx = i.isEven ? ox : ix;
        final ry = i.isEven ? oy : iy;
        final px = cx + math.cos(a) * rx;
        final py = cy + math.sin(a) * ry;
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      path.close();
    } else if (shapeKind == 'line') {
      final r = math.min(h / 2, math.max(4.0, borderRadius > 0 ? borderRadius : h / 2));
      path.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(r)));
    } else if (shapeKind == 'rounded') {
      final r = math.max(24.0, borderRadius);
      path.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(r)));
    } else {
      path.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(borderRadius)));
    }

    if (fillColor.alpha > 0) {
      final fillPaint = Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);
    }
    if (strokeWidth > 0 && strokeColor.alpha > 0) {
      final strokePaint = Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ShapeLayerPainter oldDelegate) =>
      oldDelegate.shapeKind != shapeKind ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.strokeColor != strokeColor ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.borderRadius != borderRadius;
}
