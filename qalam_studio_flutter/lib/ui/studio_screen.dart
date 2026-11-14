import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../engine/batch_processor.dart';
import '../engine/filter_matrix.dart';
import '../engine/layer_canvas.dart';
import '../models/design_project.dart';
import '../storage/local_project_store.dart';

class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key});

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  final ImagePicker _picker = ImagePicker();
  final GlobalKey _canvasExportKey = GlobalKey();
  final TextEditingController _textController = TextEditingController();

  List<DesignProject> _projects = [];
  late DesignProject _project;
  int _pageIndex = 0;
  String? _selectedLayerId;
  int _navIndex = 0; // 0=Studio, 1=Pages, 2=Batch, 3=Projects
  int _inspectorTab = 0; // 0=Design, 1=Overlay, 2=Filters, 3=Layers
  bool _sheetExpanded = true;

  // Batch state
  List<String> _batchInputs = [];
  List<String> _batchOutputs = [];
  bool _batchProcessing = false;
  bool _batchBw = false;
  double _batchRemoveWhite = 0.0;
  double _batchBrightness = 1.0;
  double _batchContrast = 1.0;

  @override
  void initState() {
    super.initState();
    _project = _buildDefaultProject();
    _loadSavedProjects();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  DesignProject _buildDefaultProject() => DesignProject(
        id: 'proj_default_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Qalam Design Studio',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        pages: [
          DocumentPage(
            id: 'page_1',
            title: 'Page 1',
            width: 900,
            height: 1200,
            backgroundColor: const Color(0xFF191C22),
            layers: [
              DesignLayer(
                id: 't1',
                name: 'Urdu Headline',
                type: LayerType.text,
                x: 80,
                y: 160,
                width: 740,
                height: 220,
                text: 'ہر لفظ ایک تصویر ہے',
                isRtl: true,
                fontFamily: 'NotoNastaliqUrdu',
                fontSize: 48,
                lineHeight: 2.3,
                textColor: const Color(0xFFFFFFFF),
              ),
              DesignLayer(
                id: 't2',
                name: 'English Subtitle',
                type: LayerType.text,
                x: 80,
                y: 420,
                width: 740,
                height: 120,
                text: 'QALAM STUDIO — OFFLINE DESIGN & DOCS',
                isRtl: false,
                fontFamily: 'PlusJakartaSans',
                fontSize: 24,
                lineHeight: 1.4,
                textColor: const Color(0xFFF59E0B),
              ),
            ],
          ),
        ],
      );

  Future<void> _loadSavedProjects() async {
    try {
      final list = await LocalProjectStore.instance.loadAllProjects();
      if (!mounted) return;
      if (list.isNotEmpty) {
        setState(() {
          _projects = list;
          _project = list.first;
          _pageIndex = 0;
        });
      } else {
        await LocalProjectStore.instance.saveProject(_project);
        if (mounted) setState(() => _projects = [_project]);
      }
    } catch (_) {}
  }

  DocumentPage get _page => _project.pages[_pageIndex.clamp(0, _project.pages.length - 1)];

  DesignLayer? get _activeLayer {
    for (final l in _page.layers) {
      if (l.id == _selectedLayerId) return l;
    }
    return null;
  }

  void _selectLayer(String? id) {
    setState(() {
      _selectedLayerId = id;
      final l = _activeLayer;
      if (l != null && l.type == LayerType.text) {
        _textController.text = l.text;
      }
    });
  }

  Future<void> _saveCurrentProject({bool showToast = true}) async {
    _project.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await LocalProjectStore.instance.saveProject(_project);
    final list = await LocalProjectStore.instance.loadAllProjects();
    if (!mounted) return;
    setState(() => _projects = list);
    if (showToast) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project saved locally offline')),
      );
    }
  }

  static const MethodChannel _mediaChannel = MethodChannel('com.qalam.studio/media');

  Future<String> _saveBytesToDeviceGallery(Uint8List bytes, String fileName) async {
    if (Platform.isAndroid) {
      try {
        final saved = await _mediaChannel.invokeMethod<String>('saveImageToGallery', {
          'bytes': bytes,
          'name': fileName,
        });
        if (saved != null && saved.isNotEmpty) return saved;
      } catch (_) {}
    }
    final extDir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(extDir.path, 'QalamStudio'));
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    final outPath = p.join(outDir.path, fileName);
    await File(outPath).writeAsBytes(bytes);
    return outPath;
  }

  Future<void> _exportPngToGallery() async {
    try {
      setState(() => _selectedLayerId = null);
      await Future.delayed(const Duration(milliseconds: 60));
      final boundary =
          _canvasExportKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final pngBytes = byteData.buffer.asUint8List();
      final fileName = 'qalam_export_${DateTime.now().millisecondsSinceEpoch}.png';
      final savedLocation = await _saveBytesToDeviceGallery(pngBytes, fileName);
      final tmpDir = await getTemporaryDirectory();
      final tmpPath = p.join(tmpDir.path, fileName);
      await File(tmpPath).writeAsBytes(pngBytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved to Gallery: $savedLocation'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Share',
            textColor: const Color(0xFFF59E0B),
            onPressed: () => Share.shareXFiles([XFile(tmpPath)], text: _project.name),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export error: $e')));
    }
  }

  Future<void> _importCanvasImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await File(picked.path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    final natW = (decoded?.width ?? 1080).toDouble();
    final natH = (decoded?.height ?? 1080).toDouble();

    final canvasLayer = DesignLayer(
      id: 'canvas_${DateTime.now().microsecondsSinceEpoch}',
      name: p.basenameWithoutExtension(picked.path),
      type: LayerType.image,
      x: 0,
      y: 0,
      width: natW,
      height: natH,
      locked: true,
      isCanvasBackground: true,
      localImagePath: picked.path,
      aspectLocked: true,
      objectFit: BoxFit.cover,
    );

    setState(() {
      _page.width = natW;
      _page.height = natH;
      if (_page.layers.isNotEmpty &&
          _page.layers.first.type == LayerType.image &&
          (_page.layers.first.isCanvasBackground ||
              (_page.layers.first.x == 0 && _page.layers.first.y == 0))) {
        _page.layers[0] = canvasLayer;
      } else {
        _page.layers.insert(0, canvasLayer);
      }
      _selectedLayerId = null; // Never select or move canvas photo on canvas
      _inspectorTab = 2; // Open Filters tab right away
      _sheetExpanded = true;
    });
    await _saveCurrentProject(showToast: false);
  }

  Future<void> _addOverlayImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await File(picked.path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    final natW = (decoded?.width ?? 600).toDouble();
    final natH = (decoded?.height ?? 600).toDouble();
    final ratio = natW / (natH <= 0 ? 1 : natH);
    final targetW = _page.width * 0.6;
    final targetH = targetW / ratio;

    final layer = DesignLayer(
      id: 'img_${DateTime.now().microsecondsSinceEpoch}',
      name: p.basenameWithoutExtension(picked.path),
      type: LayerType.image,
      x: (_page.width - targetW) / 2,
      y: (_page.height - targetH) / 2,
      width: targetW,
      height: targetH,
      localImagePath: picked.path,
      aspectLocked: true,
      objectFit: BoxFit.cover,
    );

    setState(() {
      _page.layers.add(layer);
      _selectedLayerId = layer.id;
      _inspectorTab = 1;
      _sheetExpanded = true;
    });
  }

  void _addTextLayer() {
    final layer = DesignLayer(
      id: 'txt_${DateTime.now().microsecondsSinceEpoch}',
      name: 'Urdu / English Text',
      type: LayerType.text,
      x: _page.width * 0.1,
      y: _page.height * 0.25,
      width: _page.width * 0.8,
      height: 180,
      text: 'نیا متن لکھیں',
      isRtl: true,
      fontFamily: 'NotoNastaliqUrdu',
      fontSize: 44,
      lineHeight: 2.3,
      textColor: const Color(0xFFFFFFFF),
    );
    setState(() {
      _page.layers.add(layer);
      _selectedLayerId = layer.id;
      _textController.text = layer.text;
      _inspectorTab = 0;
      _sheetExpanded = true;
    });
  }

  void _addShapeLayer() {
    final layer = DesignLayer(
      id: 'shp_${DateTime.now().microsecondsSinceEpoch}',
      name: 'Card Overlay',
      type: LayerType.shape,
      x: _page.width * 0.15,
      y: _page.height * 0.35,
      width: _page.width * 0.7,
      height: 220,
      opacity: 0.75,
      borderRadius: 20,
      textColor: const Color(0xFF111317),
    );
    setState(() {
      _page.layers.add(layer);
      _selectedLayerId = layer.id;
      _inspectorTab = 1;
      _sheetExpanded = true;
    });
  }

  void _duplicateSelectedLayer() {
    final l = _activeLayer;
    if (l == null) return;
    final copy = l.cloneWithNewId('dup_${DateTime.now().microsecondsSinceEpoch}');
    setState(() {
      _page.layers.add(copy);
      _selectedLayerId = copy.id;
      if (copy.type == LayerType.text) _textController.text = copy.text;
    });
  }

  Future<void> _applyWhiteRemoval(DesignLayer layer, double tolerance) async {
    if (layer.localImagePath == null) return;
    if (tolerance <= 0) {
      setState(() {
        layer.filters.removeWhite = 0;
        layer.processedWhiteRemovedBytes = null;
      });
      return;
    }
    setState(() => layer.filters.removeWhite = tolerance);
    final pngBytes = await removeWhiteBackgroundOffline(layer.localImagePath!, tolerance);
    if (!mounted) return;
    setState(() => layer.processedWhiteRemovedBytes = pngBytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF16191E),
        title: Text(_project.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: 'Save Offline',
            icon: const Icon(Icons.save_outlined),
            onPressed: _saveCurrentProject,
          ),
          IconButton(
            tooltip: 'Export PNG',
            icon: const Icon(Icons.download_rounded, color: Color(0xFFF59E0B)),
            onPressed: _exportPngToGallery,
          ),
        ],
      ),
      body: IndexedStack(
        index: _navIndex,
        children: [
          _buildStudioView(),
          _buildPagesView(),
          _buildBatchView(),
          _buildProjectsView(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        backgroundColor: const Color(0xFF16191E),
        indicatorColor: const Color(0xFFF59E0B).withOpacity(0.22),
        onDestinationSelected: (i) => setState(() => _navIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.brush_outlined), label: 'Studio'),
          NavigationDestination(icon: Icon(Icons.description_outlined), label: 'Docs'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_motion_outlined), label: 'Batch'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), label: 'Projects'),
        ],
      ),
    );
  }

  Widget _buildStudioView() {
    final layer = _activeLayer;
    return Column(
      children: [
        Expanded(
          child: Container(
            color: const Color(0xFF0D0F12),
            child: LayerCanvas(
              page: _page,
              selectedLayerId: _selectedLayerId,
              exportBoundaryKey: _canvasExportKey,
              onSelectLayer: _selectLayer,
              onUpdateLayer: (_) => setState(() {}),
            ),
          ),
        ),
        // Quick Action Strip
        Container(
          height: 52,
          color: const Color(0xFF16191E),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _quickBtn(Icons.photo_size_select_large, 'Canvas Pic', _importCanvasImage, highlight: true),
              _quickBtn(Icons.title, 'Add Text', _addTextLayer),
              _quickBtn(Icons.add_photo_alternate_outlined, 'Add Overlay', _addOverlayImage),
              _quickBtn(Icons.crop_square_rounded, 'Shape', _addShapeLayer),
              if (layer != null) _quickBtn(Icons.copy_rounded, 'Duplicate', _duplicateSelectedLayer),
            ],
          ),
        ),
        // Collapsible Bottom Inspector Sheet
        Container(
          height: _sheetExpanded ? 275 : 44,
          decoration: const BoxDecoration(
            color: Color(0xFF16191E),
            border: Border(top: BorderSide(color: Colors.white12)),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 43,
                child: Row(
                  children: [
                    _tabChip(0, 'Design'),
                    _tabChip(1, 'Overlay'),
                    _tabChip(2, 'Filters'),
                    _tabChip(3, 'Layers (${_page.layers.length})'),
                    const Spacer(),
                    IconButton(
                      icon: Icon(_sheetExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up),
                      onPressed: () => setState(() => _sheetExpanded = !_sheetExpanded),
                    ),
                  ],
                ),
              ),
              if (_sheetExpanded)
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: _buildInspectorBody(layer),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _quickBtn(IconData icon, String label, VoidCallback onTap, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: highlight ? const Color(0xFFF59E0B) : Colors.white10,
          foregroundColor: highlight ? Colors.black : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _tabChip(int idx, String label) {
    final active = _inspectorTab == idx;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 11, color: active ? Colors.black : Colors.white70)),
        selected: active,
        selectedColor: const Color(0xFFF59E0B),
        backgroundColor: Colors.white10,
        onSelected: (_) => setState(() {
          _inspectorTab = idx;
          _sheetExpanded = true;
        }),
      ),
    );
  }

  Widget _buildInspectorBody(DesignLayer? layer) {
    // TAB 3: LAYERS
    if (_inspectorTab == 3) {
      final reversed = _page.layers.reversed.toList();
      return Column(
        children: reversed.map((l) {
          final isSel = !l.isCanvasBackground && l.id == _selectedLayerId;
          return Card(
            color: isSel ? const Color(0xFFF59E0B).withOpacity(0.15) : Colors.white.withOpacity(0.04),
            child: ListTile(
              dense: true,
              onTap: l.isCanvasBackground
                  ? () => setState(() {
                        _selectedLayerId = null;
                        _inspectorTab = 2;
                      })
                  : () => _selectLayer(l.id),
              title: Text(
                l.isCanvasBackground ? '${l.name} (Fixed Canvas BG)' : l.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('${(l.opacity * 100).round()}% · ${l.blendMode.name}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(l.visible ? Icons.visibility : Icons.visibility_off, size: 18),
                    onPressed: () => setState(() => l.visible = !l.visible),
                  ),
                  if (!l.isCanvasBackground)
                    IconButton(
                      icon: Icon(l.locked ? Icons.lock : Icons.lock_open, size: 18),
                      onPressed: () => setState(() => l.locked = !l.locked),
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                    onPressed: () => setState(() {
                      _page.layers.removeWhere((x) => x.id == l.id);
                      if (_selectedLayerId == l.id) _selectedLayerId = null;
                    }),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      );
    }

    // TAB 2: FILTERS (supports selected overlay OR locked Canvas Background photo!)
    if (_inspectorTab == 2) {
      DesignLayer? bgPhoto;
      for (final l in _page.layers) {
        if (l.type == LayerType.image && l.isCanvasBackground) {
          bgPhoto = l;
          break;
        }
      }
      final targetImg = (layer != null && layer.type == LayerType.image) ? layer : bgPhoto;
      if (targetImg == null) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Import a Canvas Pic or select an Overlay Image to apply Black & White, Remove White BG, or color filters.',
              style: TextStyle(color: Colors.white70)),
        );
      }
      final isBw = targetImg.filters.blackAndWhite || targetImg.filters.grayscale >= 0.99;
      final isWhiteRemoved = targetImg.filters.removeWhite > 0;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              targetImg.isCanvasBackground
                  ? 'Canvas Photo: ${targetImg.name}'
                  : 'Image: ${targetImg.name}',
              style: const TextStyle(fontSize: 12, color: Colors.amber, fontWeight: FontWeight.w600),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: isBw ? const Color(0xFFF59E0B) : Colors.white12,
                    foregroundColor: isBw ? Colors.black : Colors.white,
                  ),
                  onPressed: () => setState(() {
                    targetImg.filters.blackAndWhite = !isBw;
                    targetImg.filters.grayscale = !isBw ? 1.0 : 0.0;
                    targetImg.filters.contrast = !isBw ? 1.28 : 1.0;
                  }),
                  icon: const Icon(Icons.contrast, size: 18),
                  label: const Text('Black & White', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: isWhiteRemoved ? const Color(0xFF10B981) : Colors.white12,
                    foregroundColor: isWhiteRemoved ? Colors.black : Colors.white,
                  ),
                  onPressed: () => _applyWhiteRemoval(targetImg, isWhiteRemoved ? 0.0 : 35.0),
                  icon: const Icon(Icons.auto_fix_high, size: 18),
                  label: const Text('Remove White BG', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
          if (isWhiteRemoved)
            _sliderRow('White Tolerance', targetImg.filters.removeWhite, 5, 95,
                (v) => _applyWhiteRemoval(targetImg, v)),
          _sliderRow('Brightness', targetImg.filters.brightness, 0.4, 1.8,
              (v) => setState(() => targetImg.filters.brightness = v)),
          _sliderRow('Contrast', targetImg.filters.contrast, 0.5, 2.0,
              (v) => setState(() => targetImg.filters.contrast = v)),
          _sliderRow('Saturation', targetImg.filters.saturate, 0.0, 2.0,
              (v) => setState(() => targetImg.filters.saturate = v)),
        ],
      );
    }

    // TAB 1: OVERLAY & TRANSFORM
    if (_inspectorTab == 1) {
      if (layer == null) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Tap any layer on the canvas to adjust Opacity, Blend Mode, Rotation, or Nudge.',
              style: TextStyle(color: Colors.white70)),
        );
      }
      final blends = [
        BlendMode.srcOver,
        BlendMode.multiply,
        BlendMode.screen,
        BlendMode.overlay,
        BlendMode.darken,
        BlendMode.lighten,
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sliderRow('Opacity', layer.opacity, 0.0, 1.0, (v) => setState(() => layer.opacity = v)),
          _sliderRow('Rotation', layer.rotation, -180.0, 180.0, (v) => setState(() => layer.rotation = v)),
          const SizedBox(height: 6),
          const Text('Blend Mode', style: TextStyle(fontSize: 12, color: Colors.white70)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: blends.map((b) {
              final sel = layer.blendMode == b;
              return ChoiceChip(
                label: Text(b.name, style: TextStyle(fontSize: 11, color: sel ? Colors.black : Colors.white)),
                selected: sel,
                selectedColor: const Color(0xFFF59E0B),
                onSelected: (_) => setState(() => layer.blendMode = b),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(onPressed: () => setState(() => layer.x -= 5), icon: const Icon(Icons.arrow_back)),
              IconButton(onPressed: () => setState(() => layer.y -= 5), icon: const Icon(Icons.arrow_upward)),
              IconButton(onPressed: () => setState(() => layer.y += 5), icon: const Icon(Icons.arrow_downward)),
              IconButton(onPressed: () => setState(() => layer.x += 5), icon: const Icon(Icons.arrow_forward)),
            ],
          ),
        ],
      );
    }

    // TAB 0: DESIGN
    if (layer == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.black),
            onPressed: _importCanvasImage,
            icon: const Icon(Icons.upload_rounded),
            label: const Text('Import Canvas Image (Match Photo Size)'),
          ),
          const SizedBox(height: 12),
          const Text('Canvas Background', style: TextStyle(fontSize: 12, color: Colors.white70)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              const Color(0xFF191C22),
              const Color(0xFF000000),
              const Color(0xFFFFFFFF),
              const Color(0xFFFAF9F6),
              Colors.transparent,
            ].map((c) {
              return GestureDetector(
                onTap: () => setState(() => _page.backgroundColor = c),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c == Colors.transparent ? Colors.grey.shade800 : c,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _page.backgroundColor == c ? const Color(0xFFF59E0B) : Colors.white24,
                      width: 2,
                    ),
                  ),
                  child: c == Colors.transparent ? const Icon(Icons.grid_on, size: 16) : null,
                ),
              );
            }).toList(),
          ),
        ],
      );
    }

    if (layer.type == LayerType.text) {
      final fontItems = const [
        ('NotoNastaliqUrdu', 'Urdu Nastaliq', true, 2.3),
        ('Gulzar', 'Gulzar Urdu', true, 2.1),
        ('NotoNaskhArabic', 'Naskh Urdu', true, 1.9),
        ('IBMPlexSansArabicSemiBold', 'Halka Bold (Urdu+Eng)', true, 1.8),
        ('PlusJakartaSans', 'Jakarta Sans', false, 1.35),
        ('Montserrat', 'Montserrat', false, 1.3),
        ('Poppins', 'Poppins', false, 1.35),
        ('PlayfairDisplay', 'Playfair Serif', false, 1.3),
        ('Lora', 'Lora Serif', false, 1.4),
        ('Oswald', 'Oswald Bold', false, 1.2),
        ('BebasNeue', 'Bebas Poster', false, 1.1),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _textController,
            textDirection: layer.isRtl ? TextDirection.rtl : TextDirection.ltr,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Edit Text (Urdu / English)',
              border: OutlineInputBorder(),
            ),
            onChanged: (val) => setState(() => layer.text = val),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: fontItems.map((f) {
              final sel = layer.fontFamily == f.$1;
              return ChoiceChip(
                label: Text(f.$2, style: TextStyle(fontSize: 11, color: sel ? Colors.black : Colors.white)),
                selected: sel,
                selectedColor: const Color(0xFFF59E0B),
                onSelected: (_) => setState(() {
                  layer.fontFamily = f.$1;
                  layer.isRtl = f.$3;
                  layer.lineHeight = f.$4;
                  if (f.$1 == 'IBMPlexSansArabicSemiBold') layer.fontWeight = 600;
                }),
              );
            }).toList(),
          ),
          Row(
            children: [
              ChoiceChip(
                label: Text('Regular', style: TextStyle(fontSize: 11, color: layer.fontWeight < 550 ? Colors.black : Colors.white)),
                selected: layer.fontWeight < 550,
                selectedColor: const Color(0xFFF59E0B),
                onSelected: (_) => setState(() => layer.fontWeight = 400),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text('Halka Bold (SemiBold)', style: TextStyle(fontSize: 11, color: layer.fontWeight >= 550 ? Colors.black : Colors.white)),
                selected: layer.fontWeight >= 550,
                selectedColor: const Color(0xFFF59E0B),
                onSelected: (_) => setState(() => layer.fontWeight = 600),
              ),
            ],
          ),
          _sliderRow('Text Scale', layer.fontSize, 12, 200, (v) => setState(() => layer.fontSize = v)),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => layer.fontSize = (layer.fontSize - 6).clamp(12.0, 200.0)),
                  child: const Text('A− Smaller'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => layer.fontSize = (layer.fontSize + 6).clamp(12.0, 200.0)),
                  child: const Text('A+ Larger'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              const Color(0xFFFFFFFF),
              const Color(0xFFF59E0B),
              const Color(0xFF0F172A),
              const Color(0xFF10B981),
              const Color(0xFFE11D48),
            ].map((c) {
              return GestureDetector(
                onTap: () => setState(() => layer.textColor = c),
                child: CircleAvatar(radius: 14, backgroundColor: c),
              );
            }).toList(),
          ),
        ],
      );
    }

    if (layer.type == LayerType.image) {
      final curScale = ((layer.width / (_page.width <= 0 ? 1 : _page.width)) * 100.0).clamp(10.0, 250.0);
      void applyImageScale(double pct) {
        final safePct = pct.clamp(10.0, 250.0);
        final ratio = layer.width / (layer.height <= 0 ? 1.0 : layer.height);
        final nextW = (_page.width * safePct / 100.0).clamp(24.0, 4000.0);
        setState(() {
          layer.width = nextW;
          if (layer.aspectLocked) {
            layer.height = (nextW / (ratio <= 0.05 ? 1.0 : ratio)).clamp(24.0, 4000.0);
          }
        });
      }

      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: layer.aspectLocked ? const Color(0xFFF59E0B) : Colors.white12,
                    foregroundColor: layer.aspectLocked ? Colors.black : Colors.white,
                  ),
                  onPressed: () => setState(() => layer.aspectLocked = !layer.aspectLocked),
                  icon: Icon(layer.aspectLocked ? Icons.lock : Icons.lock_open, size: 16),
                  label: Text(layer.aspectLocked ? 'Ratio Locked' : 'Free Stretch'),
                ),
              ),
            ],
          ),
          _sliderRow('Image Scale %', curScale, 10, 250, applyImageScale),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => applyImageScale(curScale - 10),
                  child: const Text('− Smaller'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => applyImageScale(curScale + 10),
                  child: const Text('+ Larger'),
                ),
              ),
            ],
          ),
          _sliderRow('Corner Radius', layer.borderRadius, 0, 160,
              (v) => setState(() => layer.borderRadius = v)),
        ],
      );
    }

    return _sliderRow('Corner Radius', layer.borderRadius, 0, 120,
        (v) => setState(() => layer.borderRadius = v));
  }

  Widget _sliderRow(String label, double val, double min, double max, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 96, child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70))),
        Expanded(
          child: Slider(
            value: val.clamp(min, max),
            min: min,
            max: max,
            activeColor: const Color(0xFFF59E0B),
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 38, child: Text(val.toStringAsFixed(val > 5 ? 0 : 2), style: const TextStyle(fontSize: 11))),
      ],
    );
  }

  Widget _buildPagesView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Document Pages', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _project.pages.add(DocumentPage(
                    id: 'pg_${DateTime.now().microsecondsSinceEpoch}',
                    title: 'Page ${_project.pages.length + 1}',
                    width: 992,
                    height: 1403,
                    backgroundColor: const Color(0xFFFAF9F6),
                    layers: [],
                  ));
                  _pageIndex = _project.pages.length - 1;
                  _navIndex = 0;
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('Add A4 Page'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...List.generate(_project.pages.length, (i) {
          final pg = _project.pages[i];
          return Card(
            color: i == _pageIndex ? const Color(0xFFF59E0B).withOpacity(0.15) : const Color(0xFF191C22),
            child: ListTile(
              title: Text(pg.title),
              subtitle: Text('${pg.width.round()} x ${pg.height.round()} · ${pg.layers.length} layers'),
              onTap: () => setState(() {
                _pageIndex = i;
                _selectedLayerId = null;
                _navIndex = 0;
              }),
              trailing: _project.pages.length > 1
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () => setState(() {
                        _project.pages.removeAt(i);
                        _pageIndex = 0;
                      }),
                    )
                  : null,
            ),
          );
        }),
      ],
    );
  }

  Widget _buildBatchView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Offline Batch Processor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () async {
            final imgs = await _picker.pickMultiImage();
            if (imgs.isNotEmpty) setState(() => _batchInputs = imgs.map((e) => e.path).toList());
          },
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(_batchInputs.isEmpty ? 'Select Multiple Photos' : '${_batchInputs.length} Photos Selected'),
        ),
        SwitchListTile(
          title: const Text('Black & White Filter'),
          value: _batchBw,
          onChanged: (v) => setState(() => _batchBw = v),
        ),
        SwitchListTile(
          title: const Text('Remove White Background (PNG)'),
          value: _batchRemoveWhite > 0,
          onChanged: (v) => setState(() => _batchRemoveWhite = v ? 35.0 : 0.0),
        ),
        _sliderRow('Brightness', _batchBrightness, 0.5, 1.8, (v) => setState(() => _batchBrightness = v)),
        _sliderRow('Contrast', _batchContrast, 0.5, 2.0, (v) => setState(() => _batchContrast = v)),
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.black),
          onPressed: _batchInputs.isEmpty || _batchProcessing
              ? null
              : () async {
                  setState(() => _batchProcessing = true);
                  final dir = await getTemporaryDirectory();
                  final out = await runBatchOffline(BatchJobRequest(
                    inputPaths: _batchInputs,
                    outputDir: dir.path,
                    brightness: _batchBrightness,
                    contrast: _batchContrast,
                    blackAndWhite: _batchBw,
                    removeWhiteTolerance: _batchRemoveWhite,
                  ));
                  if (!mounted) return;
                  setState(() {
                    _batchOutputs = out;
                    _batchProcessing = false;
                  });
                  if (out.isNotEmpty) {
                    for (final fp in out) { await _saveBytesToDeviceGallery(await File(fp).readAsBytes(), p.basename(fp)); }
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved ${out.length} batch images to Gallery')));
                  }
                },
          child: Text(_batchProcessing ? 'Processing...' : 'Process & Export Batch'),
        ),
        if (_batchOutputs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Processed ${_batchOutputs.length} images locally!',
                style: const TextStyle(color: Colors.greenAccent)),
          ),
      ],
    );
  }

  Widget _buildProjectsView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Offline Projects', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            FilledButton.icon(
              onPressed: () async {
                final fresh = _buildDefaultProject();
                await LocalProjectStore.instance.saveProject(fresh);
                final list = await LocalProjectStore.instance.loadAllProjects();
                if (!mounted) return;
                setState(() {
                  _projects = list;
                  _project = fresh;
                  _pageIndex = 0;
                  _selectedLayerId = null;
                  _navIndex = 0;
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('New Project'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._projects.map((proj) {
          final isCurrent = proj.id == _project.id;
          return Card(
            color: isCurrent ? const Color(0xFFF59E0B).withOpacity(0.15) : const Color(0xFF191C22),
            child: ListTile(
              title: Text(proj.name),
              subtitle: Text('${proj.pages.length} page(s) · Saved offline'),
              onTap: () => setState(() {
                _project = proj;
                _pageIndex = 0;
                _selectedLayerId = null;
                _navIndex = 0;
              }),
              trailing: _projects.length > 1
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () async {
                        await LocalProjectStore.instance.deleteProject(proj.id);
                        await _loadSavedProjects();
                      },
                    )
                  : null,
            ),
          );
        }),
      ],
    );
  }
}
