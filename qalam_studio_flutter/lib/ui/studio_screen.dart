import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../engine/batch_processor.dart';
import '../engine/filter_matrix.dart';
import '../engine/layer_canvas.dart';
import '../main.dart';
import '../models/design_project.dart';
import '../storage/local_project_store.dart';

class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key});

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  static const Color _amber = Color(0xFFF59E0B);
  static const MethodChannel _mediaChannel = MethodChannel('com.qalam.studio/media');

  final ImagePicker _picker = ImagePicker();
  final GlobalKey _canvasExportKey = GlobalKey();
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _sigTextController = TextEditingController(text: 'Huzaifa');

  List<DesignProject> _projects = [];
  late DesignProject _project;
  int _pageIndex = 0;
  String? _selectedLayerId;
  int _navIndex = 0; // 0=Studio, 1=Fill, 2=Sign, 3=Docs, 4=Batch, 5=Projects
  int _inspectorTab = 0; // 0=Design, 1=Overlay, 2=BG Clean, 3=Layers
  bool _sheetExpanded = true;
  bool _exportTransparentCanvas = false;
  bool _showGuides = true;
  bool _hideOverlaysForExport = false;
  final List<_ScannedDocPage> _scannedPages = [];
  int _activeScanIdx = 0;
  int _whiteRemovalSeq = 0;
  final List<(int, String)> _undoStack = [];
  final List<(int, String)> _redoStack = [];

  // Global Saving HUD overlay state
  OverlayEntry? _saveHudEntry;
  Timer? _saveHudTimer;
  String _saveHudPhase = 'saving'; // 'saving' | 'saved' | 'error'
  String _saveHudTitle = 'Saving...';
  String _saveHudSubtitle = '';

  // Signature Studio state
  int _sigMode = 0;
  String _sigFontFamily = 'GreatVibes';
  Color _sigInkColor = const Color(0xFF0F172A);
  double _sigFontSize = 78;
  double _sigLetterSpacing = 0.0;
  bool _sigSlanted = true;
  bool _sigBold = false;
  bool _sigTransparentBg = true;
  double _sigPenWidth = 4.0;
  Size _sigCanvasSize = const Size(1100, 520);
  final List<(List<Offset>, Color, double)> _sigStrokes = [];
  final List<(List<Offset>, Color, double)> _sigRedoStrokes = [];
  List<Offset>? _sigCurrentStroke;

  // Rubber Stamp / مہر Maker state
  String _stampShape = 'round'; // 'round', 'oval', 'box'
  final TextEditingController _stampOrgCtrl = TextEditingController(text: 'QALAM TRADERS');
  final TextEditingController _stampStatusCtrl = TextEditingController(text: 'PAID · ادا شدہ');
  final TextEditingController _stampSubCtrl = TextEditingController(text: 'LAHORE · PAKISTAN');
  Color _stampInkColor = const Color(0xFF1E3A8A);
  bool _stampShowDate = true;
  bool _stampTransparentBg = true;

  // Batch state
  List<String> _batchInputs = [];
  List<String> _batchOutputs = [];
  bool _batchProcessing = false;
  double _batchRemoveWhite = 0.0;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _cardBg => _isDark ? const Color(0xFF16191E) : Colors.white;
  Color get _panelBg => _isDark ? const Color(0xFF16191E) : Colors.white;
  Color get _inputBg => _isDark ? const Color(0xFF111317) : const Color(0xFFF8FAFC);
  Color get _chipBg => _isDark ? const Color(0xFF222731) : const Color(0xFFF1F5F9);
  Color get _borderColor => _isDark ? const Color(0xFF262B35) : const Color(0xFFE2E8F0);
  Color get _textColor => _isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
  Color get _subColor => _isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
  Color get _mutedColor => _isDark ? const Color(0xFF64748B) : const Color(0xFF64748B);
  Color get _accentText => _isDark ? _amber : const Color(0xFFB45309);

  @override
  void initState() {
    super.initState();
    _project = _buildDefaultProject();
    _loadSavedProjects();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkQuickTourOnFirstLaunch());
  }

  @override
  void dispose() {
    _saveHudTimer?.cancel();
    _saveHudEntry?.remove();
    _saveHudEntry = null;
    _textController.dispose();
    _sigTextController.dispose();
    _stampOrgCtrl.dispose();
    _stampStatusCtrl.dispose();
    _stampSubCtrl.dispose();
    super.dispose();
  }

  void _showSaveHud({
    required String phase,
    required String title,
    String subtitle = '',
  }) {
    if (!mounted) return;
    _saveHudPhase = phase;
    _saveHudTitle = title;
    _saveHudSubtitle = subtitle;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    if (_saveHudEntry == null) {
      _saveHudEntry = OverlayEntry(
        builder: (ctx) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final isSaving = _saveHudPhase == 'saving';
          final isError = _saveHudPhase == 'error';
          final borderCol = isError
              ? const Color(0xFFEF4444)
              : (isSaving ? _amber : const Color(0xFF10B981));
          return Positioned(
            top: MediaQuery.of(ctx).padding.top + 12,
            left: 16,
            right: 16,
            child: IgnorePointer(
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    constraints: const BoxConstraints(maxWidth: 340),
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF16191E) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderCol.withOpacity(0.75), width: 1.4),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                          color: Colors.black.withOpacity(isDark ? 0.45 : 0.16),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: isSaving
                                  ? const SizedBox(
                                      key: ValueKey('hud_spin'),
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.6,
                                        color: _amber,
                                      ),
                                    )
                                  : Icon(
                                      isError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
                                      key: ValueKey(_saveHudPhase),
                                      color: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                                      size: 24,
                                    ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _saveHudTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  if (_saveHudSubtitle.isNotEmpty)
                                    Text(
                                      _saveHudSubtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (isSaving) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              minHeight: 3,
                              color: _amber,
                              backgroundColor: _amber.withOpacity(0.18),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
      overlay.insert(_saveHudEntry!);
    } else {
      _saveHudEntry!.markNeedsBuild();
    }
  }

  void _scheduleHideSaveHud([int ms = 1450]) {
    _saveHudTimer?.cancel();
    _saveHudTimer = Timer(Duration(milliseconds: ms), () {
      _saveHudEntry?.remove();
      _saveHudEntry = null;
    });
  }

  Future<T?> _runWithSavingHud<T>({
    required String savingTitle,
    String savingSubtitle = '',
    required String savedTitle,
    String savedSubtitle = '',
    required Future<T> Function() action,
  }) async {
    _saveHudTimer?.cancel();
    _showSaveHud(phase: 'saving', title: savingTitle, subtitle: savingSubtitle);
    try {
      final results = await Future.wait<dynamic>([
        action(),
        Future.delayed(const Duration(milliseconds: 380)),
      ]);
      final res = results[0] as T;
      if (mounted) {
        _showSaveHud(phase: 'saved', title: savedTitle, subtitle: savedSubtitle);
        _scheduleHideSaveHud(1450);
      }
      return res;
    } catch (e) {
      if (mounted) {
        _showSaveHud(
          phase: 'error',
          title: 'Save Failed',
          subtitle: e.toString(),
        );
        _scheduleHideSaveHud(2200);
      }
      return null;
    }
  }

  Future<void> _checkQuickTourOnFirstLaunch() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final flag = File(p.join(docsDir.path, 'qalam_tour_seen_v1.flag'));
      if (!flag.existsSync() && mounted) {
        await flag.writeAsString('1');
        if (mounted) _showQuickTourSheet();
      }
    } catch (_) {}
  }

  void _showQuickTourSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panelBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _mutedColor.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: _amber.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.explore_outlined, color: _accentText, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Qalam Studio — Quick Guide', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _textColor)),
                          Text('Urdu Nastaliq & Business Design Suite (Offline)', style: TextStyle(fontSize: 11.5, color: _subColor)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _tourTile(
                  Icons.receipt_long_rounded,
                  'Cash Memo, Letterhead & Sanad',
                  'Docs tab mein ready-to-edit Urdu Cash Memo, Letterhead aur Certificate templates maujood hain.',
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _navIndex = 3);
                  },
                ),
                _tourTile(
                  Icons.verified_rounded,
                  'Official Stamps (مہر) & Signatures',
                  'Sign/Seal tab mein Round, Oval ya Box rubber stamp banayen (PAID, منظور شدہ) aur 1 tap mein canvas par lagayen.',
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _navIndex = 2;
                      _sigMode = 2;
                    });
                  },
                ),
                _tourTile(
                  Icons.touch_app_rounded,
                  'Canvas Handle Colors',
                  'Amber Corner = Size Scale · Blue Top = Rotate · Green Side = Urdu/English Text Box Width.',
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _navIndex = 0);
                  },
                ),
                _tourTile(
                  Icons.edit_note_rounded,
                  'Quick Fill & Portable Share',
                  'Fill tab se Customer Name ya Photo seconds mein badlen — exact coordinates wahin rehte hain.',
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _navIndex = 1);
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _amber,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Start Designing', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tourTile(IconData icon, String title, String subtitle, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: _inputBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _borderColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _amber, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _textColor)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 11.5, color: _subColor, height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
                textColor: _amber,
              ),
            ],
          ),
        ],
      );

  Future<String> _persistPickedImageOffline(String sourcePath) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final imgDir = Directory(p.join(docsDir.path, 'qalam_images'));
      if (!imgDir.existsSync()) imgDir.createSync(recursive: true);
      final ext = p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
      final destPath = p.join(imgDir.path, 'img_${DateTime.now().microsecondsSinceEpoch}$ext');
      await File(sourcePath).copy(destPath);
      return destPath;
    } catch (_) {
      return sourcePath;
    }
  }

  Future<void> _rehydrateProjectFilters(DesignProject proj) async {
    bool changed = false;
    for (final pg in proj.pages) {
      for (final l in pg.layers) {
        if (l.type == LayerType.image &&
            l.filters.removeWhite > 0 &&
            l.localImagePath != null &&
            File(l.localImagePath!).existsSync() &&
            l.processedWhiteRemovedBytes == null) {
          final bytes = await removeWhiteBackgroundOffline(l.localImagePath!, l.filters.removeWhite);
          if (bytes != null) {
            l.processedWhiteRemovedBytes = bytes;
            changed = true;
          }
        }
      }
    }
    if (changed && mounted) setState(() {});
  }

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
        await _rehydrateProjectFilters(_project);
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

  void _pushUndoSnapshot() {
    _undoStack.add((_pageIndex, _project.encode()));
    if (_undoStack.length > 25) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _restoreEncodedSnapshot((int, String) snap) {
    final cache = <String, Uint8List>{};
    for (final pg in _project.pages) {
      for (final l in pg.layers) {
        if (l.processedWhiteRemovedBytes != null) {
          cache['${l.id}_${l.filters.removeWhite.round()}'] = l.processedWhiteRemovedBytes!;
        }
      }
    }
    final restored = DesignProject.decode(snap.$2);
    for (final pg in restored.pages) {
      for (final l in pg.layers) {
        final key = '${l.id}_${l.filters.removeWhite.round()}';
        if (cache.containsKey(key)) {
          l.processedWhiteRemovedBytes = cache[key];
        }
      }
    }
    setState(() {
      _project = restored;
      _pageIndex = snap.$1.clamp(0, restored.pages.length - 1);
      final stillExists = _page.layers.any((l) => l.id == _selectedLayerId);
      if (!stillExists) _selectedLayerId = null;
      final cur = _activeLayer;
      if (cur != null && cur.type == LayerType.text) {
        _textController.text = cur.text;
      }
    });
    _saveCurrentProject(showToast: false);
    _rehydrateProjectFilters(restored);
  }

  void _undoCanvas() {
    if (_undoStack.isEmpty) return;
    _redoStack.add((_pageIndex, _project.encode()));
    final prev = _undoStack.removeLast();
    _restoreEncodedSnapshot(prev);
  }

  void _redoCanvas() {
    if (_redoStack.isEmpty) return;
    _undoStack.add((_pageIndex, _project.encode()));
    final next = _redoStack.removeLast();
    _restoreEncodedSnapshot(next);
  }

  Future<void> _renameProjectDialog(DesignProject proj) async {
    final ctrl = TextEditingController(text: proj.name);
    final nextName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rename Project', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Project Title'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _amber, foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (nextName != null && nextName.isNotEmpty) {
      setState(() => proj.name = nextName);
      await LocalProjectStore.instance.saveProject(proj);
      final list = await LocalProjectStore.instance.loadAllProjects();
      if (mounted) setState(() => _projects = list);
    }
  }

  Future<void> _saveCurrentProject({bool showToast = true}) async {
    Future<void> persist() async {
      _project.updatedAt = DateTime.now().millisecondsSinceEpoch;
      await LocalProjectStore.instance.saveProject(_project);
      final list = await LocalProjectStore.instance.loadAllProjects();
      if (!mounted) return;
      setState(() => _projects = list);
    }

    if (showToast) {
      await _runWithSavingHud(
        savingTitle: 'Saving Project...',
        savingSubtitle: _project.name,
        savedTitle: 'Project Saved',
        savedSubtitle: 'Stored offline on device',
        action: persist,
      );
    } else {
      await persist();
    }
  }

  Future<void> _renameLayerDialog(DesignLayer layer) async {
    final ctrl = TextEditingController(text: layer.name);
    final nextName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rename Layer', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Layer Name (e.g. Name, Photo, Signature)',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _amber, foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (nextName != null && nextName.isNotEmpty) {
      setState(() => layer.name = nextName);
      await _runWithSavingHud(
        savingTitle: 'Saving Layer...',
        savedTitle: 'Layer Saved',
        savedSubtitle: nextName,
        action: () => _saveCurrentProject(showToast: false),
      );
    }
  }

  Future<void> _applyFontToAllTextLayers(
    String fontFamily,
    int fontWeight,
    double lineHeight,
  ) async {
    int count = 0;
    setState(() {
      for (final l in _page.layers) {
        if (l.type == LayerType.text) {
          l.fontFamily = fontFamily;
          l.fontWeight = fontWeight;
          l.lineHeight = lineHeight;
          count++;
        }
      }
    });
    await _runWithSavingHud(
      savingTitle: 'Applying Font...',
      savedTitle: 'Font Saved',
      savedSubtitle: 'Updated $count text layer(s)',
      action: () => _saveCurrentProject(showToast: false),
    );
  }

  Future<void> _replaceLayerImageKeepingConfig(DesignLayer layer) async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    await _runWithSavingHud(
      savingTitle: 'Updating Image...',
      savingSubtitle: layer.name,
      savedTitle: 'Layer Saved',
      savedSubtitle: 'Replaced "${layer.name}"',
      action: () async {
        final permanentPath = await _persistPickedImageOffline(picked.path);
        if (!mounted) return;
        setState(() {
          layer.localImagePath = permanentPath;
          layer.processedWhiteRemovedBytes = null;
        });
        if (layer.filters.removeWhite > 0) {
          await _applyWhiteRemoval(layer, layer.filters.removeWhite);
        }
        await _saveCurrentProject(showToast: false);
      },
    );
  }

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

  Future<Uint8List?> _captureCanvasBytes({
    double pixelRatio = 2.0,
    String format = 'png',
    bool transparent = false,
  }) async {
    final prevNav = _navIndex;
    setState(() {
      _navIndex = 0;
      _selectedLayerId = null;
      _hideOverlaysForExport = true;
      _exportTransparentCanvas = format == 'png' && transparent;
    });
    await Future.delayed(const Duration(milliseconds: 90));
    try {
      final boundary =
          _canvasExportKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      final pngBytes = byteData.buffer.asUint8List();
      if (format == 'jpg') {
        final decoded = img.decodePng(pngBytes);
        if (decoded != null) {
          return Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
        }
      }
      return pngBytes;
    } finally {
      if (mounted) {
        setState(() {
          _hideOverlaysForExport = false;
          _exportTransparentCanvas = false;
          _navIndex = prevNav;
        });
      }
    }
  }

  Future<void> _executeExport({
    required String format,
    required double scale,
    required bool transparent,
    required bool shareOnly,
    required bool asPdf,
  }) async {
    if (asPdf) {
      await _runWithSavingHud(
        savingTitle: 'Generating PDF...',
        savingSubtitle: '${_project.pages.length} page(s)',
        savedTitle: 'PDF Ready',
        savedSubtitle: 'Opening print & save view',
        action: () async {
          final origPageIdx = _pageIndex;
          final doc = pw.Document();
          try {
            for (int i = 0; i < _project.pages.length; i++) {
              if (_pageIndex != i) {
                setState(() => _pageIndex = i);
                await Future.delayed(const Duration(milliseconds: 70));
              }
              final pgBytes = await _captureCanvasBytes(
                pixelRatio: scale,
                format: 'png',
                transparent: false,
              );
              if (pgBytes != null) {
                final pg = _project.pages[i];
                final pdfImg = pw.MemoryImage(pgBytes);
                doc.addPage(
                  pw.Page(
                    pageFormat: PdfPageFormat(pg.width, pg.height),
                    margin: pw.EdgeInsets.zero,
                    build: (_) => pw.Center(child: pw.Image(pdfImg, fit: pw.BoxFit.contain)),
                  ),
                );
              }
            }
          } finally {
            if (mounted && _pageIndex != origPageIdx) {
              setState(() => _pageIndex = origPageIdx);
            }
          }
          await Printing.layoutPdf(onLayout: (_) async => doc.save());
        },
      );
      return;
    }

    String? tmpPathForShare;
    String? savedLocation;
    await _runWithSavingHud(
      savingTitle: shareOnly ? 'Preparing Share...' : 'Saving ${format.toUpperCase()}...',
      savingSubtitle: _project.name,
      savedTitle: shareOnly ? 'Ready to Share' : 'Saved to Gallery',
      savedSubtitle: '${format.toUpperCase()} · ${scale.toStringAsFixed(0)}x',
      action: () async {
        final bytes = await _captureCanvasBytes(
          pixelRatio: scale,
          format: format,
          transparent: transparent,
        );
        if (bytes == null) throw Exception('Canvas capture failed');
        final ext = format == 'jpg' ? 'jpg' : 'png';
        final fileName = 'qalam_export_${DateTime.now().millisecondsSinceEpoch}.$ext';
        final tmpDir = await getTemporaryDirectory();
        final tmpPath = p.join(tmpDir.path, fileName);
        await File(tmpPath).writeAsBytes(bytes);
        tmpPathForShare = tmpPath;
        if (shareOnly) {
          await Share.shareXFiles([XFile(tmpPath)], text: _project.name);
        } else {
          savedLocation = await _saveBytesToDeviceGallery(bytes, fileName);
        }
      },
    );
    if (!shareOnly && savedLocation != null && tmpPathForShare != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved to Gallery: $savedLocation'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Share',
            textColor: _amber,
            onPressed: () => Share.shareXFiles([XFile(tmpPathForShare!)], text: _project.name),
          ),
        ),
      );
    }
  }

  Future<void> _showExportOptionsSheet() async {
    String format = 'png';
    double scale = 2.0;
    bool transparent = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _mutedColor.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _amber.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.download_rounded, color: _accentText, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Export Options', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                              Text(
                                '${_page.width.round()} × ${_page.height.round()} px · ${(scale).toInt()}x Output',
                                style: TextStyle(fontSize: 12, color: _subColor),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('File Format', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _subColor)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _optionTile(
                            label: 'PNG (Lossless)',
                            selected: format == 'png',
                            onTap: () => setSheetState(() => format = 'png'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _optionTile(
                            label: 'JPG (Compact)',
                            selected: format == 'jpg',
                            onTap: () => setSheetState(() {
                              format = 'jpg';
                              transparent = false;
                            }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text('Resolution Scale', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _subColor)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final s in [1.0, 2.0, 3.0]) ...[
                          Expanded(
                            child: _optionTile(
                              label: s == 1.0 ? '1x Std' : (s == 2.0 ? '2x HD' : '3x Ultra'),
                              selected: scale == s,
                              onTap: () => setSheetState(() => scale = s),
                            ),
                          ),
                          if (s != 3.0) const SizedBox(width: 8),
                        ],
                      ],
                    ),
                    if (format == 'png') ...[
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: _inputBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _borderColor),
                        ),
                        child: SwitchListTile(
                          dense: true,
                          title: const Text('Transparent Background', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text('Export overlays without canvas fill', style: TextStyle(fontSize: 11, color: _subColor)),
                          value: transparent,
                          activeColor: _amber,
                          onChanged: (v) => setSheetState(() => transparent = v),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _amber,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _executeExport(
                            format: format,
                            scale: scale,
                            transparent: transparent,
                            shareOnly: false,
                            asPdf: false,
                          );
                        },
                        icon: const Icon(Icons.save_alt_rounded, size: 19),
                        label: const Text('Save to Gallery', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              side: BorderSide(color: _borderColor),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _executeExport(
                                format: format,
                                scale: scale,
                                transparent: transparent,
                                shareOnly: true,
                                asPdf: false,
                              );
                            },
                            icon: const Icon(Icons.share_outlined, size: 18),
                            label: const Text('Share'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              side: BorderSide(color: _borderColor),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _executeExport(
                                format: 'png',
                                scale: scale,
                                transparent: false,
                                shareOnly: false,
                                asPdf: true,
                              );
                            },
                            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                            label: Text(_project.pages.length > 1 ? 'PDF (${_project.pages.length} Pages)' : 'Print / PDF'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(color: _borderColor),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _shareProjectFile(_project);
                        },
                        icon: Icon(Icons.folder_shared_outlined, size: 18, color: _accentText),
                        label: const Text('Share Editable Project (.qalam.json)'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _optionTile({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _amber : _chipBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? _amber : _borderColor),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.black : _textColor,
          ),
        ),
      ),
    );
  }

  Future<void> _importCanvasImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final permanentPath = await _persistPickedImageOffline(picked.path);
    final bytes = await File(permanentPath).readAsBytes();
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
      localImagePath: permanentPath,
      aspectLocked: true,
      objectFit: BoxFit.cover,
    );

    _pushUndoSnapshot();
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
      _selectedLayerId = null;
      _inspectorTab = 2;
      _sheetExpanded = true;
    });
    await _saveCurrentProject(showToast: false);
  }

  Future<void> _addOverlayImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final permanentPath = await _persistPickedImageOffline(picked.path);
    final bytes = await File(permanentPath).readAsBytes();
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
      localImagePath: permanentPath,
      aspectLocked: true,
      objectFit: BoxFit.cover,
    );

    _pushUndoSnapshot();
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
    _clampLayerInPage(layer);
    _pushUndoSnapshot();
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
    _clampLayerInPage(layer);
    _pushUndoSnapshot();
    setState(() {
      _page.layers.add(layer);
      _selectedLayerId = layer.id;
      _inspectorTab = 1;
      _sheetExpanded = true;
    });
  }

  void _clampLayerInPage(DesignLayer layer) {
    if (layer.isCanvasBackground) return;
    layer.width = layer.width.clamp(16.0, math.max(16.0, _page.width * 3.0)).toDouble();
    layer.height = layer.height.clamp(16.0, math.max(16.0, _page.height * 3.0)).toDouble();
    const minOverlap = 24.0;
    final minX = -(layer.width - minOverlap);
    final maxX = _page.width - minOverlap;
    final minY = -(layer.height - minOverlap);
    final maxY = _page.height - minOverlap;
    layer.x = layer.x.clamp(minX, maxX).toDouble();
    layer.y = layer.y.clamp(minY, maxY).toDouble();
  }

  void _duplicateSelectedLayer() {
    final l = _activeLayer;
    if (l == null) return;
    _pushUndoSnapshot();
    final copy = l.cloneWithNewId('dup_${DateTime.now().microsecondsSinceEpoch}');
    _clampLayerInPage(copy);
    setState(() {
      _page.layers.add(copy);
      _selectedLayerId = copy.id;
      if (copy.type == LayerType.text) _textController.text = copy.text;
    });
  }

  void _deleteSelectedLayer() {
    final l = _activeLayer;
    if (l == null || l.isCanvasBackground) return;
    _pushUndoSnapshot();
    setState(() {
      _page.layers.removeWhere((x) => x.id == l.id);
      _selectedLayerId = null;
    });
  }

  void _moveLayerOrder(DesignLayer layer, int delta) {
    if (layer.isCanvasBackground) return;
    final idx = _page.layers.indexWhere((x) => x.id == layer.id);
    if (idx == -1) return;
    final minIdx = _page.layers.isNotEmpty && _page.layers.first.isCanvasBackground ? 1 : 0;
    final target = (idx + delta).clamp(minIdx, _page.layers.length - 1);
    if (target == idx) return;
    _pushUndoSnapshot();
    setState(() {
      final item = _page.layers.removeAt(idx);
      _page.layers.insert(target, item);
    });
  }

  Future<void> _applyWhiteRemoval(DesignLayer layer, double tolerance) async {
    if (layer.localImagePath == null) return;
    final seq = ++_whiteRemovalSeq;
    if (tolerance <= 0) {
      setState(() {
        layer.filters.removeWhite = 0;
        layer.processedWhiteRemovedBytes = null;
      });
      return;
    }
    setState(() => layer.filters.removeWhite = tolerance);
    final pngBytes = await removeWhiteBackgroundOffline(layer.localImagePath!, tolerance);
    if (!mounted || seq != _whiteRemovalSeq) return;
    setState(() => layer.processedWhiteRemovedBytes = pngBytes);
    await _saveCurrentProject(showToast: false);
  }

  @override
  Widget build(BuildContext context) {
    final stageBg = _isDark ? const Color(0xFF0A0C0F) : const Color(0xFFE5E7EB);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 58,
        titleSpacing: 14,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _borderColor),
        ),
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: _amber,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Q',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: () => _renameProjectDialog(_project),
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            _project.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.edit_outlined, size: 13, color: _mutedColor),
                      ],
                    ),
                    Text(
                      '${_page.title} · ${_page.width.round()}×${_page.height.round()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: _subColor),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Document Scanner',
            icon: Icon(Icons.document_scanner_outlined, size: 21, color: _accentText),
            onPressed: _openDocumentScannerSheet,
          ),
          if (_navIndex == 0)
            IconButton(
              tooltip: _showGuides ? 'Guides: ON (Tap to Hide)' : 'Guides: OFF (Tap to Show)',
              icon: Icon(
                _showGuides ? Icons.grid_on_rounded : Icons.grid_off_rounded,
                size: 20,
                color: _showGuides ? _accentText : _mutedColor,
              ),
              onPressed: () => setState(() => _showGuides = !_showGuides),
            ),
          IconButton(
            tooltip: 'Quick Guide & Help',
            icon: const Icon(Icons.help_outline_rounded, size: 21),
            onPressed: _showQuickTourSheet,
          ),
          IconButton(
            tooltip: _isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            icon: Icon(
              _isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: _accentText,
              size: 21,
            ),
            onPressed: () {
              appThemeMode.value = _isDark ? ThemeMode.light : ThemeMode.dark;
            },
          ),
          IconButton(
            tooltip: 'Save Offline',
            icon: const Icon(Icons.save_outlined, size: 21),
            onPressed: _saveCurrentProject,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10, left: 2),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _amber,
                foregroundColor: Colors.black,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              onPressed: _showExportOptionsSheet,
              icon: const Icon(Icons.download_rounded, size: 17),
              label: const Text('Export', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _navIndex,
        children: [
          _buildStudioView(stageBg),
          _navIndex == 1 ? _buildQuickFillView() : const SizedBox.shrink(),
          _navIndex == 2 ? _buildSignatureView() : const SizedBox.shrink(),
          _buildPagesView(),
          _buildBatchView(),
          _buildProjectsView(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: _borderColor)),
        ),
        child: NavigationBar(
          selectedIndex: _navIndex,
          onDestinationSelected: (i) => setState(() {
            _navIndex = i;
            if (i == 0 && _activeLayer?.type == LayerType.text) {
              _textController.text = _activeLayer!.text;
            }
          }),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.brush_outlined), selectedIcon: Icon(Icons.brush_rounded), label: 'Studio'),
            NavigationDestination(icon: Icon(Icons.edit_note_rounded), label: 'Fill'),
            NavigationDestination(icon: Icon(Icons.draw_outlined), selectedIcon: Icon(Icons.draw_rounded), label: 'Sign/Seal'),
            NavigationDestination(icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description_rounded), label: 'Docs'),
            NavigationDestination(icon: Icon(Icons.auto_awesome_motion_outlined), selectedIcon: Icon(Icons.auto_awesome_motion_rounded), label: 'Batch'),
            NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder_rounded), label: 'Projects'),
          ],
        ),
      ),
    );
  }

  Widget _buildStudioView(Color stageBg) {
    final layer = _activeLayer;
    final screenH = MediaQuery.of(context).size.height;
    final expandedH = math.min(248.0, math.max(190.0, screenH * 0.29));

    return Column(
      children: [
        Expanded(
          child: Container(
            color: stageBg,
            child: LayerCanvas(
              page: _page,
              selectedLayerId: _selectedLayerId,
              exportBoundaryKey: _canvasExportKey,
              showSelectionHandles: !_hideOverlaysForExport,
              showGuides: _showGuides,
              hideOverlaysForExport: _hideOverlaysForExport,
              forceTransparentBackground: _exportTransparentCanvas,
              onSelectLayer: _selectLayer,
              onUpdateLayer: (_) => setState(() {}),
              onInteractionStart: _pushUndoSnapshot,
            ),
          ),
        ),
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: _panelBg,
            border: Border(top: BorderSide(color: _borderColor)),
          ),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            children: [
              _quickBtn(Icons.photo_size_select_large, 'Canvas Pic', _importCanvasImage, highlight: true),
              _quickBtn(Icons.document_scanner_outlined, 'Scanner', _openDocumentScannerSheet),
              if (_undoStack.isNotEmpty) _quickBtn(Icons.undo_rounded, 'Undo', _undoCanvas),
              if (_redoStack.isNotEmpty) _quickBtn(Icons.redo_rounded, 'Redo', _redoCanvas),
              _quickBtn(Icons.title_rounded, 'Add Text', _addTextLayer),
              _quickBtn(Icons.add_photo_alternate_outlined, 'Overlay', _addOverlayImage),
              _quickBtn(Icons.crop_square_rounded, 'Shape', _addShapeLayer),
              if (layer != null) ...[
                _quickBtn(Icons.copy_rounded, 'Duplicate', _duplicateSelectedLayer),
                if (!layer.isCanvasBackground)
                  _quickBtn(Icons.delete_outline_rounded, 'Delete', _deleteSelectedLayer, danger: true),
              ],
            ],
          ),
        ),
        Container(
          height: _sheetExpanded ? expandedH : 44,
          decoration: BoxDecoration(
            color: _panelBg,
            border: Border(top: BorderSide(color: _borderColor)),
          ),
          child: Column(
            children: [
              Container(
                height: 43,
                padding: const EdgeInsets.only(left: 8, right: 4),
                decoration: BoxDecoration(
                  border: _sheetExpanded ? Border(bottom: BorderSide(color: _borderColor)) : null,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _tabChip(0, 'Design', Icons.tune_rounded),
                            _tabChip(1, 'Overlay', Icons.layers_outlined),
                            _tabChip(2, 'BG Clean', Icons.cleaning_services_outlined),
                            _tabChip(3, 'Layers (${_page.layers.length})', Icons.format_list_bulleted_rounded),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: _sheetExpanded ? 'Collapse Panel' : 'Expand Panel',
                      icon: Icon(
                        _sheetExpanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                        color: _subColor,
                      ),
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

  Widget _quickBtn(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool highlight = false,
    bool danger = false,
  }) {
    final bg = highlight
        ? _amber
        : (danger ? Colors.redAccent.withOpacity(0.12) : _chipBg);
    final fg = highlight
        ? Colors.black
        : (danger ? Colors.redAccent : _textColor);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(9),
            border: highlight ? null : Border.all(color: danger ? Colors.redAccent.withOpacity(0.3) : _borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabChip(int idx, String label, IconData icon) {
    final active = _inspectorTab == idx;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => setState(() {
          _inspectorTab = idx;
          _sheetExpanded = true;
        }),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active ? _amber : _chipBg,
            borderRadius: BorderRadius.circular(8),
            border: active ? null : Border.all(color: _borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: active ? Colors.black : _subColor),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? Colors.black : _textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInspectorBody(DesignLayer? layer) {
    // TAB 3: LAYERS
    if (_inspectorTab == 3) {
      if (_page.layers.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Text('No layers yet. Use Add Text, Overlay, or Canvas Pic above.', style: TextStyle(color: _subColor)),
        );
      }
      final reversed = _page.layers.reversed.toList();
      return ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: reversed.length,
        onReorder: (oldIndex, newIndex) {
          if (oldIndex < 0 || oldIndex >= reversed.length) return;
          final dragged = reversed[oldIndex];
          if (dragged.isCanvasBackground) return;
          if (newIndex > oldIndex) newIndex -= 1;
          final total = _page.layers.length;
          final fromArr = total - 1 - oldIndex;
          var toArr = total - 1 - newIndex;
          final minArr = _page.layers.isNotEmpty && _page.layers.first.isCanvasBackground ? 1 : 0;
          toArr = toArr.clamp(minArr, total - 1);
          if (fromArr == toArr) return;
          _pushUndoSnapshot();
          setState(() {
            final item = _page.layers.removeAt(fromArr);
            _page.layers.insert(toArr, item);
          });
        },
        itemBuilder: (context, index) {
          final l = reversed[index];
          final isSel = !l.isCanvasBackground && l.id == _selectedLayerId;
          final typeIcon = l.isCanvasBackground
              ? Icons.wallpaper_rounded
              : (l.type == LayerType.text
                  ? Icons.title_rounded
                  : (l.type == LayerType.image ? Icons.image_outlined : Icons.crop_square_rounded));
          return Container(
            key: ValueKey('layer_row_${l.id}'),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 6),
            decoration: BoxDecoration(
              color: isSel ? _amber.withOpacity(0.12) : _inputBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isSel ? _amber : _borderColor, width: isSel ? 1.4 : 1),
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: l.isCanvasBackground
                      ? () => setState(() {
                            _selectedLayerId = null;
                            _inspectorTab = 2;
                          })
                      : () => _selectLayer(l.id),
                  child: Row(
                    children: [
                      if (!l.isCanvasBackground)
                        ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
                            child: Icon(Icons.drag_indicator_rounded, size: 20, color: _mutedColor),
                          ),
                        ),
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: isSel ? _amber.withOpacity(0.22) : _chipBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(typeIcon, size: 16, color: isSel ? _accentText : _subColor),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.isCanvasBackground ? '${l.name} (Fixed Canvas BG)' : l.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${(l.opacity * 100).round()}% · ${l.blendMode.name} · ${l.width.round()}×${l.height.round()}',
                              style: TextStyle(fontSize: 11, color: _subColor),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!l.isCanvasBackground) ...[
                      _compactLayerIcon(Icons.arrow_upward_rounded, 'Bring Forward', () => _moveLayerOrder(l, 1)),
                      _compactLayerIcon(Icons.arrow_downward_rounded, 'Send Backward', () => _moveLayerOrder(l, -1)),
                    ],
                    _compactLayerIcon(Icons.edit_outlined, 'Rename Layer', () => _renameLayerDialog(l)),
                    if (l.type == LayerType.image)
                      _compactLayerIcon(
                        Icons.swap_horiz_rounded,
                        'Replace Image',
                        () => _replaceLayerImageKeepingConfig(l),
                        color: _accentText,
                      ),
                    _compactLayerIcon(
                      l.visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      l.visible ? 'Hide' : 'Show',
                      () => setState(() => l.visible = !l.visible),
                    ),
                    if (!l.isCanvasBackground)
                      _compactLayerIcon(
                        l.locked ? Icons.lock_outline : Icons.lock_open_rounded,
                        l.locked ? 'Unlock' : 'Lock',
                        () => setState(() => l.locked = !l.locked),
                      ),
                    _compactLayerIcon(
                      Icons.delete_outline_rounded,
                      'Delete',
                      () => setState(() {
                        _page.layers.removeWhere((x) => x.id == l.id);
                        if (_selectedLayerId == l.id) _selectedLayerId = null;
                      }),
                      color: Colors.redAccent,
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    }

    // TAB 2: BG CLEAN
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
        return Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            'Import a Canvas Pic or select an Overlay Image to use Remove White BG.',
            style: TextStyle(color: _subColor, fontSize: 13),
          ),
        );
      }
      final isWhiteRemoved = targetImg.filters.removeWhite > 0;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cleaning_services_outlined, size: 15, color: _accentText),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  targetImg.isCanvasBackground
                      ? 'Canvas Photo: ${targetImg.name}'
                      : 'Image: ${targetImg.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: _accentText, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () async {
                  await _runWithSavingHud(
                    savingTitle: 'Resetting BG Clean...',
                    savedTitle: 'Reset Saved',
                    action: () async {
                      setState(() {
                        targetImg.filters = FilterSettings();
                        targetImg.processedWhiteRemovedBytes = null;
                      });
                      await _saveCurrentProject(showToast: false);
                    },
                  );
                },
                child: const Text('Reset', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: isWhiteRemoved ? const Color(0xFF10B981) : _chipBg,
                foregroundColor: isWhiteRemoved ? Colors.black : _textColor,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _applyWhiteRemoval(targetImg, isWhiteRemoved ? 0.0 : 35.0),
              icon: const Icon(Icons.cleaning_services_outlined, size: 17),
              label: Text(
                isWhiteRemoved ? 'White BG Removed ✓' : 'Remove White BG',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (isWhiteRemoved)
            _sliderRow(
              'White Tol.',
              targetImg.filters.removeWhite,
              5,
              95,
              (v) => setState(() => targetImg.filters.removeWhite = v),
              onChangeEnd: (v) => _applyWhiteRemoval(targetImg, v),
            ),
        ],
      );
    }

    // TAB 1: OVERLAY & TRANSFORM
    if (_inspectorTab == 1) {
      if (layer == null) {
        return Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            'Tap any layer on the canvas to adjust exact Size, Opacity, Blend Mode, Rotation, or Nudge.',
            style: TextStyle(color: _subColor, fontSize: 13),
          ),
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
          _buildExactSizeInputs(layer),
          const SizedBox(height: 6),
          _sliderRow('Opacity', layer.opacity, 0.0, 1.0, (v) => setState(() => layer.opacity = v)),
          _sliderRow('Rotation', layer.rotation, -180.0, 180.0, (v) => setState(() => layer.rotation = v)),
          const SizedBox(height: 6),
          Text('Blend Mode', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _subColor)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: blends.map((b) {
              final sel = layer.blendMode == b;
              return _choicePill(
                label: b.name,
                selected: sel,
                onTap: () => setState(() => layer.blendMode = b),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _inputBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _borderColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Nudge (5px)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _subColor)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _compactLayerIcon(Icons.arrow_back_rounded, 'Left', () => setState(() {
                      layer.x -= 5;
                      _clampLayerInPage(layer);
                    })),
                    _compactLayerIcon(Icons.arrow_upward_rounded, 'Up', () => setState(() {
                      layer.y -= 5;
                      _clampLayerInPage(layer);
                    })),
                    _compactLayerIcon(Icons.arrow_downward_rounded, 'Down', () => setState(() {
                      layer.y += 5;
                      _clampLayerInPage(layer);
                    })),
                    _compactLayerIcon(Icons.arrow_forward_rounded, 'Right', () => setState(() {
                      layer.x += 5;
                      _clampLayerInPage(layer);
                    })),
                    const SizedBox(width: 4),
                    _compactLayerIcon(
                      Icons.center_focus_strong_outlined,
                      'Center on Canvas',
                      () => setState(() {
                        layer.x = (_page.width - layer.width) / 2;
                        layer.y = (_page.height - layer.height) / 2;
                        _clampLayerInPage(layer);
                      }),
                      color: _accentText,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    // TAB 0: DESIGN
    if (layer == null) {
      final bgColors = [
        const Color(0xFF191C22),
        const Color(0xFF000000),
        const Color(0xFFFFFFFF),
        const Color(0xFFFAF9F6),
        Colors.transparent,
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _amber,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _importCanvasImage,
            icon: const Icon(Icons.upload_rounded, size: 18),
            label: const Text('Import Canvas Image (Match Photo Size)', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 12),
          Text('Canvas Size Presets', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _subColor)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ('Poster 900×1200', 900.0, 1200.0),
              ('Square 1080×1080', 1080.0, 1080.0),
              ('Story 1080×1920', 1080.0, 1920.0),
              ('Thumb 1280×720', 1280.0, 720.0),
              ('A4 Doc 992×1403', 992.0, 1403.0),
            ].map((pItem) {
              final sel = (_page.width - pItem.$2).abs() < 2 && (_page.height - pItem.$3).abs() < 2;
              return _choicePill(
                label: pItem.$1,
                selected: sel,
                onTap: () {
                  _pushUndoSnapshot();
                  setState(() {
                    _page.width = pItem.$2;
                    _page.height = pItem.$3;
                    for (final l in _page.layers) {
                      _clampLayerInPage(l);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ExactNumberBox(
                  key: ValueKey('pgw_${_page.id}'),
                  value: _page.width,
                  min: 200,
                  max: 4096,
                  labelText: 'Canvas W',
                  onChanged: (v) => setState(() => _page.width = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ExactNumberBox(
                  key: ValueKey('pgh_${_page.id}'),
                  value: _page.height,
                  min: 200,
                  max: 4096,
                  labelText: 'Canvas H',
                  onChanged: (v) => setState(() => _page.height = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Canvas Background', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _subColor)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: bgColors.map((c) {
              final sel = _page.backgroundColor.value == c.value;
              return GestureDetector(
                onTap: () => setState(() => _page.backgroundColor = c),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: c == Colors.transparent ? _chipBg : c,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: sel ? _amber : _borderColor,
                      width: sel ? 2.5 : 1.2,
                    ),
                  ),
                  child: c == Colors.transparent
                      ? Icon(Icons.grid_on_rounded, size: 17, color: _subColor)
                      : (sel
                          ? Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: c.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                            )
                          : null),
                ),
              );
            }).toList(),
          ),
        ],
      );
    }

    if (layer.type == LayerType.text) {
      const fontItems = [
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
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Edit Text (Urdu / English)',
            ),
            onChanged: (val) => setState(() => layer.text = val),
          ),
          const SizedBox(height: 10),
          Text('Font Family', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _subColor)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: fontItems.map((f) {
              return _choicePill(
                label: f.$2,
                selected: layer.fontFamily == f.$1,
                onTap: () => setState(() {
                  layer.fontFamily = f.$1;
                  layer.isRtl = f.$3;
                  layer.lineHeight = f.$4;
                  if (f.$1 == 'IBMPlexSansArabicSemiBold') layer.fontWeight = 600;
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _choicePill(
                label: 'Regular',
                selected: layer.fontWeight < 550,
                onTap: () => setState(() => layer.fontWeight = 400),
              ),
              const SizedBox(width: 8),
              _choicePill(
                label: 'Halka Bold (SemiBold)',
                selected: layer.fontWeight >= 550,
                onTap: () => setState(() => layer.fontWeight = 600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _sliderRow('Text Scale', layer.fontSize, 12, 200, (v) => setState(() => layer.fontSize = v)),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(side: BorderSide(color: _borderColor)),
                  onPressed: () => setState(() => layer.fontSize = (layer.fontSize - 6).clamp(12.0, 200.0)),
                  child: const Text('A− Smaller'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(side: BorderSide(color: _borderColor)),
                  onPressed: () => setState(() => layer.fontSize = (layer.fontSize + 6).clamp(12.0, 200.0)),
                  child: const Text('A+ Larger'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Alignment & Direction', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _subColor)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _choicePill(
                label: 'Left',
                selected: (layer.textAlign ?? (layer.isRtl ? TextAlign.right : TextAlign.left)) == TextAlign.left,
                onTap: () => setState(() => layer.textAlign = TextAlign.left),
              ),
              _choicePill(
                label: 'Center',
                selected: layer.textAlign == TextAlign.center,
                onTap: () => setState(() => layer.textAlign = TextAlign.center),
              ),
              _choicePill(
                label: 'Right',
                selected: (layer.textAlign ?? (layer.isRtl ? TextAlign.right : TextAlign.left)) == TextAlign.right,
                onTap: () => setState(() => layer.textAlign = TextAlign.right),
              ),
              _choicePill(
                label: layer.isRtl ? 'RTL (Urdu)' : 'LTR (Eng)',
                selected: true,
                onTap: () => setState(() => layer.isRtl = !layer.isRtl),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Text Color', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _subColor)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            children: [
              const Color(0xFFFFFFFF),
              _amber,
              const Color(0xFF0F172A),
              const Color(0xFF10B981),
              const Color(0xFFE11D48),
              const Color(0xFF2563EB),
            ].map((c) {
              final sel = layer.textColor.value == c.value;
              return GestureDetector(
                onTap: () => setState(() => layer.textColor = c),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: sel ? _amber : _borderColor,
                      width: sel ? 3 : 1.2,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Text('Text Highlight Box', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _subColor)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            children: [
              Colors.transparent,
              const Color(0xCC000000),
              const Color(0xE6FFFFFF),
              _amber,
              const Color(0xFF047857),
              const Color(0xFFB91C1C),
            ].map((c) {
              final sel = layer.textBgColor.value == c.value;
              return GestureDetector(
                onTap: () => setState(() => layer.textBgColor = c),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: c == Colors.transparent ? _chipBg : c,
                    shape: BoxShape.circle,
                    border: Border.all(color: sel ? _amber : _borderColor, width: sel ? 3 : 1.2),
                  ),
                  child: c == Colors.transparent
                      ? Icon(Icons.block_rounded, size: 15, color: _subColor)
                      : null,
                ),
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
          _clampLayerInPage(layer);
        });
      }

      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: layer.aspectLocked ? _amber : _chipBg,
                    foregroundColor: layer.aspectLocked ? Colors.black : _textColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => setState(() => layer.aspectLocked = !layer.aspectLocked),
                  icon: Icon(layer.aspectLocked ? Icons.lock : Icons.lock_open, size: 16),
                  label: Text(layer.aspectLocked ? 'Ratio Locked' : 'Free Stretch',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          _sliderRow('Image Scale %', curScale, 10, 250, applyImageScale),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(side: BorderSide(color: _borderColor)),
                  onPressed: () => applyImageScale(curScale - 10),
                  child: const Text('− Smaller'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(side: BorderSide(color: _borderColor)),
                  onPressed: () => applyImageScale(curScale + 10),
                  child: const Text('+ Larger'),
                ),
              ),
            ],
          ),
          _sliderRow('Corner Radius', layer.borderRadius, 0, 160,
              (v) => setState(() => layer.borderRadius = v)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(side: BorderSide(color: layer.flipX ? _amber : _borderColor)),
                  onPressed: () => setState(() => layer.flipX = !layer.flipX),
                  icon: const Icon(Icons.flip_rounded, size: 16),
                  label: const Text('Flip H'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(side: BorderSide(color: layer.flipY ? _amber : _borderColor)),
                  onPressed: () => setState(() => layer.flipY = !layer.flipY),
                  icon: const Icon(Icons.flip_camera_android_rounded, size: 16),
                  label: const Text('Flip V'),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sliderRow('Corner Radius', layer.borderRadius, 0, 120,
            (v) => setState(() => layer.borderRadius = v)),
        const SizedBox(height: 6),
        Text('Shape Color', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _subColor)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          children: [
            const Color(0xFF111317),
            const Color(0xFFFFFFFF),
            _amber,
            const Color(0xFF10B981),
            const Color(0xFFE11D48),
            const Color(0xFF2563EB),
          ].map((c) {
            final sel = layer.textColor.value == c.value;
            return GestureDetector(
              onTap: () => setState(() => layer.textColor = c),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(color: sel ? _amber : _borderColor, width: sel ? 3 : 1.2),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _choicePill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _amber : _chipBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? _amber : _borderColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.black : _textColor,
          ),
        ),
      ),
    );
  }

  Widget _compactLayerIcon(IconData icon, String tooltip, VoidCallback onTap, {Color? color}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 17, color: color ?? _subColor),
        ),
      ),
    );
  }

  Widget _buildExactSizeInputs(DesignLayer layer) {
    return Row(
      children: [
        Expanded(
          child: _ExactNumberBox(
            key: ValueKey('w_${layer.id}'),
            value: layer.width,
            min: 1.0,
            max: 20000.0,
            labelText: 'Width (px)',
            onChanged: (nextW) {
              setState(() {
                if (layer.type == LayerType.image && layer.aspectLocked && layer.width > 0 && layer.height > 0) {
                  final ratio = layer.width / layer.height;
                  layer.height = (nextW / ratio).clamp(1.0, 20000.0);
                }
                layer.width = nextW;
                _clampLayerInPage(layer);
              });
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ExactNumberBox(
            key: ValueKey('h_${layer.id}'),
            value: layer.height,
            min: 1.0,
            max: 20000.0,
            labelText: 'Height (px)',
            onChanged: (nextH) {
              setState(() {
                if (layer.type == LayerType.image && layer.aspectLocked && layer.width > 0 && layer.height > 0) {
                  final ratio = layer.width / layer.height;
                  layer.width = (nextH * ratio).clamp(1.0, 20000.0);
                }
                layer.height = nextH;
                _clampLayerInPage(layer);
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _sliderRow(
    String label,
    double val,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    ValueChanged<double>? onChangeEnd,
    bool allowCustomInput = false,
    double? inputMin,
    double? inputMax,
  }) {
    final iMin = inputMin ?? min;
    final iMax = inputMax ?? max;
    return Row(
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _subColor),
          ),
        ),
        Expanded(
          child: Slider(
            value: val.clamp(min, max),
            min: min,
            max: max,
            activeColor: _amber,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        if (allowCustomInput)
          SizedBox(
            width: 58,
            child: _ExactNumberBox(
              key: ValueKey('num_${label}_${_selectedLayerId ?? "page"}'),
              value: val,
              min: iMin,
              max: iMax,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              onChanged: onChanged,
            ),
          )
        else
          SizedBox(
            width: 42,
            child: Text(
              val.toStringAsFixed(val > 5 ? 0 : 2),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _textColor),
            ),
          ),
      ],
    );
  }

  Widget _buildQuickFillView() {
    final fields = _page.layers.where((l) => l.type == LayerType.text || l.type == LayerType.image).toList();
    final textFields = _page.layers.where((l) => l.type == LayerType.text).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Quick Fill Form', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(
                    'Update text & photos by Layer Name — exact coordinates & layout kept',
                    style: TextStyle(fontSize: 12, color: _subColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _amber, foregroundColor: Colors.black),
              onPressed: () => setState(() => _navIndex = 0),
              icon: const Icon(Icons.brush_outlined, size: 16),
              label: const Text('Studio'),
            ),
          ],
        ),
        if (textFields.length > 1) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _amber.withOpacity(0.8)),
                foregroundColor: _accentText,
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
              onPressed: () async {
                final chosen = await showModalBottomSheet<(String, String, int, double)>(
                  context: context,
                  backgroundColor: _cardBg,
                  builder: (ctx) {
                    const presets = [
                      ('NotoNastaliqUrdu', 'Urdu Nastaliq', 400, 2.3),
                      ('Gulzar', 'Gulzar Urdu', 400, 2.1),
                      ('NotoNaskhArabic', 'Naskh Urdu', 400, 1.9),
                      ('IBMPlexSansArabicSemiBold', 'Halka Bold (Urdu+Eng)', 600, 1.8),
                      ('PlusJakartaSans', 'Jakarta Sans', 400, 1.35),
                      ('Montserrat', 'Montserrat', 400, 1.3),
                      ('Poppins', 'Poppins', 400, 1.35),
                      ('PlayfairDisplay', 'Playfair Serif', 400, 1.3),
                      ('Lora', 'Lora Serif', 400, 1.4),
                      ('Oswald', 'Oswald Bold', 400, 1.2),
                      ('BebasNeue', 'Bebas Poster', 400, 1.1),
                    ];
                    return SafeArea(
                      child: ListView(
                        padding: const EdgeInsets.all(14),
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text('Pick 1 Font for ALL Text Layers', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                          ...presets.map((f) => ListTile(
                                title: Text(f.$2, style: TextStyle(fontFamily: f.$1)),
                                trailing: Icon(Icons.check_circle_outline, color: _accentText),
                                onTap: () => Navigator.pop(ctx, f),
                              )),
                        ],
                      ),
                    );
                  },
                );
                if (chosen != null) await _applyFontToAllTextLayers(chosen.$1, chosen.$3, chosen.$4);
              },
              icon: const Icon(Icons.font_download_outlined, size: 17),
              label: Text('Apply Same Font to All (${textFields.length} Text Layers)'),
            ),
          ),
        ],
        if (_project.pages.length > 1) ...[
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(
                _project.pages.length,
                (i) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _choicePill(
                    label: _project.pages[i].title,
                    selected: i == _pageIndex,
                    onTap: () => setState(() {
                      _pageIndex = i;
                      _selectedLayerId = null;
                    }),
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        if (fields.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No text or image layers on this page yet. Add layers in Studio and name them (e.g. Name, Father Name, Photo).',
                style: TextStyle(color: _subColor),
              ),
            ),
          )
        else
          ...fields.map((l) {
            if (l.type == LayerType.text) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.title_rounded, size: 16, color: _accentText),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            ),
                            Text('X:${l.x.round()} Y:${l.y.round()}', style: TextStyle(fontSize: 11, color: _mutedColor)),
                            IconButton(
                              tooltip: 'Rename Field',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              onPressed: () => _renameLayerDialog(l),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          key: ValueKey('${_project.id}_${_page.id}_${l.id}_${l.name}'),
                          initialValue: l.text,
                          textDirection: l.isRtl ? TextDirection.rtl : TextDirection.ltr,
                          maxLines: null,
                          style: TextStyle(
                            fontFamily: l.fontFamily,
                            fontSize: 17,
                            fontVariations: [ui.FontVariation('wght', l.fontWeight.toDouble())],
                          ),
                          decoration: InputDecoration(hintText: 'Enter ${l.name}...'),
                          onChanged: (val) => setState(() {
                            l.text = val;
                            if (_selectedLayerId == l.id) _textController.text = val;
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final filterTags = <String>[
              if (l.filters.removeWhite > 0) 'White BG Removed (${l.filters.removeWhite.round()}%)',
            ];
            Widget? thumb;
            if (l.processedWhiteRemovedBytes != null) {
              thumb = Image.memory(l.processedWhiteRemovedBytes!, fit: BoxFit.contain);
            } else if (l.localImagePath != null && File(l.localImagePath!).existsSync()) {
              thumb = Image.file(File(l.localImagePath!), fit: BoxFit.contain);
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.image_outlined, size: 16, color: _accentText),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              l.isCanvasBackground ? '${l.name} (Canvas BG)' : l.name,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                          ),
                          Text('${l.width.round()}×${l.height.round()}', style: TextStyle(fontSize: 11, color: _mutedColor)),
                          IconButton(
                            tooltip: 'Rename Field',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            onPressed: () => _renameLayerDialog(l),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: _inputBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _borderColor),
                            ),
                            child: thumb == null
                                ? Icon(Icons.image_outlined, color: _mutedColor)
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(9),
                                    child: ColorFiltered(colorFilter: buildLayerColorFilter(l.filters), child: thumb),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  filterTags.isEmpty
                                      ? 'Same position & size kept'
                                      : filterTags.join(' · '),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: filterTags.isEmpty
                                        ? _subColor
                                        : (_isDark ? Colors.greenAccent : Colors.green.shade700),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(backgroundColor: _amber, foregroundColor: Colors.black),
                                  onPressed: () => _replaceLayerImageKeepingConfig(l),
                                  icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                                  label: const Text('Replace Image'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Future<void> _loadBusinessTemplate(String kind) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    late DesignProject tpl;
    if (kind == 'cash_memo') {
      tpl = DesignProject(
        id: 'tpl_bill_$now',
        name: 'Cash Memo / Bill (رسید)',
        updatedAt: now,
        pages: [
          DocumentPage(
            id: 'pg_bill_$now',
            title: 'Cash Memo A4',
            width: 992,
            height: 1403,
            backgroundColor: Colors.white,
            layers: [
              DesignLayer(
                id: 'bill_hdr_$now',
                name: 'Header Banner',
                type: LayerType.shape,
                x: 48,
                y: 48,
                width: 896,
                height: 170,
                textColor: const Color(0xFF0F172A),
                borderRadius: 16,
              ),
              DesignLayer(
                id: 'bill_shop_en_$now',
                name: 'Shop Name (English)',
                type: LayerType.text,
                x: 78,
                y: 78,
                width: 430,
                height: 110,
                text: 'AL-NOOR TRADERS\nWHOLESALE & PRINT HOUSE',
                fontFamily: 'PlusJakartaSans',
                fontSize: 30,
                fontWeight: 700,
                textAlign: TextAlign.left,
                isRtl: false,
                textColor: Colors.white,
                lineHeight: 1.3,
              ),
              DesignLayer(
                id: 'bill_shop_ur_$now',
                name: 'Shop Name (Urdu)',
                type: LayerType.text,
                x: 515,
                y: 70,
                width: 400,
                height: 125,
                text: 'النور ٹریڈرز اینڈ پرنٹرز\nکیش میمو / بل رسید',
                fontFamily: 'NotoNastaliqUrdu',
                fontSize: 28,
                fontWeight: 700,
                textAlign: TextAlign.right,
                isRtl: true,
                textColor: const Color(0xFFFBBF24),
                lineHeight: 1.95,
              ),
              DesignLayer(
                id: 'bill_meta_$now',
                name: 'Bill No & Date',
                type: LayerType.text,
                x: 56,
                y: 248,
                width: 880,
                height: 76,
                text: 'Bill No: #INV-1042      Date: 17 Nov 2025      Ph: 0300-1234567',
                fontFamily: 'PlusJakartaSans',
                fontSize: 22,
                fontWeight: 600,
                textAlign: TextAlign.left,
                isRtl: false,
                textColor: const Color(0xFF334155),
                textBgColor: const Color(0xFFF8FAFC),
              ),
              DesignLayer(
                id: 'bill_cust_$now',
                name: 'Customer Name (نام خریدار)',
                type: LayerType.text,
                x: 56,
                y: 344,
                width: 880,
                height: 92,
                text: 'نام خریدار: محمد بلال صاحب  |  Lahore Cantt',
                fontFamily: 'NotoNaskhArabic',
                fontSize: 27,
                fontWeight: 700,
                textAlign: TextAlign.right,
                isRtl: true,
                textColor: const Color(0xFF0F172A),
                textBgColor: const Color(0xFFFFFBEB),
                lineHeight: 1.65,
              ),
              DesignLayer(
                id: 'bill_items_$now',
                name: 'Items List (تفصیل اشیاء)',
                type: LayerType.text,
                x: 56,
                y: 468,
                width: 880,
                height: 460,
                text: '1. Letterhead Printing (500 Sheets) — Rs. 4,500\n2. Business Rubber Stamp (گول مہر) — Rs. 1,200\n3. Custom Bill Books (10 Books) — Rs. 6,800\n4. Lamination & Binding — Rs. 1,500',
                fontFamily: 'PlusJakartaSans',
                fontSize: 25,
                fontWeight: 500,
                textAlign: TextAlign.left,
                isRtl: false,
                textColor: const Color(0xFF1E293B),
                textBgColor: const Color(0xFFF8FAFC),
                lineHeight: 2.0,
              ),
              DesignLayer(
                id: 'bill_total_$now',
                name: 'Total Amount (کل رقم)',
                type: LayerType.text,
                x: 56,
                y: 965,
                width: 880,
                height: 110,
                text: 'TOTAL PAYABLE / کل رقم:   Rs. 14,000 /-',
                fontFamily: 'PlusJakartaSans',
                fontSize: 33,
                fontWeight: 700,
                textAlign: TextAlign.center,
                isRtl: false,
                textColor: Colors.white,
                textBgColor: const Color(0xFF0F172A),
              ),
            ],
          ),
        ],
      );
    } else if (kind == 'letterhead') {
      tpl = DesignProject(
        id: 'tpl_lh_$now',
        name: 'Official Letterhead (دفتری لیٹر ہیڈ)',
        updatedAt: now,
        pages: [
          DocumentPage(
            id: 'pg_lh_$now',
            title: 'Letterhead A4',
            width: 992,
            height: 1403,
            backgroundColor: const Color(0xFFFAF9F6),
            layers: [
              DesignLayer(
                id: 'lh_bar_$now',
                name: 'Top Accent Stripe',
                type: LayerType.shape,
                x: 0,
                y: 0,
                width: 992,
                height: 22,
                textColor: const Color(0xFFB45309),
              ),
              DesignLayer(
                id: 'lh_en_$now',
                name: 'Company Name (English)',
                type: LayerType.text,
                x: 64,
                y: 66,
                width: 460,
                height: 110,
                text: 'QALAM ENTERPRISES\nLegal & Design Consultancy',
                fontFamily: 'PlayfairDisplay',
                fontSize: 34,
                fontWeight: 700,
                textAlign: TextAlign.left,
                isRtl: false,
                textColor: const Color(0xFF0F172A),
                lineHeight: 1.25,
              ),
              DesignLayer(
                id: 'lh_ur_$now',
                name: 'Company Name (Urdu)',
                type: LayerType.text,
                x: 520,
                y: 58,
                width: 408,
                height: 125,
                text: 'قلم انٹرپرائزز\nدفتری و تجارتی مراسلہ',
                fontFamily: 'NotoNastaliqUrdu',
                fontSize: 29,
                fontWeight: 700,
                textAlign: TextAlign.right,
                isRtl: true,
                textColor: const Color(0xFF92400E),
                lineHeight: 2.0,
              ),
              DesignLayer(
                id: 'lh_ref_$now',
                name: 'Ref & Date',
                type: LayerType.text,
                x: 64,
                y: 225,
                width: 864,
                height: 55,
                text: 'Ref No: QE/2025/084                    Date: 17 / 11 / 2025',
                fontFamily: 'PlusJakartaSans',
                fontSize: 21,
                fontWeight: 600,
                textAlign: TextAlign.left,
                isRtl: false,
                textColor: const Color(0xFF475569),
              ),
              DesignLayer(
                id: 'lh_body_$now',
                name: 'Letter Body (متن تحریر)',
                type: LayerType.text,
                x: 64,
                y: 325,
                width: 864,
                height: 580,
                text: 'بخدمت جناب مینیجر صاحب،\n\nگزارش ہے کہ ہمارے ادارے کی جانب سے تمام دستاویزات کی تصدیق مکمل ہو چکی ہے۔ آپ Fill tab سے نام اور تاریخ بدل کر پرنٹ کر سکتے ہیں اور Sign/Seal tab سے مہر شامل کر سکتے ہیں۔\n\nوالسلام',
                fontFamily: 'NotoNastaliqUrdu',
                fontSize: 28,
                textAlign: TextAlign.right,
                isRtl: true,
                textColor: const Color(0xFF0F172A),
                lineHeight: 2.3,
              ),
              DesignLayer(
                id: 'lh_ftr_$now',
                name: 'Footer Contact Bar',
                type: LayerType.text,
                x: 64,
                y: 1285,
                width: 864,
                height: 70,
                text: 'Office 14, Shahrah-e-Quaid-e-Azam, Lahore · 042-3555-0192',
                fontFamily: 'PlusJakartaSans',
                fontSize: 20,
                fontWeight: 600,
                textAlign: TextAlign.center,
                isRtl: false,
                textColor: const Color(0xFF475569),
                textBgColor: const Color(0xFFF1F5F9),
              ),
            ],
          ),
        ],
      );
    } else {
      tpl = DesignProject(
        id: 'tpl_sanad_$now',
        name: 'Urdu Sanad / Certificate (سند)',
        updatedAt: now,
        pages: [
          DocumentPage(
            id: 'pg_sanad_$now',
            title: 'Certificate 4:3',
            width: 1200,
            height: 900,
            backgroundColor: const Color(0xFFB45309),
            layers: [
              DesignLayer(
                id: 'snd_in_$now',
                name: 'Certificate Paper Card',
                type: LayerType.shape,
                x: 32,
                y: 32,
                width: 1136,
                height: 836,
                textColor: const Color(0xFFFFFDF7),
                borderRadius: 18,
              ),
              DesignLayer(
                id: 'snd_ttl_$now',
                name: 'Certificate Title',
                type: LayerType.text,
                x: 140,
                y: 110,
                width: 920,
                height: 170,
                text: 'سندِ اعزاز و امتیازی کارکردگی\nCERTIFICATE OF EXCELLENCE',
                fontFamily: 'NotoNastaliqUrdu',
                fontSize: 38,
                fontWeight: 700,
                textAlign: TextAlign.center,
                isRtl: true,
                textColor: const Color(0xFF0F172A),
                lineHeight: 1.9,
              ),
              DesignLayer(
                id: 'snd_rec_$now',
                name: 'Recipient Name (نام)',
                type: LayerType.text,
                x: 180,
                y: 340,
                width: 840,
                height: 120,
                text: 'محمد حمزہ طارق',
                fontFamily: 'NotoNastaliqUrdu',
                fontSize: 48,
                fontWeight: 700,
                textAlign: TextAlign.center,
                isRtl: true,
                textColor: const Color(0xFFB45309),
                textBgColor: const Color(0xFFFEF3C7),
                lineHeight: 1.95,
              ),
              DesignLayer(
                id: 'snd_cit_$now',
                name: 'Citation Text (تفصیل)',
                type: LayerType.text,
                x: 130,
                y: 505,
                width: 940,
                height: 165,
                text: 'کو سالانہ امتحانات و نصابی سرگرمیوں میں شاندار کارکردگی کا مظاہرہ کرنے پر یہ سندِ اعزاز پیش کی جاتی ہے۔',
                fontFamily: 'NotoNastaliqUrdu',
                fontSize: 28,
                textAlign: TextAlign.center,
                isRtl: true,
                textColor: const Color(0xFF334155),
                lineHeight: 2.2,
              ),
              DesignLayer(
                id: 'snd_ftr_$now',
                name: 'Date & Principal Sign',
                type: LayerType.text,
                x: 120,
                y: 740,
                width: 960,
                height: 70,
                text: 'Date: 17 Nov 2025                      Principal Sign & Official Seal',
                fontFamily: 'PlayfairDisplay',
                fontSize: 22,
                fontWeight: 700,
                textAlign: TextAlign.center,
                isRtl: false,
                textColor: const Color(0xFF1E293B),
              ),
            ],
          ),
        ],
      );
    }

    await _runWithSavingHud(
      savingTitle: 'Creating Template...',
      savingSubtitle: tpl.name,
      savedTitle: 'Template Saved',
      savedSubtitle: tpl.name,
      action: () async {
        await LocalProjectStore.instance.saveProject(tpl);
        final all = await LocalProjectStore.instance.loadAllProjects();
        if (!mounted) return;
        setState(() {
          _projects = all;
          _project = tpl;
          _pageIndex = 0;
          _selectedLayerId = null;
          _undoStack.clear();
          _redoStack.clear();
          _navIndex = 0;
        });
      },
    );
  }

  Widget _businessStarterCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 220,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: _accentText, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _textColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: _subColor),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 36,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _amber,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
              ),
              onPressed: onTap,
              child: const Text('Use Template', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPagesView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _amber.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _amber.withOpacity(0.45)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _amber,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.document_scanner_rounded, color: Colors.black, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Document Scanner', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                    Text(
                      'Scan or upload pages · Live Preview · Save PDF / JPEG',
                      style: TextStyle(fontSize: 11.5, color: _subColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _amber, foregroundColor: Colors.black),
                onPressed: _openDocumentScannerSheet,
                child: const Text('Scan', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        const Text('Urdu Business & Office Starters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text('Quick-Fill ready invoices, letterheads & Urdu certificates', style: TextStyle(fontSize: 12, color: _subColor)),
        const SizedBox(height: 10),
        SizedBox(
          height: 158,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _businessStarterCard(
                icon: Icons.receipt_long_rounded,
                title: 'Cash Memo / Bill\nرسید و انوائس',
                subtitle: 'Bilingual A4 shop bill · Quick Fill ready',
                onTap: () => _loadBusinessTemplate('cash_memo'),
              ),
              _businessStarterCard(
                icon: Icons.description_rounded,
                title: 'Official Letterhead\nدفتری لیٹر ہیڈ',
                subtitle: 'Urdu + English header, Ref & footer',
                onTap: () => _loadBusinessTemplate('letterhead'),
              ),
              _businessStarterCard(
                icon: Icons.workspace_premium_rounded,
                title: 'Urdu Sanad\nسندِ اعزاز',
                subtitle: 'Gold frame certificate with Nastaliq title',
                onTap: () => _loadBusinessTemplate('sanad'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Document Pages', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                Text('${_project.pages.length} page(s) in current project', style: TextStyle(fontSize: 12, color: _subColor)),
              ],
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _amber, foregroundColor: Colors.black),
              onPressed: () async {
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
                await _runWithSavingHud(
                  savingTitle: 'Saving Page...',
                  savedTitle: 'Page Added',
                  savedSubtitle: 'Page ${_project.pages.length} saved',
                  action: () => _saveCurrentProject(showToast: false),
                );
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add A4 Page'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ...List.generate(_project.pages.length, (i) {
          final pg = _project.pages[i];
          final active = i == _pageIndex;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () => setState(() {
                _pageIndex = i;
                _selectedLayerId = null;
                _navIndex = 0;
              }),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: active ? _amber.withOpacity(0.12) : _cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: active ? _amber : _borderColor, width: active ? 1.5 : 1),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 48,
                      decoration: BoxDecoration(
                        color: pg.backgroundColor == Colors.transparent ? _chipBg : pg.backgroundColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _borderColor),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: pg.backgroundColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(pg.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                              if (active) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _amber,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('ACTIVE', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Colors.black)),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${pg.width.round()} × ${pg.height.round()} px · ${pg.layers.length} layer(s)',
                            style: TextStyle(fontSize: 12, color: _subColor),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Duplicate Page',
                      icon: Icon(Icons.copy_rounded, size: 19, color: _subColor),
                      onPressed: () async {
                        _pushUndoSnapshot();
                        final clone = DocumentPage.fromJson(pg.toJson());
                        clone.id = 'pg_${DateTime.now().microsecondsSinceEpoch}';
                        clone.title = '${pg.title} Copy';
                        for (int k = 0; k < clone.layers.length; k++) {
                          clone.layers[k].id = 'dup_${DateTime.now().microsecondsSinceEpoch}_$k';
                        }
                        setState(() {
                          _project.pages.insert(i + 1, clone);
                          _pageIndex = i + 1;
                          _selectedLayerId = null;
                        });
                        await _runWithSavingHud(
                          savingTitle: 'Duplicating Page...',
                          savedTitle: 'Page Duplicated',
                          savedSubtitle: clone.title,
                          action: () async {
                            await _rehydrateProjectFilters(_project);
                            await _saveCurrentProject(showToast: false);
                          },
                        );
                      },
                    ),
                    if (_project.pages.length > 1)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () {
                          _pushUndoSnapshot();
                          setState(() {
                            _project.pages.removeAt(i);
                            _pageIndex = 0;
                            _selectedLayerId = null;
                          });
                        },
                      ),
                  ],
                ),
              ),
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
        const Text('Offline Batch Processor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text('Process multiple scanned documents or images offline at once', style: TextStyle(fontSize: 12, color: _subColor)),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _chipBg,
                    foregroundColor: _textColor,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    final imgs = await _picker.pickMultiImage();
                    if (imgs.isNotEmpty) setState(() => _batchInputs = imgs.map((e) => e.path).toList());
                  },
                  icon: Icon(Icons.photo_library_outlined, color: _accentText),
                  label: Text(
                    _batchInputs.isEmpty ? 'Select Multiple Photos' : '${_batchInputs.length} Photo(s) Selected',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Remove White Background (PNG)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  activeColor: _amber,
                  value: _batchRemoveWhite > 0,
                  onChanged: (v) => setState(() => _batchRemoveWhite = v ? 35.0 : 0.0),
                ),
                if (_batchRemoveWhite > 0)
                  _sliderRow('White Tol.', _batchRemoveWhite, 5, 95, (v) => setState(() => _batchRemoveWhite = v)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _amber,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _batchInputs.isEmpty || _batchProcessing
                ? null
                : () async {
                    setState(() => _batchProcessing = true);
                    try {
                      await _runWithSavingHud(
                        savingTitle: 'Processing & Saving...',
                        savingSubtitle: '${_batchInputs.length} image(s)',
                        savedTitle: 'Batch Saved',
                        savedSubtitle: '${_batchInputs.length} image(s) saved to Gallery',
                        action: () async {
                          final dir = await getTemporaryDirectory();
                          final out = await runBatchOffline(BatchJobRequest(
                            inputPaths: _batchInputs,
                            outputDir: dir.path,
                            brightness: 1.0,
                            contrast: 1.0,
                            blackAndWhite: false,
                            removeWhiteTolerance: _batchRemoveWhite,
                          ));
                          for (final fp in out) {
                            await _saveBytesToDeviceGallery(await File(fp).readAsBytes(), p.basename(fp));
                          }
                          if (mounted) {
                            setState(() => _batchOutputs = out);
                          }
                        },
                      );
                    } finally {
                      if (mounted) setState(() => _batchProcessing = false);
                    }
                  },
            icon: Icon(_batchProcessing ? Icons.hourglass_top_rounded : Icons.auto_awesome_motion_rounded, size: 18),
            label: Text(
              _batchProcessing ? 'Processing...' : 'Process & Export Batch',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (_batchOutputs.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: _isDark ? Colors.greenAccent : Colors.green.shade700, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Processed & saved ${_batchOutputs.length} image(s) to Gallery!',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _isDark ? Colors.greenAccent : Colors.green.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _shareProjectFile(DesignProject proj) async {
    await _runWithSavingHud(
      savingTitle: 'Preparing Project File...',
      savingSubtitle: proj.name,
      savedTitle: 'Project Ready to Share',
      savedSubtitle: '${proj.pages.length} page(s)',
      action: () async {
        final embedded = <String, String>{};
        for (final pg in proj.pages) {
          for (final l in pg.layers) {
            if (l.type == LayerType.image && l.localImagePath != null && l.localImagePath!.isNotEmpty) {
              final f = File(l.localImagePath!);
              if (f.existsSync() && !embedded.containsKey(l.localImagePath!)) {
                embedded[l.localImagePath!] = base64Encode(await f.readAsBytes());
              }
            }
          }
        }
        final bundle = <String, dynamic>{
          'format': 'qalam_project_v1',
          'exportedAt': DateTime.now().millisecondsSinceEpoch,
          'project': jsonDecode(proj.encode()),
          'embeddedImages': embedded,
        };
        final safeName = proj.name
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
            .replaceAll(RegExp(r'^-|-$'), '');
        final fileName = '${safeName.isEmpty ? "qalam-project" : safeName}.qalam.json';
        final tmpDir = await getTemporaryDirectory();
        final outPath = p.join(tmpDir.path, fileName);
        await File(outPath).writeAsString(jsonEncode(bundle));
        await Share.shareXFiles(
          [XFile(outPath)],
          subject: 'Qalam Studio Project: ${proj.name}',
          text: 'Qalam Studio Project (${proj.pages.length} page(s))',
        );
      },
    );
  }

  Future<String?> _writeBase64ToLocalImage(String b64OrDataUri, String prefix) async {
    try {
      var raw = b64OrDataUri.trim();
      var ext = '.png';
      if (raw.startsWith('data:')) {
        final comma = raw.indexOf(',');
        if (comma == -1) return null;
        final header = raw.substring(0, comma).toLowerCase();
        if (header.contains('jpeg') || header.contains('jpg')) ext = '.jpg';
        raw = raw.substring(comma + 1);
      }
      final bytes = base64Decode(raw);
      final docsDir = await getApplicationDocumentsDirectory();
      final imgDir = Directory(p.join(docsDir.path, 'qalam_images'));
      if (!imgDir.existsSync()) imgDir.createSync(recursive: true);
      final dest = p.join(imgDir.path, '${prefix}_${DateTime.now().microsecondsSinceEpoch}$ext');
      await File(dest).writeAsBytes(bytes);
      return dest;
    } catch (_) {
      return null;
    }
  }

  Color _parseColorAny(dynamic raw, Color fallback) {
    if (raw is int) return Color(raw);
    if (raw is String) {
      final clean = raw.trim().toLowerCase();
      if (clean == 'transparent') return Colors.transparent;
      if (clean.startsWith('#')) {
        var hex = clean.substring(1);
        if (hex.length == 3) {
          hex = '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}';
        }
        if (hex.length == 6) hex = 'ff$hex';
        final val = int.tryParse(hex, radix: 16);
        if (val != null) return Color(val);
      }
    }
    return fallback;
  }

  BlendMode _parseBlendModeAny(dynamic raw) {
    if (raw is int && raw >= 0 && raw < BlendMode.values.length) {
      return BlendMode.values[raw];
    }
    if (raw is String) {
      switch (raw.toLowerCase()) {
        case 'multiply':
          return BlendMode.multiply;
        case 'screen':
          return BlendMode.screen;
        case 'overlay':
          return BlendMode.overlay;
        case 'darken':
          return BlendMode.darken;
        case 'lighten':
          return BlendMode.lighten;
        default:
          return BlendMode.srcOver;
      }
    }
    return BlendMode.srcOver;
  }

  Future<void> _importProjectFile() async {
    try {
      String? raw;
      if (Platform.isAndroid) {
        raw = await _mediaChannel.invokeMethod<String>('pickProjectFile');
      }
      if (raw == null || raw.trim().isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid JSON object');
      }

      Map<String, dynamic> projMap;
      final embedded = <String, String>{};
      if (decoded['format'] == 'qalam_project_v1' && decoded['project'] is Map<String, dynamic>) {
        projMap = Map<String, dynamic>.from(decoded['project'] as Map);
        final embRaw = decoded['embeddedImages'];
        if (embRaw is Map) {
          for (final entry in embRaw.entries) {
            if (entry.key is String && entry.value is String) {
              embedded[entry.key as String] = entry.value as String;
            }
          }
        }
      } else if (decoded['pages'] is List) {
        projMap = Map<String, dynamic>.from(decoded);
      } else {
        throw const FormatException('Not a Qalam Studio project file');
      }

      final restoredPaths = <String, String>{};
      for (final entry in embedded.entries) {
        final local = await _writeBase64ToLocalImage(entry.value, 'imp');
        if (local != null) restoredPaths[entry.key] = local;
      }

      final rawPages = (projMap['pages'] as List? ?? []);
      if (rawPages.isEmpty) throw const FormatException('Project has no pages');

      final pages = <DocumentPage>[];
      for (int pi = 0; pi < rawPages.length; pi++) {
        final pgRaw = Map<String, dynamic>.from(rawPages[pi] as Map);
        final rawLayers = (pgRaw['layers'] as List? ?? []);
        final layers = <DesignLayer>[];
        for (int li = 0; li < rawLayers.length; li++) {
          final lRaw = Map<String, dynamic>.from(rawLayers[li] as Map);
          final typeStr = (lRaw['type'] ?? 'text').toString();
          final lType = LayerType.values.firstWhere(
            (t) => t.name == typeStr,
            orElse: () => LayerType.text,
          );
          String? imgPath = lRaw['localImagePath'] as String?;
          if (imgPath != null && restoredPaths.containsKey(imgPath)) {
            imgPath = restoredPaths[imgPath];
          } else if (lType == LayerType.image && lRaw['src'] is String) {
            final src = lRaw['src'] as String;
            if (src.startsWith('data:image')) {
              imgPath = await _writeBase64ToLocalImage(src, 'webimg');
            }
          }
          final fMap = (lRaw['filters'] is Map)
              ? Map<String, dynamic>.from(lRaw['filters'] as Map)
              : <String, dynamic>{};
          layers.add(DesignLayer(
            id: (lRaw['id'] ?? 'l_${pi}_$li').toString(),
            name: (lRaw['name'] ?? 'Layer ${li + 1}').toString(),
            type: lType,
            x: (lRaw['x'] ?? 40).toDouble(),
            y: (lRaw['y'] ?? 40).toDouble(),
            width: (lRaw['width'] ?? 240).toDouble(),
            height: (lRaw['height'] ?? 160).toDouble(),
            rotation: (lRaw['rotation'] ?? 0).toDouble(),
            opacity: (lRaw['opacity'] ?? 1.0).toDouble(),
            blendMode: _parseBlendModeAny(lRaw['blendMode']),
            visible: lRaw['visible'] ?? true,
            locked: lRaw['locked'] ?? false,
            isCanvasBackground: lRaw['isCanvasBackground'] ?? false,
            text: (lRaw['text'] ?? '').toString(),
            isRtl: lRaw['isRtl'] ?? (lRaw['direction'] == 'rtl'),
            fontFamily: (lRaw['fontFamily'] ?? 'PlusJakartaSans').toString(),
            fontSize: (lRaw['fontSize'] ?? 32).toDouble(),
            fontWeight: ((lRaw['fontWeight'] ?? 400) as num).toInt(),
            lineHeight: (lRaw['lineHeight'] ?? 1.4).toDouble(),
            textColor: _parseColorAny(
              lRaw['textColor'] ?? lRaw['color'] ?? lRaw['fillColor'],
              const Color(0xFFFFFFFF),
            ),
            textAlign: lRaw['textAlign'] is String
                ? TextAlign.values.firstWhere(
                    (t) => t.name == lRaw['textAlign'],
                    orElse: () => (lRaw['isRtl'] ?? lRaw['direction'] == 'rtl') ? TextAlign.right : TextAlign.left,
                  )
                : null,
            textBgColor: _parseColorAny(lRaw['textBgColor'] ?? lRaw['backgroundColor'], Colors.transparent),
            flipX: lRaw['flipX'] ?? false,
            flipY: lRaw['flipY'] ?? false,
            localImagePath: imgPath,
            aspectLocked: lRaw['aspectLocked'] ?? true,
            objectFit: lRaw['objectFit'] is int
                ? BoxFit.values[(lRaw['objectFit'] as int).clamp(0, BoxFit.values.length - 1)]
                : BoxFit.cover,
            borderRadius: (lRaw['borderRadius'] ?? 0).toDouble(),
            filters: FilterSettings.fromJson(fMap),
          ));
        }
        pages.add(DocumentPage(
          id: (pgRaw['id'] ?? 'pg_$pi').toString(),
          title: (pgRaw['title'] ?? 'Page ${pi + 1}').toString(),
          width: (pgRaw['width'] ?? 900).toDouble(),
          height: (pgRaw['height'] ?? 1200).toDouble(),
          backgroundColor: _parseColorAny(pgRaw['backgroundColor'], const Color(0xFF191C22)),
          layers: layers,
        ));
      }

      final imported = DesignProject(
        id: 'proj_imp_${DateTime.now().millisecondsSinceEpoch}',
        name: (projMap['name'] ?? 'Imported Project').toString(),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        pages: pages,
      );

      await _runWithSavingHud(
        savingTitle: 'Importing Project...',
        savingSubtitle: imported.name,
        savedTitle: 'Project Imported',
        savedSubtitle: imported.name,
        action: () async {
          await LocalProjectStore.instance.saveProject(imported);
          final list = await LocalProjectStore.instance.loadAllProjects();
          if (!mounted) return;
          setState(() {
            _projects = list;
            _project = imported;
            _pageIndex = 0;
            _selectedLayerId = null;
            _undoStack.clear();
            _redoStack.clear();
            _navIndex = 0;
          });
          await _rehydrateProjectFilters(imported);
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not import project file: $e')),
      );
    }
  }

  Widget _buildProjectsView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Offline Projects', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text('${_projects.length} saved locally on device', style: TextStyle(fontSize: 12, color: _subColor)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _amber,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                    ),
                    onPressed: () async {
                      final fresh = _buildDefaultProject();
                      await _runWithSavingHud(
                        savingTitle: 'Creating Project...',
                        savingSubtitle: fresh.name,
                        savedTitle: 'Project Saved',
                        savedSubtitle: fresh.name,
                        action: () async {
                          await LocalProjectStore.instance.saveProject(fresh);
                          final list = await LocalProjectStore.instance.loadAllProjects();
                          if (!mounted) return;
                          setState(() {
                            _projects = list;
                            _project = fresh;
                            _pageIndex = 0;
                            _selectedLayerId = null;
                            _undoStack.clear();
                            _redoStack.clear();
                            _navIndex = 0;
                          });
                        },
                      );
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New Project', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: _amber.withOpacity(0.7)),
                      foregroundColor: _accentText,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                    ),
                    onPressed: _importProjectFile,
                    icon: const Icon(Icons.file_open_outlined, size: 18),
                    label: const Text('Import .qalam', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        ..._projects.map((proj) {
          final isCurrent = proj.id == _project.id;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () async {
                setState(() {
                  _project = proj;
                  _pageIndex = 0;
                  _selectedLayerId = null;
                  _undoStack.clear();
                  _redoStack.clear();
                  _navIndex = 0;
                });
                await _rehydrateProjectFilters(proj);
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isCurrent ? _amber.withOpacity(0.12) : _cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isCurrent ? _amber : _borderColor, width: isCurrent ? 1.5 : 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isCurrent ? _amber : _chipBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.folder_open_rounded, color: isCurrent ? Colors.black : _subColor, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      proj.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  if (isCurrent) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(color: _amber, borderRadius: BorderRadius.circular(6)),
                                      child: const Text('OPEN', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Colors.black)),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text('${proj.pages.length} page(s) · Stored offline', style: TextStyle(fontSize: 12, color: _subColor)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _compactLayerIcon(Icons.edit_outlined, 'Rename Project', () => _renameProjectDialog(proj)),
                        _compactLayerIcon(Icons.copy_rounded, 'Duplicate Project', () async {
                          final dup = DesignProject.decode(proj.encode());
                          dup.id = 'proj_dup_${DateTime.now().millisecondsSinceEpoch}';
                          dup.name = '${proj.name} (Copy)';
                          dup.updatedAt = DateTime.now().millisecondsSinceEpoch;
                          await _runWithSavingHud(
                            savingTitle: 'Duplicating Project...',
                            savingSubtitle: dup.name,
                            savedTitle: 'Project Duplicated',
                            savedSubtitle: dup.name,
                            action: () async {
                              await LocalProjectStore.instance.saveProject(dup);
                              final list = await LocalProjectStore.instance.loadAllProjects();
                              if (mounted) setState(() => _projects = list);
                            },
                          );
                        }),
                        _compactLayerIcon(
                          Icons.share_outlined,
                          'Share Project (.qalam.json)',
                          () => _shareProjectFile(proj),
                          color: _accentText,
                        ),
                        if (_projects.length > 1)
                          _compactLayerIcon(
                            Icons.delete_outline,
                            'Delete Project',
                            () async {
                              final deletingCurrent = proj.id == _project.id;
                              await LocalProjectStore.instance.deleteProject(proj.id);
                              await _loadSavedProjects();
                              if (deletingCurrent && mounted) {
                                setState(() {
                                  _selectedLayerId = null;
                                  _undoStack.clear();
                                  _redoStack.clear();
                                });
                              }
                            },
                            color: Colors.redAccent,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  static const List<(String, String, String, bool)> _signatureFonts = [
    ('GreatVibes', 'Great Vibes', 'Royal Calligraphy', false),
    ('AlexBrush', 'Alex Brush', 'Clean Executive', false),
    ('Allura', 'Allura', 'Formal Flow', false),
    ('Sacramento', 'Sacramento', 'Fine Pen', false),
    ('Parisienne', 'Parisienne', 'Graceful Cursive', false),
    ('PinyonScript', 'Pinyon Script', 'Aristocrat', false),
    ('HerrVonMuellerhoff', 'Muellerhoff', 'Vintage Nib', false),
    ('MrDafoe', 'Mr Dafoe', 'Bold Marker', false),
    ('Satisfy', 'Satisfy', 'Classic Sign', false),
    ('DancingScript', 'Dancing Script', 'Modern Ink', false),
    ('Pacifico', 'Pacifico', 'Brush Sign', false),
    ('HomemadeApple', 'Homemade Apple', 'Handwritten', false),
    ('Caveat', 'Caveat', 'Natural Pen', false),
    ('MarckScript', 'Marck Script', 'Slanted Ink', false),
    ('Yesteryear', 'Yesteryear', 'Retro Script', false),
    ('ReenieBeanie', 'Reenie Beanie', 'Quick Ballpoint', false),
    ('NotoNastaliqUrdu', 'Urdu Nastaliq', 'Urdu Signature', true),
    ('Gulzar', 'Gulzar Urdu', 'Urdu Calligraphy', true),
  ];

  Offset _toCanonicalPadPoint(Offset localPos, Size widgetSize) {
    final sx = widgetSize.width / math.max(1.0, _sigCanvasSize.width);
    final sy = widgetSize.height / math.max(1.0, _sigCanvasSize.height);
    final scale = math.min(sx, sy);
    final dx = (widgetSize.width - _sigCanvasSize.width * scale) / 2.0;
    final dy = (widgetSize.height - _sigCanvasSize.height * scale) / 2.0;
    return Offset((localPos.dx - dx) / math.max(0.001, scale), (localPos.dy - dy) / math.max(0.001, scale));
  }

  void _undoSignatureStroke() {
    if (_sigStrokes.isEmpty) return;
    setState(() {
      _sigRedoStrokes.add(_sigStrokes.removeLast());
    });
  }

  void _redoSignatureStroke() {
    if (_sigRedoStrokes.isEmpty) return;
    setState(() {
      _sigStrokes.add(_sigRedoStrokes.removeLast());
    });
  }

  void _clearSignatureStrokes() {
    if (_sigStrokes.isEmpty) return;
    setState(() {
      _sigStrokes.clear();
      _sigRedoStrokes.clear();
    });
  }

  Future<void> _openFullScreenSignaturePad() async {
    const inkSwatches = [
      Color(0xFF0F172A),
      Color(0xFF1D4ED8),
      Color(0xFF1E3A8A),
      Color(0xFF047857),
      Color(0xFFB91C1C),
    ];

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (routeCtx) {
          return StatefulBuilder(
            builder: (ctx, setModalState) {
              return Scaffold(
                backgroundColor: _isDark ? const Color(0xFF0D0F12) : const Color(0xFFF3F5F8),
                appBar: AppBar(
                  backgroundColor: _cardBg,
                  leading: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                  title: const Text('Draw Signature', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  actions: [
                    IconButton(
                      tooltip: 'Undo',
                      onPressed: _sigStrokes.isEmpty
                          ? null
                          : () {
                              _undoSignatureStroke();
                              setModalState(() {});
                            },
                      icon: const Icon(Icons.undo_rounded),
                    ),
                    IconButton(
                      tooltip: 'Redo',
                      onPressed: _sigRedoStrokes.isEmpty
                          ? null
                          : () {
                              _redoSignatureStroke();
                              setModalState(() {});
                            },
                      icon: const Icon(Icons.redo_rounded),
                    ),
                    IconButton(
                      tooltip: 'Clear All',
                      onPressed: _sigStrokes.isEmpty
                          ? null
                          : () {
                              _clearSignatureStrokes();
                              setModalState(() {});
                            },
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 10, left: 4),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _amber,
                          foregroundColor: Colors.black,
                          minimumSize: const Size(0, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.check_rounded, size: 17),
                        label: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
                body: SafeArea(
                  child: Column(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final padSize = Size(constraints.maxWidth, constraints.maxHeight);
                              if (_sigStrokes.isEmpty) {
                                _sigCanvasSize = padSize;
                              }
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  width: padSize.width,
                                  height: padSize.height,
                                  decoration: BoxDecoration(
                                    color: _sigTransparentBg ? const Color(0xFFF8FAFC) : Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: _amber.withOpacity(0.75), width: 1.6),
                                  ),
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        left: 24,
                                        right: 24,
                                        bottom: padSize.height * 0.28,
                                        child: Container(
                                          height: 1,
                                          color: const Color(0xFFCBD5E1),
                                        ),
                                      ),
                                      if (_sigStrokes.isEmpty)
                                        const Center(
                                          child: Text(
                                            'Draw your signature freely with your finger',
                                            style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
                                          ),
                                        ),
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onPanStart: (d) {
                                          if (_sigStrokes.isEmpty) {
                                            _sigCanvasSize = padSize;
                                          }
                                          final pt = _toCanonicalPadPoint(d.localPosition, padSize);
                                          _sigCurrentStroke = [pt];
                                          _sigRedoStrokes.clear();
                                          _sigStrokes.add((_sigCurrentStroke!, _sigInkColor, _sigPenWidth));
                                          setModalState(() {});
                                          setState(() {});
                                        },
                                        onPanUpdate: (d) {
                                          if (_sigCurrentStroke == null) return;
                                          _sigCurrentStroke!.add(_toCanonicalPadPoint(d.localPosition, padSize));
                                          setModalState(() {});
                                          setState(() {});
                                        },
                                        onPanEnd: (_) => _sigCurrentStroke = null,
                                        child: CustomPaint(
                                          painter: _SignaturePadPainter(_sigStrokes, _sigCanvasSize),
                                          size: padSize,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                        decoration: BoxDecoration(
                          color: _cardBg,
                          border: Border(top: BorderSide(color: _borderColor)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Text('Ink:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _subColor)),
                                const SizedBox(width: 8),
                                ...inkSwatches.map(
                                  (c) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() => _sigInkColor = c);
                                        setModalState(() {});
                                      },
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: c,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: _sigInkColor == c ? _amber : _borderColor,
                                            width: _sigInkColor == c ? 3 : 1.2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                _choicePill(
                                  label: _sigTransparentBg ? 'Transparent' : 'White BG',
                                  selected: _sigTransparentBg,
                                  onTap: () {
                                    setState(() => _sigTransparentBg = !_sigTransparentBg);
                                    setModalState(() {});
                                  },
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                SizedBox(
                                  width: 68,
                                  child: Text('Pen Size', style: TextStyle(fontSize: 12, color: _subColor)),
                                ),
                                Expanded(
                                  child: Slider(
                                    value: _sigPenWidth.clamp(2.0, 14.0),
                                    min: 2.0,
                                    max: 14.0,
                                    activeColor: _amber,
                                    onChanged: (v) {
                                      setState(() => _sigPenWidth = v);
                                      setModalState(() {});
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: 32,
                                  child: Text('${_sigPenWidth.round()}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<Uint8List?> _renderSignaturePngBytes({bool? forceTransparent}) async {
    final useTransparent = forceTransparent ?? _sigTransparentBg;
    const w = 1100.0;
    const h = 420.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, w, h));
    if (!useTransparent) {
      canvas.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.white);
    }
    if (_sigMode == 0) {
      final raw = _sigTextController.text.trim();
      final text = raw.isEmpty ? 'Signature' : raw;
      final isRtl = RegExp(r'[\u0600-\u06FF]').hasMatch(text) ||
          _sigFontFamily == 'NotoNastaliqUrdu' ||
          _sigFontFamily == 'Gulzar';
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: _sigFontFamily,
            fontSize: _sigFontSize * 1.35,
            fontWeight: _sigBold ? FontWeight.bold : FontWeight.normal,
            fontStyle: (_sigSlanted && !isRtl) ? FontStyle.italic : FontStyle.normal,
            color: _sigInkColor,
            letterSpacing: _sigLetterSpacing,
            height: isRtl ? 2.0 : 1.3,
          ),
        ),
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: w - 80);
      tp.paint(canvas, Offset((w - tp.width) / 2, (h - tp.height) / 2));
    } else if (_sigStrokes.isNotEmpty) {
      double minX = double.infinity, minY = double.infinity;
      double maxX = -double.infinity, maxY = -double.infinity;
      for (final s in _sigStrokes) {
        for (final pt in s.$1) {
          if (pt.dx < minX) minX = pt.dx;
          if (pt.dy < minY) minY = pt.dy;
          if (pt.dx > maxX) maxX = pt.dx;
          if (pt.dy > maxY) maxY = pt.dy;
        }
      }
      final bw = math.max(20.0, maxX - minX);
      final bh = math.max(20.0, maxY - minY);
      const pad = 44.0;
      final scale = math.min((w - pad * 2) / bw, (h - pad * 2) / bh);
      final offX = (w - bw * scale) / 2.0 - minX * scale;
      final offY = (h - bh * scale) / 2.0 - minY * scale;

      for (final stroke in _sigStrokes) {
        final pts = stroke.$1;
        if (pts.isEmpty) continue;
        final strokeW = (stroke.$3 * math.min(2.6, math.max(1.2, scale * 0.85))).clamp(2.5, 22.0);
        final paint = Paint()
          ..color = stroke.$2
          ..strokeWidth = strokeW
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;
        if (pts.length == 1) {
          canvas.drawCircle(
            Offset(pts[0].dx * scale + offX, pts[0].dy * scale + offY),
            strokeW / 2,
            Paint()..color = stroke.$2,
          );
          continue;
        }
        final path = Path()..moveTo(pts[0].dx * scale + offX, pts[0].dy * scale + offY);
        for (int i = 1; i < pts.length; i++) {
          path.lineTo(pts[i].dx * scale + offX, pts[i].dy * scale + offY);
        }
        canvas.drawPath(path, paint);
      }
    }
    final uiImg = await recorder.endRecording().toImage(w.toInt(), h.toInt());
    final byteData = await uiImg.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _addSignatureToProjectCanvas() async {
    if (_sigMode == 1 && _sigStrokes.isEmpty) return;
    await _runWithSavingHud(
      savingTitle: 'Saving Signature...',
      savedTitle: 'Signature Added',
      savedSubtitle: 'Placed on Studio Canvas',
      action: () async {
        final bytes = await _renderSignaturePngBytes(forceTransparent: true);
        if (bytes == null) throw Exception('Signature render failed');
        final docsDir = await getApplicationDocumentsDirectory();
        final assetsDir = Directory(p.join(docsDir.path, 'qalam_assets'));
        if (!assetsDir.existsSync()) assetsDir.createSync(recursive: true);
        final filePath = p.join(assetsDir.path, 'sig_${DateTime.now().microsecondsSinceEpoch}.png');
        await File(filePath).writeAsBytes(bytes);
        final targetW = _page.width * 0.55;
        final targetH = targetW * (420.0 / 1100.0);
        final layer = DesignLayer(
          id: 'sig_${DateTime.now().microsecondsSinceEpoch}',
          name: _sigMode == 0 ? 'Sign: ${_sigTextController.text.trim()}' : 'Drawn Signature',
          type: LayerType.image,
          x: (_page.width - targetW) / 2,
          y: _page.height * 0.65,
          width: targetW,
          height: targetH,
          localImagePath: filePath,
          aspectLocked: true,
          objectFit: BoxFit.contain,
        );
        if (mounted) {
          setState(() {
            _page.layers.add(layer);
            _selectedLayerId = layer.id;
            _navIndex = 0;
          });
        }
        await _saveCurrentProject(showToast: false);
      },
    );
  }

  Future<void> _exportSignaturePng({required bool shareOnly}) async {
    if (_sigMode == 1 && _sigStrokes.isEmpty) return;
    await _runWithSavingHud(
      savingTitle: shareOnly ? 'Preparing Signature...' : 'Saving Signature PNG...',
      savedTitle: shareOnly ? 'Ready to Share' : 'Signature Saved',
      savedSubtitle: shareOnly ? 'PNG ready' : 'Saved to Gallery',
      action: () async {
        final bytes = await _renderSignaturePngBytes();
        if (bytes == null) throw Exception('Signature render failed');
        final fileName = 'qalam_signature_${DateTime.now().millisecondsSinceEpoch}.png';
        final tmpDir = await getTemporaryDirectory();
        final tmpPath = p.join(tmpDir.path, fileName);
        await File(tmpPath).writeAsBytes(bytes);
        if (shareOnly) {
          await Share.shareXFiles([XFile(tmpPath)], text: 'Digital Signature');
        } else {
          await _saveBytesToDeviceGallery(bytes, fileName);
        }
      },
    );
  }

  Future<Uint8List?> _renderStampPngBytes({bool? forceTransparent}) async {
    final useTransparent = forceTransparent ?? _stampTransparentBg;
    const size = 640.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));
    if (!useTransparent) {
      canvas.drawRect(const Rect.fromLTWH(0, 0, size, size), Paint()..color = Colors.white);
    }
    _StampPainter(
      shape: _stampShape,
      org: _stampOrgCtrl.text,
      status: _stampStatusCtrl.text,
      sub: _stampSubCtrl.text,
      inkColor: _stampInkColor,
      showDate: _stampShowDate,
      transparentBg: useTransparent,
    ).paint(canvas, const Size(size, size));
    final uiImg = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final byteData = await uiImg.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _addStampToProjectCanvas() async {
    final bytes = await _renderStampPngBytes(forceTransparent: true);
    if (bytes == null) return;
    final docsDir = await getApplicationDocumentsDirectory();
    final assetsDir = Directory(p.join(docsDir.path, 'qalam_assets'));
    if (!assetsDir.existsSync()) assetsDir.createSync(recursive: true);
    final filePath = p.join(assetsDir.path, 'stamp_${DateTime.now().microsecondsSinceEpoch}.png');
    await File(filePath).writeAsBytes(bytes);

    final targetDim = math.min(_page.width, _page.height) * 0.32;
    final layer = DesignLayer(
      id: 'stamp_${DateTime.now().microsecondsSinceEpoch}',
      name: 'Stamp: ${_stampStatusCtrl.text.trim().isEmpty ? 'Seal' : _stampStatusCtrl.text.trim()}',
      type: LayerType.image,
      x: (_page.width - targetDim) * 0.85,
      y: (_page.height - targetDim) * 0.82,
      width: targetDim,
      height: targetDim,
      localImagePath: filePath,
      aspectLocked: true,
      objectFit: BoxFit.contain,
    );
    _pushUndoSnapshot();
    setState(() {
      _page.layers.add(layer);
      _selectedLayerId = layer.id;
      _navIndex = 0;
    });
    await _runWithSavingHud(
      savingTitle: 'Saving Stamp...',
      savedTitle: 'Official Stamp Saved',
      savedSubtitle: 'Placed on Studio Canvas',
      action: () => _saveCurrentProject(showToast: false),
    );
  }

  Future<void> _exportStampPng({required bool shareOnly}) async {
    await _runWithSavingHud(
      savingTitle: shareOnly ? 'Preparing Stamp...' : 'Saving Stamp PNG...',
      savedTitle: shareOnly ? 'Ready to Share' : 'Stamp Saved',
      savedSubtitle: shareOnly ? 'PNG ready' : 'Saved to Gallery',
      action: () async {
        final bytes = await _renderStampPngBytes();
        if (bytes == null) throw Exception('Stamp render failed');
        final fileName = 'qalam_stamp_${DateTime.now().millisecondsSinceEpoch}.png';
        final tmpDir = await getTemporaryDirectory();
        final tmpPath = p.join(tmpDir.path, fileName);
        await File(tmpPath).writeAsBytes(bytes);
        if (shareOnly) {
          await Share.shareXFiles([XFile(tmpPath)], text: 'Official Stamp');
        } else {
          await _saveBytesToDeviceGallery(bytes, fileName);
        }
      },
    );
  }

  Widget _buildSignatureView() {
    const inkSwatches = [
      Color(0xFF0F172A),
      Color(0xFF1D4ED8),
      Color(0xFF1E3A8A),
      Color(0xFF047857),
      Color(0xFFB91C1C),
    ];
    final raw = _sigTextController.text.trim();
    final previewText = raw.isEmpty ? 'Signature' : raw;
    final isRtl = RegExp(r'[\u0600-\u06FF]').hasMatch(previewText) ||
        _sigFontFamily == 'NotoNastaliqUrdu' ||
        _sigFontFamily == 'Gulzar';
    const paperPreviewBg = Color(0xFFF8FAFC);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Sign & Official Seal Studio', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text('18 signature fonts · Draw pad · Rubber Stamp / مہر Maker', style: TextStyle(fontSize: 12, color: _subColor)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('18 Fonts'), icon: Icon(Icons.title_rounded, size: 15)),
              ButtonSegment(value: 1, label: Text('Draw'), icon: Icon(Icons.draw_rounded, size: 15)),
              ButtonSegment(value: 2, label: Text('Stamp / مہر'), icon: Icon(Icons.verified_outlined, size: 15)),
            ],
            selected: {_sigMode},
            onSelectionChanged: (s) => setState(() => _sigMode = s.first),
          ),
        ),
        const SizedBox(height: 12),
        if (_sigMode == 0)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _sigTextController,
                    textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Enter Signature Name (English / Urdu)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    height: 140,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _sigTransparentBg ? paperPreviewBg : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              previewText,
                              textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                              style: TextStyle(
                                fontFamily: _sigFontFamily,
                                fontSize: _sigFontSize,
                                fontWeight: _sigBold ? FontWeight.bold : FontWeight.normal,
                                fontStyle: (_sigSlanted && !isRtl) ? FontStyle.italic : FontStyle.normal,
                                letterSpacing: _sigLetterSpacing,
                                height: isRtl ? 2.0 : 1.3,
                                color: _sigInkColor,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _sigTransparentBg ? 'Transparent PNG' : 'White Paper',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text('Ink Color:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _subColor)),
                      const SizedBox(width: 10),
                      ...inkSwatches.map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setState(() => _sigInkColor = c),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _sigInkColor == c ? _amber : _borderColor,
                                  width: _sigInkColor == c ? 3 : 1.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _sliderRow('Size', _sigFontSize, 42, 130, (v) => setState(() => _sigFontSize = v)),
                  _sliderRow('Spacing', _sigLetterSpacing, -4, 12, (v) => setState(() => _sigLetterSpacing = v)),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _choicePill(
                        label: 'Slant',
                        selected: _sigSlanted,
                        onTap: () => setState(() => _sigSlanted = !_sigSlanted),
                      ),
                      _choicePill(
                        label: 'Bold Ink',
                        selected: _sigBold,
                        onTap: () => setState(() => _sigBold = !_sigBold),
                      ),
                      _choicePill(
                        label: _sigTransparentBg ? 'BG: Transparent' : 'BG: White Paper',
                        selected: _sigTransparentBg,
                        onTap: () => setState(() => _sigTransparentBg = !_sigTransparentBg),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
        else if (_sigMode == 1)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: _amber.withOpacity(0.8)),
                        foregroundColor: _accentText,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _openFullScreenSignaturePad,
                      icon: const Icon(Icons.open_in_full_rounded, size: 17),
                      label: const Text('Open Full-Screen Draw Pad (Easier Signing)', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      ...inkSwatches.map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setState(() => _sigInkColor = c),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _sigInkColor == c ? _amber : _borderColor,
                                  width: _sigInkColor == c ? 3 : 1.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Undo',
                        onPressed: _sigStrokes.isEmpty ? null : _undoSignatureStroke,
                        icon: const Icon(Icons.undo_rounded),
                      ),
                      IconButton(
                        tooltip: 'Redo',
                        onPressed: _sigRedoStrokes.isEmpty ? null : _redoSignatureStroke,
                        icon: const Icon(Icons.redo_rounded),
                      ),
                      IconButton(
                        tooltip: 'Clear',
                        onPressed: _sigStrokes.isEmpty ? null : _clearSignatureStrokes,
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                      ),
                    ],
                  ),
                  _sliderRow('Pen Size', _sigPenWidth, 2, 14, (v) => setState(() => _sigPenWidth = v)),
                  LayoutBuilder(
                    builder: (context, padConstraints) {
                      final padW = padConstraints.maxWidth;
                      const padH = 195.0;
                      final padSize = Size(padW, padH);
                      if (_sigStrokes.isEmpty) {
                        _sigCanvasSize = padSize;
                      }
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: padW,
                          height: padH,
                          decoration: BoxDecoration(
                            color: _sigTransparentBg ? paperPreviewBg : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _amber.withOpacity(0.7), width: 1.4),
                          ),
                          child: Stack(
                            children: [
                              if (_sigStrokes.isEmpty)
                                const Center(
                                  child: Text(
                                    'Sign here or open Full-Screen Pad above',
                                    style: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                                  ),
                                ),
                              GestureDetector(
                                onPanStart: (d) => setState(() {
                                  if (_sigStrokes.isEmpty) _sigCanvasSize = padSize;
                                  _sigCurrentStroke = [_toCanonicalPadPoint(d.localPosition, padSize)];
                                  _sigRedoStrokes.clear();
                                  _sigStrokes.add((_sigCurrentStroke!, _sigInkColor, _sigPenWidth));
                                }),
                                onPanUpdate: (d) {
                                  if (_sigCurrentStroke == null) return;
                                  setState(() => _sigCurrentStroke!.add(_toCanonicalPadPoint(d.localPosition, padSize)));
                                },
                                onPanEnd: (_) => _sigCurrentStroke = null,
                                child: CustomPaint(
                                  painter: _SignaturePadPainter(_sigStrokes, _sigCanvasSize),
                                  size: padSize,
                                ),
                              ),
                              Positioned(
                                right: 6,
                                bottom: 6,
                                child: InkWell(
                                  onTap: _openFullScreenSignaturePad,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.72),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.fullscreen_rounded, size: 15, color: Colors.white),
                                        SizedBox(width: 4),
                                        Text('Big Pad', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _choicePill(
                    label: _sigTransparentBg ? 'BG: Transparent PNG' : 'BG: White Paper',
                    selected: _sigTransparentBg,
                    onTap: () => setState(() => _sigTransparentBg = !_sigTransparentBg),
                  ),
                ],
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 210,
                      height: 210,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _stampTransparentBg ? paperPreviewBg : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: CustomPaint(
                        painter: _StampPainter(
                          shape: _stampShape,
                          org: _stampOrgCtrl.text,
                          status: _stampStatusCtrl.text,
                          sub: _stampSubCtrl.text,
                          inkColor: _stampInkColor,
                          showDate: _stampShowDate,
                          transparentBg: _stampTransparentBg,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _choicePill(
                          label: 'Round Seal',
                          selected: _stampShape == 'round',
                          onTap: () => setState(() => _stampShape = 'round'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _choicePill(
                          label: 'Oval Stamp',
                          selected: _stampShape == 'oval',
                          onTap: () => setState(() => _stampShape = 'oval'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _choicePill(
                          label: 'Box Stamp',
                          selected: _stampShape == 'box',
                          onTap: () => setState(() => _stampShape = 'box'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _stampOrgCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Shop / Organization Name (Top)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _stampStatusCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Center Badge (PAID / منظور شدہ)'),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: ['PAID · ادا شدہ', 'منظور شدہ', 'VERIFIED', 'ORIGINAL', 'وصول پایا']
                        .map(
                          (preset) => _choicePill(
                            label: preset,
                            selected: _stampStatusCtrl.text == preset,
                            onTap: () => setState(() => _stampStatusCtrl.text = preset),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _stampSubCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'City / Reg No. (Bottom)'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text('Ink:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _subColor)),
                      const SizedBox(width: 8),
                      ...[
                        const Color(0xFF1E3A8A),
                        const Color(0xFFB91C1C),
                        const Color(0xFF047857),
                        const Color(0xFF0F172A),
                      ].map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setState(() => _stampInkColor = c),
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _stampInkColor == c ? _amber : _borderColor,
                                  width: _stampInkColor == c ? 3 : 1.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      _choicePill(
                        label: _stampShowDate ? 'Date: On' : 'Date: Off',
                        selected: _stampShowDate,
                        onTap: () => setState(() => _stampShowDate = !_stampShowDate),
                      ),
                      const SizedBox(width: 6),
                      _choicePill(
                        label: _stampTransparentBg ? 'Clear PNG' : 'White',
                        selected: _stampTransparentBg,
                        onTap: () => setState(() => _stampTransparentBg = !_stampTransparentBg),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _amber,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _sigMode == 2 ? _addStampToProjectCanvas : _addSignatureToProjectCanvas,
            icon: const Icon(Icons.add_to_photos_outlined, size: 18),
            label: Text(
              _sigMode == 2 ? 'Add Stamp (مہر) to Studio Canvas' : 'Add Signature to Studio Canvas',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _sigMode == 2 ? _exportStampPng(shareOnly: false) : _exportSignaturePng(shareOnly: false),
                  icon: const Icon(Icons.save_alt_rounded, size: 18),
                  label: const Text('Save PNG'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _sigMode == 2 ? _exportStampPng(shareOnly: true) : _exportSignaturePng(shareOnly: true),
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Share'),
                ),
              ),
            ),
          ],
        ),
        if (_sigMode == 0) ...[
          const SizedBox(height: 16),
          const Text('Signature Fonts (18 Styles)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.5,
            ),
            itemCount: _signatureFonts.length,
            itemBuilder: (ctx, i) {
              final f = _signatureFonts[i];
              final sel = f.$1 == _sigFontFamily;
              return InkWell(
                onTap: () => setState(() => _sigFontFamily = f.$1),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: sel ? _amber.withOpacity(0.14) : _cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: sel ? _amber : _borderColor, width: sel ? 1.8 : 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: sel ? _accentText : _textColor,
                        ),
                      ),
                      Text(
                        f.$3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: _mutedColor),
                      ),
                      Expanded(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              previewText,
                              textDirection: f.$4 ? TextDirection.rtl : TextDirection.ltr,
                              style: TextStyle(
                                fontFamily: f.$1,
                                fontSize: f.$4 ? 22 : 28,
                                color: sel ? _accentText : _textColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Future<_ScannedDocPage> _renderScannedDocPreview(
    String id,
    String rawPath,
    Uint8List rawBytes,
    int rotationDeg,
  ) async {
    var decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      return _ScannedDocPage(
        id: id,
        rawPath: rawPath,
        rawBytes: rawBytes,
        previewBytes: rawBytes,
        rotationDeg: rotationDeg,
        width: 1000,
        height: 1400,
      );
    }

    if (rotationDeg % 360 != 0) {
      decoded = img.copyRotate(decoded, angle: rotationDeg);
    }
    if (math.max(decoded.width, decoded.height) > 2000) {
      final scale = 2000 / math.max(decoded.width, decoded.height);
      decoded = img.copyResize(
        decoded,
        width: math.max(1, (decoded.width * scale).round()),
        height: math.max(1, (decoded.height * scale).round()),
      );
    }

    final jpg = Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
    return _ScannedDocPage(
      id: id,
      rawPath: rawPath,
      rawBytes: rawBytes,
      previewBytes: jpg,
      rotationDeg: rotationDeg,
      width: decoded.width,
      height: decoded.height,
    );
  }

  Future<void> _appendScannedPaths(
    List<String> paths,
    void Function(void Function()) setModalState,
  ) async {
    if (paths.isEmpty) return;
    final added = <_ScannedDocPage>[];
    for (final srcPath in paths) {
      try {
        final permanent = await _persistPickedImageOffline(srcPath);
        final bytes = await File(permanent).readAsBytes();
        final pageObj = await _renderScannedDocPreview(
          'scan_${DateTime.now().microsecondsSinceEpoch}_${added.length}',
          permanent,
          bytes,
          0,
        );
        added.add(pageObj);
      } catch (_) {}
    }
    if (!mounted || added.isEmpty) return;
    setModalState(() {
      final startIdx = _scannedPages.length;
      _scannedPages.addAll(added);
      _activeScanIdx = startIdx;
    });
  }

  Future<void> _openDocumentScannerSheet() async {
    bool localBusy = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panelBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final safeIdx = _scannedPages.isEmpty
                ? 0
                : _activeScanIdx.clamp(0, _scannedPages.length - 1);
            final activePage = _scannedPages.isEmpty ? null : _scannedPages[safeIdx];

            Future<void> runDocumentScanner() async {
              setModalState(() => localBusy = true);
              DocumentScanner? scanner;
              try {
                final options = DocumentScannerOptions(
                  documentFormat: DocumentFormat.jpeg,
                  mode: ScannerMode.full,
                  pageLimit: 12,
                  isGalleryImport: true,
                );
                scanner = DocumentScanner(options: options);
                final result = await scanner.scanDocument();
                if (result.images.isNotEmpty) {
                  await _appendScannedPaths(result.images, setModalState);
                }
              } on PlatformException catch (e) {
                final msg = e.message ?? '';
                if (!msg.toLowerCase().contains('cancel') && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Document Scanner: ${msg.isEmpty ? e.code : msg}')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Document Scanner error: $e')),
                  );
                }
              } finally {
                try {
                  await scanner?.close();
                } catch (_) {}
                if (ctx.mounted) setModalState(() => localBusy = false);
              }
            }

            Future<void> rotateActivePage(int nextRot) async {
              if (activePage == null) return;
              setModalState(() => localBusy = true);
              try {
                final updated = await _renderScannedDocPreview(
                  activePage.id,
                  activePage.rawPath,
                  activePage.rawBytes,
                  nextRot,
                );
                if (ctx.mounted) {
                  setModalState(() {
                    _scannedPages[safeIdx] = updated;
                  });
                }
              } finally {
                if (ctx.mounted) setModalState(() => localBusy = false);
              }
            }

            Future<Uint8List> buildScannerPdfBytes() async {
              final doc = pw.Document();
              for (final pg in _scannedPages) {
                final pdfImg = pw.MemoryImage(pg.previewBytes);
                doc.addPage(
                  pw.Page(
                    pageFormat: PdfPageFormat(pg.width.toDouble(), pg.height.toDouble()),
                    margin: pw.EdgeInsets.zero,
                    build: (_) => pw.Center(child: pw.Image(pdfImg, fit: pw.BoxFit.contain)),
                  ),
                );
              }
              return doc.save();
            }

            Future<void> downloadScannerPdf() async {
              if (_scannedPages.isEmpty) return;
              setModalState(() => localBusy = true);
              String? shareTmpPath;
              String savedLoc = '';
              try {
                await _runWithSavingHud(
                  savingTitle: 'Saving PDF...',
                  savingSubtitle: '${_scannedPages.length} scanned page(s)',
                  savedTitle: 'PDF Saved',
                  savedSubtitle: '${_scannedPages.length} page(s) saved',
                  action: () async {
                    final pdfBytes = await buildScannerPdfBytes();
                    final fileName = 'qalam_scan_${DateTime.now().millisecondsSinceEpoch}.pdf';
                    if (Platform.isAndroid) {
                      try {
                        savedLoc = await _mediaChannel.invokeMethod<String>('savePdfToDownloads', {
                              'bytes': pdfBytes,
                              'name': fileName,
                            }) ??
                            '';
                      } catch (_) {}
                    }
                    final tmpDir = await getTemporaryDirectory();
                    final tmpPath = p.join(tmpDir.path, fileName);
                    await File(tmpPath).writeAsBytes(pdfBytes);
                    shareTmpPath = tmpPath;
                    if (savedLoc.isEmpty) {
                      final extDir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
                      final outDir = Directory(p.join(extDir.path, 'QalamStudio'));
                      if (!outDir.existsSync()) outDir.createSync(recursive: true);
                      final outPath = p.join(outDir.path, fileName);
                      await File(outPath).writeAsBytes(pdfBytes);
                      savedLoc = outPath;
                    }
                  },
                );
                if (!mounted || shareTmpPath == null) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('PDF Saved: $savedLoc'),
                    duration: const Duration(seconds: 3),
                    action: SnackBarAction(
                      label: 'Share PDF',
                      onPressed: () => Share.shareXFiles([XFile(shareTmpPath!)], text: 'Qalam Scanned PDF'),
                    ),
                  ),
                );
              } finally {
                if (ctx.mounted) setModalState(() => localBusy = false);
              }
            }

            Future<void> saveScannerJpeg() async {
              if (activePage == null) return;
              setModalState(() => localBusy = true);
              String lastSaved = '';
              String lastTmp = '';
              try {
                await _runWithSavingHud(
                  savingTitle: 'Saving JPEG(s)...',
                  savingSubtitle: '${_scannedPages.length} page(s)',
                  savedTitle: 'JPEG Saved',
                  savedSubtitle: '${_scannedPages.length} image(s) in Gallery',
                  action: () async {
                    final tmpDir = await getTemporaryDirectory();
                    for (int i = 0; i < _scannedPages.length; i++) {
                      final pg = _scannedPages[i];
                      final fname = 'qalam_scan_${DateTime.now().millisecondsSinceEpoch}_p${i + 1}.jpg';
                      lastSaved = await _saveBytesToDeviceGallery(pg.previewBytes, fname);
                      lastTmp = p.join(tmpDir.path, fname);
                      await File(lastTmp).writeAsBytes(pg.previewBytes);
                    }
                  },
                );
                if (!mounted || lastTmp.isEmpty) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${_scannedPages.length} JPEG(s) Saved: $lastSaved'),
                    duration: const Duration(seconds: 3),
                    action: SnackBarAction(
                      label: 'Share',
                      onPressed: () => Share.shareXFiles([XFile(lastTmp)], text: 'Qalam Scanned JPEG'),
                    ),
                  ),
                );
              } finally {
                if (ctx.mounted) setModalState(() => localBusy = false);
              }
            }

            Future<void> sendScannedToStudio() async {
              if (activePage == null) return;
              await _runWithSavingHud(
                savingTitle: 'Saving to Studio...',
                savedTitle: 'Added to Canvas',
                savedSubtitle: 'Scanned Page ${safeIdx + 1}',
                action: () async {
                  final cleanName = 'scan_page_${DateTime.now().millisecondsSinceEpoch}.jpg';
                  final docs = await getApplicationDocumentsDirectory();
                  final outDir = Directory(p.join(docs.path, 'qalam_media'));
                  if (!outDir.existsSync()) outDir.createSync(recursive: true);
                  final outPath = p.join(outDir.path, cleanName);
                  await File(outPath).writeAsBytes(activePage.previewBytes);

                  final canvasLayer = DesignLayer(
                    id: 'canvas_${DateTime.now().microsecondsSinceEpoch}',
                    name: 'Scanned Doc ${safeIdx + 1}',
                    type: LayerType.image,
                    x: 0,
                    y: 0,
                    width: activePage.width.toDouble(),
                    height: activePage.height.toDouble(),
                    locked: true,
                    isCanvasBackground: true,
                    localImagePath: outPath,
                    aspectLocked: true,
                    objectFit: BoxFit.cover,
                  );
                  _pushUndoSnapshot();
                  if (mounted) {
                    setState(() {
                      _page.width = activePage.width.toDouble();
                      _page.height = activePage.height.toDouble();
                      if (_page.layers.isNotEmpty && _page.layers.first.isCanvasBackground) {
                        _page.layers[0] = canvasLayer;
                      } else {
                        _page.layers.insert(0, canvasLayer);
                      }
                      for (final l in _page.layers) {
                        _clampLayerInPage(l);
                      }
                      _selectedLayerId = null;
                      _inspectorTab = 2;
                      _navIndex = 0;
                    });
                  }
                  await _saveCurrentProject(showToast: false);
                },
              );
              if (ctx.mounted) Navigator.pop(ctx);
            }

            return SafeArea(
              child: DraggableScrollableSheet(
                initialChildSize: 0.9,
                minChildSize: 0.55,
                maxChildSize: 0.96,
                expand: false,
                builder: (_, scrollCtrl) {
                  return ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: _mutedColor.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: _amber.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.document_scanner_rounded, color: _accentText, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Document Scanner', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                                Text('Scan or Import Photos · Preview · PDF / JPEG', style: TextStyle(fontSize: 11, color: _subColor)),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _amber,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                          ),
                          onPressed: localBusy ? null : runDocumentScanner,
                          icon: const Icon(Icons.document_scanner_outlined, size: 19),
                          label: const Text('Scan / Upload Document', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (localBusy)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: LinearProgressIndicator(minHeight: 3),
                        ),
                      if (activePage == null)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 20),
                          decoration: BoxDecoration(
                            color: _inputBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _borderColor),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.insert_drive_file_outlined, size: 44, color: _accentText),
                              const SizedBox(height: 10),
                              const Text(
                                'No Scanned Pages Yet',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Tap Scan / Upload Document to scan pages or import photos using Document Scanner tools, preview them cleanly, and save as PDF or JPEG.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, color: _subColor, height: 1.4),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        Container(
                          height: 310,
                          decoration: BoxDecoration(
                            color: _isDark ? const Color(0xFF0A0C0F) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _borderColor),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            children: [
                              Center(
                                child: Image.memory(
                                  activePage.previewBytes,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.7),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Page ${safeIdx + 1}/${_scannedPages.length} · ${activePage.width}×${activePage.height}',
                                    style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 76,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _scannedPages.length,
                            itemBuilder: (_, i) {
                              final pg = _scannedPages[i];
                              final sel = i == safeIdx;
                              return GestureDetector(
                                onTap: () => setModalState(() => _activeScanIdx = i),
                                child: Container(
                                  width: 58,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: sel ? _amber : _borderColor,
                                      width: sel ? 2.2 : 1,
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.memory(pg.previewBytes, fit: BoxFit.cover),
                                      Positioned(
                                        bottom: 3,
                                        left: 3,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.black87,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text('${i + 1}', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
                                        ),
                                      ),
                                      Positioned(
                                        top: 2,
                                        right: 2,
                                        child: GestureDetector(
                                          onTap: () => setModalState(() {
                                            _scannedPages.removeAt(i);
                                            if (_activeScanIdx >= _scannedPages.length && _activeScanIdx > 0) {
                                              _activeScanIdx = _scannedPages.length - 1;
                                            }
                                          }),
                                          child: Container(
                                            width: 18,
                                            height: 18,
                                            decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                                            child: const Icon(Icons.close, size: 12, color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  side: BorderSide(color: _borderColor),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: localBusy
                                    ? null
                                    : () => rotateActivePage((activePage.rotationDeg + 90) % 360),
                                icon: Icon(Icons.rotate_right_rounded, size: 18, color: _accentText),
                                label: const Text('Rotate 90°', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: _amber,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                                ),
                                onPressed: localBusy ? null : downloadScannerPdf,
                                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                                label: Text(
                                  _scannedPages.length > 1 ? 'Download PDF (${_scannedPages.length}p)' : 'Download PDF',
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: _isDark ? Colors.white12 : const Color(0xFF0F172A),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                                ),
                                onPressed: localBusy ? null : saveScannerJpeg,
                                icon: Icon(Icons.download_rounded, size: 18, color: _amber),
                                label: Text(
                                  _scannedPages.length > 1 ? 'Save JPEGs (${_scannedPages.length})' : 'Save JPEG',
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 11),
                                  side: BorderSide(color: _borderColor),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                                ),
                                onPressed: localBusy
                                    ? null
                                    : () async {
                                        await _runWithSavingHud(
                                          savingTitle: 'Preparing PDF...',
                                          savedTitle: 'PDF Ready',
                                          action: () async {
                                            final bytes = await buildScannerPdfBytes();
                                            await Printing.layoutPdf(onLayout: (_) async => bytes);
                                          },
                                        );
                                      },
                                icon: const Icon(Icons.print_outlined, size: 17),
                                label: const Text('Print / Preview PDF', style: TextStyle(fontSize: 12.5)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 11),
                                  side: BorderSide(color: _amber.withOpacity(0.75)),
                                  foregroundColor: _accentText,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                                ),
                                onPressed: localBusy ? null : sendScannedToStudio,
                                icon: const Icon(Icons.brush_outlined, size: 17),
                                label: const Text('Open in Studio', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

}

class _ScannedDocPage {
  final String id;
  final String rawPath;
  final Uint8List rawBytes;
  final Uint8List previewBytes;
  final int rotationDeg;
  final int width;
  final int height;

  const _ScannedDocPage({
    required this.id,
    required this.rawPath,
    required this.rawBytes,
    required this.previewBytes,
    required this.rotationDeg,
    required this.width,
    required this.height,
  });
}

class _ExactNumberBox extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final String? labelText;
  final TextAlign textAlign;
  final EdgeInsetsGeometry? contentPadding;
  final TextStyle? style;
  final ValueChanged<double> onChanged;

  const _ExactNumberBox({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.labelText,
    this.textAlign = TextAlign.start,
    this.contentPadding,
    this.style,
  });

  @override
  State<_ExactNumberBox> createState() => _ExactNumberBoxState();
}

class _ExactNumberBoxState extends State<_ExactNumberBox> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.round().toString());
    _focus = FocusNode()
      ..addListener(() {
        if (!_focus.hasFocus) {
          final parsed = double.tryParse(_ctrl.text.trim());
          if (parsed != null) {
            final clamped = parsed.clamp(widget.min, widget.max).toDouble();
            if ((clamped - widget.value).abs() > 0.01) {
              widget.onChanged(clamped);
            }
            _ctrl.text = clamped.round().toString();
          } else {
            _ctrl.text = widget.value.round().toString();
          }
        }
      });
  }

  @override
  void didUpdateWidget(covariant _ExactNumberBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && (widget.value - oldWidget.value).abs() > 0.49) {
      _ctrl.text = widget.value.round().toString();
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      focusNode: _focus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: widget.textAlign,
      style: widget.style,
      decoration: InputDecoration(
        labelText: widget.labelText,
        isDense: true,
        contentPadding: widget.contentPadding,
      ),
      onChanged: (raw) {
        final parsed = double.tryParse(raw.trim());
        if (parsed == null) return;
        if (parsed >= widget.min && parsed <= widget.max) {
          widget.onChanged(parsed);
        } else if (parsed > widget.max) {
          widget.onChanged(widget.max);
        }
      },
      onSubmitted: (raw) {
        final parsed = double.tryParse(raw.trim());
        if (parsed != null) {
          final clamped = parsed.clamp(widget.min, widget.max).toDouble();
          widget.onChanged(clamped);
          _ctrl.text = clamped.round().toString();
        } else {
          _ctrl.text = widget.value.round().toString();
        }
      },
    );
  }
}

class _SignaturePadPainter extends CustomPainter {
  final List<(List<Offset>, Color, double)> strokes;
  final Size sourceSize;
  _SignaturePadPainter(this.strokes, this.sourceSize);

  @override
  void paint(Canvas canvas, Size size) {
    final sw = math.max(1.0, sourceSize.width);
    final sh = math.max(1.0, sourceSize.height);
    final scale = math.min(size.width / sw, size.height / sh);
    final ox = (size.width - sw * scale) / 2.0;
    final oy = (size.height - sh * scale) / 2.0;

    for (final stroke in strokes) {
      final pts = stroke.$1;
      if (pts.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.$2
        ..strokeWidth = (stroke.$3 * scale).clamp(1.5, 24.0)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (pts.length == 1) {
        canvas.drawCircle(
          Offset(pts[0].dx * scale + ox, pts[0].dy * scale + oy),
          (stroke.$3 * scale) / 2,
          Paint()..color = stroke.$2,
        );
        continue;
      }
      final path = Path()..moveTo(pts[0].dx * scale + ox, pts[0].dy * scale + oy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx * scale + ox, pts[i].dy * scale + oy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePadPainter oldDelegate) => true;
}


class _StampPainter extends CustomPainter {
  final String shape;
  final String org;
  final String status;
  final String sub;
  final Color inkColor;
  final bool showDate;
  final bool transparentBg;

  const _StampPainter({
    required this.shape,
    required this.org,
    required this.status,
    required this.sub,
    required this.inkColor,
    required this.showDate,
    required this.transparentBg,
  });

  bool _isRtl(String text) => RegExp(r'[\u0600-\u06FF]').hasMatch(text);

  String _todayBadge() {
    final now = DateTime.now();
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    final d = now.day.toString().padLeft(2, '0');
    return '$d ${months[now.month - 1]} ${now.year}';
  }

  void _paintCenteredText(
    Canvas canvas,
    String text,
    Offset center,
    double maxW,
    double fontSize, {
    FontWeight weight = FontWeight.w700,
    Color? color,
    String? fontFamily,
  }) {
    final rtl = _isRtl(text);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color ?? inkColor,
          fontSize: fontSize,
          fontWeight: weight,
          fontFamily: fontFamily ?? (rtl ? 'NotoNaskhArabic' : 'PlusJakartaSans'),
        ),
      ),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxW);
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  void _paintArcLatin(Canvas canvas, String text, Offset center, double radius, bool isTop, double fontSize) {
    final chars = text.trim().toUpperCase().split('');
    if (chars.isEmpty) return;
    final painters = <TextPainter>[];
    double totalW = 0;
    for (final ch in chars) {
      final tp = TextPainter(
        text: TextSpan(
          text: ch,
          style: TextStyle(color: inkColor, fontSize: fontSize, fontWeight: FontWeight.w800, fontFamily: 'PlusJakartaSans'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painters.add(tp);
      totalW += tp.width + 2.0;
    }
    final totalAngle = math.min(math.pi * 1.15, totalW / math.max(1.0, radius));
    final stepScale = totalAngle / math.max(1.0, totalW);
    double cursor = isTop ? -math.pi / 2 - totalAngle / 2 : math.pi / 2 + totalAngle / 2;

    for (final tp in painters) {
      final half = ((tp.width + 2.0) * stepScale) / 2;
      cursor += isTop ? half : -half;
      canvas.save();
      canvas.translate(center.dx + math.cos(cursor) * radius, center.dy + math.sin(cursor) * radius);
      canvas.rotate(isTop ? cursor + math.pi / 2 : cursor - math.pi / 2);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
      cursor += isTop ? half : -half;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final orgText = org.trim().isEmpty ? 'QALAM STUDIO' : org.trim();
    final statusText = status.trim().isEmpty ? 'APPROVED' : status.trim();
    final subText = sub.trim().isEmpty ? 'OFFICIAL SEAL' : sub.trim();
    final today = _todayBadge();

    final outerStroke = Paint()
      ..color = inkColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.014;
    final thinStroke = Paint()
      ..color = inkColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.005;

    if (shape == 'round') {
      final rOuter = math.min(w, h) * 0.43;
      final rInner = rOuter * 0.67;
      canvas.drawCircle(center, rOuter, outerStroke);
      canvas.drawCircle(center, rOuter - w * 0.02, thinStroke);
      canvas.drawCircle(center, rInner, thinStroke..strokeWidth = w * 0.006);

      final textR = (rOuter - w * 0.02 + rInner) / 2;
      if (_isRtl(orgText)) {
        _paintCenteredText(canvas, orgText, Offset(center.dx, center.dy - textR + 2), rInner * 1.4, w * 0.045);
      } else {
        _paintArcLatin(canvas, orgText, center, textR, true, w * 0.042);
      }
      if (_isRtl(subText)) {
        _paintCenteredText(canvas, subText, Offset(center.dx, center.dy + textR - 2), rInner * 1.4, w * 0.04);
      } else {
        _paintArcLatin(canvas, subText, center, textR, false, w * 0.036);
      }

      final bw = rInner * 2.25;
      final bh = w * 0.14;
      final rect = Rect.fromCenter(center: center, width: bw, height: bh);
      canvas.drawRect(rect, Paint()..color = transparentBg ? Colors.white.withOpacity(0.92) : Colors.white);
      canvas.drawRect(rect, Paint()..color = inkColor..style = PaintingStyle.stroke..strokeWidth = w * 0.007);
      _paintCenteredText(
        canvas,
        statusText,
        Offset(center.dx, showDate ? center.dy - w * 0.02 : center.dy),
        bw - 16,
        w * 0.052,
        weight: FontWeight.w800,
      );
      if (showDate) {
        _paintCenteredText(canvas, today, Offset(center.dx, center.dy + w * 0.034), bw - 16, w * 0.028);
      }
    } else if (shape == 'oval') {
      final rx = w * 0.44;
      final ry = h * 0.34;
      canvas.drawOval(Rect.fromCenter(center: center, width: rx * 2, height: ry * 2), outerStroke);
      canvas.drawOval(Rect.fromCenter(center: center, width: (rx - w * 0.022) * 2, height: (ry - w * 0.022) * 2), thinStroke);

      canvas.drawLine(Offset(center.dx - rx * 0.7, center.dy - ry * 0.28), Offset(center.dx + rx * 0.7, center.dy - ry * 0.28), thinStroke);
      canvas.drawLine(Offset(center.dx - rx * 0.7, center.dy + ry * 0.28), Offset(center.dx + rx * 0.7, center.dy + ry * 0.28), thinStroke);

      _paintCenteredText(canvas, _isRtl(orgText) ? orgText : orgText.toUpperCase(), Offset(center.dx, center.dy - ry * 0.54), rx * 1.35, w * 0.042);
      _paintCenteredText(canvas, _isRtl(subText) ? subText : subText.toUpperCase(), Offset(center.dx, center.dy + ry * 0.54), rx * 1.35, w * 0.036);
      _paintCenteredText(canvas, statusText, Offset(center.dx, showDate ? center.dy - w * 0.02 : center.dy), rx * 1.5, w * 0.056, weight: FontWeight.w800);
      if (showDate) {
        _paintCenteredText(canvas, today, Offset(center.dx, center.dy + w * 0.036), rx * 1.25, w * 0.028);
      }
    } else {
      final bw = w * 0.84;
      final bh = h * 0.52;
      final rect = Rect.fromCenter(center: center, width: bw, height: bh);
      canvas.drawRect(rect, outerStroke);
      canvas.drawRect(rect.deflate(w * 0.02), thinStroke);

      _paintCenteredText(canvas, _isRtl(orgText) ? orgText : orgText.toUpperCase(), Offset(center.dx, rect.top + bh * 0.2), bw - 28, w * 0.04);
      _paintCenteredText(canvas, statusText, Offset(center.dx, showDate ? center.dy - w * 0.01 : center.dy + w * 0.01), bw - 28, w * 0.068, weight: FontWeight.w800);
      canvas.drawLine(Offset(rect.left + w * 0.04, rect.bottom - bh * 0.25), Offset(rect.right - w * 0.04, rect.bottom - bh * 0.25), thinStroke);

      final botText = showDate ? '$subText · $today' : subText;
      _paintCenteredText(canvas, _isRtl(botText) ? botText : botText.toUpperCase(), Offset(center.dx, rect.bottom - bh * 0.14), bw - 32, w * 0.032);
    }
  }

  @override
  bool shouldRepaint(covariant _StampPainter oldDelegate) => true;
}
