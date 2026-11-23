import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
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
import 'image_crop_sheet.dart';

class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key});

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> with WidgetsBindingObserver {
  static const Color _brandNib = Color(0xFFF59E0B);
  Color get _amber => _isDark ? const Color(0xFFFBBF24) : const Color(0xFFF59E0B);
  Color get _inkPrimary => _brandNib;
  Color get _onInkPrimary => const Color(0xFF1C1917);
  Color get _brandNibInk => _isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
  Color get _brandNibOnInk => const Color(0xFF1C1917);
  Color get _amberTintBg => _isDark ? const Color(0xFFF59E0B).withOpacity(0.18) : const Color(0xFFFFF6E0);
  Color get _amberTintBorder => _isDark ? const Color(0xFFFBBF24) : const Color(0xFFF59E0B);
  Color get _scannerTeal => _isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488);
  Color get _scannerTealBg => _isDark ? const Color(0xFF0D9488).withOpacity(0.18) : const Color(0xFFF0FDFA);
  Color get _scannerTealBorder => _isDark ? const Color(0xFF2DD4BF).withOpacity(0.36) : const Color(0xFF99F6E4);
  Color get _shareSky => _isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
  Color get _shareSkyBg => _isDark ? const Color(0xFF0284C7).withOpacity(0.18) : const Color(0xFFE0F2FE);
  Color get _shareSkyBorder => _isDark ? const Color(0xFF38BDF8).withOpacity(0.36) : const Color(0xFFBAE6FD);
  static const MethodChannel _mediaChannel = MethodChannel('com.qalam.studio/media');

  final ImagePicker _picker = ImagePicker();
  final GlobalKey _canvasExportKey = GlobalKey();
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _sigTextController = TextEditingController();

  List<DesignProject> _projects = [];
  late DesignProject _project;
  int _pageIndex = 0;
  String? _selectedLayerId;
  int _navIndex = 0; // 0=Projects, 1=Fill, 2=Sign/Seal, 3=Docs, 4=Batch
  bool _inStudio = false;
  (int, String)? _studioEntrySnapshot;
  int _inspectorTab = 0; // 0=Design, 1=Overlay, 2=Effects, 3=Layers
  bool _sheetExpanded = false;
  bool _sheetTall = false;
  Timer? _autosaveTimer;
  Timer? _signSealAutosaveTimer;
  final Map<String, Uint8List> _projectThumbCache = {};
  final Map<String, int> _projectThumbStamp = {};
  final Set<String> _projectThumbGenerating = {};
  bool _exportTransparentCanvas = false;
  bool _showGuides = true;
  bool _hideOverlaysForExport = false;
  final List<_ScannedDocPage> _scannedPages = [];
  int _activeScanIdx = 0;
  int _whiteRemovalSeq = 0;
  int _guillocheSeq = 0;
  bool _showLaunchSplash = true;
  double _launchSplashOpacity = 1.0;
  final List<(int, String)> _undoStack = [];
  final List<(int, String)> _redoStack = [];
  final List<_CustomInstalledFont> _customFonts = [];
  List<_FontCatalogEntry> _googleDirectoryFonts = [];
  bool _loadingGoogleDirectory = false;
  final Set<String> _previewLoadingFamilies = {};
  final Set<String> _loadedFontFamilies = {
    'NotoNastaliqUrdu',
    'Gulzar',
    'NotoNaskhArabic',
    'IBMPlexSansArabicSemiBold',
    'PlusJakartaSans',
    'PlayfairDisplay',
  };

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
  String _sigPenType = 'fountain';
  bool _sigAutoSmooth = true;
  final List<_SigStroke> _sigStrokes = [];
  final List<_SigStroke> _sigRedoStrokes = [];
  List<_SigPoint>? _sigCurrentStroke;
  String? _sigScanRawPath;
  Uint8List? _sigScanProcessedBytes;
  bool _sigScanProcessing = false;
  double _sigScanSensitivity = 56.0;
  Color? _sigScanRecolor;
  bool _sigScanAutoTrim = true;
  bool _sigScanShowOriginal = false;
  String? _customEffectPreviewPath;

  // Rubber Stamp / مہر Maker state
  String _stampShape = 'round'; // 'round', 'oval', 'box'
  final TextEditingController _stampOrgCtrl = TextEditingController();
  final TextEditingController _stampStatusCtrl = TextEditingController();
  final TextEditingController _stampSubCtrl = TextEditingController();
  Color _stampInkColor = const Color(0xFF1E3A8A);
  bool _stampShowDate = true;
  bool _stampTransparentBg = true;

  // Batch state
  List<String> _batchInputs = [];
  List<String> _batchOutputs = [];
  bool _batchProcessing = false;
  bool _batchBw = false;
  bool _batchGuilloche = false;
  String _batchGuillochePattern = 'banknote';
  double _batchRemoveWhite = 0.0;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _cardBg => _isDark ? const Color(0xFF1E222B) : Colors.white;
  Color get _panelBg => _isDark ? const Color(0xFF1E222B) : Colors.white;
  Color get _inputBg => _isDark ? const Color(0xFF12141A) : const Color(0xFFFAF8F4);
  Color get _chipBg => _isDark ? const Color(0xFF262B36) : const Color(0xFFF3F0E9);
  Color get _borderColor => _isDark ? const Color(0xFF2C313C) : const Color(0xFFE7E2D8);
  Color get _textColor => _isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1C1917);
  Color get _subColor => _isDark ? const Color(0xFF94A3B8) : const Color(0xFF57534E);
  Color get _mutedColor => _isDark ? const Color(0xFF64748B) : const Color(0xFF78716C);
  Color get _accentText => _isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _project = _buildDefaultProject();
    _loadSavedProjects();
    _loadSignSealDraft();
    _loadInstalledCustomFonts();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkQuickTourOnFirstLaunch());
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() => _launchSplashOpacity = 0.0);
      Future<void>.delayed(const Duration(milliseconds: 420), () {
        if (mounted) setState(() => _showLaunchSplash = false);
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_autosaveTimer?.isActive ?? false) {
        _autosaveTimer?.cancel();
        unawaited(_saveCurrentProject(showToast: false));
      }
      if (_signSealAutosaveTimer?.isActive ?? false) {
        _signSealAutosaveTimer?.cancel();
        unawaited(_saveSignSealDraft());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autosaveTimer?.cancel();
    _signSealAutosaveTimer?.cancel();
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
              : (isSaving ? _brandNib : const Color(0xFF10B981));
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
                      color: isDark ? const Color(0xFF1E222B) : Colors.white,
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
                                  ? SizedBox(
                                      key: const ValueKey('hud_spin'),
                                      width: 22,
                                      height: 22,
                                      child: const CircularProgressIndicator(
                                        strokeWidth: 2.6,
                                        color: _brandNib,
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
                              color: _brandNib,
                              backgroundColor: _brandNib.withOpacity(0.18),
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
      final flag = File(p.join(docsDir.path, 'qalamix_tour_seen_v1.flag'));
      if (!flag.existsSync()) {
        await flag.writeAsString('1');
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
                        color: _isDark ? const Color(0xFF16191E) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _borderColor),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        _isDark
                            ? 'assets/images/qalamix_logo_dark.png'
                            : 'assets/images/qalamix_logo.jpg',
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        isAntiAlias: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Qalamix — Quick Guide', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _textColor)),
                          Text('Urdu Nastaliq & Business Design Suite (Offline)', style: TextStyle(fontSize: 11.5, color: _subColor)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _tourTile(
                  Icons.receipt_long_rounded,
                  'Cash Memo, Letterhead & Certificate',
                  'The Docs tab includes ready-to-edit Urdu Cash Memo, Letterhead, and Certificate templates.',
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _inStudio = false;
                      _navIndex = 3;
                    });
                  },
                ),
                _tourTile(
                  Icons.verified_rounded,
                  'Official Stamps & Signatures',
                  'Create Round, Oval, or Box rubber stamps in the Sign/Seal tab and add them to the canvas in 1 tap.',
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _inStudio = false;
                      _navIndex = 2;
                      _sigMode = 3;
                    });
                  },
                ),
                _tourTile(
                  Icons.font_download_outlined,
                  'Fonts Library & Download (.TTF)',
                  'Browse, preview, install, or download Urdu, Arabic & English fonts or import local .TTF/.OTF files.',
                  onTap: () {
                    Navigator.pop(ctx);
                    _openFontsLibrarySheet();
                  },
                ),
                _tourTile(
                  Icons.touch_app_rounded,
                  'Canvas Handle Controls',
                  'Black Corners = Size Scale · Blue Top = Rotate · Green Corner = Text Box Wrap Width.',
                  onTap: () {
                    Navigator.pop(ctx);
                    _enterStudio();
                  },
                ),
                _tourTile(
                  Icons.edit_note_rounded,
                  'Quick Fill & Portable Share',
                  'Swap customer names or photos in seconds from the Fill tab without changing layer coordinates.',
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _inStudio = false;
                      _navIndex = 1;
                    });
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _inkPrimary,
                      foregroundColor: _onInkPrimary,
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
            Icon(icon, color: _brandNibInk, size: 20),
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
        name: 'Qalamix Design Studio',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        pages: [
          DocumentPage(
            id: 'page_1',
            title: 'Page 1',
            width: 900,
            height: 1200,
            backgroundColor: const Color(0xFFFAF9F6),
            layers: [
              DesignLayer(
                id: 't1',
                name: 'Urdu Headline',
                type: LayerType.text,
                x: 80,
                y: 180,
                width: 740,
                height: 220,
                text: 'ہر لفظ ایک تصویر ہے',
                isRtl: true,
                fontFamily: 'NotoNastaliqUrdu',
                fontSize: 48,
                lineHeight: 2.3,
                textColor: const Color(0xFF0F172A),
              ),
              DesignLayer(
                id: 't2',
                name: 'English Subtitle',
                type: LayerType.text,
                x: 80,
                y: 430,
                width: 740,
                height: 120,
                text: 'QALAMIX — OFFLINE DESIGN & DOCS',
                isRtl: false,
                fontFamily: 'PlusJakartaSans',
                fontSize: 24,
                lineHeight: 1.4,
                textColor: const Color(0xFFB45309),
              ),
            ],
          ),
        ],
      );

  Future<String> _persistPickedImageOffline(String sourcePath) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final imgDir = Directory(p.join(docsDir.path, 'qalamix_images'));
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
            l.localImagePath != null &&
            File(l.localImagePath!).existsSync()) {
          if (l.filters.removeWhite > 0 && l.processedWhiteRemovedBytes == null) {
            final bytes = await removeWhiteBackgroundOffline(l.localImagePath!, l.filters.removeWhite);
            if (bytes != null) {
              l.processedWhiteRemovedBytes = bytes;
              changed = true;
            }
          }
          if (l.filters.guilloche && l.processedGuillocheBytes == null) {
            final gBytes = await applyGuillocheBlendOffline(GuillocheRequest(
              filePath: l.localImagePath!,
              contrastPct: l.filters.guillocheContrast,
              bendPx: l.filters.guillocheBend,
              opacityPct: l.filters.guillocheOpacity,
              pattern: l.filters.guillochePattern,
              removeWhiteTolerance: l.filters.removeWhite,
            ));
            if (gBytes != null) {
              l.processedGuillocheBytes = gBytes;
              changed = true;
            }
          }
        }
      }
    }
    if (changed && mounted) setState(() {});
  }

  Future<void> _loadSavedProjects() async {
    try {
      var list = await LocalProjectStore.instance.loadAllProjects();
      if (!mounted) return;
      if (list.isEmpty) {
        final fallback = _buildDefaultProject();
        await LocalProjectStore.instance.saveProject(fallback);
        list = [fallback];
      }
      await _loadCachedThumbnailsFromDisk(list);
      if (!mounted) return;
      setState(() {
        _projects = list;
        final curIdx = list.indexWhere((p) => p.id == _project.id);
        _project = curIdx >= 0 ? list[curIdx] : list.first;
        _pageIndex = 0;
      });
      await _rehydrateProjectFilters(_project);
      unawaited(_ensureProjectThumbnails(list));
    } catch (_) {}
  }

  Future<void> _loadCachedThumbnailsFromDisk(List<DesignProject> list) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final thumbDir = Directory(p.join(docsDir.path, 'qalamix_thumbs'));
      if (!thumbDir.existsSync()) return;
      for (final proj in list) {
        final stampFile = File(p.join(thumbDir.path, '${proj.id}.stamp'));
        final imgFile = File(p.join(thumbDir.path, '${proj.id}.png'));
        if (imgFile.existsSync() && stampFile.existsSync()) {
          final stamp = int.tryParse(stampFile.readAsStringSync().trim()) ?? -1;
          if (stamp == proj.updatedAt) {
            final bytes = await imgFile.readAsBytes();
            if (bytes.isNotEmpty) {
              _projectThumbCache[proj.id] = bytes;
              _projectThumbStamp[proj.id] = stamp;
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _ensureProjectThumbnails(List<DesignProject> list) async {
    for (final proj in list) {
      if (!mounted) return;
      final cachedStamp = _projectThumbStamp[proj.id];
      if (_projectThumbCache.containsKey(proj.id) && cachedStamp == proj.updatedAt) {
        continue;
      }
      await _generateAndCacheProjectThumb(proj);
    }
  }

  Future<void> _generateAndCacheProjectThumb(DesignProject proj) async {
    if (proj.pages.isEmpty || _projectThumbGenerating.contains(proj.id)) return;
    _projectThumbGenerating.add(proj.id);
    try {
      final bytes = await renderPageThumbnailBytes(proj.pages.first, maxSide: 180);
      if (bytes == null || bytes.isEmpty) return;
      final docsDir = await getApplicationDocumentsDirectory();
      final thumbDir = Directory(p.join(docsDir.path, 'qalamix_thumbs'));
      if (!thumbDir.existsSync()) thumbDir.createSync(recursive: true);
      await File(p.join(thumbDir.path, '${proj.id}.png')).writeAsBytes(bytes);
      await File(p.join(thumbDir.path, '${proj.id}.stamp')).writeAsString('${proj.updatedAt}');
      if (!mounted) return;
      setState(() {
        _projectThumbCache[proj.id] = bytes;
        _projectThumbStamp[proj.id] = proj.updatedAt;
      });
    } catch (_) {
    } finally {
      _projectThumbGenerating.remove(proj.id);
    }
  }

  Future<void> _deleteCachedProjectThumb(String projId) async {
    _projectThumbCache.remove(projId);
    _projectThumbStamp.remove(projId);
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final thumbDir = Directory(p.join(docsDir.path, 'qalamix_thumbs'));
      final imgFile = File(p.join(thumbDir.path, '$projId.png'));
      final stampFile = File(p.join(thumbDir.path, '$projId.stamp'));
      if (imgFile.existsSync()) await imgFile.delete();
      if (stampFile.existsSync()) await stampFile.delete();
    } catch (_) {}
  }

  void _scheduleAutosave({Duration delay = const Duration(milliseconds: 1200)}) {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(delay, () {
      if (!mounted) return;
      unawaited(_saveCurrentProject(showToast: false));
    });
  }

  void _scheduleSignSealAutosave({
    Duration delay = const Duration(milliseconds: 1200),
  }) {
    _signSealAutosaveTimer?.cancel();
    _signSealAutosaveTimer = Timer(delay, () {
      if (!mounted) return;
      unawaited(_saveSignSealDraft());
    });
  }

  Future<void> _saveSignSealDraft() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final file = File(p.join(docsDir.path, 'qalamix_sign_seal_draft.json'));
      final payload = jsonEncode({
        'sigText': _sigTextController.text,
        'sigMode': _sigMode,
        'sigFontFamily': _sigFontFamily,
        'sigInkColor': _sigInkColor.value,
        'sigFontSize': _sigFontSize,
        'sigLetterSpacing': _sigLetterSpacing,
        'sigSlanted': _sigSlanted,
        'sigBold': _sigBold,
        'sigTransparentBg': _sigTransparentBg,
        'sigPenWidth': _sigPenWidth,
        'sigPenType': _sigPenType,
        'sigAutoSmooth': _sigAutoSmooth,
        'stampShape': _stampShape,
        'stampOrg': _stampOrgCtrl.text,
        'stampStatus': _stampStatusCtrl.text,
        'stampSub': _stampSubCtrl.text,
        'stampInkColor': _stampInkColor.value,
        'stampShowDate': _stampShowDate,
        'stampTransparentBg': _stampTransparentBg,
      });
      await file.writeAsString(payload);
    } catch (_) {}
  }

  Future<void> _loadSignSealDraft() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final file = File(p.join(docsDir.path, 'qalamix_sign_seal_draft.json'));
      if (!file.existsSync()) return;
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _sigTextController.text = (map['sigText'] ?? '').toString();
        _sigMode = (map['sigMode'] ?? _sigMode) as int;
        _sigFontFamily = (map['sigFontFamily'] ?? _sigFontFamily).toString();
        if (map['sigInkColor'] != null) {
          _sigInkColor = Color((map['sigInkColor'] as num).toInt());
        }
        _sigFontSize = (map['sigFontSize'] ?? _sigFontSize).toDouble();
        _sigLetterSpacing = (map['sigLetterSpacing'] ?? _sigLetterSpacing).toDouble();
        _sigSlanted = (map['sigSlanted'] ?? _sigSlanted) as bool;
        _sigBold = (map['sigBold'] ?? _sigBold) as bool;
        _sigTransparentBg = (map['sigTransparentBg'] ?? _sigTransparentBg) as bool;
        _sigPenWidth = (map['sigPenWidth'] ?? _sigPenWidth).toDouble();
        _sigPenType = (map['sigPenType'] ?? _sigPenType).toString();
        _sigAutoSmooth = (map['sigAutoSmooth'] ?? _sigAutoSmooth) as bool;
        _stampShape = (map['stampShape'] ?? _stampShape).toString();
        _stampOrgCtrl.text = (map['stampOrg'] ?? '').toString();
        _stampStatusCtrl.text = (map['stampStatus'] ?? '').toString();
        _stampSubCtrl.text = (map['stampSub'] ?? '').toString();
        if (map['stampInkColor'] != null) {
          _stampInkColor = Color((map['stampInkColor'] as num).toInt());
        }
        _stampShowDate = (map['stampShowDate'] ?? _stampShowDate) as bool;
        _stampTransparentBg =
            (map['stampTransparentBg'] ?? _stampTransparentBg) as bool;
      });
    } catch (_) {}
  }

  String _formatUpdatedTime(int ms) {
    if (ms <= 0) return 'Updated recently';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'Updated just now';
    if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour12:$min $ampm';
    final today = DateTime(now.year, now.month, now.day);
    final dtDay = DateTime(dt.year, dt.month, dt.day);
    if (dtDay == today) return 'Updated Today · $timeStr';
    if (dtDay == today.subtract(const Duration(days: 1))) {
      return 'Updated Yesterday · $timeStr';
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return 'Updated ${months[dt.month - 1]} ${dt.day} · $timeStr';
  }

  Future<void> _confirmDeleteProject(DesignProject proj) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Project?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Delete "${proj.name}" permanently from this device? This cannot be undone.',
          style: TextStyle(fontSize: 13.5, color: _subColor, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final deletingCurrent = proj.id == _project.id;
    await LocalProjectStore.instance.deleteProject(proj.id);
    await _deleteCachedProjectThumb(proj.id);
    await _loadSavedProjects();
    if (deletingCurrent && mounted) {
      setState(() {
        _selectedLayerId = null;
        _undoStack.clear();
        _redoStack.clear();
      });
    }
  }

  Future<void> _rotateSelectedImage90(DesignLayer layer) async {
    final srcPath = layer.localImagePath;
    if (srcPath == null || !File(srcPath).existsSync()) return;
    await _runWithSavingHud(
      savingTitle: 'Rotating 90°...',
      savingSubtitle: layer.name,
      savedTitle: 'Image Rotated',
      savedSubtitle: layer.name,
      action: () async {
        final rawBytes = await File(srcPath).readAsBytes();
        final out = await compute(_rotateImage90Isolate, (
          rawBytes,
          p.extension(srcPath).toLowerCase(),
        ));
        if (out == null) return;
        final docsDir = await getApplicationDocumentsDirectory();
        final imgDir = Directory(p.join(docsDir.path, 'qalamix_images'));
        if (!imgDir.existsSync()) imgDir.createSync(recursive: true);
        final outPath = p.join(
          imgDir.path,
          'rot90_${DateTime.now().microsecondsSinceEpoch}${out.$2}',
        );
        await File(outPath).writeAsBytes(out.$1);
        if (!mounted) return;
        _pushUndoSnapshot();
        final cx = layer.x + layer.width / 2.0;
        final cy = layer.y + layer.height / 2.0;
        final nextW = layer.height;
        final nextH = layer.width;
        setState(() {
          layer.localImagePath = outPath;
          layer.processedWhiteRemovedBytes = null;
          layer.processedGuillocheBytes = null;
          if (layer.isCanvasBackground) {
            _page.width = nextW;
            _page.height = nextH;
            layer.x = 0;
            layer.y = 0;
            layer.width = nextW;
            layer.height = nextH;
          } else {
            layer.width = nextW;
            layer.height = nextH;
            layer.x = cx - nextW / 2.0;
            layer.y = cy - nextH / 2.0;
            _clampLayerInPage(layer);
          }
        });
        if (layer.filters.removeWhite > 0) {
          await _applyWhiteRemoval(layer, layer.filters.removeWhite);
        }
        if (layer.filters.guilloche) {
          await _applyGuillocheBlend(layer);
        }
        await _saveCurrentProject(showToast: false);
      },
    );
  }

  Future<void> _cropSelectedImage(DesignLayer layer) async {
    final srcPath = layer.localImagePath;
    if (srcPath == null || !File(srcPath).existsSync()) return;
    final res = await showImageCropSheet(context, imagePath: srcPath);
    if (res == null || !mounted) return;
    _pushUndoSnapshot();
    final cx = layer.x + layer.width / 2.0;
    final cy = layer.y + layer.height / 2.0;
    final newRatio = res.width / math.max(1.0, res.height.toDouble());
    setState(() {
      layer.localImagePath = res.filePath;
      layer.processedWhiteRemovedBytes = null;
      layer.processedGuillocheBytes = null;
      if (layer.isCanvasBackground) {
        final nextW = res.width.toDouble();
        final nextH = res.height.toDouble();
        _page.width = nextW;
        _page.height = nextH;
        layer.x = 0;
        layer.y = 0;
        layer.width = nextW;
        layer.height = nextH;
      } else {
        final nextW = layer.width;
        final nextH = (nextW / math.max(0.05, newRatio)).clamp(20.0, _page.height * 2.5);
        layer.width = nextW;
        layer.height = nextH;
        layer.x = cx - nextW / 2.0;
        layer.y = cy - nextH / 2.0;
        _clampLayerInPage(layer);
      }
    });
    if (layer.filters.removeWhite > 0) {
      await _applyWhiteRemoval(layer, layer.filters.removeWhite);
    }
    if (layer.filters.guilloche) {
      await _applyGuillocheBlend(layer);
    }
    await _saveCurrentProject(showToast: false);
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
      if (id != null) {
        _sheetExpanded = true;
        _sheetTall = false;
      } else {
        _sheetExpanded = false;
        _sheetTall = false;
      }
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
    final gCache = <String, Uint8List>{};
    for (final pg in _project.pages) {
      for (final l in pg.layers) {
        if (l.processedWhiteRemovedBytes != null) {
          cache['${l.id}_${l.filters.removeWhite.round()}'] = l.processedWhiteRemovedBytes!;
        }
        if (l.processedGuillocheBytes != null && l.filters.guilloche) {
          final gKey = '${l.id}_${l.filters.guillochePattern}_${l.filters.guillocheContrast.round()}_${l.filters.guillocheBend.toStringAsFixed(1)}_${l.filters.guillocheOpacity.round()}_${l.filters.removeWhite.round()}';
          gCache[gKey] = l.processedGuillocheBytes!;
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
        if (l.filters.guilloche) {
          final gKey = '${l.id}_${l.filters.guillochePattern}_${l.filters.guillocheContrast.round()}_${l.filters.guillocheBend.toStringAsFixed(1)}_${l.filters.guillocheOpacity.round()}_${l.filters.removeWhite.round()}';
          if (gCache.containsKey(gKey)) {
            l.processedGuillocheBytes = gCache[gKey];
          }
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

  void _enterStudio({bool snapshotCurrent = true}) {
    setState(() {
      if (snapshotCurrent) {
        _studioEntrySnapshot = (_pageIndex, _project.encode());
      }
      _inStudio = true;
      _sheetExpanded = _selectedLayerId != null;
      _sheetTall = false;
      if (_activeLayer?.type == LayerType.text) {
        _textController.text = _activeLayer!.text;
      }
    });
  }

  Future<void> _confirmExitStudio() async {
    if (!_inStudio) return;
    final hasEntrySnap = _studioEntrySnapshot != null;
    final hasChanges =
        hasEntrySnap && _studioEntrySnapshot!.$2 != _project.encode();
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Exit Studio?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        content: Text(
          hasChanges
              ? 'Do you want to save your changes to "${_project.name}" before exiting Studio?'
              : 'Do you want to save "${_project.name}" before returning to Projects?',
          style: TextStyle(fontSize: 13.5, color: _subColor, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            child: const Text("Don't Save", style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _inkPrimary,
              foregroundColor: _onInkPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Save & Exit', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == 'cancel') return;
    if (choice == 'discard') {
      _autosaveTimer?.cancel();
      final snap = _studioEntrySnapshot;
      if (snap != null) {
        _restoreEncodedSnapshot(snap);
      }
      if (mounted) {
        setState(() {
          _inStudio = false;
          _navIndex = 0;
          _studioEntrySnapshot = null;
          _sheetExpanded = false;
          _sheetTall = false;
        });
      }
      return;
    }
    if (choice == 'save') {
      _autosaveTimer?.cancel();
      await _saveCurrentProject(showToast: true);
      if (mounted) {
        setState(() {
          _inStudio = false;
          _navIndex = 0;
          _studioEntrySnapshot = null;
          _sheetExpanded = false;
          _sheetTall = false;
        });
      }
    }
  }

  Widget _buildModernThemeToggle() {
    return Tooltip(
      message: _isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
      child: GestureDetector(
        onTap: () {
          final next = _isDark ? ThemeMode.light : ThemeMode.dark;
          appThemeMode.value = next;
          unawaited(saveAppThemeMode(next));
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: 60,
          height: 32,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: _isDark ? const Color(0xFF262B36) : const Color(0xFFF3F0E9),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _borderColor),
          ),
          child: Stack(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Center(
                      child: Icon(
                        Icons.light_mode_rounded,
                        size: 13.5,
                        color: !_isDark ? Colors.transparent : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Icon(
                        Icons.dark_mode_rounded,
                        size: 13.5,
                        color: _isDark ? Colors.transparent : const Color(0xFF78716C),
                      ),
                    ),
                  ),
                ],
              ),
              AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: _isDark ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 26,
                  height: 24,
                  decoration: BoxDecoration(
                    color: _amber,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                        color: Colors.black.withOpacity(0.16),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                    size: 14,
                    color: const Color(0xFF1C1917),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
            style: FilledButton.styleFrom(backgroundColor: _inkPrimary, foregroundColor: _onInkPrimary),
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
    _autosaveTimer?.cancel();
    Future<void> persist() async {
      _project.updatedAt = DateTime.now().millisecondsSinceEpoch;
      await LocalProjectStore.instance.saveProject(_project);
      final list = await LocalProjectStore.instance.loadAllProjects();
      if (!mounted) return;
      setState(() => _projects = list);
      unawaited(_generateAndCacheProjectThumb(_project));
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
            style: FilledButton.styleFrom(backgroundColor: _inkPrimary, foregroundColor: _onInkPrimary),
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
          layer.processedGuillocheBytes = null;
        });
        if (layer.filters.removeWhite > 0) {
          await _applyWhiteRemoval(layer, layer.filters.removeWhite);
        }
        if (layer.filters.guilloche) {
          await _applyGuillocheBlend(layer);
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
    final outDir = Directory(p.join(extDir.path, 'Qalamix'));
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
    final prevInStudio = _inStudio;
    final prevNav = _navIndex;
    setState(() {
      _inStudio = true;
      _selectedLayerId = null;
      _hideOverlaysForExport = true;
      _exportTransparentCanvas = format == 'png' && transparent;
    });
    await Future.delayed(const Duration(milliseconds: 120));
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
          _inStudio = prevInStudio;
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
                await Future.delayed(const Duration(milliseconds: 110));
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
        final fileName = 'qalamix_export_${DateTime.now().millisecondsSinceEpoch}.$ext';
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
                          backgroundColor: _inkPrimary,
                          foregroundColor: _onInkPrimary,
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
                        label: const Text('Share Editable Project (.qalamix.json)'),
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
          color: selected ? _amberTintBg : _chipBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? _amberTintBorder : _borderColor),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? _accentText : _textColor,
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
      _sheetExpanded = false;
      _sheetTall = false;
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
      _sheetTall = false;
    });
    _scheduleAutosave();
  }

  void _addTextLayer() {
    final lightBg = _page.backgroundColor.alpha == 0 || _page.backgroundColor.computeLuminance() > 0.45;
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
      textColor: lightBg ? const Color(0xFF0F172A) : const Color(0xFFFFFFFF),
    );
    _clampLayerInPage(layer);
    _pushUndoSnapshot();
    setState(() {
      _page.layers.add(layer);
      _selectedLayerId = layer.id;
      _textController.text = layer.text;
      _inspectorTab = 0;
      _sheetExpanded = true;
      _sheetTall = false;
    });
    _scheduleAutosave();
  }

  void _openShapePickerSheet() {
    const items = <(String, String, IconData)>[
      ('rect', 'Rectangle', Icons.crop_square_rounded),
      ('rounded', 'Rounded', Icons.rounded_corner_rounded),
      ('circle', 'Circle', Icons.circle_outlined),
      ('arrow', 'Arrow', Icons.arrow_forward_rounded),
      ('double_arrow', '2-Way Arrow', Icons.compare_arrows_rounded),
      ('line', 'Line', Icons.horizontal_rule_rounded),
      ('triangle', 'Triangle', Icons.change_history_rounded),
      ('star', 'Star', Icons.star_rounded),
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panelBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Choose a Shape',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              Text(
                'Full opacity vector shapes — customize colors & borders in Style.',
                style: TextStyle(fontSize: 12, color: _subColor),
              ),
              const SizedBox(height: 14),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 4,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.95,
                children: items.map((item) {
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.pop(ctx);
                      _addShapeKind(item.$1);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: _chipBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _borderColor),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(item.$3, size: 26, color: _amber),
                          const SizedBox(height: 6),
                          Text(
                            item.$2,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addShapeKind(String kind) {
    final minSide = math.min(_page.width, _page.height);
    final sq = math.max(120.0, minSide * 0.34);
    String name = 'Rectangle';
    double w = _page.width * 0.56;
    double h = 200;
    Color fill = const Color(0xFF111317);
    Color strokeCol = _amber;
    double strokeW = 2.0;
    double radius = 8.0;

    if (kind == 'rounded') {
      name = 'Rounded Box';
      radius = 32.0;
    } else if (kind == 'circle') {
      name = 'Circle';
      w = sq;
      h = sq;
      radius = 999.0;
    } else if (kind == 'arrow') {
      name = 'Arrow';
      w = _page.width * 0.45;
      h = 110.0;
      fill = _amber;
      strokeCol = const Color(0xFF111317);
      strokeW = 0.0;
      radius = 0.0;
    } else if (kind == 'double_arrow') {
      name = 'Double Arrow';
      w = _page.width * 0.52;
      h = 110.0;
      fill = _amber;
      strokeCol = const Color(0xFF111317);
      strokeW = 0.0;
      radius = 0.0;
    } else if (kind == 'line') {
      name = 'Line';
      w = _page.width * 0.65;
      h = 14.0;
      fill = _amber;
      strokeCol = Colors.transparent;
      strokeW = 0.0;
      radius = 999.0;
    } else if (kind == 'triangle') {
      name = 'Triangle';
      w = sq;
      h = sq;
      fill = _amber;
      strokeCol = const Color(0xFF111317);
      strokeW = 0.0;
      radius = 0.0;
    } else if (kind == 'star') {
      name = 'Star';
      w = sq;
      h = sq;
      fill = _amber;
      strokeCol = const Color(0xFF111317);
      strokeW = 0.0;
      radius = 0.0;
    }

    final layer = DesignLayer(
      id: 'shp_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      type: LayerType.shape,
      x: (_page.width - w) / 2,
      y: (_page.height - h) / 2,
      width: w,
      height: h,
      opacity: 1.0,
      borderRadius: radius,
      shapeKind: kind,
      textColor: fill,
      shapeStrokeColor: strokeCol,
      shapeStrokeWidth: strokeW,
    );
    _clampLayerInPage(layer);
    _pushUndoSnapshot();
    setState(() {
      _page.layers.add(layer);
      _selectedLayerId = layer.id;
      _inspectorTab = 0;
      _sheetExpanded = true;
      _sheetTall = false;
    });
    _scheduleAutosave();
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
      _sheetExpanded = true;
      _sheetTall = false;
      if (copy.type == LayerType.text) _textController.text = copy.text;
    });
    _scheduleAutosave();
  }

  void _deleteSelectedLayer() {
    final l = _activeLayer;
    if (l == null || l.isCanvasBackground) return;
    _pushUndoSnapshot();
    setState(() {
      _page.layers.removeWhere((x) => x.id == l.id);
      _selectedLayerId = null;
      _sheetExpanded = false;
      _sheetTall = false;
    });
    _scheduleAutosave();
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
      if (layer.filters.guilloche) {
        await _applyGuillocheBlend(layer);
      }
      return;
    }
    setState(() => layer.filters.removeWhite = tolerance);
    final pngBytes = await removeWhiteBackgroundOffline(layer.localImagePath!, tolerance);
    if (!mounted || seq != _whiteRemovalSeq) return;
    setState(() => layer.processedWhiteRemovedBytes = pngBytes);
    if (layer.filters.guilloche) {
      await _applyGuillocheBlend(layer);
    } else {
      await _saveCurrentProject(showToast: false);
    }
  }

  Future<void> _applyGuillocheBlend(DesignLayer layer) async {
    if (layer.localImagePath == null) return;
    final seq = ++_guillocheSeq;
    if (!layer.filters.guilloche) {
      setState(() => layer.processedGuillocheBytes = null);
      await _saveCurrentProject(showToast: false);
      return;
    }
    final pngBytes = await applyGuillocheBlendOffline(GuillocheRequest(
      filePath: layer.localImagePath!,
      contrastPct: layer.filters.guillocheContrast,
      bendPx: layer.filters.guillocheBend,
      opacityPct: layer.filters.guillocheOpacity,
      pattern: layer.filters.guillochePattern,
      removeWhiteTolerance: layer.filters.removeWhite,
    ));
    if (!mounted || seq != _guillocheSeq) return;
    setState(() => layer.processedGuillocheBytes = pngBytes);
    await _saveCurrentProject(showToast: false);
  }

  @override
  Widget build(BuildContext context) {
    final stageBg = _isDark ? const Color(0xFF12141A) : const Color(0xFFE6E1D6);

    const hubTitles = ['Projects', 'Quick Fill', 'Sign & Seal', 'Docs & Scanner', 'Batch Studio'];
    return PopScope(
      canPop: !_inStudio,
      onPopInvoked: (didPop) {
        if (!didPop && _inStudio) {
          _confirmExitStudio();
        }
      },
      child: Stack(
      children: [
        Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        automaticallyImplyLeading: false,
        leadingWidth: _inStudio ? 48 : null,
        leading: _inStudio
            ? IconButton(
                tooltip: 'Back to Projects',
                icon: const Icon(Icons.arrow_back_rounded, size: 22),
                onPressed: _confirmExitStudio,
              )
            : null,
        titleSpacing: _inStudio ? 4 : 12,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _borderColor),
        ),
        title: _inStudio
            ? InkWell(
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
              )
            : Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _isDark ? const Color(0xFF16191E) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _borderColor),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      _isDark
                          ? 'assets/images/qalamix_logo_dark.png'
                          : 'assets/images/qalamix_logo.jpg',
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      isAntiAlias: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Qalamix',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          hubTitles[_navIndex.clamp(0, hubTitles.length - 1)],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: _subColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _buildModernThemeToggle(),
          ),
          if (_inStudio) ...[
            IconButton(
              tooltip: 'Save Offline',
              icon: const Icon(Icons.save_outlined, size: 20),
              onPressed: _saveCurrentProject,
            ),
            PopupMenuButton<String>(
              tooltip: 'Studio Tools',
              icon: const Icon(Icons.more_vert_rounded, size: 21),
              onSelected: (val) {
                if (val == 'fonts') _openFontsLibrarySheet();
                if (val == 'scanner') _openDocumentScannerSheet();
                if (val == 'guides') setState(() => _showGuides = !_showGuides);
                if (val == 'guide') _showQuickTourSheet();
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'fonts',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.font_download_outlined, size: 20),
                    title: Text('Fonts Library'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'scanner',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.document_scanner_outlined, size: 20),
                    title: Text('Document Scanner'),
                  ),
                ),
                PopupMenuItem(
                  value: 'guides',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_showGuides ? Icons.grid_on_rounded : Icons.grid_off_rounded, size: 20),
                    title: Text(_showGuides ? 'Hide Margin Guides' : 'Show Margin Guides'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'guide',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.help_outline_rounded, size: 20),
                    title: Text('Quick Guide & Help'),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10, left: 2),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _inkPrimary,
                  foregroundColor: _onInkPrimary,
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                onPressed: _showExportOptionsSheet,
                icon: Icon(Icons.download_rounded, size: 17, color: _brandNibOnInk),
                label: const Text('Export', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
            ),
          ] else ...[
            PopupMenuButton<String>(
              tooltip: 'Tools',
              icon: const Icon(Icons.more_vert_rounded, size: 21),
              onSelected: (val) {
                if (val == 'fonts') _openFontsLibrarySheet();
                if (val == 'scanner') _openDocumentScannerSheet();
                if (val == 'guide') _showQuickTourSheet();
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(
                  value: 'fonts',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.font_download_outlined, size: 20),
                    title: Text('Fonts Library'),
                  ),
                ),
                PopupMenuItem(
                  value: 'scanner',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.document_scanner_outlined, size: 20),
                    title: Text('Document Scanner'),
                  ),
                ),
                PopupMenuItem(
                  value: 'guide',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.help_outline_rounded, size: 20),
                    title: Text('Quick Guide & Help'),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
      body: IndexedStack(
        index: _inStudio ? 0 : (_navIndex + 1),
        children: [
          _buildStudioView(stageBg),
          _buildProjectsView(),
          (!_inStudio && _navIndex == 1) ? _buildQuickFillView() : const SizedBox.shrink(),
          (!_inStudio && _navIndex == 2) ? _buildSignatureView() : const SizedBox.shrink(),
          _buildPagesView(),
          _buildBatchView(),
        ],
      ),
      bottomNavigationBar: _inStudio
          ? null
          : Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: _borderColor)),
              ),
              child: NavigationBar(
                selectedIndex: _navIndex,
                onDestinationSelected: (i) => setState(() {
                  _navIndex = i;
                }),
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder_rounded), label: 'Projects'),
                  NavigationDestination(icon: Icon(Icons.edit_note_rounded), label: 'Fill'),
                  NavigationDestination(icon: Icon(Icons.draw_outlined), selectedIcon: Icon(Icons.draw_rounded), label: 'Sign/Seal'),
                  NavigationDestination(icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description_rounded), label: 'Docs'),
                  NavigationDestination(icon: Icon(Icons.auto_awesome_motion_outlined), selectedIcon: Icon(Icons.auto_awesome_motion_rounded), label: 'Batch'),
                ],
              ),
            ),
        ),
        if (_showLaunchSplash)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: _launchSplashOpacity == 0.0,
              child: GestureDetector(
                onTap: () => setState(() {
                  _launchSplashOpacity = 0.0;
                  _showLaunchSplash = false;
                }),
                child: AnimatedOpacity(
                  opacity: _launchSplashOpacity,
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  child: Material(
                    color: _isDark ? const Color(0xFF0D0F12) : Colors.white,
                    child: SafeArea(
                      child: Stack(
                        children: [
                          Center(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.92, end: 1.0),
                              duration: const Duration(milliseconds: 480),
                              curve: Curves.easeOutCubic,
                              builder: (context, scale, child) => Transform.scale(
                                scale: scale,
                                child: child,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset(
                                    _isDark
                                        ? 'assets/images/qalamix_logo_dark.png'
                                        : 'assets/images/qalamix_logo.jpg',
                                    width: 112,
                                    height: 112,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.high,
                                    isAntiAlias: true,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Qalamix',
                                    style: TextStyle(
                                      fontFamily: 'PlusJakartaSans',
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.4,
                                      color: _isDark
                                          ? const Color(0xFFF8FAFC)
                                          : const Color(0xFF1C1917),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Design · Docs · Security Blend',
                                    style: TextStyle(
                                      fontFamily: 'PlusJakartaSans',
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.2,
                                      color: _isDark
                                          ? const Color(0xFF94A3B8)
                                          : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 36,
                            child: Center(
                              child: SizedBox(
                                width: 42,
                                height: 3,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    backgroundColor: _isDark
                                        ? const Color(0xFF2C313C)
                                        : const Color(0xFFE7E2D8),
                                    color: const Color(0xFFF59E0B),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
    );
  }

  Widget _buildStudioView(Color stageBg) {
    final layer = _activeLayer;
    final screenH = MediaQuery.of(context).size.height;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final standardH = math.min(395.0, math.max(290.0, screenH * 0.41));
    final tallH = math.min(540.0, math.max(375.0, screenH * 0.56));
    final expandedH = (_sheetTall ? tallH : standardH) + bottomInset * 0.5;

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
              onUpdateLayer: (_) {
                setState(() {});
                _scheduleAutosave();
              },
              onInteractionStart: _pushUndoSnapshot,
            ),
          ),
        ),
        Container(
          height: 50,
          decoration: BoxDecoration(
            color: _panelBg,
            border: Border(top: BorderSide(color: _borderColor)),
          ),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            children: [
              _quickBtn(Icons.photo_size_select_large, 'Canvas Pic', _importCanvasImage, highlight: true),
              _quickBtn(Icons.document_scanner_outlined, 'Scanner', _openDocumentScannerSheet, tealAccent: true),
              if (_undoStack.isNotEmpty) _quickBtn(Icons.undo_rounded, 'Undo', _undoCanvas),
              if (_redoStack.isNotEmpty) _quickBtn(Icons.redo_rounded, 'Redo', _redoCanvas),
              _quickBtn(Icons.title_rounded, 'Add Text', _addTextLayer),
              _quickBtn(Icons.font_download_outlined, 'Fonts', _openFontsLibrarySheet),
              _quickBtn(Icons.add_photo_alternate_outlined, 'Overlay', _addOverlayImage),
              _quickBtn(Icons.category_outlined, 'Shape', _openShapePickerSheet),
            ],
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: _sheetExpanded ? expandedH : (52 + bottomInset * 0.5),
          decoration: BoxDecoration(
            color: _panelBg,
            border: Border(top: BorderSide(color: _borderColor)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragEnd: (details) {
                    final v = details.primaryVelocity ?? 0.0;
                    if (v < -180) {
                      setState(() {
                        if (!_sheetExpanded) {
                          _sheetExpanded = true;
                          _sheetTall = false;
                        } else {
                          _sheetTall = true;
                        }
                      });
                    } else if (v > 180) {
                      setState(() {
                        if (_sheetTall) {
                          _sheetTall = false;
                        } else {
                          _sheetExpanded = false;
                        }
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 5, 6, 6),
                    decoration: BoxDecoration(
                      border: _sheetExpanded ? Border(bottom: BorderSide(color: _borderColor)) : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 34,
                          height: 3.5,
                          margin: const EdgeInsets.only(bottom: 5),
                          decoration: BoxDecoration(
                            color: _mutedColor.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _tabChip(0, 'Style', Icons.tune_rounded),
                                    _tabChip(1, 'Photo', Icons.layers_outlined),
                                    _tabChip(2, 'Adjust', Icons.auto_fix_high_rounded),
                                    _tabChip(3, 'Layers (${_page.layers.length})', Icons.format_list_bulleted_rounded),
                                  ],
                                ),
                              ),
                            ),
                            if (_sheetExpanded)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: InkWell(
                                  onTap: () => setState(() => _sheetTall = !_sheetTall),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: _sheetTall ? _amberTintBg : _chipBg,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: _sheetTall ? _amberTintBorder : _borderColor,
                                      ),
                                    ),
                                    child: Text(
                                      _sheetTall ? 'Smaller' : 'Larger',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: _sheetTall ? _brandNibInk : _textColor,
                                      ),
                                    ),
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
                      ],
                    ),
                  ),
                ),
                if (_sheetExpanded)
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                      child: _buildInspectorBody(layer),
                    ),
                  ),
              ],
            ),
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
    bool tealAccent = false,
  }) {
    final bg = highlight
        ? _inkPrimary
        : (danger
            ? Colors.redAccent.withOpacity(0.12)
            : (tealAccent ? _scannerTealBg : _chipBg));
    final fg = highlight
        ? _onInkPrimary
        : (danger ? Colors.redAccent : (tealAccent ? _scannerTeal : _textColor));
    final iconColor = highlight ? _brandNibOnInk : fg;
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
            border: highlight
                ? null
                : Border.all(
                    color: danger
                        ? Colors.redAccent.withOpacity(0.32)
                        : (tealAccent ? _scannerTealBorder : _borderColor),
                  ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: iconColor),
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
            color: active ? _amberTintBg : _chipBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? _amberTintBorder : _borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: active ? _accentText : _subColor),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? _accentText : _textColor,
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
          _scheduleAutosave();
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
              color: isSel ? _amberTintBg : _cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isSel ? _brandNib : _borderColor, width: isSel ? 1.5 : 1),
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: () => _selectLayer(l.id),
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
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isSel ? _amberTintBg : _chipBg,
                          borderRadius: BorderRadius.circular(8),
                          border: isSel ? Border.all(color: _amberTintBorder) : null,
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
                      () {
                        setState(() => l.visible = !l.visible);
                        _scheduleAutosave();
                      },
                    ),
                    if (!l.isCanvasBackground)
                      _compactLayerIcon(
                        l.locked ? Icons.lock_outline : Icons.lock_open_rounded,
                        l.locked ? 'Unlock' : 'Lock',
                        () {
                          setState(() => l.locked = !l.locked);
                          _scheduleAutosave();
                        },
                      ),
                    _compactLayerIcon(
                      Icons.delete_outline_rounded,
                      'Delete',
                      () {
                        _pushUndoSnapshot();
                        setState(() {
                          _page.layers.removeWhere((x) => x.id == l.id);
                          if (_selectedLayerId == l.id) _selectedLayerId = null;
                        });
                        _scheduleAutosave();
                      },
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

    // TAB 2: STUDIO EFFECTS & WHITE BACKGROUND CLEAN
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
            'Import a Canvas Pic or select an Overlay Image to apply Studio Effects or Remove White BG.',
            style: TextStyle(color: _subColor, fontSize: 13),
          ),
        );
      }
      final isWhiteRemoved = targetImg.filters.removeWhite > 0;
      final effectPresets = <(String, FilterSettings)>[
        ('Original', FilterSettings(removeWhite: targetImg.filters.removeWhite)),
        (
          'Black & White',
          FilterSettings(
            brightness: 1.04,
            contrast: 1.22,
            saturate: 0.0,
            blackAndWhite: true,
            grayscale: 1.0,
            removeWhite: targetImg.filters.removeWhite,
          ),
        ),
        (
          'Warm Gold',
          FilterSettings(
            brightness: 1.04,
            contrast: 1.08,
            saturate: 1.18,
            sepia: 0.22,
            removeWhite: targetImg.filters.removeWhite,
          ),
        ),
        (
          'Vivid Pop',
          FilterSettings(
            brightness: 1.04,
            contrast: 1.16,
            saturate: 1.35,
            removeWhite: targetImg.filters.removeWhite,
          ),
        ),
        (
          'Vintage',
          FilterSettings(
            brightness: 0.98,
            contrast: 1.08,
            saturate: 0.84,
            sepia: 0.38,
            removeWhite: targetImg.filters.removeWhite,
          ),
        ),
        (
          'Matte Soft',
          FilterSettings(
            brightness: 1.08,
            contrast: 0.90,
            saturate: 0.84,
            removeWhite: targetImg.filters.removeWhite,
          ),
        ),
        (
          'Vivid Tone & PinkHaze Warm Silk',
          FilterSettings(
            brightness: 1.06,
            contrast: 1.14,
            saturate: 1.38,
            sepia: 0.12,
            softGlow: 36,
            rosyTint: 50,
            skinSmooth: 18,
            removeWhite: targetImg.filters.removeWhite,
          ),
        ),
        (
          'Rosy Haze & Freckles Out',
          FilterSettings(
            brightness: 1.08,
            contrast: 1.02,
            saturate: 1.14,
            sepia: 0.06,
            softGlow: 30,
            rosyTint: 66,
            skinSmooth: 64,
            removeWhite: targetImg.filters.removeWhite,
          ),
        ),
        (
          'Glow Effect with Makeup',
          FilterSettings(
            brightness: 1.09,
            contrast: 1.11,
            saturate: 1.24,
            sepia: 0.06,
            softGlow: 68,
            rosyTint: 40,
            skinSmooth: 56,
            removeWhite: targetImg.filters.removeWhite,
          ),
        ),
        (
          'Portrait Blur V3',
          FilterSettings(
            brightness: 1.04,
            contrast: 1.12,
            saturate: 1.14,
            sepia: 0.04,
            softGlow: 18,
            rosyTint: 12,
            skinSmooth: 14,
            portraitBlur: 78,
            removeWhite: targetImg.filters.removeWhite,
          ),
        ),
        (
          'Golden Hour Silk',
          FilterSettings(
            brightness: 1.07,
            contrast: 1.11,
            saturate: 1.26,
            sepia: 0.24,
            softGlow: 42,
            portraitBlur: 26,
            removeWhite: targetImg.filters.removeWhite,
          ),
        ),
        (
          'Soft Peach Cream',
          FilterSettings(
            brightness: 1.10,
            contrast: 0.98,
            saturate: 1.12,
            sepia: 0.14,
            softGlow: 38,
            rosyTint: 34,
            skinSmooth: 48,
            removeWhite: targetImg.filters.removeWhite,
          ),
        ),
        (
          'Editorial Teal & Amber',
          FilterSettings(
            brightness: 1.01,
            contrast: 1.20,
            saturate: 1.18,
            sepia: 0.14,
            portraitBlur: 24,
            removeWhite: targetImg.filters.removeWhite,
          ),
        ),
        (
          'Velvet Studio Noir',
          FilterSettings(
            brightness: 1.05,
            contrast: 1.32,
            saturate: 0.0,
            blackAndWhite: true,
            grayscale: 1.0,
            portraitBlur: 36,
            removeWhite: targetImg.filters.removeWhite,
          ),
        ),
        (
          'Crisp Clarity',
          FilterSettings(
            brightness: 1.03,
            contrast: 1.28,
            saturate: 1.08,
            removeWhite: targetImg.filters.removeWhite,
          ),
        ),
        (
          'Guilloche Blend',
          FilterSettings(
            brightness: 1.0,
            contrast: 1.0,
            saturate: 1.0,
            guilloche: true,
            guillocheContrast: 13.0,
            guillocheBend: 3.0,
            guillocheOpacity: 88.0,
            guillochePattern: targetImg.filters.guillochePattern,
            removeWhite: targetImg.filters.removeWhite,
          ),
        ),
      ];
      final isGuilloche = targetImg.filters.guilloche;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_fix_high_rounded, size: 15, color: _accentText),
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
                    savingTitle: 'Resetting Effects...',
                    savedTitle: 'Reset Saved',
                    action: () async {
                      setState(() {
                        targetImg.filters = FilterSettings();
                        targetImg.processedWhiteRemovedBytes = null;
                        targetImg.processedGuillocheBytes = null;
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
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: isWhiteRemoved ? const Color(0xFF10B981) : _chipBg,
                    foregroundColor: isWhiteRemoved ? Colors.black : _textColor,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _applyWhiteRemoval(targetImg, isWhiteRemoved ? 0.0 : 35.0),
                  icon: const Icon(Icons.cleaning_services_outlined, size: 15),
                  label: Text(
                    isWhiteRemoved ? 'White BG Off ✓' : 'Remove White BG',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: isGuilloche ? _inkPrimary : _chipBg,
                    foregroundColor: isGuilloche ? _onInkPrimary : _textColor,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    _pushUndoSnapshot();
                    setState(() {
                      targetImg.filters.guilloche = !isGuilloche;
                      if (targetImg.filters.guilloche) {
                        targetImg.filters.brightness = 1.0;
                        targetImg.filters.contrast = 1.0;
                        targetImg.filters.saturate = 1.0;
                        targetImg.filters.sepia = 0.0;
                        targetImg.filters.blackAndWhite = false;
                      } else {
                        targetImg.processedGuillocheBytes = null;
                      }
                    });
                    await _applyGuillocheBlend(targetImg);
                  },
                  icon: const Icon(Icons.fingerprint_rounded, size: 16),
                  label: Text(
                    isGuilloche ? 'Guilloche ON ✓' : 'Guilloche Blend',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          if (isWhiteRemoved) ...[
            const SizedBox(height: 6),
            _sliderRow(
              'White Tol.',
              targetImg.filters.removeWhite,
              5,
              95,
              (v) => setState(() => targetImg.filters.removeWhite = v),
              onChangeEnd: (v) => _applyWhiteRemoval(targetImg, v),
            ),
          ],
          if (isGuilloche) ...[
            const SizedBox(height: 8),
            Text('Security Texture', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _subColor)),
            const SizedBox(height: 6),
            Row(
              children: [
                ('banknote', 'Banknote'),
                ('rosette', 'Rosette'),
                ('mesh', 'Mesh'),
              ].map((pat) {
                final sel = targetImg.filters.guillochePattern == pat.$1;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _choicePill(
                      label: pat.$2,
                      selected: sel,
                      onTap: () {
                        _pushUndoSnapshot();
                        setState(() => targetImg.filters.guillochePattern = pat.$1);
                        _applyGuillocheBlend(targetImg);
                      },
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 6),
            _sliderRow(
              'Contrast +%',
              targetImg.filters.guillocheContrast,
              0,
              25,
              (v) => setState(() => targetImg.filters.guillocheContrast = v),
              onChangeEnd: (_) => _applyGuillocheBlend(targetImg),
            ),
            _sliderRow(
              'Contour Bend',
              targetImg.filters.guillocheBend,
              0,
              6,
              (v) => setState(() => targetImg.filters.guillocheBend = v),
              onChangeEnd: (_) => _applyGuillocheBlend(targetImg),
            ),
            _sliderRow(
              'Skin Opacity',
              targetImg.filters.guillocheOpacity,
              75,
              100,
              (v) => setState(() => targetImg.filters.guillocheOpacity = v),
              onChangeEnd: (_) => _applyGuillocheBlend(targetImg),
            ),
          ],
          const SizedBox(height: 10),
          Text('Studio Effects', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _subColor)),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: effectPresets.map((entry) {
                final label = entry.$1;
                final preset = entry.$2;
                final active = preset.guilloche
                    ? targetImg.filters.guilloche
                    : (!targetImg.filters.guilloche &&
                        (targetImg.filters.brightness - preset.brightness).abs() < 0.02 &&
                        (targetImg.filters.contrast - preset.contrast).abs() < 0.02 &&
                        (targetImg.filters.sepia - preset.sepia).abs() < 0.02 &&
                        (targetImg.filters.portraitBlur - preset.portraitBlur).abs() < 2.0 &&
                        (targetImg.filters.softGlow - preset.softGlow).abs() < 2.0 &&
                        (targetImg.filters.rosyTint - preset.rosyTint).abs() < 2.0 &&
                        targetImg.filters.blackAndWhite == preset.blackAndWhite);
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: active ? FontWeight.w700 : FontWeight.w600)),
                    selected: active,
                    selectedColor: _amberTintBg,
                    backgroundColor: _chipBg,
                    checkmarkColor: _accentText,
                    side: BorderSide(color: active ? _amberTintBorder : _borderColor),
                    labelStyle: TextStyle(color: active ? _accentText : _textColor),
                    onSelected: (_) {
                      _pushUndoSnapshot();
                      setState(() {
                        targetImg.filters = preset.copy();
                        if (!preset.guilloche) {
                          targetImg.processedGuillocheBytes = null;
                        }
                      });
                      if (preset.guilloche) {
                        _applyGuillocheBlend(targetImg);
                      } else {
                        _scheduleAutosave();
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          _sliderRow(
            'Brightness',
            targetImg.filters.brightness * 100,
            50,
            160,
            (v) => setState(() => targetImg.filters.brightness = v / 100.0),
            onChangeEnd: (_) => _scheduleAutosave(),
          ),
          _sliderRow(
            'Contrast',
            targetImg.filters.contrast * 100,
            50,
            180,
            (v) => setState(() => targetImg.filters.contrast = v / 100.0),
            onChangeEnd: (_) => _scheduleAutosave(),
          ),
          _sliderRow(
            'Saturation',
            targetImg.filters.saturate * 100,
            0,
            200,
            (v) => setState(() {
              targetImg.filters.saturate = v / 100.0;
              if (v > 5) targetImg.filters.blackAndWhite = false;
            }),
            onChangeEnd: (_) => _scheduleAutosave(),
          ),
          _sliderRow(
            'Warmth / Sepia',
            targetImg.filters.sepia * 100,
            0,
            100,
            (v) => setState(() => targetImg.filters.sepia = v / 100.0),
            onChangeEnd: (_) => _scheduleAutosave(),
          ),
          _sliderRow(
            'Portrait Blur V3',
            targetImg.filters.portraitBlur,
            0,
            100,
            (v) => setState(() => targetImg.filters.portraitBlur = v),
            onChangeEnd: (_) => _scheduleAutosave(),
          ),
          _sliderRow(
            'Soft Glow',
            targetImg.filters.softGlow,
            0,
            100,
            (v) => setState(() => targetImg.filters.softGlow = v),
            onChangeEnd: (_) => _scheduleAutosave(),
          ),
          _sliderRow(
            'PinkHaze Silk',
            targetImg.filters.rosyTint,
            0,
            100,
            (v) => setState(() => targetImg.filters.rosyTint = v),
            onChangeEnd: (_) => _scheduleAutosave(),
          ),
          _sliderRow(
            'Skin Smooth',
            targetImg.filters.skinSmooth,
            0,
            100,
            (v) => setState(() => targetImg.filters.skinSmooth = v),
            onChangeEnd: (_) => _scheduleAutosave(),
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
        BlendMode.softLight,
        BlendMode.hardLight,
        BlendMode.darken,
        BlendMode.lighten,
        BlendMode.colorDodge,
        BlendMode.colorBurn,
        BlendMode.difference,
        BlendMode.exclusion,
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSelectedLayerActionBar(layer),
          if (layer.type == LayerType.image && layer.localImagePath != null) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _borderColor),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _rotateSelectedImage90(layer),
                    icon: const Icon(Icons.rotate_90_degrees_cw_rounded, size: 17),
                    label: const Text('Rotate 90°', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _inkPrimary,
                      foregroundColor: _onInkPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _cropSelectedImage(layer),
                    icon: Icon(Icons.crop_rounded, size: 17, color: _brandNibOnInk),
                    label: const Text('Crop Image', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          _buildExactSizeInputs(layer),
          const SizedBox(height: 6),
          _sliderRow(
            'Opacity',
            layer.opacity,
            0.0,
            1.0,
            (v) => setState(() => layer.opacity = v),
            onChangeEnd: (_) => _scheduleAutosave(),
          ),
          _sliderRow(
            'Rotation',
            layer.rotation,
            -180.0,
            180.0,
            (v) => setState(() => layer.rotation = v),
            onChangeEnd: (_) => _scheduleAutosave(),
          ),
          const SizedBox(height: 6),
          Text('Blend Mode', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _subColor)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: blends.map((b) {
              final sel = layer.blendMode == b;
              return _choicePill(
                label: _blendLabel(b),
                selected: sel,
                onTap: () {
                  setState(() => layer.blendMode = b);
                  _scheduleAutosave();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _inputBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Align Layer on Canvas', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _subColor)),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          layer.x = (_page.width - layer.width) / 2;
                          layer.y = (_page.height - layer.height) / 2;
                          _clampLayerInPage(layer);
                        });
                        _scheduleAutosave();
                      },
                      child: Text('Center Both', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _accentText)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _canvasAlignBtn(Icons.align_horizontal_left_rounded, 'Left', () {
                        setState(() {
                          layer.x = 0;
                          _clampLayerInPage(layer);
                        });
                        _scheduleAutosave();
                      }),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _canvasAlignBtn(Icons.align_horizontal_center_rounded, 'Center', () {
                        setState(() {
                          layer.x = (_page.width - layer.width) / 2;
                          _clampLayerInPage(layer);
                        });
                        _scheduleAutosave();
                      }),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _canvasAlignBtn(Icons.align_horizontal_right_rounded, 'Right', () {
                        setState(() {
                          layer.x = _page.width - layer.width;
                          _clampLayerInPage(layer);
                        });
                        _scheduleAutosave();
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _canvasAlignBtn(Icons.align_vertical_top_rounded, 'Top', () {
                        setState(() {
                          layer.y = 0;
                          _clampLayerInPage(layer);
                        });
                        _scheduleAutosave();
                      }),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _canvasAlignBtn(Icons.align_vertical_center_rounded, 'Middle', () {
                        setState(() {
                          layer.y = (_page.height - layer.height) / 2;
                          _clampLayerInPage(layer);
                        });
                        _scheduleAutosave();
                      }),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _canvasAlignBtn(Icons.align_vertical_bottom_rounded, 'Bottom', () {
                        setState(() {
                          layer.y = _page.height - layer.height;
                          _clampLayerInPage(layer);
                        });
                        _scheduleAutosave();
                      }),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
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
                    _compactLayerIcon(Icons.arrow_back_rounded, 'Left', () {
                      setState(() {
                        layer.x -= 5;
                        _clampLayerInPage(layer);
                      });
                      _scheduleAutosave();
                    }),
                    _compactLayerIcon(Icons.arrow_upward_rounded, 'Up', () {
                      setState(() {
                        layer.y -= 5;
                        _clampLayerInPage(layer);
                      });
                      _scheduleAutosave();
                    }),
                    _compactLayerIcon(Icons.arrow_downward_rounded, 'Down', () {
                      setState(() {
                        layer.y += 5;
                        _clampLayerInPage(layer);
                      });
                      _scheduleAutosave();
                    }),
                    _compactLayerIcon(Icons.arrow_forward_rounded, 'Right', () {
                      setState(() {
                        layer.x += 5;
                        _clampLayerInPage(layer);
                      });
                      _scheduleAutosave();
                    }),
                    const SizedBox(width: 4),
                    _compactLayerIcon(
                      Icons.center_focus_strong_outlined,
                      'Center on Canvas',
                      () {
                        setState(() {
                          layer.x = (_page.width - layer.width) / 2;
                          layer.y = (_page.height - layer.height) / 2;
                          _clampLayerInPage(layer);
                        });
                        _scheduleAutosave();
                      },
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
              backgroundColor: _inkPrimary,
              foregroundColor: _onInkPrimary,
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
                  _scheduleAutosave();
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
                  onChanged: (v) {
                    setState(() => _page.width = v);
                    _scheduleAutosave();
                  },
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
                  onChanged: (v) {
                    setState(() => _page.height = v);
                    _scheduleAutosave();
                  },
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
                onTap: () {
                  setState(() => _page.backgroundColor = c);
                  _scheduleAutosave();
                },
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
      final fontItems = _availableTextFontOptions();
      final strokePalette = <Color>[
        const Color(0xFF000000),
        const Color(0xFFFFFFFF),
        _brandNib,
        const Color(0xFFE11D48),
        const Color(0xFF2563EB),
        const Color(0xFF047857),
      ];
      final shadowPalette = <Color>[
        const Color(0x80000000),
        const Color(0xCC000000),
        const Color(0x99FFFFFF),
        const Color(0x99F59E0B),
        const Color(0x991D4ED8),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSelectedLayerActionBar(layer),
          TextField(
            controller: _textController,
            textDirection: layer.isRtl ? TextDirection.rtl : TextDirection.ltr,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Edit Text (Urdu / English)',
            ),
            onChanged: (val) {
              setState(() => layer.text = val);
              _scheduleAutosave();
            },
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Font Family (${fontItems.length})', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _subColor)),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: _openFontsLibrarySheet,
                icon: Icon(Icons.font_download_outlined, size: 15, color: _accentText),
                label: Text('Fonts Library (.TTF)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _accentText)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: fontItems.map((f) {
              return _choicePill(
                label: f.$2,
                selected: layer.fontFamily == f.$1,
                onTap: () {
                  setState(() {
                    layer.fontFamily = f.$1;
                    layer.isRtl = f.$3;
                    layer.lineHeight = f.$4;
                    if (f.$1 == 'IBMPlexSansArabicSemiBold') layer.fontWeight = 600;
                  });
                  _scheduleAutosave();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _choicePill(
                label: 'Regular',
                selected: layer.fontWeight < 550,
                onTap: () {
                  setState(() => layer.fontWeight = 400);
                  _scheduleAutosave();
                },
              ),
              const SizedBox(width: 8),
              _choicePill(
                label: 'SemiBold',
                selected: layer.fontWeight >= 550 && layer.fontWeight < 680,
                onTap: () {
                  setState(() => layer.fontWeight = 600);
                  _scheduleAutosave();
                },
              ),
              const SizedBox(width: 8),
              _choicePill(
                label: 'Bold',
                selected: layer.fontWeight >= 680,
                onTap: () {
                  setState(() => layer.fontWeight = 700);
                  _scheduleAutosave();
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          _sliderRow(
            'Text Scale',
            layer.fontSize,
            12,
            200,
            (v) => setState(() => layer.fontSize = v),
            onChangeEnd: (_) => _scheduleAutosave(),
          ),
          _sliderRow(
            'Letter Space',
            layer.letterSpacing,
            -2,
            24,
            (v) => setState(() => layer.letterSpacing = v),
            onChangeEnd: (_) => _scheduleAutosave(),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(side: BorderSide(color: _borderColor)),
                  onPressed: () {
                    setState(() => layer.fontSize = (layer.fontSize - 6).clamp(12.0, 200.0));
                    _scheduleAutosave();
                  },
                  child: const Text('A− Smaller'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(side: BorderSide(color: _borderColor)),
                  onPressed: () {
                    setState(() => layer.fontSize = (layer.fontSize + 6).clamp(12.0, 200.0));
                    _scheduleAutosave();
                  },
                  child: const Text('A+ Larger'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Text Alignment', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _subColor)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _textAlignBtn(
                  Icons.format_align_left_rounded,
                  'Left',
                  (layer.textAlign ?? (layer.isRtl ? TextAlign.right : TextAlign.left)) == TextAlign.left,
                  () {
                    setState(() => layer.textAlign = TextAlign.left);
                    _scheduleAutosave();
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _textAlignBtn(
                  Icons.format_align_center_rounded,
                  'Center',
                  layer.textAlign == TextAlign.center,
                  () {
                    setState(() => layer.textAlign = TextAlign.center);
                    _scheduleAutosave();
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _textAlignBtn(
                  Icons.format_align_right_rounded,
                  'Right',
                  (layer.textAlign ?? (layer.isRtl ? TextAlign.right : TextAlign.left)) == TextAlign.right,
                  () {
                    setState(() => layer.textAlign = TextAlign.right);
                    _scheduleAutosave();
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _textAlignBtn(
                  Icons.format_align_justify_rounded,
                  'Justify',
                  layer.textAlign == TextAlign.justify,
                  () {
                    setState(() => layer.textAlign = TextAlign.justify);
                    _scheduleAutosave();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Script Direction:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _subColor)),
              const SizedBox(width: 8),
              _choicePill(
                label: 'RTL (Urdu/Arabic)',
                selected: layer.isRtl,
                onTap: () {
                  setState(() {
                    layer.isRtl = true;
                    layer.textAlign ??= TextAlign.right;
                  });
                  _scheduleAutosave();
                },
              ),
              const SizedBox(width: 6),
              _choicePill(
                label: 'LTR (English)',
                selected: !layer.isRtl,
                onTap: () {
                  setState(() {
                    layer.isRtl = false;
                    layer.textAlign ??= TextAlign.left;
                  });
                  _scheduleAutosave();
                },
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
                onTap: () {
                  setState(() => layer.textColor = c);
                  _scheduleAutosave();
                },
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
                onTap: () {
                  setState(() => layer.textBgColor = c);
                  _scheduleAutosave();
                },
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
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _inputBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Text Stroke (Outline)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _textColor)),
                    const Spacer(),
                    if (layer.textStrokeWidth > 0.05)
                      _choicePill(
                        label: 'Off',
                        selected: false,
                        onTap: () {
                          setState(() => layer.textStrokeWidth = 0.0);
                          _scheduleAutosave();
                        },
                      ),
                  ],
                ),
                _sliderRow(
                  'Stroke Width',
                  layer.textStrokeWidth,
                  0,
                  16,
                  (v) => setState(() => layer.textStrokeWidth = v),
                  onChangeEnd: (_) => _scheduleAutosave(),
                ),
                Wrap(
                  spacing: 10,
                  children: strokePalette.map((c) {
                    final sel = layer.textStrokeColor.value == c.value;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          layer.textStrokeColor = c;
                          if (layer.textStrokeWidth <= 0.05) {
                            layer.textStrokeWidth = 3.0;
                          }
                        });
                        _scheduleAutosave();
                      },
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(color: sel ? _brandNib : _borderColor, width: sel ? 2.6 : 1.2),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _inputBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Soft Text Shadow', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _textColor)),
                    const Spacer(),
                    if (layer.textShadowBlur > 0.05 ||
                        layer.textShadowOffsetX.abs() > 0.1 ||
                        layer.textShadowOffsetY.abs() > 0.1)
                      _choicePill(
                        label: 'Off',
                        selected: false,
                        onTap: () {
                          setState(() {
                            layer.textShadowBlur = 0.0;
                            layer.textShadowOffsetX = 0.0;
                            layer.textShadowOffsetY = 0.0;
                          });
                          _scheduleAutosave();
                        },
                      ),
                  ],
                ),
                _sliderRow(
                  'Shadow Blur',
                  layer.textShadowBlur,
                  0,
                  24,
                  (v) => setState(() => layer.textShadowBlur = v),
                  onChangeEnd: (_) => _scheduleAutosave(),
                ),
                _sliderRow(
                  'Offset X',
                  layer.textShadowOffsetX,
                  -20,
                  20,
                  (v) => setState(() => layer.textShadowOffsetX = v),
                  onChangeEnd: (_) => _scheduleAutosave(),
                ),
                _sliderRow(
                  'Offset Y',
                  layer.textShadowOffsetY,
                  -20,
                  20,
                  (v) => setState(() => layer.textShadowOffsetY = v),
                  onChangeEnd: (_) => _scheduleAutosave(),
                ),
                Wrap(
                  spacing: 10,
                  children: shadowPalette.map((c) {
                    final sel = layer.textShadowColor.value == c.value;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          layer.textShadowColor = c;
                          if (layer.textShadowBlur <= 0.05 &&
                              layer.textShadowOffsetX.abs() < 0.1 &&
                              layer.textShadowOffsetY.abs() < 0.1) {
                            layer.textShadowBlur = 8.0;
                            layer.textShadowOffsetY = 3.0;
                          }
                        });
                        _scheduleAutosave();
                      },
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: c.withOpacity(1.0),
                          shape: BoxShape.circle,
                          border: Border.all(color: sel ? _brandNib : _borderColor, width: sel ? 2.6 : 1.2),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSelectedLayerActionBar(layer),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: layer.aspectLocked ? _inkPrimary : _chipBg,
                    foregroundColor: layer.aspectLocked ? _onInkPrimary : _textColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    setState(() => layer.aspectLocked = !layer.aspectLocked);
                    _scheduleAutosave();
                  },
                  icon: Icon(layer.aspectLocked ? Icons.lock : Icons.lock_open, size: 16),
                  label: Text(layer.aspectLocked ? 'Ratio Locked' : 'Free Stretch',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          _sliderRow(
            'Image Scale %',
            curScale,
            10,
            250,
            applyImageScale,
            onChangeEnd: (_) => _scheduleAutosave(),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(side: BorderSide(color: _borderColor)),
                  onPressed: () {
                    applyImageScale(curScale - 10);
                    _scheduleAutosave();
                  },
                  child: const Text('− Smaller'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(side: BorderSide(color: _borderColor)),
                  onPressed: () {
                    applyImageScale(curScale + 10);
                    _scheduleAutosave();
                  },
                  child: const Text('+ Larger'),
                ),
              ),
            ],
          ),
          _sliderRow(
            'Corner Radius',
            layer.borderRadius,
            0,
            160,
            (v) => setState(() => layer.borderRadius = v),
            onChangeEnd: (_) => _scheduleAutosave(),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(side: BorderSide(color: layer.flipX ? _amber : _borderColor)),
                  onPressed: () {
                    setState(() => layer.flipX = !layer.flipX);
                    _scheduleAutosave();
                  },
                  icon: const Icon(Icons.flip_rounded, size: 16),
                  label: const Text('Flip H'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(side: BorderSide(color: layer.flipY ? _amber : _borderColor)),
                  onPressed: () {
                    setState(() => layer.flipY = !layer.flipY);
                    _scheduleAutosave();
                  },
                  icon: const Icon(Icons.flip_camera_android_rounded, size: 16),
                  label: const Text('Flip V'),
                ),
              ),
            ],
          ),
        ],
      );
    }

    const shapeTypes = <(String, String)>[
      ('rect', 'Rectangle'),
      ('rounded', 'Rounded'),
      ('circle', 'Circle'),
      ('arrow', 'Arrow'),
      ('double_arrow', '2-Way Arrow'),
      ('line', 'Line'),
      ('triangle', 'Triangle'),
      ('star', 'Star'),
    ];
    final palette = <Color>[
      const Color(0xFF111317),
      const Color(0xFFFFFFFF),
      _amber,
      const Color(0xFF10B981),
      const Color(0xFFE11D48),
      const Color(0xFF2563EB),
      Colors.transparent,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSelectedLayerActionBar(layer),
        Text('Shape Style', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _subColor)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: shapeTypes.map((st) {
            final sel = layer.shapeKind == st.$1;
            return ChoiceChip(
              label: Text(st.$2, style: TextStyle(fontSize: 11, fontWeight: sel ? FontWeight.w700 : FontWeight.w600)),
              selected: sel,
              selectedColor: _amberTintBg,
              backgroundColor: _chipBg,
              checkmarkColor: _accentText,
              side: BorderSide(color: sel ? _amberTintBorder : _borderColor),
              labelStyle: TextStyle(color: sel ? _accentText : _textColor),
              onSelected: (_) {
                setState(() => layer.shapeKind = st.$1);
                _scheduleAutosave();
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        _sliderRow(
          'Corner Radius',
          layer.borderRadius,
          0,
          120,
          (v) => setState(() => layer.borderRadius = v),
          onChangeEnd: (_) => _scheduleAutosave(),
        ),
        _sliderRow(
          'Border Width',
          layer.shapeStrokeWidth,
          0,
          20,
          (v) => setState(() => layer.shapeStrokeWidth = v),
          onChangeEnd: (_) => _scheduleAutosave(),
        ),
        const SizedBox(height: 6),
        Text('Fill Color', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _subColor)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          children: palette.map((c) {
            final sel = layer.textColor.value == c.value;
            return GestureDetector(
              onTap: () {
                setState(() => layer.textColor = c);
                _scheduleAutosave();
              },
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: c == Colors.transparent ? _chipBg : c,
                  shape: BoxShape.circle,
                  border: Border.all(color: sel ? _amber : _borderColor, width: sel ? 3 : 1.2),
                ),
                child: c == Colors.transparent ? Icon(Icons.block_rounded, size: 15, color: _subColor) : null,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        Text('Border Color', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _subColor)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          children: palette.map((c) {
            final sel = layer.shapeStrokeColor.value == c.value;
            return GestureDetector(
              onTap: () {
                setState(() {
                  layer.shapeStrokeColor = c;
                  if (c == Colors.transparent) {
                    layer.shapeStrokeWidth = 0;
                  } else if (layer.shapeStrokeWidth <= 0) {
                    layer.shapeStrokeWidth = 3;
                  }
                });
                _scheduleAutosave();
              },
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: c == Colors.transparent ? _chipBg : c,
                  shape: BoxShape.circle,
                  border: Border.all(color: sel ? _amber : _borderColor, width: sel ? 3 : 1.2),
                ),
                child: c == Colors.transparent ? Icon(Icons.block_rounded, size: 15, color: _subColor) : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSelectedLayerActionBar(DesignLayer layer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _inputBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              layer.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _textColor),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: _duplicateSelectedLayer,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: _chipBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _borderColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy_rounded, size: 13.5, color: _textColor),
                  const SizedBox(width: 4),
                  Text('Duplicate', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _textColor)),
                ],
              ),
            ),
          ),
          if (!layer.isCanvasBackground) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: _deleteSelectedLayer,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.32)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_outline_rounded, size: 13.5, color: Colors.redAccent),
                    SizedBox(width: 4),
                    Text('Delete', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.redAccent)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
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
          color: selected ? _amberTintBg : _chipBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? _amberTintBorder : _borderColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? _accentText : _textColor,
          ),
        ),
      ),
    );
  }

  Widget _canvasAlignBtn(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _borderColor),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: _accentText),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _textColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textAlignBtn(IconData icon, String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? _amberTintBg : _inputBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? _amberTintBorder : _borderColor),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: selected ? _accentText : _subColor),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? _accentText : _textColor,
                ),
              ),
            ),
          ],
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
              _scheduleAutosave();
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
              _scheduleAutosave();
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
              style: FilledButton.styleFrom(backgroundColor: _inkPrimary, foregroundColor: _onInkPrimary),
              onPressed: () => _enterStudio(),
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
                    final presets = _availableTextFontOptions()
                        .map((f) => (f.$1, f.$2, f.$1 == 'IBMPlexSansArabicSemiBold' ? 600 : 400, f.$4))
                        .toList();
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
                          onChanged: (val) {
                            setState(() {
                              l.text = val;
                              if (_selectedLayerId == l.id) _textController.text = val;
                            });
                            _scheduleAutosave();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final filterTags = <String>[
              if (l.filters.guilloche) 'Guilloche Blend (${l.filters.guillochePattern})',
              if (l.filters.removeWhite > 0) 'White BG Removed (${l.filters.removeWhite.round()}%)',
            ];
            Widget? thumb;
            if (l.filters.guilloche && l.processedGuillocheBytes != null) {
              thumb = Image.memory(l.processedGuillocheBytes!, fit: BoxFit.contain);
            } else if (l.processedWhiteRemovedBytes != null) {
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
                                  style: FilledButton.styleFrom(backgroundColor: _inkPrimary, foregroundColor: _onInkPrimary),
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
                text: 'QALAMIX ENTERPRISES\nLegal & Design Consultancy',
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
        });
        _enterStudio();
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
                backgroundColor: _inkPrimary,
                foregroundColor: _onInkPrimary,
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
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _scannerTealBorder, width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _scannerTealBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _scannerTealBorder),
                ),
                child: Icon(Icons.document_scanner_rounded, color: _scannerTeal, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Document Scanner',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _textColor),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Scan or upload pages · Live Preview · PDF / JPEG',
                      style: TextStyle(fontSize: 11.5, color: _subColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _scannerTeal,
                  foregroundColor: _isDark ? const Color(0xFF0A0C0F) : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                ),
                onPressed: _openDocumentScannerSheet,
                child: const Text('Scan', style: TextStyle(fontWeight: FontWeight.w800)),
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
              style: FilledButton.styleFrom(backgroundColor: _inkPrimary, foregroundColor: _onInkPrimary),
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
                });
                _enterStudio(snapshotCurrent: false);
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
              onTap: () {
                setState(() {
                  _pageIndex = i;
                  _selectedLayerId = null;
                });
                _enterStudio();
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: active ? _brandNib : _borderColor, width: active ? 1.5 : 1),
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
                                    color: _brandNib.withOpacity(0.15),
                                    border: Border.all(color: _brandNib.withOpacity(0.45)),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('ACTIVE', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: _brandNibInk)),
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
        Text('Process multiple photos, preview results, then download or share', style: TextStyle(fontSize: 12, color: _subColor)),
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
                    if (imgs.isNotEmpty) {
                      setState(() {
                        _batchInputs = imgs.map((e) => e.path).toList();
                        _batchOutputs = [];
                      });
                    }
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
                  title: const Text('Black & White Effect', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text('Crisp monochrome contrast', style: TextStyle(fontSize: 11.5, color: _subColor)),
                  activeColor: _amber,
                  value: _batchBw,
                  onChanged: (v) => setState(() {
                    _batchBw = v;
                    if (v) _batchGuilloche = false;
                  }),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Guilloche Blend (Security Portrait)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text('Grayscale + contour bend + banknote texture + cream tint', style: TextStyle(fontSize: 11.5, color: _subColor)),
                  activeColor: _amber,
                  value: _batchGuilloche,
                  onChanged: (v) => setState(() {
                    _batchGuilloche = v;
                    if (v) _batchBw = false;
                  }),
                ),
                if (_batchGuilloche) ...[
                  Row(
                    children: [
                      ('banknote', 'Banknote'),
                      ('rosette', 'Rosette'),
                      ('mesh', 'Mesh'),
                    ].map((pat) {
                      final sel = _batchGuillochePattern == pat.$1;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: _choicePill(
                            label: pat.$2,
                            selected: sel,
                            onTap: () => setState(() => _batchGuillochePattern = pat.$1),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 6),
                ],
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
              backgroundColor: _inkPrimary,
              foregroundColor: _onInkPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _batchInputs.isEmpty || _batchProcessing
                ? null
                : () async {
                    setState(() => _batchProcessing = true);
                    try {
                      await _runWithSavingHud(
                        savingTitle: 'Creating Previews...',
                        savingSubtitle: '${_batchInputs.length} image(s)',
                        savedTitle: 'Previews Ready',
                        savedSubtitle: 'Tap any image to inspect or download',
                        action: () async {
                          final dir = await getTemporaryDirectory();
                          final out = await runBatchOffline(BatchJobRequest(
                            inputPaths: _batchInputs,
                            outputDir: dir.path,
                            brightness: _batchBw ? 1.03 : 1.0,
                            contrast: _batchBw ? 1.22 : 1.0,
                            blackAndWhite: _batchBw,
                            guilloche: _batchGuilloche,
                            guillochePattern: _batchGuillochePattern,
                            removeWhiteTolerance: _batchRemoveWhite,
                          ));
                          if (mounted) {
                            setState(() => _batchOutputs = out);
                          }
                        },
                      );
                    } finally {
                      if (mounted) setState(() => _batchProcessing = false);
                    }
                  },
            icon: Icon(_batchProcessing ? Icons.hourglass_top_rounded : Icons.visibility_rounded, size: 18),
            label: Text(
              _batchProcessing ? 'Building Previews...' : 'Process & Preview',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (_batchOutputs.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Processed Previews (${_batchOutputs.length})',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  await _runWithSavingHud(
                    savingTitle: 'Downloading All...',
                    savingSubtitle: '${_batchOutputs.length} image(s)',
                    savedTitle: 'Saved to Gallery',
                    savedSubtitle: '${_batchOutputs.length} image(s) downloaded',
                    action: () async {
                      for (final fp in _batchOutputs) {
                        await _saveBytesToDeviceGallery(await File(fp).readAsBytes(), p.basename(fp));
                      }
                    },
                  );
                },
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Download All', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: 'Share All',
                icon: Icon(Icons.share_rounded, color: _accentText),
                onPressed: () async {
                  await Share.shareXFiles(
                    _batchOutputs.map((fp) => XFile(fp)).toList(),
                    text: 'Qalamix Batch (${_batchOutputs.length})',
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.78,
            ),
            itemCount: _batchOutputs.length,
            itemBuilder: (ctx, idx) {
              final fp = _batchOutputs[idx];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          showDialog<void>(
                            context: context,
                            builder: (dCtx) => Dialog(
                              backgroundColor: _panelBg,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            p.basename(fp),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.close_rounded),
                                          onPressed: () => Navigator.pop(dCtx),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxHeight: 380),
                                    child: Image.file(File(fp), fit: BoxFit.contain),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: FilledButton.icon(
                                            style: FilledButton.styleFrom(
                                              backgroundColor: _inkPrimary,
                                              foregroundColor: _onInkPrimary,
                                            ),
                                            onPressed: () async {
                                              Navigator.pop(dCtx);
                                              await _runWithSavingHud(
                                                savingTitle: 'Downloading...',
                                                savedTitle: 'Saved to Gallery',
                                                action: () async {
                                                  await _saveBytesToDeviceGallery(
                                                    await File(fp).readAsBytes(),
                                                    p.basename(fp),
                                                  );
                                                },
                                              );
                                            },
                                            icon: const Icon(Icons.download_rounded, size: 17),
                                            label: const Text('Download', style: TextStyle(fontWeight: FontWeight.w700)),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.share_rounded),
                                          onPressed: () => Share.shareXFiles([XFile(fp)]),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        child: Image.file(File(fp), fit: BoxFit.cover),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.basename(fp),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Download',
                            icon: const Icon(Icons.download_rounded, size: 18),
                            onPressed: () async {
                              await _runWithSavingHud(
                                savingTitle: 'Downloading...',
                                savedTitle: 'Saved to Gallery',
                                action: () async {
                                  await _saveBytesToDeviceGallery(
                                    await File(fp).readAsBytes(),
                                    p.basename(fp),
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
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
          'format': 'qalamix_project_v1',
          'exportedAt': DateTime.now().millisecondsSinceEpoch,
          'project': jsonDecode(proj.encode()),
          'embeddedImages': embedded,
        };
        final safeName = proj.name
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
            .replaceAll(RegExp(r'^-|-$'), '');
        final fileName = '${safeName.isEmpty ? "qalamix-project" : safeName}.qalamix.json';
        final tmpDir = await getTemporaryDirectory();
        final outPath = p.join(tmpDir.path, fileName);
        await File(outPath).writeAsString(jsonEncode(bundle));
        await Share.shareXFiles(
          [XFile(outPath)],
          subject: 'Qalamix Project: ${proj.name}',
          text: 'Qalamix Project (${proj.pages.length} page(s))',
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
      final imgDir = Directory(p.join(docsDir.path, 'qalamix_images'));
      if (!imgDir.existsSync()) imgDir.createSync(recursive: true);
      final dest = p.join(imgDir.path, '${prefix}_${DateTime.now().microsecondsSinceEpoch}$ext');
      await File(dest).writeAsBytes(bytes);
      return dest;
    } catch (_) {
      return null;
    }
  }



  String _blendLabel(BlendMode b) {
    switch (b) {
      case BlendMode.srcOver:
        return 'Normal';
      case BlendMode.multiply:
        return 'Multiply';
      case BlendMode.screen:
        return 'Screen';
      case BlendMode.overlay:
        return 'Overlay';
      case BlendMode.softLight:
        return 'Soft Light';
      case BlendMode.hardLight:
        return 'Hard Light';
      case BlendMode.darken:
        return 'Darken';
      case BlendMode.lighten:
        return 'Lighten';
      case BlendMode.colorDodge:
        return 'Color Dodge';
      case BlendMode.colorBurn:
        return 'Color Burn';
      case BlendMode.difference:
        return 'Difference';
      case BlendMode.exclusion:
        return 'Exclusion';
      default:
        return b.name;
    }
  }

  Future<void> _importProjectFile() async {
    try {
      String? raw;
      if (Platform.isAndroid) {
        raw = await _mediaChannel.invokeMethod<String>('pickProjectFile');
      }
      if (raw == null || raw.trim().isEmpty) return;

      final imported = await parseImportedProjectBundle(
        raw,
        writeImage: _writeBase64ToLocalImage,
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
          });
          await _rehydrateProjectFilters(imported);
          if (mounted) _enterStudio();
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not import project file: $e')),
      );
    }
  }

  static final List<_PhotoEffectSpec> _photoEffectSpecs = [
    _PhotoEffectSpec(
      id: 'vivid-pinkhaze-silk',
      name: 'Vivid Tone & PinkHaze Warm Silk',
      subtitle: 'Boosts color depth, warmth, and soft lighting.',
      assetPath: 'assets/images/scenic_botanical_sample.jpg',
      filters: FilterSettings(
        brightness: 1.06,
        contrast: 1.14,
        saturate: 1.38,
        sepia: 0.12,
        softGlow: 36,
        rosyTint: 50,
        skinSmooth: 18,
      ),
    ),
    _PhotoEffectSpec(
      id: 'rosy-haze-freckles',
      name: 'Rosy Haze & Freckles Out',
      subtitle: 'Soft rosy tint paired with natural skin clarity.',
      assetPath: 'assets/images/portrait_male_sample.jpg',
      filters: FilterSettings(
        brightness: 1.08,
        contrast: 1.02,
        saturate: 1.14,
        sepia: 0.06,
        softGlow: 30,
        rosyTint: 66,
        skinSmooth: 64,
      ),
    ),
    _PhotoEffectSpec(
      id: 'glow-makeup',
      name: 'Glow Effect with Makeup',
      subtitle: 'Radiant skin smoothing with light styling glow.',
      assetPath: 'assets/images/portrait_male_sample.jpg',
      filters: FilterSettings(
        brightness: 1.09,
        contrast: 1.11,
        saturate: 1.24,
        sepia: 0.06,
        softGlow: 68,
        rosyTint: 40,
        skinSmooth: 56,
      ),
    ),
    _PhotoEffectSpec(
      id: 'portrait-blur-v3',
      name: 'Portrait Blur V3',
      subtitle: 'Softens backgrounds while keeping portraits sharp.',
      assetPath: 'assets/images/portrait_male_sample.jpg',
      filters: FilterSettings(
        brightness: 1.04,
        contrast: 1.12,
        saturate: 1.14,
        sepia: 0.04,
        softGlow: 18,
        rosyTint: 12,
        skinSmooth: 14,
        portraitBlur: 78,
      ),
    ),
    _PhotoEffectSpec(
      id: 'golden-hour-silk',
      name: 'Golden Hour Silk',
      subtitle: 'Sunlit amber highlights & soft nature depth.',
      assetPath: 'assets/images/scenic_botanical_sample.jpg',
      filters: FilterSettings(
        brightness: 1.07,
        contrast: 1.11,
        saturate: 1.26,
        sepia: 0.24,
        softGlow: 42,
        portraitBlur: 26,
      ),
    ),
    _PhotoEffectSpec(
      id: 'soft-peach-cream',
      name: 'Soft Peach Cream',
      subtitle: 'Airy pastel tones with gentle silk softness.',
      assetPath: 'assets/images/scenic_botanical_sample.jpg',
      filters: FilterSettings(
        brightness: 1.10,
        contrast: 0.98,
        saturate: 1.12,
        sepia: 0.14,
        softGlow: 38,
        rosyTint: 34,
        skinSmooth: 48,
      ),
    ),
    _PhotoEffectSpec(
      id: 'editorial-teal-amber',
      name: 'Editorial Teal & Amber',
      subtitle: 'Rich botanical contrast with balanced warm tones.',
      assetPath: 'assets/images/scenic_botanical_sample.jpg',
      filters: FilterSettings(
        brightness: 1.01,
        contrast: 1.20,
        saturate: 1.18,
        sepia: 0.14,
        portraitBlur: 24,
      ),
    ),
    _PhotoEffectSpec(
      id: 'velvet-studio-noir',
      name: 'Velvet Studio Noir',
      subtitle: 'Crisp high-contrast monochrome portrait bokeh.',
      assetPath: 'assets/images/portrait_male_sample.jpg',
      filters: FilterSettings(
        brightness: 1.05,
        contrast: 1.32,
        saturate: 0.0,
        blackAndWhite: true,
        grayscale: 1.0,
        portraitBlur: 36,
      ),
    ),
  ];

  Future<void> _pickCustomPreviewPhotoForEffects() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 92);
    if (picked == null || !mounted) return;
    setState(() => _customEffectPreviewPath = picked.path);
  }

  Future<void> _openProjectWithPhotoEffect(_PhotoEffectSpec spec) async {
    await _runWithSavingHud(
      savingTitle: 'Applying ${spec.name}...',
      savedTitle: 'Studio Ready',
      savedSubtitle: spec.name,
      action: () async {
        final docsDir = await getApplicationDocumentsDirectory();
        final assetsDir = Directory(p.join(docsDir.path, 'qalamix_assets'));
        if (!assetsDir.existsSync()) assetsDir.createSync(recursive: true);

        late final String targetPath;
        if (_customEffectPreviewPath != null && File(_customEffectPreviewPath!).existsSync()) {
          final ext = p.extension(_customEffectPreviewPath!).isEmpty
              ? '.jpg'
              : p.extension(_customEffectPreviewPath!);
          targetPath = p.join(assetsDir.path, 'fx_${DateTime.now().microsecondsSinceEpoch}$ext');
          await File(_customEffectPreviewPath!).copy(targetPath);
        } else {
          final data = await rootBundle.load(spec.assetPath);
          final bytes = data.buffer.asUint8List();
          targetPath = p.join(assetsDir.path, 'fx_${spec.id}_${DateTime.now().microsecondsSinceEpoch}.jpg');
          await File(targetPath).writeAsBytes(bytes);
        }

        final now = DateTime.now().millisecondsSinceEpoch;
        final layerId = 'img_${DateTime.now().microsecondsSinceEpoch}';
        final fresh = DesignProject(
          id: 'proj_fx_$now',
          name: spec.name,
          updatedAt: now,
          pages: [
            DocumentPage(
              id: 'page_1',
              title: 'Photo 1',
              width: 900,
              height: 1200,
              backgroundColor: const Color(0xFF111317),
              layers: [
                DesignLayer(
                  id: layerId,
                  name: 'Photo Layer',
                  type: LayerType.image,
                  x: 0,
                  y: 0,
                  width: 900,
                  height: 1200,
                  isCanvasBackground: true,
                  aspectLocked: false,
                  objectFit: BoxFit.cover,
                  localImagePath: targetPath,
                  filters: spec.filters.copy(),
                ),
              ],
            ),
          ],
        );

        await LocalProjectStore.instance.saveProject(fresh);
        final list = await LocalProjectStore.instance.loadAllProjects();
        if (!mounted) return;
        setState(() {
          _projects = list;
          _project = fresh;
          _pageIndex = 0;
          _selectedLayerId = layerId;
          _inspectorTab = 2;
          _sheetExpanded = true;
          _sheetTall = false;
          _undoStack.clear();
          _redoStack.clear();
          _studioEntrySnapshot = (0, fresh.encode());
          _inStudio = true;
        });
      },
    );
  }

  Widget _buildProjectsPhotoEffectsSection() {
    final hasCustom = _customEffectPreviewPath != null && File(_customEffectPreviewPath!).existsSync();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome_rounded, size: 17, color: _brandNib),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'Photo & Portrait Effects',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
              ),
            ),
            if (hasCustom)
              TextButton(
                onPressed: () => setState(() => _customEffectPreviewPath = null),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text('Samples', style: TextStyle(fontSize: 12, color: _subColor)),
              ),
            OutlinedButton.icon(
              onPressed: _pickCustomPreviewPhotoForEffects,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _borderColor),
                foregroundColor: _textColor,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: const Size(0, 32),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
              ),
              icon: Icon(Icons.photo_camera_outlined, size: 14, color: _brandNib),
              label: Text(
                hasCustom ? 'Change Photo' : 'My Photo',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          'Tap any effect card to open Studio with that look ready to adjust & export.',
          style: TextStyle(fontSize: 11.5, color: _subColor),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _photoEffectSpecs.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.75,
          ),
          itemBuilder: (context, idx) {
            final spec = _photoEffectSpecs[idx];
            return InkWell(
              onTap: () => _openProjectWithPhotoEffect(spec),
              borderRadius: BorderRadius.circular(14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    buildOpticalFilteredImageWidget(
                      filters: spec.filters,
                      childBuilder: () => hasCustom
                          ? Image.file(
                              File(_customEffectPreviewPath!),
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            )
                          : Image.asset(
                              spec.assetPath,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: _borderColor.withOpacity(0.5)),
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.28),
                            Colors.black.withOpacity(0.88),
                          ],
                          stops: const [0.42, 0.68, 1.0],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            spec.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            spec.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.82),
                              fontSize: 10,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildProjectsView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Offline Projects', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      Text('${_projects.length} saved locally · Tap a project to edit in Studio', style: TextStyle(fontSize: 12, color: _subColor)),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _borderColor),
                    foregroundColor: _textColor,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _enterStudio(),
                  icon: const Icon(Icons.brush_outlined, size: 16),
                  label: const Text('Open Studio', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _inkPrimary,
                      foregroundColor: _onInkPrimary,
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
                            _studioEntrySnapshot = (0, fresh.encode());
                            _inStudio = true;
                          });
                        },
                      );
                    },
                    icon: Icon(Icons.add_rounded, size: 18, color: _brandNibOnInk),
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
                    label: const Text('Import .qalamix', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          'Saved Projects (${_projects.length})',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _textColor),
        ),
        const SizedBox(height: 10),
        ..._projects.map((proj) {
          final isCurrent = proj.id == _project.id;
          final thumbBytes = _projectThumbCache[proj.id];
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
                  _studioEntrySnapshot = (0, proj.encode());
                  _inStudio = true;
                  _sheetExpanded = false;
                  _sheetTall = false;
                });
                await _rehydrateProjectFilters(proj);
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isCurrent ? _brandNib : _borderColor,
                    width: isCurrent ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 58,
                          decoration: BoxDecoration(
                            color: _amberTintBg,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: isCurrent ? _brandNib : _amberTintBorder,
                              width: isCurrent ? 1.5 : 1,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: thumbBytes != null
                              ? Image.memory(
                                  thumbBytes,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                )
                              : Icon(
                                  isCurrent ? Icons.layers_rounded : Icons.folder_open_rounded,
                                  color: _accentText,
                                  size: 22,
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                proj.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _textColor),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  if (isCurrent) ...[
                                    Container(
                                      width: 6,
                                      height: 6,
                                      margin: const EdgeInsets.only(right: 5),
                                      decoration: BoxDecoration(color: _brandNibInk, shape: BoxShape.circle),
                                    ),
                                    Text(
                                      'Active · ',
                                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _brandNibInk),
                                    ),
                                  ],
                                  Flexible(
                                    child: Text(
                                      '${proj.pages.length} ${proj.pages.length == 1 ? 'page' : 'pages'} · Offline',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 11.5, color: _subColor),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatUpdatedTime(proj.updatedAt),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: _mutedColor),
                              ),
                            ],
                          ),
                        ),
                        _compactLayerIcon(Icons.edit_outlined, 'Rename Project', () => _renameProjectDialog(proj)),
                        _compactLayerIcon(
                          Icons.delete_outline_rounded,
                          'Delete Project',
                          () => _confirmDeleteProject(proj),
                          color: Colors.redAccent,
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),
                    Divider(height: 1, thickness: 1, color: _borderColor),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              setState(() {
                                _project = proj;
                                _pageIndex = 0;
                                _selectedLayerId = null;
                                _undoStack.clear();
                                _redoStack.clear();
                                _studioEntrySnapshot = (0, proj.encode());
                                _inStudio = true;
                                _sheetExpanded = false;
                                _sheetTall = false;
                              });
                              await _rehydrateProjectFilters(proj);
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              height: 36,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: _inkPrimary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.brush_outlined, size: 15, color: _brandNibOnInk),
                                  const SizedBox(width: 6),
                                  Text(
                                    isCurrent ? 'Open Studio' : 'Open',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _onInkPrimary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => _shareProjectFile(proj),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: _shareSkyBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _shareSkyBorder),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.share_outlined, size: 15, color: _shareSky),
                                const SizedBox(width: 5),
                                Text(
                                  'Share',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _shareSky),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () async {
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
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: _chipBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _borderColor),
                            ),
                            child: Icon(Icons.copy_rounded, size: 15, color: _subColor),
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
        const SizedBox(height: 18),
        _buildProjectsPhotoEffectsSection(),
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

  Widget _buildSignaturePenSelector({VoidCallback? onChanged}) {
    const pens = [
      ('fountain', 'Fountain Nib'),
      ('brush', 'Brush Pen'),
      ('calligraphy', 'Chisel 45°'),
      ('ballpoint', 'Ballpoint'),
      ('fineliner', 'Fine Liner'),
      ('marker', 'Soft Marker'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ...pens.map((p) {
                final selected = _sigPenType == p.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(p.$2, style: TextStyle(fontSize: 11.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w600)),
                    selected: selected,
                    selectedColor: _amberTintBg,
                    backgroundColor: _chipBg,
                    checkmarkColor: _accentText,
                    side: BorderSide(color: selected ? _amberTintBorder : _borderColor),
                    labelStyle: TextStyle(color: selected ? _accentText : _textColor),
                    onSelected: (_) {
                      setState(() => _sigPenType = p.$1);
                      onChanged?.call();
                    },
                  ),
                );
              }),
              ChoiceChip(
                label: Text(
                  _sigAutoSmooth ? 'Auto Smooth: On' : 'Auto Smooth: Off',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
                selected: _sigAutoSmooth,
                selectedColor: _amberTintBg,
                backgroundColor: _chipBg,
                checkmarkColor: _accentText,
                side: BorderSide(color: _sigAutoSmooth ? _amberTintBorder : _borderColor),
                labelStyle: TextStyle(color: _sigAutoSmooth ? _accentText : _subColor),
                onSelected: (_) {
                  setState(() => _sigAutoSmooth = !_sigAutoSmooth);
                  onChanged?.call();
                },
              ),
            ],
          ),
        ),
      ],
    );
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
                backgroundColor: _isDark ? const Color(0xFF12141A) : const Color(0xFFF6F4EF),
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
                          backgroundColor: _inkPrimary,
                          foregroundColor: _onInkPrimary,
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
                                          _sigCurrentStroke = [_SigPoint(pt, DateTime.now().millisecondsSinceEpoch)];
                                          _sigRedoStrokes.clear();
                                          _sigStrokes.add(_SigStroke(
                                            points: _sigCurrentStroke!,
                                            color: _sigInkColor,
                                            width: _sigPenWidth,
                                            penType: _sigPenType,
                                          ));
                                          setModalState(() {});
                                          setState(() {});
                                        },
                                        onPanUpdate: (d) {
                                          if (_sigCurrentStroke == null) return;
                                          final pt = _toCanonicalPadPoint(d.localPosition, padSize);
                                          final prev = _sigCurrentStroke!.last.pos;
                                          if ((pt - prev).distance < 2.0) return;
                                          _sigCurrentStroke!.add(_SigPoint(pt, DateTime.now().millisecondsSinceEpoch));
                                          setModalState(() {});
                                          setState(() {});
                                        },
                                        onPanEnd: (_) {
                                          if (_sigAutoSmooth && _sigStrokes.isNotEmpty) {
                                            final last = _sigStrokes.last;
                                            last.points = _smoothSigPoints(last.points);
                                            setModalState(() {});
                                            setState(() {});
                                          }
                                          _sigCurrentStroke = null;
                                        },
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
                            _buildSignaturePenSelector(onChanged: () => setModalState(() {})),
                            const SizedBox(height: 8),
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
        for (final pt in s.points) {
          if (pt.pos.dx < minX) minX = pt.pos.dx;
          if (pt.pos.dy < minY) minY = pt.pos.dy;
          if (pt.pos.dx > maxX) maxX = pt.pos.dx;
          if (pt.pos.dy > maxY) maxY = pt.pos.dy;
        }
      }
      final bw = math.max(20.0, maxX - minX);
      final bh = math.max(20.0, maxY - minY);
      const pad = 44.0;
      final scale = math.min((w - pad * 2) / bw, (h - pad * 2) / bh);
      final offX = (w - bw * scale) / 2.0 - minX * scale;
      final offY = (h - bh * scale) / 2.0 - minY * scale;

      _paintSignatureStrokeList(
        canvas,
        _sigStrokes,
        scale: scale,
        offsetX: offX,
        offsetY: offY,
        widthMultiplier: math.min(2.6, math.max(1.2, scale * 0.85)),
      );
    }
    final uiImg = await recorder.endRecording().toImage(w.toInt(), h.toInt());
    final byteData = await uiImg.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _reprocessScannedSignature() async {
    final rawPath = _sigScanRawPath;
    if (rawPath == null) return;
    if (mounted) setState(() => _sigScanProcessing = true);
    try {
      final png = await extractScannedSignatureOffline(
        ScanSignatureRequest(
          filePath: rawPath,
          sensitivity: _sigScanSensitivity,
          recolorArgb: _sigScanRecolor?.value,
          autoTrim: _sigScanAutoTrim,
          transparentBg: _sigTransparentBg,
        ),
      );
      if (mounted && _sigScanRawPath == rawPath) {
        setState(() => _sigScanProcessedBytes = png);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not clean scanned signature: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sigScanProcessing = false);
    }
  }

  Future<void> _scanSignatureWithDocScanner() async {
    DocumentScanner? scanner;
    try {
      final options = DocumentScannerOptions(
        documentFormat: DocumentFormat.jpeg,
        mode: ScannerMode.full,
        pageLimit: 1,
        isGalleryImport: true,
      );
      scanner = DocumentScanner(options: options);
      final result = await scanner.scanDocument();
      if (result.images.isNotEmpty) {
        setState(() {
          _sigScanRawPath = result.images.first;
          _sigScanShowOriginal = false;
        });
        await _reprocessScannedSignature();
      }
    } on PlatformException catch (e) {
      final msg = e.message ?? '';
      if (!msg.toLowerCase().contains('cancel') && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scanner: ${msg.isEmpty ? e.code : msg}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scanner unavailable: $e')),
        );
      }
    } finally {
      try {
        await scanner?.close();
      } catch (_) {}
    }
  }

  Future<void> _pickScannedSignatureImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 95);
      if (picked == null) return;
      setState(() {
        _sigScanRawPath = picked.path;
        _sigScanShowOriginal = false;
      });
      await _reprocessScannedSignature();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image picker error: $e')),
        );
      }
    }
  }

  Future<void> _addSignatureToProjectCanvas() async {
    if (_sigMode == 1 && _sigStrokes.isEmpty) return;
    if (_sigMode == 2 && _sigScanRawPath == null) return;
    await _runWithSavingHud(
      savingTitle: _sigMode == 2 ? 'Placing Scanned Signature...' : 'Saving Signature...',
      savedTitle: 'Signature Added',
      savedSubtitle: 'Placed on Studio Canvas',
      action: () async {
        Uint8List? bytes;
        if (_sigMode == 2 && _sigScanRawPath != null) {
          bytes = await extractScannedSignatureOffline(
            ScanSignatureRequest(
              filePath: _sigScanRawPath!,
              sensitivity: _sigScanSensitivity,
              recolorArgb: _sigScanRecolor?.value,
              autoTrim: _sigScanAutoTrim,
              transparentBg: true,
            ),
          );
        } else {
          bytes = await _renderSignaturePngBytes(forceTransparent: true);
        }
        if (bytes == null) throw Exception('Signature render failed');
        final docsDir = await getApplicationDocumentsDirectory();
        final assetsDir = Directory(p.join(docsDir.path, 'qalamix_assets'));
        if (!assetsDir.existsSync()) assetsDir.createSync(recursive: true);
        final filePath = p.join(assetsDir.path, 'sig_${DateTime.now().microsecondsSinceEpoch}.png');
        await File(filePath).writeAsBytes(bytes);

        double targetW = _page.width * 0.55;
        double targetH = targetW * (420.0 / 1100.0);
        if (_sigMode == 2) {
          final decoded = img.decodeImage(bytes);
          if (decoded != null && decoded.width > 0 && decoded.height > 0) {
            final aspect = decoded.width / decoded.height;
            targetW = _page.width * 0.52;
            targetH = targetW / aspect;
            if (targetH > _page.height * 0.36) {
              targetH = _page.height * 0.36;
              targetW = targetH * aspect;
            }
          }
        }

        final sigLabel = _sigTextController.text.trim();
        final layer = DesignLayer(
          id: 'sig_${DateTime.now().microsecondsSinceEpoch}',
          name: _sigMode == 0
              ? 'Sign: ${sigLabel.isEmpty ? 'Signature' : sigLabel}'
              : _sigMode == 2
                  ? 'Scanned Signature'
                  : 'Drawn Signature',
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
            _sheetExpanded = true;
            _sheetTall = false;
            _inStudio = true;
          });
        }
        await _saveCurrentProject(showToast: false);
      },
    );
  }

  Future<void> _exportSignaturePng({required bool shareOnly}) async {
    if (_sigMode == 1 && _sigStrokes.isEmpty) return;
    if (_sigMode == 2 && _sigScanRawPath == null) return;
    await _runWithSavingHud(
      savingTitle: shareOnly ? 'Preparing Signature...' : 'Saving Signature PNG...',
      savedTitle: shareOnly ? 'Ready to Share' : 'Signature Saved',
      savedSubtitle: shareOnly ? 'PNG ready' : 'Saved to Gallery',
      action: () async {
        final bytes = _sigMode == 2 && _sigScanRawPath != null
            ? await extractScannedSignatureOffline(
                ScanSignatureRequest(
                  filePath: _sigScanRawPath!,
                  sensitivity: _sigScanSensitivity,
                  recolorArgb: _sigScanRecolor?.value,
                  autoTrim: _sigScanAutoTrim,
                  transparentBg: _sigTransparentBg,
                ),
              )
            : await _renderSignaturePngBytes();
        if (bytes == null) throw Exception('Signature render failed');
        final fileName = 'qalamix_signature_${DateTime.now().millisecondsSinceEpoch}.png';
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
    final assetsDir = Directory(p.join(docsDir.path, 'qalamix_assets'));
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
      _sheetExpanded = true;
      _sheetTall = false;
      _inStudio = true;
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
        final fileName = 'qalamix_stamp_${DateTime.now().millisecondsSinceEpoch}.png';
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

    Widget sigTabBtn(int idx, IconData icon, String label) {
      final sel = _sigMode == idx;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _sigMode = idx),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            decoration: BoxDecoration(
              color: sel ? _amberTintBg : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: sel ? Border.all(color: _amberTintBorder) : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: sel ? _accentText : _subColor,
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w600,
                      color: sel ? _accentText : _textColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _borderColor),
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
                      color: _amberTintBg,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: _amberTintBorder),
                    ),
                    child: Icon(
                      _sigMode == 3
                          ? Icons.verified_outlined
                          : _sigMode == 2
                              ? Icons.document_scanner_rounded
                              : Icons.draw_rounded,
                      color: _accentText,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sign & Official Seal Studio',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _textColor),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Type Fonts · Smooth Draw · Scan Sign · Stamp / مہر',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: _subColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _chipBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _borderColor),
                ),
                child: Row(
                  children: [
                    sigTabBtn(0, Icons.title_rounded, '18 Fonts'),
                    sigTabBtn(1, Icons.draw_rounded, 'Draw'),
                    sigTabBtn(2, Icons.document_scanner_rounded, 'Scan Sign'),
                    sigTabBtn(3, Icons.verified_outlined, 'Stamp'),
                  ],
                ),
              ),
            ],
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
                    onChanged: (_) {
                      setState(() {});
                      _scheduleSignSealAutosave();
                    },
                    decoration: const InputDecoration(
                      labelText: 'Enter Signature Name (English / Urdu)',
                      hintText: 'Your Name / دستخط',
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
                            onTap: () {
                              setState(() => _sigInkColor = c);
                              _scheduleSignSealAutosave();
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
                    ],
                  ),
                  const SizedBox(height: 4),
                  _sliderRow(
                    'Size',
                    _sigFontSize,
                    42,
                    130,
                    (v) => setState(() => _sigFontSize = v),
                    onChangeEnd: (_) => _scheduleSignSealAutosave(),
                  ),
                  _sliderRow(
                    'Spacing',
                    _sigLetterSpacing,
                    -4,
                    12,
                    (v) => setState(() => _sigLetterSpacing = v),
                    onChangeEnd: (_) => _scheduleSignSealAutosave(),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _choicePill(
                        label: 'Slant',
                        selected: _sigSlanted,
                        onTap: () {
                          setState(() => _sigSlanted = !_sigSlanted);
                          _scheduleSignSealAutosave();
                        },
                      ),
                      _choicePill(
                        label: 'Bold Ink',
                        selected: _sigBold,
                        onTap: () {
                          setState(() => _sigBold = !_sigBold);
                          _scheduleSignSealAutosave();
                        },
                      ),
                      _choicePill(
                        label: _sigTransparentBg ? 'BG: Transparent' : 'BG: White Paper',
                        selected: _sigTransparentBg,
                        onTap: () {
                          setState(() => _sigTransparentBg = !_sigTransparentBg);
                          _scheduleSignSealAutosave();
                        },
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
                  const SizedBox(height: 8),
                  _buildSignaturePenSelector(onChanged: _scheduleSignSealAutosave),
                  _sliderRow(
                    'Pen Size',
                    _sigPenWidth,
                    2,
                    14,
                    (v) => setState(() => _sigPenWidth = v),
                    onChangeEnd: (_) => _scheduleSignSealAutosave(),
                  ),
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
                              Positioned(
                                left: 22,
                                right: 22,
                                bottom: 42,
                                child: IgnorePointer(
                                  child: Container(
                                    height: 1,
                                    color: const Color(0xFF94A3B8).withOpacity(0.45),
                                  ),
                                ),
                              ),
                              if (_sigStrokes.isEmpty)
                                const Center(
                                  child: Text(
                                    'Sign above the line or open Big Pad',
                                    style: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                                  ),
                                ),
                              GestureDetector(
                                onPanStart: (d) => setState(() {
                                  if (_sigStrokes.isEmpty) _sigCanvasSize = padSize;
                                  final pt = _toCanonicalPadPoint(d.localPosition, padSize);
                                  _sigCurrentStroke = [_SigPoint(pt, DateTime.now().millisecondsSinceEpoch)];
                                  _sigRedoStrokes.clear();
                                  _sigStrokes.add(_SigStroke(
                                    points: _sigCurrentStroke!,
                                    color: _sigInkColor,
                                    width: _sigPenWidth,
                                    penType: _sigPenType,
                                  ));
                                }),
                                onPanUpdate: (d) {
                                  if (_sigCurrentStroke == null) return;
                                  final pt = _toCanonicalPadPoint(d.localPosition, padSize);
                                  final prev = _sigCurrentStroke!.last.pos;
                                  if ((pt - prev).distance < 2.0) return;
                                  setState(() => _sigCurrentStroke!.add(_SigPoint(pt, DateTime.now().millisecondsSinceEpoch)));
                                },
                                onPanEnd: (_) {
                                  if (_sigAutoSmooth && _sigStrokes.isNotEmpty) {
                                    setState(() {
                                      _sigStrokes.last.points = _smoothSigPoints(_sigStrokes.last.points);
                                    });
                                  }
                                  _sigCurrentStroke = null;
                                },
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
                    onTap: () {
                      setState(() => _sigTransparentBg = !_sigTransparentBg);
                      _scheduleSignSealAutosave();
                    },
                  ),
                ],
              ),
            ),
          )
        else if (_sigMode == 2)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Paper Signature Scanner',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _textColor),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Scan your signature from white paper with ML Kit Scanner — shadows & paper background are removed automatically.',
                    style: TextStyle(fontSize: 11.5, color: _subColor),
                  ),
                  const SizedBox(height: 12),
                  if (_sigScanRawPath == null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
                      decoration: BoxDecoration(
                        color: _cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _scannerTealBorder, width: 1.3),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: _scannerTealBg,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(color: _scannerTealBorder),
                            ),
                            child: Icon(Icons.document_scanner_rounded, color: _scannerTeal, size: 26),
                          ),
                          const SizedBox(height: 11),
                          Text(
                            'Scan Handwritten Signature',
                            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: _textColor),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Sign on plain paper, scan cleanly, and export a transparent PNG cutout.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11.5, color: _subColor),
                          ),
                          const SizedBox(height: 15),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: _inkPrimary,
                                foregroundColor: _onInkPrimary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                              ),
                              onPressed: _scanSignatureWithDocScanner,
                              icon: Icon(Icons.document_scanner_outlined, size: 18, color: _brandNibOnInk),
                              label: const Text('Scan with Document Scanner', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ),
                          const SizedBox(height: 9),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: _amberTintBg,
                                    foregroundColor: _brandNibInk,
                                    side: BorderSide(color: _amberTintBorder),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: () => _pickScannedSignatureImage(ImageSource.camera),
                                  icon: Icon(Icons.camera_alt_outlined, size: 16, color: _brandNibInk),
                                  label: const Text('Camera', style: TextStyle(fontWeight: FontWeight.w700)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: _scannerTealBg,
                                    foregroundColor: _scannerTeal,
                                    side: BorderSide(color: _scannerTealBorder),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: () => _pickScannedSignatureImage(ImageSource.gallery),
                                  icon: Icon(Icons.photo_library_outlined, size: 16, color: _scannerTeal),
                                  label: const Text('Gallery', style: TextStyle(fontWeight: FontWeight.w700)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Container(
                      width: double.infinity,
                      height: 195,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _sigScanShowOriginal
                            ? _inputBg
                            : (_sigTransparentBg ? paperPreviewBg : Colors.white),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _borderColor),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: _sigScanShowOriginal
                                ? Image.file(File(_sigScanRawPath!), fit: BoxFit.contain)
                                : (_sigScanProcessedBytes != null
                                    ? Image.memory(
                                        _sigScanProcessedBytes!,
                                        fit: BoxFit.contain,
                                        gaplessPlayback: true,
                                      )
                                    : const SizedBox.shrink()),
                          ),
                          if (_sigScanProcessing)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.75),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: const Text(
                                  'Cleaning...',
                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.white),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _choicePill(
                          label: 'Re-scan',
                          selected: false,
                          onTap: _scanSignatureWithDocScanner,
                        ),
                        _choicePill(
                          label: 'Gallery',
                          selected: false,
                          onTap: () => _pickScannedSignatureImage(ImageSource.gallery),
                        ),
                        _choicePill(
                          label: _sigScanShowOriginal ? 'Showing Original' : 'Compare Original',
                          selected: _sigScanShowOriginal,
                          onTap: () => setState(() => _sigScanShowOriginal = !_sigScanShowOriginal),
                        ),
                        _choicePill(
                          label: 'Clear',
                          selected: false,
                          onTap: () => setState(() {
                            _sigScanRawPath = null;
                            _sigScanProcessedBytes = null;
                            _sigScanShowOriginal = false;
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _sliderRow(
                      'Paper Clean',
                      _sigScanSensitivity,
                      15,
                      92,
                      (v) => setState(() => _sigScanSensitivity = v),
                      onChangeEnd: (_) => _reprocessScannedSignature(),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('Ink:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _subColor)),
                        const SizedBox(width: 8),
                        _choicePill(
                          label: 'Original',
                          selected: _sigScanRecolor == null,
                          onTap: () {
                            setState(() => _sigScanRecolor = null);
                            _reprocessScannedSignature();
                          },
                        ),
                        const SizedBox(width: 8),
                        ...inkSwatches.map(
                          (c) => Padding(
                            padding: const EdgeInsets.only(right: 7),
                            child: GestureDetector(
                              onTap: () {
                                setState(() => _sigScanRecolor = c);
                                _reprocessScannedSignature();
                              },
                              child: Container(
                                width: 25,
                                height: 25,
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _sigScanRecolor == c ? _brandNib : _borderColor,
                                    width: _sigScanRecolor == c ? 2.8 : 1.2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _choicePill(
                          label: _sigScanAutoTrim ? 'Auto-Trim: On' : 'Auto-Trim: Off',
                          selected: _sigScanAutoTrim,
                          onTap: () {
                            setState(() => _sigScanAutoTrim = !_sigScanAutoTrim);
                            _reprocessScannedSignature();
                          },
                        ),
                        _choicePill(
                          label: _sigTransparentBg ? 'BG: Transparent PNG' : 'BG: White Paper',
                          selected: _sigTransparentBg,
                          onTap: () {
                            setState(() => _sigTransparentBg = !_sigTransparentBg);
                            _reprocessScannedSignature();
                          },
                        ),
                      ],
                    ),
                  ],
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
                          onTap: () {
                            setState(() => _stampShape = 'round');
                            _scheduleSignSealAutosave();
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _choicePill(
                          label: 'Oval Stamp',
                          selected: _stampShape == 'oval',
                          onTap: () {
                            setState(() => _stampShape = 'oval');
                            _scheduleSignSealAutosave();
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _choicePill(
                          label: 'Box Stamp',
                          selected: _stampShape == 'box',
                          onTap: () {
                            setState(() => _stampShape = 'box');
                            _scheduleSignSealAutosave();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _stampOrgCtrl,
                    onChanged: (_) {
                      setState(() {});
                      _scheduleSignSealAutosave();
                    },
                    decoration: const InputDecoration(
                      labelText: 'Organization Name (Top)',
                      hintText: 'Organization Name',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _stampStatusCtrl,
                    onChanged: (_) {
                      setState(() {});
                      _scheduleSignSealAutosave();
                    },
                    decoration: const InputDecoration(
                      labelText: 'Center Badge (Status)',
                      hintText: 'APPROVED / VERIFIED',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: ['APPROVED', 'VERIFIED', 'ORIGINAL', 'منظور شدہ', 'وصول پایا']
                        .map(
                          (preset) => _choicePill(
                            label: preset,
                            selected: _stampStatusCtrl.text == preset,
                            onTap: () {
                              setState(() => _stampStatusCtrl.text = preset);
                              _scheduleSignSealAutosave();
                            },
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _stampSubCtrl,
                    onChanged: (_) {
                      setState(() {});
                      _scheduleSignSealAutosave();
                    },
                    decoration: const InputDecoration(
                      labelText: 'City / Reg No. (Bottom)',
                      hintText: 'City or Reg No.',
                    ),
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
                            onTap: () {
                              setState(() => _stampInkColor = c);
                              _scheduleSignSealAutosave();
                            },
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
                        onTap: () {
                          setState(() => _stampShowDate = !_stampShowDate);
                          _scheduleSignSealAutosave();
                        },
                      ),
                      const SizedBox(width: 6),
                      _choicePill(
                        label: _stampTransparentBg ? 'Clear PNG' : 'White',
                        selected: _stampTransparentBg,
                        onTap: () {
                          setState(() => _stampTransparentBg = !_stampTransparentBg);
                          _scheduleSignSealAutosave();
                        },
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
              backgroundColor: _inkPrimary,
              foregroundColor: _onInkPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _sigMode == 3
                ? _addStampToProjectCanvas
                : ((_sigMode == 1 && _sigStrokes.isEmpty) ||
                        (_sigMode == 2 && (_sigScanProcessedBytes == null || _sigScanProcessing)))
                    ? null
                    : _addSignatureToProjectCanvas,
            icon: const Icon(Icons.add_to_photos_outlined, size: 18),
            label: Text(
              _sigMode == 3
                  ? 'Add Stamp (مہر) to Studio Canvas'
                  : _sigMode == 2
                      ? 'Add Scanned Signature to Canvas'
                      : 'Add Signature to Studio Canvas',
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
                  onPressed: ((_sigMode == 1 && _sigStrokes.isEmpty) ||
                          (_sigMode == 2 && (_sigScanProcessedBytes == null || _sigScanProcessing)))
                      ? null
                      : () => _sigMode == 3 ? _exportStampPng(shareOnly: false) : _exportSignaturePng(shareOnly: false),
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
                  onPressed: ((_sigMode == 1 && _sigStrokes.isEmpty) ||
                          (_sigMode == 2 && (_sigScanProcessedBytes == null || _sigScanProcessing)))
                      ? null
                      : () => _sigMode == 3 ? _exportStampPng(shareOnly: true) : _exportSignaturePng(shareOnly: true),
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
    final res = await compute(
      _decodeAndRenderScanIsolate,
      _ScanRenderArgs(rawBytes, rotationDeg),
    );
    return _ScannedDocPage(
      id: id,
      rawPath: rawPath,
      rawBytes: rawBytes,
      previewBytes: res.previewBytes,
      rotationDeg: rotationDeg,
      width: res.width,
      height: res.height,
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

  static const List<_FontCatalogEntry> _kFontsCatalog = [
    _FontCatalogEntry(
      family: 'NotoNastaliqUrdu',
      name: 'Noto Nastaliq Urdu',
      script: 'Urdu',
      sample: 'خوش آمدید — قلمکس اردو نستعلیق',
      isRtl: true,
      defaultLineHeight: 2.3,
      bundled: true,
      ttfUrl: 'https://raw.githubusercontent.com/google/fonts/main/ofl/notonastaliqurdu/NotoNastaliqUrdu%5Bwght%5D.ttf',
    ),
    _FontCatalogEntry(
      family: 'Gulzar',
      name: 'Gulzar Nastaliq',
      script: 'Urdu',
      sample: 'گلزار خطاطی — اردو و فارسی',
      isRtl: true,
      defaultLineHeight: 2.1,
      bundled: true,
      ttfUrl: 'https://raw.githubusercontent.com/google/fonts/main/ofl/gulzar/Gulzar-Regular.ttf',
    ),
    _FontCatalogEntry(
      family: 'NotoNaskhArabic',
      name: 'Noto Naskh Arabic',
      script: 'Urdu',
      sample: 'معیاری نسخ خط — اردو دستاویزات',
      isRtl: true,
      defaultLineHeight: 1.9,
      bundled: true,
      ttfUrl: 'https://raw.githubusercontent.com/google/fonts/main/ofl/notonaskharabic/NotoNaskhArabic%5Bwght%5D.ttf',
    ),
    _FontCatalogEntry(
      family: 'IBMPlexSansArabicSemiBold',
      name: 'IBM Plex SemiBold',
      script: 'Urdu',
      sample: 'جدید اردو اور انگلش ہیڈنگ',
      isRtl: true,
      defaultLineHeight: 1.8,
      bundled: true,
      ttfUrl: 'https://raw.githubusercontent.com/google/fonts/main/ofl/ibmplexsansarabic/IBMPlexSansArabic-SemiBold.ttf',
    ),
    _FontCatalogEntry(
      family: 'Amiri',
      name: 'Amiri Classical',
      script: 'Calligraphy',
      sample: 'امیری خطاطی — بسم اللہ الرحمن الرحیم',
      isRtl: true,
      defaultLineHeight: 1.95,
      bundled: false,
      ttfUrl: 'https://raw.githubusercontent.com/google/fonts/main/ofl/amiri/Amiri-Regular.ttf',
    ),
    _FontCatalogEntry(
      family: 'Lateef',
      name: 'Lateef Naskh',
      script: 'Urdu',
      sample: 'لطیف اردو خط — واضح تحریر',
      isRtl: true,
      defaultLineHeight: 1.9,
      bundled: false,
      ttfUrl: 'https://raw.githubusercontent.com/google/fonts/main/ofl/lateef/Lateef-Regular.ttf',
    ),
    _FontCatalogEntry(
      family: 'ScheherazadeNew',
      name: 'Scheherazade New',
      script: 'Arabic',
      sample: 'شہر زاد عربی و اردو خط',
      isRtl: true,
      defaultLineHeight: 1.95,
      bundled: false,
      ttfUrl: 'https://raw.githubusercontent.com/google/fonts/main/ofl/scheherazadenew/ScheherazadeNew-Regular.ttf',
    ),
    _FontCatalogEntry(
      family: 'Cairo',
      name: 'Cairo Modern',
      script: 'Arabic',
      sample: 'قاہرہ ماڈرن سانس ٹائپوگرافی',
      isRtl: true,
      defaultLineHeight: 1.75,
      bundled: false,
      ttfUrl: 'https://raw.githubusercontent.com/google/fonts/main/ofl/cairo/Cairo%5Bslnt%2Cwght%5D.ttf',
    ),
    _FontCatalogEntry(
      family: 'Tajawal',
      name: 'Tajawal Clean',
      script: 'Arabic',
      sample: 'تجوّل صاف اور جدید عربی خط',
      isRtl: true,
      defaultLineHeight: 1.75,
      bundled: false,
      ttfUrl: 'https://raw.githubusercontent.com/google/fonts/main/ofl/tajawal/Tajawal-Regular.ttf',
    ),
    _FontCatalogEntry(
      family: 'ReemKufi',
      name: 'Reem Kufi Display',
      script: 'Calligraphy',
      sample: 'ریم کوفی — منفرد خطاطی',
      isRtl: true,
      defaultLineHeight: 1.85,
      bundled: false,
      ttfUrl: 'https://raw.githubusercontent.com/google/fonts/main/ofl/reemkufi/ReemKufi%5Bwght%5D.ttf',
    ),
    _FontCatalogEntry(
      family: 'ArefRuqaa',
      name: 'Aref Ruqaa Ink',
      script: 'Calligraphy',
      sample: 'عارف رقعہ — دستخط اور خطاطی',
      isRtl: true,
      defaultLineHeight: 1.95,
      bundled: false,
      ttfUrl: 'https://raw.githubusercontent.com/google/fonts/main/ofl/arefruqaa/ArefRuqaa-Regular.ttf',
    ),
    _FontCatalogEntry(
      family: 'PlusJakartaSans',
      name: 'Plus Jakarta Sans',
      script: 'English',
      sample: 'Qalamix Modern Studio UI',
      isRtl: false,
      defaultLineHeight: 1.35,
      bundled: true,
      ttfUrl: 'https://raw.githubusercontent.com/google/fonts/main/ofl/plusjakartasans/PlusJakartaSans%5Bwght%5D.ttf',
    ),
    _FontCatalogEntry(
      family: 'PlayfairDisplay',
      name: 'Playfair Display Serif',
      script: 'English',
      sample: 'Editorial Elegance & Titles',
      isRtl: false,
      defaultLineHeight: 1.3,
      bundled: true,
      ttfUrl: 'https://raw.githubusercontent.com/google/fonts/main/ofl/playfairdisplay/PlayfairDisplay%5Bwght%5D.ttf',
    ),
    _FontCatalogEntry(
      family: 'Montserrat',
      name: 'Montserrat Geometric',
      script: 'English',
      sample: 'CLEAN BRANDING & POSTERS',
      isRtl: false,
      defaultLineHeight: 1.3,
      bundled: false,
      ttfUrl: 'https://raw.githubusercontent.com/google/fonts/main/ofl/montserrat/Montserrat%5Bwght%5D.ttf',
    ),
    _FontCatalogEntry(
      family: 'Poppins',
      name: 'Poppins Rounded',
      script: 'English',
      sample: 'Friendly Headline Typeface',
      isRtl: false,
      defaultLineHeight: 1.35,
      bundled: false,
      ttfUrl: 'https://raw.githubusercontent.com/google/fonts/main/ofl/poppins/Poppins-SemiBold.ttf',
    ),
    _FontCatalogEntry(
      family: 'Lora',
      name: 'Lora Document Serif',
      script: 'English',
      sample: 'Formal Letters & Certificates',
      isRtl: false,
      defaultLineHeight: 1.4,
      bundled: false,
      ttfUrl: 'https://raw.githubusercontent.com/google/fonts/main/ofl/lora/Lora%5Bwght%5D.ttf',
    ),
    _FontCatalogEntry(
      family: 'Oswald',
      name: 'Oswald Condensed',
      script: 'English',
      sample: 'BOLD THUMBNAIL DISPLAY',
      isRtl: false,
      defaultLineHeight: 1.2,
      bundled: false,
      ttfUrl: 'https://raw.githubusercontent.com/google/fonts/main/ofl/oswald/Oswald%5Bwght%5D.ttf',
    ),
    _FontCatalogEntry(
      family: 'BebasNeue',
      name: 'Bebas Neue Poster',
      script: 'English',
      sample: 'CINEMATIC BANNER HEADLINES',
      isRtl: false,
      defaultLineHeight: 1.1,
      bundled: false,
      ttfUrl: 'https://raw.githubusercontent.com/google/fonts/main/ofl/bebasneue/BebasNeue-Regular.ttf',
    ),
  ];

  List<(String, String, bool, double)> _availableTextFontOptions() {
    final base = <(String, String, bool, double)>[
      ('NotoNastaliqUrdu', 'Urdu Nastaliq', true, 2.3),
      ('Gulzar', 'Gulzar Urdu', true, 2.1),
      ('NotoNaskhArabic', 'Naskh Urdu', true, 1.9),
      ('IBMPlexSansArabicSemiBold', 'IBM Plex SemiBold', true, 1.8),
      ('PlusJakartaSans', 'Jakarta Sans', false, 1.35),
      ('PlayfairDisplay', 'Playfair Serif', false, 1.3),
    ];
    final seen = base.map((e) => e.$1).toSet();
    for (final c in _customFonts) {
      if (seen.add(c.family)) {
        base.add((c.family, c.name, c.isRtl, c.defaultLineHeight));
      }
    }
    return base;
  }

  Future<void> _loadInstalledCustomFonts() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final idxFile = File(p.join(docsDir.path, 'qalamix_fonts_index.json'));
      if (!idxFile.existsSync()) return;
      final decoded = jsonDecode(await idxFile.readAsString());
      if (decoded is! List) return;
      final restored = <_CustomInstalledFont>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final family = (item['family'] ?? '').toString();
        final name = (item['name'] ?? family).toString();
        final script = (item['script'] ?? 'Urdu').toString();
        final filePath = (item['filePath'] ?? '').toString();
        final isRtl = item['isRtl'] == true;
        final lh = (item['defaultLineHeight'] as num?)?.toDouble() ?? (isRtl ? 2.0 : 1.35);
        if (family.isEmpty || filePath.isEmpty || !File(filePath).existsSync()) continue;
        final bytes = await File(filePath).readAsBytes();
        final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
        restored.add(_CustomInstalledFont(
          family: family,
          name: name,
          script: script,
          filePath: filePath,
          isRtl: isRtl,
          defaultLineHeight: lh,
        ));
        _loadedFontFamilies.add(family);
      }
      if (mounted && restored.isNotEmpty) {
        setState(() {
          _customFonts
            ..clear()
            ..addAll(restored);
        });
      }
    } catch (_) {}
  }

  Future<void> _persistCustomFontsIndex() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final idxFile = File(p.join(docsDir.path, 'qalamix_fonts_index.json'));
      final payload = _customFonts
          .map((f) => {
                'family': f.family,
                'name': f.name,
                'script': f.script,
                'filePath': f.filePath,
                'isRtl': f.isRtl,
                'defaultLineHeight': f.defaultLineHeight,
              })
          .toList();
      await idxFile.writeAsString(jsonEncode(payload));
    } catch (_) {}
  }

  Future<Uint8List> _downloadBytesRaw(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final chunks = <int>[];
      await for (final chunk in resp) {
        chunks.addAll(chunk);
      }
      final bytes = Uint8List.fromList(chunks);
      if (bytes.length < 512) throw Exception('Invalid payload');
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> _resolveGoogleCssTtfUrl(String familyName) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final encoded = Uri.encodeComponent(familyName.trim()).replaceAll('%20', '+');
      final req = await client.getUrl(
        Uri.parse('https://fonts.googleapis.com/css2?family=$encoded&display=swap'),
      );
      req.headers.set(HttpHeaders.userAgentHeader, 'Dart/3.4 (dart:io)');
      final resp = await req.close();
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final css = await utf8.decoder.bind(resp).join();
      final match = RegExp(r'https://[^\s)]+\.ttf').firstMatch(css);
      return match?.group(0);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<Uint8List> _fetchRemoteFontBytes(String primaryUrl, {String? fallbackFamilyName}) async {
    if (primaryUrl.isNotEmpty) {
      try {
        final raw = await _downloadBytesRaw(primaryUrl);
        if (raw.length >= 1024) return raw;
      } catch (_) {}
    }
    if (fallbackFamilyName != null && fallbackFamilyName.trim().isNotEmpty) {
      final ttfUrl = await _resolveGoogleCssTtfUrl(fallbackFamilyName);
      if (ttfUrl != null) {
        final raw = await _downloadBytesRaw(ttfUrl);
        if (raw.length >= 1024) return raw;
      }
    }
    throw Exception('Could not download font from Google Fonts');
  }

  List<_FontCatalogEntry> _mapGoogleDirectoryJson(List<dynamic> rawList) {
    final result = <_FontCatalogEntry>[];
    for (final item in rawList) {
      if (item is! Map) continue;
      final id = (item['id'] ?? '').toString();
      final familyName = (item['family'] ?? '').toString();
      if (id.isEmpty || familyName.isEmpty) continue;
      final subsetsRaw = item['subsets'];
      final subsets = subsetsRaw is List ? subsetsRaw.map((e) => e.toString()).toList() : const ['latin'];
      final weightsRaw = item['weights'];
      final weights = weightsRaw is List ? weightsRaw.whereType<num>().map((e) => e.toInt()).toList() : [400];
      final defSubset = (item['defSubset'] ?? (subsets.contains('latin') ? 'latin' : subsets.first)).toString();
      final category = (item['category'] ?? 'sans-serif').toString().toLowerCase();
      final lower = familyName.toLowerCase();
      final isArabic = subsets.contains('arabic');
      String script = 'English';
      if (isArabic) {
        script = (lower.contains('nastaliq') || lower.contains('urdu') || lower.contains('gulzar'))
            ? 'Urdu'
            : 'Arabic';
      } else if (category == 'handwriting') {
        script = 'Calligraphy';
      }
      final w = weights.contains(400) ? 400 : (weights.isNotEmpty ? weights.first : 400);
      final safeFamily = 'GF_${id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
      result.add(_FontCatalogEntry(
        family: safeFamily,
        name: familyName,
        script: script,
        sample: isArabic
            ? 'خوش آمدید — اردو و عربی خطاطی'
            : (script == 'Calligraphy' ? 'Signature & Handwritten Style' : 'Qalamix Studio — AaBbCc 123'),
        isRtl: isArabic,
        defaultLineHeight: (lower.contains('nastaliq') || lower.contains('gulzar'))
            ? 2.15
            : (isArabic ? 1.75 : 1.35),
        bundled: false,
        ttfUrl: 'https://cdn.jsdelivr.net/fontsource/fonts/$id@latest/$defSubset-$w-normal.ttf',
      ));
    }
    return result;
  }

  Future<void> _ensureGoogleFontsDirectoryLoaded([void Function(void Function())? setModalState]) async {
    if (_googleDirectoryFonts.isNotEmpty || _loadingGoogleDirectory) return;
    _loadingGoogleDirectory = true;
    setModalState?.call(() {});
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final cacheFile = File(p.join(docsDir.path, 'qalamix_gf_directory.json'));
      if (cacheFile.existsSync()) {
        final age = DateTime.now().difference(cacheFile.lastModifiedSync());
        if (age.inHours < 24) {
          final parsed = jsonDecode(await cacheFile.readAsString());
          if (parsed is List && parsed.isNotEmpty) {
            _googleDirectoryFonts = _mapGoogleDirectoryJson(parsed);
            if (mounted) setState(() {});
            setModalState?.call(() {});
            return;
          }
        }
      }

      final bytes = await _downloadBytesRaw('https://api.fontsource.org/v1/fonts');
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is List && decoded.isNotEmpty) {
        final slim = decoded
            .whereType<Map>()
            .map((e) => {
                  'id': e['id'],
                  'family': e['family'],
                  'subsets': e['subsets'],
                  'weights': e['weights'],
                  'defSubset': e['defSubset'],
                  'category': e['category'],
                })
            .toList();
        await cacheFile.writeAsString(jsonEncode(slim));
        _googleDirectoryFonts = _mapGoogleDirectoryJson(slim);
        if (mounted) setState(() {});
      }
    } catch (_) {
    } finally {
      _loadingGoogleDirectory = false;
      setModalState?.call(() {});
    }
  }

  Future<void> _preloadPreviewFont(
    _FontCatalogEntry entry,
    void Function(void Function()) setModalState,
  ) async {
    if (entry.bundled ||
        _loadedFontFamilies.contains(entry.family) ||
        _previewLoadingFamilies.contains(entry.family)) {
      return;
    }
    _previewLoadingFamilies.add(entry.family);
    try {
      final raw = await _fetchRemoteFontBytes(entry.ttfUrl, fallbackFamilyName: entry.name);
      final loader = FontLoader(entry.family)
        ..addFont(Future.value(ByteData.sublistView(raw)));
      await loader.load();
      _loadedFontFamilies.add(entry.family);
      setModalState(() {});
    } catch (_) {
    } finally {
      _previewLoadingFamilies.remove(entry.family);
    }
  }

  Future<void> _installOrApplyCatalogFont(_FontCatalogEntry entry) async {
    if (!entry.bundled && !_loadedFontFamilies.contains(entry.family)) {
      final bytes = await _runWithSavingHud<Uint8List>(
        savingTitle: 'Installing ${entry.name}...',
        savingSubtitle: 'Saving offline font',
        savedTitle: '${entry.name} Ready',
        savedSubtitle: 'Installed & applied to Studio',
        action: () async {
          final raw = await _fetchRemoteFontBytes(entry.ttfUrl, fallbackFamilyName: entry.name);
          final docsDir = await getApplicationDocumentsDirectory();
          final dir = Directory(p.join(docsDir.path, 'qalamix_fonts'));
          if (!dir.existsSync()) dir.createSync(recursive: true);
          final outPath = p.join(dir.path, '${entry.family}.ttf');
          await File(outPath).writeAsBytes(raw);
          final loader = FontLoader(entry.family)
            ..addFont(Future.value(ByteData.sublistView(raw)));
          await loader.load();
          _loadedFontFamilies.add(entry.family);
          _customFonts.removeWhere((f) => f.family == entry.family);
          _customFonts.add(_CustomInstalledFont(
            family: entry.family,
            name: entry.name,
            script: entry.script,
            filePath: outPath,
            isRtl: entry.isRtl,
            defaultLineHeight: entry.defaultLineHeight,
          ));
          await _persistCustomFontsIndex();
          return raw;
        },
      );
      if (bytes == null) return;
    }

    if (!mounted) return;
    setState(() {
      final active = _activeLayer;
      if (active != null && active.type == LayerType.text) {
        active.fontFamily = entry.family;
        active.isRtl = entry.isRtl;
        active.lineHeight = entry.defaultLineHeight;
      } else {
        final newLayer = DesignLayer(
          id: 'txt_${DateTime.now().microsecondsSinceEpoch}',
          name: entry.isRtl ? 'Urdu Typography' : 'Heading Text',
          type: LayerType.text,
          x: _page.width * 0.1,
          y: _page.height * 0.25,
          width: _page.width * 0.8,
          height: 180,
          text: entry.isRtl ? 'نیا عنوان لکھیں' : 'Qalamix Heading',
          fontFamily: entry.family,
          fontSize: 46,
          fontWeight: 600,
          lineHeight: entry.defaultLineHeight,
          isRtl: entry.isRtl,
          textColor: Colors.white,
        );
        _page.layers.add(newLayer);
        _selectedLayerId = newLayer.id;
        _textController.text = newLayer.text;
        _inspectorTab = 0;
      }
      _inStudio = true;
    });
  }

  Future<void> _downloadFontFileToDevice(_FontCatalogEntry entry) async {
    String? savedPath;
    String? tmpPath;
    await _runWithSavingHud<void>(
      savingTitle: 'Downloading ${entry.name}.ttf...',
      savingSubtitle: 'Fetching typeface file',
      savedTitle: 'Font Saved (.TTF)',
      savedSubtitle: '${entry.name} saved to Downloads/Qalamix/Fonts',
      action: () async {
        Uint8List bytes;
        final existing = _customFonts.cast<_CustomInstalledFont?>().firstWhere((f) => f!.family == entry.family, orElse: () => null);
        if (existing != null && File(existing.filePath).existsSync()) {
          bytes = await File(existing.filePath).readAsBytes();
        } else {
          bytes = await _fetchRemoteFontBytes(entry.ttfUrl, fallbackFamilyName: entry.name);
        }
        final fname = '${entry.family}.ttf';
        if (Platform.isAndroid) {
          try {
            savedPath = await _mediaChannel.invokeMethod<String>('saveFontToDownloads', {
              'bytes': bytes,
              'name': fname,
            });
          } catch (_) {}
        }
        final tmpDir = await getTemporaryDirectory();
        tmpPath = p.join(tmpDir.path, fname);
        await File(tmpPath!).writeAsBytes(bytes);
      },
    );
    if (!mounted || tmpPath == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(savedPath != null ? 'Saved: $savedPath' : '${entry.name}.ttf ready'),
        action: SnackBarAction(
          label: 'Share .TTF',
          onPressed: () => Share.shareXFiles([XFile(tmpPath!)], text: '${entry.name} Font (.ttf)'),
        ),
      ),
    );
  }

  Future<void> _importLocalFontFromDevice(void Function(void Function()) setModalState) async {
    try {
      final res = await _mediaChannel.invokeMethod<dynamic>('pickFontFile');
      if (res is! Map) return;
      final fileName = (res['name'] ?? 'CustomFont.ttf').toString();
      final rawBytes = res['bytes'];
      if (rawBytes is! Uint8List || rawBytes.isEmpty) return;

      final lower = fileName.toLowerCase();
      if (!lower.endsWith('.ttf') && !lower.endsWith('.otf')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please pick a valid .ttf or .otf font file')),
          );
        }
        return;
      }

      final cleanLabel = p.basenameWithoutExtension(fileName).replaceAll(RegExp(r'[_-]+'), ' ').trim();
      final family = 'Custom_${DateTime.now().millisecondsSinceEpoch}';
      final isUrduGuess = RegExp(r'urdu|nastaliq|jameel|noori|alvi|faiz|mehr|arabic|naskh', caseSensitive: false)
          .hasMatch(fileName);

      await _runWithSavingHud<void>(
        savingTitle: 'Importing $cleanLabel...',
        savedTitle: 'Custom Font Installed',
        savedSubtitle: cleanLabel,
        action: () async {
          final docsDir = await getApplicationDocumentsDirectory();
          final dir = Directory(p.join(docsDir.path, 'qalamix_fonts'));
          if (!dir.existsSync()) dir.createSync(recursive: true);
          final outPath = p.join(dir.path, '$family${p.extension(fileName)}');
          await File(outPath).writeAsBytes(rawBytes);

          final loader = FontLoader(family)
            ..addFont(Future.value(ByteData.sublistView(rawBytes)));
          await loader.load();

          _loadedFontFamilies.add(family);
          _customFonts.add(_CustomInstalledFont(
            family: family,
            name: cleanLabel.isEmpty ? 'Custom Font' : cleanLabel,
            script: isUrduGuess ? 'Urdu' : 'English',
            filePath: outPath,
            isRtl: isUrduGuess,
            defaultLineHeight: isUrduGuess ? 2.1 : 1.35,
          ));
          await _persistCustomFontsIndex();
        },
      );
      if (mounted) setState(() {});
      setModalState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Font import error: $e')),
        );
      }
    }
  }

  Future<void> _openFontsLibrarySheet() async {
    String filterTab = 'All';
    String searchQuery = '';
    double previewSize = 22.0;
    final sampleCtrl = TextEditingController(text: 'خوش آمدید · Qalamix Typography');
    bool triggeredDir = false;

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
            if (!triggeredDir) {
              triggeredDir = true;
              Future.microtask(() => _ensureGoogleFontsDirectoryLoaded(setModalState));
            }
            final seenNames = <String>{};
            final entries = <_FontCatalogEntry>[];
            for (final c in _customFonts) {
              if (_kFontsCatalog.any((k) => k.family == c.family)) continue;
              seenNames.add(c.name.toLowerCase());
              entries.add(_FontCatalogEntry(
                family: c.family,
                name: c.name,
                script: c.script,
                sample: c.isRtl ? 'خوش آمدید — قلمکس' : 'Installed Custom Font Preview',
                isRtl: c.isRtl,
                defaultLineHeight: c.defaultLineHeight,
                bundled: true,
                ttfUrl: 'https://cdn.jsdelivr.net/fontsource/fonts/${c.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}@latest/latin-400-normal.ttf',
              ));
            }
            for (final k in _kFontsCatalog) {
              seenNames.add(k.name.toLowerCase());
              entries.add(k);
            }
            for (final g in _googleDirectoryFonts) {
              if (seenNames.add(g.name.toLowerCase())) {
                entries.add(g);
              }
            }

            final q = searchQuery.trim().toLowerCase();
            var matched = entries.where((e) {
              if (q.isNotEmpty && !e.name.toLowerCase().contains(q) && !e.script.toLowerCase().contains(q)) {
                return false;
              }
              if (filterTab == 'Installed') {
                return e.bundled || _loadedFontFamilies.contains(e.family);
              }
              if (filterTab != 'All') {
                return e.script == filterTab;
              }
              return true;
            }).toList();

            if (q.isNotEmpty) {
              matched.sort((a, b) {
                final an = a.name.toLowerCase();
                final bn = b.name.toLowerCase();
                final aRank = an == q ? 0 : (an.startsWith(q) ? 1 : 2);
                final bRank = bn == q ? 0 : (bn.startsWith(q) ? 1 : 2);
                if (aRank != bRank) return aRank - bRank;
                final aReady = (a.bundled || _loadedFontFamilies.contains(a.family)) ? 0 : 1;
                final bReady = (b.bundled || _loadedFontFamilies.contains(b.family)) ? 0 : 1;
                return aReady.compareTo(bReady);
              });
            }

            var filtered = matched.take(60).toList();
            if (q.isNotEmpty && filtered.isEmpty) {
              final rawName = searchQuery.trim();
              final slug = rawName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
              filtered = [
                _FontCatalogEntry(
                  family: 'GF_${slug.replaceAll('-', '_')}',
                  name: rawName,
                  script: 'English',
                  sample: 'Qalamix Studio — $rawName',
                  isRtl: false,
                  defaultLineHeight: 1.35,
                  bundled: false,
                  ttfUrl: slug.isNotEmpty ? 'https://cdn.jsdelivr.net/fontsource/fonts/$slug@latest/latin-400-normal.ttf' : '',
                ),
              ];
            }

            if (q.length >= 2) {
              for (final topItem in filtered.take(3)) {
                Future.microtask(() => _preloadPreviewFont(topItem, setModalState));
              }
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
                            child: Icon(Icons.font_download_rounded, color: _accentText, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Qalamix Fonts Library', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                                Text(
                                  _loadingGoogleDirectory
                                      ? 'Loading full Google Fonts directory...'
                                      : '${entries.length} Google Fonts · Search, Preview & Save .TTF',
                                  style: TextStyle(fontSize: 11, color: _subColor),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              decoration: const InputDecoration(
                                hintText: 'Search any Google Font (e.g. Roboto, Poppins, Amiri)...',
                                prefixIcon: Icon(Icons.search_rounded, size: 19),
                                isDense: true,
                              ),
                              onChanged: (v) => setModalState(() => searchQuery = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: _inkPrimary,
                              foregroundColor: _onInkPrimary,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => _importLocalFontFromDevice(setModalState),
                            icon: const Icon(Icons.upload_file_rounded, size: 18),
                            label: const Text('Import .TTF', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: sampleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Live Preview Text',
                          isDense: true,
                        ),
                        onChanged: (_) => setModalState(() {}),
                      ),
                      _sliderRow('Preview Size', previewSize, 14, 38, (v) => setModalState(() => previewSize = v)),
                      const SizedBox(height: 6),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: ['All', 'Urdu', 'Arabic', 'Calligraphy', 'English', 'Installed'].map((tab) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: _choicePill(
                                label: tab,
                                selected: filterTab == tab,
                                onTap: () => setModalState(() => filterTab = tab),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...filtered.map((entry) {
                        final installed = entry.bundled || _loadedFontFamilies.contains(entry.family);
                        final previewText = sampleCtrl.text.trim().isEmpty ? entry.sample : sampleCtrl.text;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _inputBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: installed ? _amber.withOpacity(0.45) : _borderColor,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      entry.name,
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: installed ? const Color(0xFF10B981).withOpacity(0.16) : _chipBg,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      installed ? '${entry.script} · Ready' : entry.script,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: installed ? const Color(0xFF10B981) : _subColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                decoration: BoxDecoration(
                                  color: _cardBg,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: _borderColor),
                                ),
                                child: Text(
                                  previewText,
                                  textDirection: entry.isRtl ? TextDirection.rtl : TextDirection.ltr,
                                  textAlign: entry.isRtl ? TextAlign.right : TextAlign.left,
                                  style: TextStyle(
                                    fontFamily: installed ? entry.family : null,
                                    fontSize: previewSize,
                                    height: entry.isRtl ? 1.9 : 1.3,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: _inkPrimary,
                                        foregroundColor: _onInkPrimary,
                                        padding: const EdgeInsets.symmetric(vertical: 9),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                                      ),
                                      onPressed: () async {
                                        await _installOrApplyCatalogFont(entry);
                                        if (ctx.mounted) Navigator.pop(ctx);
                                      },
                                      icon: Icon(installed ? Icons.check_circle_outline : Icons.download_done_rounded, size: 16),
                                      label: Text(
                                        installed ? 'Use in Studio' : 'Install & Use',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                  ),
                                  if (entry.ttfUrl.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(color: _borderColor),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                                      ),
                                      onPressed: () => _downloadFontFileToDevice(entry),
                                      icon: const Icon(Icons.download_rounded, size: 16),
                                      label: const Text('.TTF', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
    sampleCtrl.dispose();
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
                    final fileName = 'qalamix_scan_${DateTime.now().millisecondsSinceEpoch}.pdf';
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
                      final outDir = Directory(p.join(extDir.path, 'Qalamix'));
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
                      onPressed: () => Share.shareXFiles([XFile(shareTmpPath!)], text: 'Qalamix Scanned PDF'),
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
                      final fname = 'qalamix_scan_${DateTime.now().millisecondsSinceEpoch}_p${i + 1}.jpg';
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
                      onPressed: () => Share.shareXFiles([XFile(lastTmp)], text: 'Qalamix Scanned JPEG'),
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
                  final outDir = Directory(p.join(docs.path, 'qalamix_media'));
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
                      _inStudio = true;
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
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _scannerTealBg,
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(color: _scannerTealBorder),
                            ),
                            child: Icon(Icons.document_scanner_rounded, color: _scannerTeal, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Document Scanner', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _textColor)),
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
                            backgroundColor: _inkPrimary,
                            foregroundColor: _onInkPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                          ),
                          onPressed: localBusy ? null : runDocumentScanner,
                          icon: Icon(Icons.document_scanner_outlined, size: 19, color: _brandNibOnInk),
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
                          padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
                          decoration: BoxDecoration(
                            color: _cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _scannerTealBorder, width: 1.2),
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 58,
                                height: 58,
                                decoration: BoxDecoration(
                                  color: _scannerTealBg,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: _scannerTealBorder),
                                ),
                                child: Icon(Icons.insert_drive_file_outlined, size: 30, color: _scannerTeal),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No Scanned Pages Yet',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _textColor),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Tap Scan / Upload Document to scan pages or import photos, preview them cleanly, and save as PDF or JPEG.',
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
                                  gaplessPlayback: true,
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
                                  backgroundColor: _inkPrimary,
                                  foregroundColor: _onInkPrimary,
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                                ),
                                onPressed: localBusy ? null : downloadScannerPdf,
                                icon: Icon(Icons.picture_as_pdf_rounded, size: 18, color: _brandNibOnInk),
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
                                  backgroundColor: _scannerTeal,
                                  foregroundColor: _isDark ? const Color(0xFF0A0C0F) : Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                                ),
                                onPressed: localBusy ? null : saveScannerJpeg,
                                icon: const Icon(Icons.download_rounded, size: 18),
                                label: Text(
                                  _scannedPages.length > 1 ? 'Save JPEGs (${_scannedPages.length})' : 'Save JPEG',
                                  style: const TextStyle(fontWeight: FontWeight.w800),
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
                                  backgroundColor: _amberTintBg,
                                  side: BorderSide(color: _amberTintBorder),
                                  foregroundColor: _brandNibInk,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                                ),
                                onPressed: localBusy ? null : sendScannedToStudio,
                                icon: Icon(Icons.brush_outlined, size: 17, color: _brandNibInk),
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

class _PhotoEffectSpec {
  final String id;
  final String name;
  final String subtitle;
  final String assetPath;
  final FilterSettings filters;

  const _PhotoEffectSpec({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.assetPath,
    required this.filters,
  });
}

class _SigPoint {
  final Offset pos;
  final int timestampMs;
  const _SigPoint(this.pos, this.timestampMs);
}

class _SigStroke {
  List<_SigPoint> points;
  final Color color;
  final double width;
  final String penType;

  _SigStroke({
    required this.points,
    required this.color,
    required this.width,
    this.penType = 'fountain',
  });
}

/// Decimates hand-tremor jitter and runs pinned-endpoint Chaikin curve smoothing.
List<_SigPoint> _smoothSigPoints(List<_SigPoint> raw, {int passes = 3}) {
  if (raw.length < 3) return raw;
  final decimated = <_SigPoint>[raw.first];
  const minDist = 3.2;
  for (int i = 1; i < raw.length - 1; i++) {
    if ((raw[i].pos - decimated.last.pos).distance >= minDist) {
      decimated.add(raw[i]);
    }
  }
  decimated.add(raw.last);
  if (decimated.length < 3) return decimated;

  var pts = decimated;
  for (int pass = 0; pass < passes; pass++) {
    final next = <_SigPoint>[pts.first];
    for (int i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      next.add(_SigPoint(
        Offset(a.pos.dx * 0.75 + b.pos.dx * 0.25, a.pos.dy * 0.75 + b.pos.dy * 0.25),
        (a.timestampMs * 0.75 + b.timestampMs * 0.25).round(),
      ));
      next.add(_SigPoint(
        Offset(a.pos.dx * 0.25 + b.pos.dx * 0.75, a.pos.dy * 0.25 + b.pos.dy * 0.75),
        (a.timestampMs * 0.25 + b.timestampMs * 0.75).round(),
      ));
    }
    next.add(pts.last);
    pts = next;
  }
  return pts;
}

void _paintSignatureStrokeList(
  Canvas canvas,
  List<_SigStroke> strokes, {
  required double scale,
  required double offsetX,
  required double offsetY,
  double widthMultiplier = 1.0,
}) {
  Offset mapPt(Offset p) => Offset(p.dx * scale + offsetX, p.dy * scale + offsetY);

  void drawUniformSmooth(_SigStroke stroke, double wFactor, double opacity) {
    final pts = stroke.points;
    final w = (stroke.width * widthMultiplier * wFactor).clamp(1.2, 28.0);
    final paint = Paint()
      ..color = opacity < 0.99 ? stroke.color.withOpacity(opacity) : stroke.color
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (pts.length == 1) {
      canvas.drawCircle(
        mapPt(pts.first.pos),
        w / 2,
        Paint()..color = paint.color,
      );
      return;
    }

    final path = Path();
    final p0 = mapPt(pts.first.pos);
    path.moveTo(p0.dx, p0.dy);
    for (int i = 1; i < pts.length - 1; i++) {
      final curr = mapPt(pts[i].pos);
      final next = mapPt(pts[i + 1].pos);
      final mid = Offset((curr.dx + next.dx) / 2.0, (curr.dy + next.dy) / 2.0);
      path.quadraticBezierTo(curr.dx, curr.dy, mid.dx, mid.dy);
    }
    final last = mapPt(pts.last.pos);
    path.lineTo(last.dx, last.dy);
    canvas.drawPath(path, paint);
  }

  for (final stroke in strokes) {
    final pts = stroke.points;
    if (pts.isEmpty) continue;
    final pen = stroke.penType;

    if (pen == 'ballpoint') {
      drawUniformSmooth(stroke, 1.0, 1.0);
      continue;
    }
    if (pen == 'fineliner') {
      drawUniformSmooth(stroke, 0.52, 1.0);
      continue;
    }
    if (pen == 'marker') {
      drawUniformSmooth(stroke, 1.85, 0.9);
      continue;
    }

    final baseWidth = (stroke.width * widthMultiplier).clamp(1.5, 26.0);
    if (pts.length == 1) {
      canvas.drawCircle(
        mapPt(pts.first.pos),
        baseWidth / 2,
        Paint()..color = stroke.color,
      );
      continue;
    }

    final fillPaint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.fill;

    if (pen == 'calligraphy') {
      final nibHalfLen = baseWidth * 0.78;
      final nibHalfThick = math.max(1.0, baseWidth * 0.16);
      const nibAngle = -math.pi / 4.0;
      for (int i = 0; i < pts.length - 1; i++) {
        final p0 = mapPt(pts[i].pos);
        final p1 = mapPt(pts[i + 1].pos);
        final dist = (p1 - p0).distance;
        final steps = math.max(1, (dist / 2.0).ceil());
        for (int st = 0; st <= steps; st++) {
          final f = st / steps;
          final px = p0.dx + (p1.dx - p0.dx) * f;
          final py = p0.dy + (p1.dy - p0.dy) * f;
          canvas.save();
          canvas.translate(px, py);
          canvas.rotate(nibAngle);
          canvas.drawRect(
            Rect.fromCenter(center: Offset.zero, width: nibHalfLen * 2, height: nibHalfThick * 2),
            fillPaint,
          );
          canvas.restore();
        }
      }
      continue;
    }

    // Fountain Nib or Brush Pen
    double smoothedR = baseWidth * 0.52;
    final total = pts.length;
    for (int i = 0; i < total - 1; i++) {
      final p0 = mapPt(pts[i].pos);
      final p1 = mapPt(pts[i + 1].pos);
      final delta = p1 - p0;
      final segLen = delta.distance;
      if (segLen < 0.05) continue;

      final progress = i / math.max(1, total - 1);
      final edgeTaper = (progress / 0.1).clamp(0.0, 1.0) * 0.28 +
          ((1.0 - progress) / 0.14).clamp(0.0, 1.0) * 0.38 +
          0.34;

      double targetR = baseWidth * 0.5;
      if (pen == 'fountain') {
        final angle = math.atan2(delta.dy, delta.dx);
        final nibMod = 0.44 + 0.68 * math.sin(angle - math.pi * 0.22).abs();
        targetR = (baseWidth * 0.62) * nibMod * edgeTaper;
      } else {
        final dt = math.max(6, pts[i + 1].timestampMs - pts[i].timestampMs);
        final speed = segLen / dt;
        final pressure = (1.38 - speed * 0.42).clamp(0.32, 1.55);
        targetR = (baseWidth * 0.60) * pressure * edgeTaper;
      }

      final prevR = smoothedR;
      smoothedR = prevR * 0.68 + targetR * 0.32;
      final steps = math.max(1, (segLen / 1.8).ceil());
      for (int st = 0; st <= steps; st++) {
        final f = st / steps;
        final cx = p0.dx + delta.dx * f;
        final cy = p0.dy + delta.dy * f;
        final r = math.max(0.75, prevR + (smoothedR - prevR) * f);
        canvas.drawCircle(Offset(cx, cy), r, fillPaint);
      }
    }
  }
}

class _SignaturePadPainter extends CustomPainter {
  final List<_SigStroke> strokes;
  final Size sourceSize;
  _SignaturePadPainter(this.strokes, this.sourceSize);

  @override
  void paint(Canvas canvas, Size size) {
    final sw = math.max(1.0, sourceSize.width);
    final sh = math.max(1.0, sourceSize.height);
    final scale = math.min(size.width / sw, size.height / sh);
    final ox = (size.width - sw * scale) / 2.0;
    final oy = (size.height - sh * scale) / 2.0;

    _paintSignatureStrokeList(
      canvas,
      strokes,
      scale: scale,
      offsetX: ox,
      offsetY: oy,
      widthMultiplier: scale,
    );
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
    final orgText = org.trim().isEmpty ? 'ORGANIZATION' : org.trim();
    final statusText = status.trim().isEmpty ? 'STATUS' : status.trim();
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

class _ScanRenderArgs {
  final Uint8List rawBytes;
  final int rotationDeg;
  const _ScanRenderArgs(this.rawBytes, this.rotationDeg);
}

class _ScanRenderOutput {
  final Uint8List previewBytes;
  final int width;
  final int height;
  const _ScanRenderOutput(this.previewBytes, this.width, this.height);
}

_ScanRenderOutput _decodeAndRenderScanIsolate(_ScanRenderArgs args) {
  var decoded = img.decodeImage(args.rawBytes);
  if (decoded == null) {
    return _ScanRenderOutput(args.rawBytes, 1000, 1400);
  }
  if (args.rotationDeg % 360 != 0) {
    decoded = img.copyRotate(decoded, angle: args.rotationDeg);
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
  return _ScanRenderOutput(jpg, decoded.width, decoded.height);
}

class _FontCatalogEntry {
  final String family;
  final String name;
  final String script;
  final String sample;
  final bool isRtl;
  final double defaultLineHeight;
  final bool bundled;
  final String ttfUrl;

  const _FontCatalogEntry({
    required this.family,
    required this.name,
    required this.script,
    required this.sample,
    required this.isRtl,
    required this.defaultLineHeight,
    required this.bundled,
    required this.ttfUrl,
  });
}

class _CustomInstalledFont {
  final String family;
  final String name;
  final String script;
  final String filePath;
  final bool isRtl;
  final double defaultLineHeight;

  const _CustomInstalledFont({
    required this.family,
    required this.name,
    required this.script,
    required this.filePath,
    required this.isRtl,
    required this.defaultLineHeight,
  });
}

(Uint8List, String)? _rotateImage90Isolate((Uint8List, String) args) {
  final decoded = img.decodeImage(args.$1);
  if (decoded == null) return null;
  final oriented = img.bakeOrientation(decoded);
  final rotated = img.copyRotate(oriented, angle: 90);
  final preferPng = args.$2 == '.png' || rotated.numChannels == 4;
  if (preferPng) {
    return (Uint8List.fromList(img.encodePng(rotated)), '.png');
  }
  return (Uint8List.fromList(img.encodeJpg(rotated, quality: 95)), '.jpg');
}
