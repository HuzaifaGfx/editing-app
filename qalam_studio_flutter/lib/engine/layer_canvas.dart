import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
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

  final Map<String, ui.Image> _decodedImages = {};
  final Set<String> _loadingImageKeys = {};
  final Map<String, String> _fileMtimeCache = {};

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

  @override
  void initState() {
    super.initState();
    _syncDecodedImages();
  }

  @override
  void didUpdateWidget(covariant LayerCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncDecodedImages();
  }

  @override
  void dispose() {
    _transformController.dispose();
    for (final img in _decodedImages.values) {
      img.dispose();
    }
    _decodedImages.clear();
    super.dispose();
  }

  String _imageSourceKey(DesignLayer layer) {
    if (layer.filters.guilloche && layer.processedGuillocheBytes != null) {
      final b = layer.processedGuillocheBytes!;
      return 'g:${layer.id}:${identityHashCode(b)}:${b.length}';
    }
    if (layer.processedWhiteRemovedBytes != null) {
      final b = layer.processedWhiteRemovedBytes!;
      return 'w:${layer.id}:${identityHashCode(b)}:${b.length}';
    }
    if (layer.localImagePath != null) {
      final path = layer.localImagePath!;
      var stamp = _fileMtimeCache[path];
      if (stamp == null) {
        try {
          final f = File(path);
          if (f.existsSync()) {
            stamp = '${f.lengthSync()}_${f.lastModifiedSync().millisecondsSinceEpoch}';
          } else {
            stamp = 'missing';
          }
        } catch (_) {
          stamp = 'err';
        }
        _fileMtimeCache[path] = stamp;
      }
      return 'f:$path:$stamp';
    }
    return '';
  }

  void _syncDecodedImages() {
    final activeKeys = <String>{};
    for (final layer in widget.page.layers) {
      if (!layer.visible || layer.type != LayerType.image) continue;
      final key = _imageSourceKey(layer);
      if (key.isEmpty) continue;
      activeKeys.add(key);
      if (!_decodedImages.containsKey(key) && !_loadingImageKeys.contains(key)) {
        _loadingImageKeys.add(key);
        unawaited(_decodeLayerImage(layer, key));
      }
    }

    final staleKeys = _decodedImages.keys.where((k) => !activeKeys.contains(k)).toList();
    if (staleKeys.isNotEmpty) {
      final toDispose = <ui.Image>[];
      for (final k in staleKeys) {
        final removed = _decodedImages.remove(k);
        if (removed != null) toDispose.add(removed);
      }
      if (toDispose.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final img in toDispose) {
            img.dispose();
          }
        });
      }
    }
  }

  Future<void> _decodeLayerImage(DesignLayer layer, String key) async {
    try {
      Uint8List? bytes;
      if (layer.filters.guilloche && layer.processedGuillocheBytes != null) {
        bytes = layer.processedGuillocheBytes;
      } else if (layer.processedWhiteRemovedBytes != null) {
        bytes = layer.processedWhiteRemovedBytes;
      } else if (layer.localImagePath != null) {
        final file = File(layer.localImagePath!);
        if (await file.exists()) {
          bytes = await file.readAsBytes();
        }
      }
      if (bytes == null || bytes.isEmpty) {
        _loadingImageKeys.remove(key);
        return;
      }
      final completer = Completer<ui.Image>();
      ui.decodeImageFromList(bytes, (ui.Image result) {
        if (!completer.isCompleted) completer.complete(result);
      });
      final decoded = await completer.future;
      if (!mounted) {
        decoded.dispose();
        return;
      }
      setState(() {
        _loadingImageKeys.remove(key);
        final prev = _decodedImages[key];
        _decodedImages[key] = decoded;
        if (prev != null && !identical(prev, decoded)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => prev.dispose());
        }
      });
    } catch (_) {
      _loadingImageKeys.remove(key);
    }
  }

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
    _syncDecodedImages();
    final page = widget.page;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final layerImages = <String, ui.Image>{};
    for (final layer in page.layers) {
      if (!layer.visible || layer.type != LayerType.image) continue;
      final key = _imageSourceKey(layer);
      final img = _decodedImages[key];
      if (img != null) {
        layerImages[layer.id] = img;
      }
    }

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
                              child: Stack(
                                key: _canvasStackKey,
                                clipBehavior: Clip.none,
                                children: [
                                  // Single unified Canvas Picture: guarantees all 12 BlendModes and 0..100% Opacity
                                  // composite accurately against page background & lower layers in both Impeller & Skia.
                                  Positioned.fill(
                                    child: CustomPaint(
                                      isComplex: true,
                                      willChange: true,
                                      painter: _ArtboardPainter(
                                        page: page,
                                        layerImages: layerImages,
                                        forceTransparentBackground: widget.forceTransparentBackground,
                                      ),
                                    ),
                                  ),
                                  // Interactive gesture hit-targets & clipped selection box (pure hit layer, zero artwork)
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

                                            final hitChild = Transform.rotate(
                                              angle: layer.rotation * math.pi / 180.0,
                                              child: selected
                                                  ? IgnorePointer(
                                                      child: Container(
                                                        decoration: BoxDecoration(
                                                          border: Border.all(
                                                            color: const Color(0xFF111317),
                                                            width: (2.5 * invScale).clamp(2.0, 20.0),
                                                          ),
                                                          boxShadow: [
                                                            BoxShadow(
                                                              color: Colors.white.withOpacity(0.55),
                                                              blurRadius: 0,
                                                              spreadRadius: (1.0 * invScale).clamp(0.8, 4.0),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    )
                                                  : const SizedBox.expand(),
                                            );

                                            return Positioned(
                                              left: layer.x,
                                              top: layer.y,
                                              width: layer.width,
                                              height: layer.height,
                                              child: layer.isCanvasBackground
                                                  ? IgnorePointer(ignoring: true, child: hitChild)
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
                                                      child: hitChild,
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
                          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF111317), shape: BoxShape.circle)),
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
                        height: 20,
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),
                      InkWell(
                        onTap: _resetZoom,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Text(
                            '${(_currentZoom * 100).round()}%',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 20,
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

  Widget _buildSelectionHandlesOverlay(DesignLayer layer, double invScale) {
    final page = widget.page;
    final badgeSize = (28.0 * invScale).clamp(24.0, 200.0);
    final hitSize = (46.0 * invScale).clamp(40.0, 280.0);
    final iconSize = (15.0 * invScale).clamp(13.0, 110.0);
    final ringWidth = (2.2 * invScale).clamp(1.8, 12.0);
    final pad = hitSize * 0.5;

    final minVis = math.max(16.0, 16.0 * invScale);
    final isUnrotated = layer.rotation.abs() < 0.5;
    final visLeft = isUnrotated
        ? layer.x.clamp(0.0, math.max(0.0, page.width - minVis)).toDouble()
        : layer.x.clamp(-page.width * 0.35, math.max(0.0, page.width - minVis)).toDouble();
    final visTop = isUnrotated
        ? layer.y.clamp(0.0, math.max(0.0, page.height - minVis)).toDouble()
        : layer.y.clamp(-page.height * 0.35, math.max(0.0, page.height - minVis)).toDouble();
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
                        color: const Color(0xFF111317),
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
                      child: Icon(Icons.open_in_full_rounded, size: iconSize * 0.92, color: Colors.white),
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

/// Unified single-Picture artboard painter.
/// Paints page background and all layers sequentially into the same Canvas pass
/// so every BlendMode (Multiply, Screen, Overlay, Soft Light, etc.) and Opacity (0..100%)
/// blends reliably across Images (with Filters/Blur/Glow/Rounded/Flip), Text, and Shapes
/// on both Impeller and Skia as well as PNG/PDF exports.
class _ArtboardPainter extends CustomPainter {
  final DocumentPage page;
  final Map<String, ui.Image> layerImages;
  final bool forceTransparentBackground;

  const _ArtboardPainter({
    required this.page,
    required this.layerImages,
    required this.forceTransparentBackground,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    if (!forceTransparentBackground && page.backgroundColor.alpha > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = page.backgroundColor,
      );
    }

    for (final layer in page.layers) {
      if (!layer.visible) continue;
      final layerOpacity = layer.opacity.clamp(0.0, 1.0);
      if (layerOpacity <= 0.001) continue;

      final needsBlend = layer.blendMode != BlendMode.srcOver;
      final needsAlpha = layerOpacity < 0.999;

      TextPainter? preparedTextPainter;
      TextPainter? preparedStrokePainter;
      double textPadX = 0.0;
      double textPadY = 0.0;
      Rect localBounds;

      if (layer.type == LayerType.text) {
        final hasBg = layer.textBgColor.alpha > 0;
        textPadX = hasBg ? 14.0 : 0.0;
        textPadY = hasBg ? 8.0 : 0.0;
        final innerW = math.max(1.0, layer.width - textPadX * 2);
        final hasStroke =
            layer.textStrokeWidth > 0.05 && layer.textStrokeColor.alpha > 0;

        preparedTextPainter = _buildTextPainter(
          layer,
          innerW,
          isStrokePass: false,
          includeShadow: !hasStroke,
        );
        if (hasStroke) {
          preparedStrokePainter = _buildTextPainter(
            layer,
            innerW,
            isStrokePass: true,
            includeShadow: true,
          );
        }

        final effectPad = 16.0 +
            layer.textStrokeWidth +
            layer.textShadowBlur * 2.0 +
            math.max(layer.textShadowOffsetX.abs(), layer.textShadowOffsetY.abs());
        final maxH = math.max(layer.height, preparedTextPainter.height + textPadY * 2);
        localBounds = Rect.fromLTWH(
          -layer.width / 2 - effectPad,
          -layer.height / 2 - effectPad,
          layer.width + effectPad * 2,
          maxH + effectPad * 2,
        );
      } else if (layer.type == LayerType.shape) {
        final strokePad = math.max(4.0, layer.shapeStrokeWidth / 2 + 4.0);
        localBounds = Rect.fromLTWH(
          -layer.width / 2 - strokePad,
          -layer.height / 2 - strokePad,
          layer.width + strokePad * 2,
          layer.height + strokePad * 2,
        );
      } else {
        localBounds = Rect.fromLTWH(
          -layer.width / 2 - 2.0,
          -layer.height / 2 - 2.0,
          layer.width + 4.0,
          layer.height + 4.0,
        );
      }

      canvas.save();
      canvas.translate(layer.x + layer.width / 2.0, layer.y + layer.height / 2.0);
      if (layer.rotation.abs() > 0.0001) {
        canvas.rotate(layer.rotation * math.pi / 180.0);
      }

      if (needsBlend) {
        canvas.saveLayer(
          localBounds,
          Paint()..blendMode = layer.blendMode,
        );
      }
      if (needsAlpha) {
        final alpha = (layerOpacity * 255).round().clamp(0, 255);
        canvas.saveLayer(
          localBounds,
          Paint()..color = Color.fromARGB(alpha, 255, 255, 255),
        );
      }

      if (layer.type == LayerType.image) {
        _paintImageLayer(canvas, layer, layerImages[layer.id]);
      } else if (layer.type == LayerType.text) {
        _paintTextLayer(
          canvas,
          layer,
          preparedTextPainter!,
          preparedStrokePainter,
          textPadX,
          textPadY,
        );
      } else {
        _paintShapeLayer(canvas, layer);
      }

      if (needsAlpha) {
        canvas.restore();
      }
      if (needsBlend) {
        canvas.restore();
      }
      canvas.restore();
    }

    canvas.restore();
  }

  void _paintImageLayer(Canvas canvas, DesignLayer layer, ui.Image? uiImg) {
    final rect = Rect.fromLTWH(-layer.width / 2.0, -layer.height / 2.0, layer.width, layer.height);
    canvas.save();
    if (layer.borderRadius > 0) {
      canvas.clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(layer.borderRadius)));
    } else {
      canvas.clipRect(rect);
    }

    if (uiImg == null) {
      canvas.drawRect(rect, Paint()..color = const Color(0xFF262B35));
      canvas.restore();
      return;
    }

    if (layer.flipX || layer.flipY) {
      canvas.scale(layer.flipX ? -1.0 : 1.0, layer.flipY ? -1.0 : 1.0);
    }

    final fit = layer.aspectLocked ? layer.objectFit : BoxFit.fill;
    final imgW = math.max(1.0, uiImg.width.toDouble());
    final imgH = math.max(1.0, uiImg.height.toDouble());
    final fitted = applyBoxFit(fit, Size(imgW, imgH), Size(layer.width, layer.height));
    final srcRect = Alignment.center.inscribe(fitted.source, Rect.fromLTWH(0, 0, imgW, imgH));
    final dstRect = Alignment.center.inscribe(fitted.destination, rect);

    final f = layer.filters;
    final useRawGuilloche = f.guilloche && layer.processedGuillocheBytes != null;
    final hasColorGrade = !useRawGuilloche &&
        ((f.brightness - 1.0).abs() >= 0.005 ||
            (f.contrast - 1.0).abs() >= 0.005 ||
            (f.saturate - 1.0).abs() >= 0.005 ||
            f.sepia >= 0.005 ||
            f.grayscale >= 0.005 ||
            f.blackAndWhite);
    final ColorFilter? gradeFilter = hasColorGrade ? buildLayerColorFilter(f) : null;

    void drawGraded({ColorFilter? extraFilter}) {
      final p = Paint()..filterQuality = FilterQuality.medium;
      if (extraFilter != null && gradeFilter != null) {
        canvas.saveLayer(rect, Paint()..colorFilter = extraFilter);
        p.colorFilter = gradeFilter;
        canvas.drawImageRect(uiImg, srcRect, dstRect, p);
        canvas.restore();
        return;
      } else if (extraFilter != null) {
        p.colorFilter = extraFilter;
      } else if (gradeFilter != null) {
        p.colorFilter = gradeFilter;
      }
      canvas.drawImageRect(uiImg, srcRect, dstRect, p);
    }

    // 1. Sharp graded base image
    drawGraded();

    if (!useRawGuilloche) {
      final pBlur = f.guilloche ? 0.0 : f.portraitBlur.clamp(0.0, 100.0);
      final skinSmooth = f.guilloche ? 0.0 : f.skinSmooth.clamp(0.0, 100.0);
      final softGlow = f.guilloche ? 0.0 : f.softGlow.clamp(0.0, 100.0);
      final rosyTint = f.guilloche ? 0.0 : f.rosyTint.clamp(0.0, 100.0);

      // 2. Portrait Blur V3 (peripheral bokeh with sharp center cutout)
      if (pBlur > 0.5) {
        canvas.saveLayer(rect, Paint());
        canvas.saveLayer(
          rect,
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: (pBlur / 100.0) * 12.0,
              sigmaY: (pBlur / 100.0) * 12.0,
              tileMode: TileMode.clamp,
            ),
        );
        drawGraded();
        canvas.restore();

        final maskShader = RadialGradient(
          center: const Alignment(0.0, -0.16),
          radius: 0.72,
          colors: [
            Colors.black,
            Colors.black.withOpacity(0.86),
            Colors.transparent,
          ],
          stops: const [0.0, 0.44, 0.94],
        ).createShader(rect);
        canvas.drawRect(
          rect,
          Paint()
            ..blendMode = ui.BlendMode.dstOut
            ..shader = maskShader,
        );
        canvas.restore();
      }

      // 3. Skin & Freckle Clarity Smoothing
      if (skinSmooth > 0.5) {
        final alpha = ((skinSmooth / 100.0) * 0.36 * 255).round().clamp(0, 255);
        canvas.saveLayer(
          rect,
          Paint()
            ..color = Color.fromARGB(alpha, 255, 255, 255)
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: (skinSmooth / 100.0) * 3.8,
              sigmaY: (skinSmooth / 100.0) * 3.8,
              tileMode: TileMode.clamp,
            ),
        );
        drawGraded();
        canvas.restore();
      }

      // 4. Radiant Soft Glow Bloom
      if (softGlow > 0.5) {
        final alpha = ((softGlow / 100.0) * 0.32 * 255).round().clamp(0, 255);
        final plusFilter = ColorFilter.mode(
          Colors.white.withOpacity(0.24),
          ui.BlendMode.plus,
        );
        canvas.saveLayer(
          rect,
          Paint()
            ..color = Color.fromARGB(alpha, 255, 255, 255)
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: 3.0 + (softGlow / 100.0) * 9.0,
              sigmaY: 3.0 + (softGlow / 100.0) * 9.0,
              tileMode: TileMode.clamp,
            ),
        );
        drawGraded(extraFilter: plusFilter);
        canvas.restore();
      }

      // 5. PinkHaze / Rosy Silk Veil
      if (rosyTint > 0.5) {
        canvas.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFFFB6CE).withOpacity((rosyTint / 100.0) * 0.24),
                const Color(0xFFFCA5C0).withOpacity((rosyTint / 100.0) * 0.18),
                const Color(0xFFFED7AA).withOpacity((rosyTint / 100.0) * 0.16),
              ],
            ).createShader(rect),
        );
        canvas.drawRect(
          rect,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(0.0, -0.10),
              radius: 0.65,
              colors: [
                const Color(0xFFF47298).withOpacity((rosyTint / 100.0) * 0.14),
                Colors.transparent,
              ],
            ).createShader(rect),
        );
      }
    }

    canvas.restore();
  }

  TextPainter _buildTextPainter(
    DesignLayer layer,
    double innerW, {
    required bool isStrokePass,
    required bool includeShadow,
  }) {
    final weightIndex = ((layer.fontWeight / 100).round() - 1).clamp(0, 8);
    final effectiveAlign =
        layer.textAlign ?? (layer.isRtl ? TextAlign.right : TextAlign.left);
    final hasShadow = includeShadow &&
        (layer.textShadowBlur > 0.05 ||
            layer.textShadowOffsetX.abs() > 0.1 ||
            layer.textShadowOffsetY.abs() > 0.1) &&
        layer.textShadowColor.alpha > 0;
    final shadows = hasShadow
        ? [
            Shadow(
              color: layer.textShadowColor,
              blurRadius: layer.textShadowBlur.clamp(0.0, 48.0),
              offset: Offset(layer.textShadowOffsetX, layer.textShadowOffsetY),
            ),
          ]
        : null;
    final strokePaint = isStrokePass
        ? (Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = layer.textStrokeWidth
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..color = layer.textStrokeColor)
        : null;
    return TextPainter(
      text: TextSpan(
        text: layer.text,
        style: TextStyle(
          fontFamily: layer.fontFamily,
          fontSize: layer.fontSize,
          fontWeight: FontWeight.values[weightIndex],
          fontVariations: [ui.FontVariation('wght', layer.fontWeight.toDouble())],
          height: layer.lineHeight,
          letterSpacing:
              layer.letterSpacing.abs() < 0.01 ? null : layer.letterSpacing,
          color: isStrokePass ? null : layer.textColor,
          foreground: strokePaint,
          shadows: shadows,
        ),
      ),
      textDirection: layer.isRtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: effectiveAlign,
    )..layout(minWidth: innerW, maxWidth: innerW);
  }

  void _paintTextLayer(
    Canvas canvas,
    DesignLayer layer,
    TextPainter fillTp,
    TextPainter? strokeTp,
    double padX,
    double padY,
  ) {
    final left = -layer.width / 2.0;
    final top = -layer.height / 2.0;
    if (layer.textBgColor.alpha > 0) {
      final bgR = layer.borderRadius > 0 ? layer.borderRadius : 12.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, layer.width, layer.height),
          Radius.circular(bgR),
        ),
        Paint()..color = layer.textBgColor,
      );
    }
    final offset = Offset(left + padX, top + padY);
    if (strokeTp != null) {
      strokeTp.paint(canvas, offset);
    }
    fillTp.paint(canvas, offset);
  }

  void _paintShapeLayer(Canvas canvas, DesignLayer layer) {
    canvas.save();
    canvas.translate(-layer.width / 2.0, -layer.height / 2.0);
    _ShapeLayerPainter(
      shapeKind: layer.shapeKind,
      fillColor: layer.textColor,
      strokeColor: layer.shapeStrokeColor,
      strokeWidth: layer.shapeStrokeWidth,
      borderRadius: layer.borderRadius,
    ).paint(canvas, Size(layer.width, layer.height));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ArtboardPainter oldDelegate) => true;
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
      ..color = const Color(0xFFF59E0B).withOpacity(0.55)
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

Future<Uint8List?> renderPageThumbnailBytes(
  DocumentPage page, {
  double maxSide = 180,
}) async {
  final decodedImages = <String, ui.Image>{};
  try {
    for (final layer in page.layers) {
      if (!layer.visible || layer.type != LayerType.image) continue;
      Uint8List? bytes;
      if (layer.filters.guilloche && layer.processedGuillocheBytes != null) {
        bytes = layer.processedGuillocheBytes;
      } else if (layer.processedWhiteRemovedBytes != null) {
        bytes = layer.processedWhiteRemovedBytes;
      } else if (layer.localImagePath != null) {
        final f = File(layer.localImagePath!);
        if (await f.exists()) {
          bytes = await f.readAsBytes();
        }
      }
      if (bytes == null || bytes.isEmpty) continue;
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 260);
      final frame = await codec.getNextFrame();
      decodedImages[layer.id] = frame.image;
      codec.dispose();
    }

    final safeW = math.max(1.0, page.width);
    final safeH = math.max(1.0, page.height);
    final aspect = safeW / safeH;
    final double outW =
        aspect >= 1.0 ? maxSide : math.max(24.0, maxSide * aspect);
    final double outH =
        aspect >= 1.0 ? math.max(24.0, maxSide / aspect) : maxSide;
    final scale = outW / safeW;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, outW, outH));
    if (page.backgroundColor.alpha == 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, outW, outH),
        Paint()..color = const Color(0xFFFFFFFF),
      );
    }
    canvas.save();
    canvas.scale(scale, scale);
    _ArtboardPainter(
      page: page,
      layerImages: decodedImages,
      forceTransparentBackground: false,
    ).paint(canvas, Size(safeW, safeH));
    canvas.restore();

    final picture = recorder.endRecording();
    final imgOut = await picture.toImage(
      outW.round().clamp(1, 512),
      outH.round().clamp(1, 512),
    );
    final bd = await imgOut.toByteData(format: ui.ImageByteFormat.png);
    imgOut.dispose();
    picture.dispose();
    return bd?.buffer.asUint8List();
  } catch (_) {
    return null;
  } finally {
    for (final im in decodedImages.values) {
      im.dispose();
    }
  }
}

Future<Uint8List?> renderPagePngBytes(
  DocumentPage page, {
  double pixelRatio = 1.0,
  bool forceTransparentBackground = false,
  int? maxLongestSide,
}) async {
  final uniqueImages = <ui.Image>[];
  final pathCache = <String, ui.Image>{};
  final decodedImages = <String, ui.Image>{};
  try {
    for (final layer in page.layers) {
      if (!layer.visible || layer.type != LayerType.image) continue;
      if (layer.filters.guilloche && layer.processedGuillocheBytes != null) {
        final bytes = layer.processedGuillocheBytes!;
        if (bytes.isEmpty) continue;
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        codec.dispose();
        uniqueImages.add(frame.image);
        decodedImages[layer.id] = frame.image;
      } else if (layer.processedWhiteRemovedBytes != null) {
        final bytes = layer.processedWhiteRemovedBytes!;
        if (bytes.isEmpty) continue;
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        codec.dispose();
        uniqueImages.add(frame.image);
        decodedImages[layer.id] = frame.image;
      } else if (layer.localImagePath != null &&
          layer.localImagePath!.isNotEmpty) {
        final path = layer.localImagePath!;
        final cached = pathCache[path];
        if (cached != null) {
          decodedImages[layer.id] = cached;
        } else {
          final f = File(path);
          if (!await f.exists()) continue;
          final bytes = await f.readAsBytes();
          if (bytes.isEmpty) continue;
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          codec.dispose();
          uniqueImages.add(frame.image);
          pathCache[path] = frame.image;
          decodedImages[layer.id] = frame.image;
        }
      }
    }

    final safeW = math.max(1.0, page.width);
    final safeH = math.max(1.0, page.height);
    var targetW = safeW * pixelRatio;
    var targetH = safeH * pixelRatio;
    if (maxLongestSide != null && maxLongestSide > 0) {
      final longest = math.max(targetW, targetH);
      if (longest > maxLongestSide) {
        final factor = maxLongestSide / longest;
        targetW *= factor;
        targetH *= factor;
      }
    }
    final int outW = math.max(1, targetW.round());
    final int outH = math.max(1, targetH.round());
    final scaleX = outW / safeW;
    final scaleY = outH / safeH;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
    );
    canvas.save();
    canvas.scale(scaleX, scaleY);
    _ArtboardPainter(
      page: page,
      layerImages: decodedImages,
      forceTransparentBackground: forceTransparentBackground,
    ).paint(canvas, Size(safeW, safeH));
    canvas.restore();

    final picture = recorder.endRecording();
    final imgOut = await picture.toImage(outW, outH);
    final bd = await imgOut.toByteData(format: ui.ImageByteFormat.png);
    imgOut.dispose();
    picture.dispose();
    return bd?.buffer.asUint8List();
  } catch (_) {
    return null;
  } finally {
    for (final im in uniqueImages) {
      im.dispose();
    }
  }
}
