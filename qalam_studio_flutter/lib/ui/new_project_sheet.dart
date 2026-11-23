import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/design_project.dart';

class NewProjectSheetResult {
  final DesignProject? project;
  final bool openPdf;

  const NewProjectSheetResult({
    this.project,
    this.openPdf = false,
  });
}

Future<NewProjectSheetResult?> showNewProjectSheet(BuildContext context) {
  return showModalBottomSheet<NewProjectSheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _NewProjectSheet(),
  );
}

class _SizePreset {
  final String key;
  final String name;
  final double width;
  final double height;

  const _SizePreset(this.key, this.name, this.width, this.height);
}

class _NewProjectSheet extends StatefulWidget {
  const _NewProjectSheet();

  @override
  State<_NewProjectSheet> createState() => _NewProjectSheetState();
}

class _NewProjectSheetState extends State<_NewProjectSheet> {
  static const List<_SizePreset> _paperPresets = [
    _SizePreset('a4_portrait', 'A4 Portrait', 992, 1403),
    _SizePreset('a4_landscape', 'A4 Landscape', 1403, 992),
    _SizePreset('card', 'Card', 1050, 600),
  ];

  static const List<_SizePreset> _screenPresets = [
    _SizePreset('square', 'Square', 1080, 1080),
    _SizePreset('story', 'Story', 1080, 1920),
    _SizePreset('wide', 'Wide', 1280, 720),
  ];

  static const List<Color> _paperColors = [
    Color(0xFFFAF9F6),
    Color(0xFFFFFFFF),
    Color(0xFFF1F5F9),
    Color(0xFF111317),
  ];

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _wCtrl = TextEditingController(text: '992');
  final TextEditingController _hCtrl = TextEditingController(text: '1403');

  String _selectedKey = 'a4_portrait';
  double _width = 992;
  double _height = 1403;
  Color _paperColor = const Color(0xFFFAF9F6);

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _panelBg => _isDark ? const Color(0xFF1E222B) : Colors.white;
  Color get _cardBg => _isDark ? const Color(0xFF161920) : const Color(0xFFFAF8F4);
  Color get _borderColor => _isDark ? const Color(0xFF2C313C) : const Color(0xFFE7E2D8);
  Color get _textColor => _isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1C1917);
  Color get _subColor => _isDark ? const Color(0xFF94A3B8) : const Color(0xFF57534E);
  Color get _amber => _isDark ? const Color(0xFFFBBF24) : const Color(0xFFF59E0B);
  Color get _amberTintBg =>
      _isDark ? const Color(0xFFF59E0B).withOpacity(0.18) : const Color(0xFFFFF6E0);
  Color get _accentText => _isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _wCtrl.dispose();
    _hCtrl.dispose();
    super.dispose();
  }

  void _selectPreset(_SizePreset preset) {
    setState(() {
      _selectedKey = preset.key;
      _width = preset.width;
      _height = preset.height;
      _wCtrl.text = preset.width.round().toString();
      _hCtrl.text = preset.height.round().toString();
    });
  }

  void _onCustomChanged() {
    final parsedW = double.tryParse(_wCtrl.text.trim());
    final parsedH = double.tryParse(_hCtrl.text.trim());
    setState(() {
      _selectedKey = 'custom';
      if (parsedW != null) _width = parsedW.clamp(200, 4096).toDouble();
      if (parsedH != null) _height = parsedH.clamp(200, 4096).toDouble();
    });
  }

  void _createProject() {
    final parsedW = (double.tryParse(_wCtrl.text.trim()) ?? _width).clamp(200.0, 4096.0).toDouble();
    final parsedH = (double.tryParse(_hCtrl.text.trim()) ?? _height).clamp(200.0, 4096.0).toDouble();
    final rawName = _nameCtrl.text.trim();
    final name = rawName.isEmpty ? 'Untitled' : rawName;
    final now = DateTime.now().millisecondsSinceEpoch;
    final project = DesignProject(
      id: 'proj_$now',
      name: name,
      updatedAt: now,
      pages: [
        DocumentPage(
          id: 'page_1',
          title: 'Page 1',
          width: parsedW,
          height: parsedH,
          backgroundColor: _paperColor,
          layers: [],
        ),
      ],
    );
    Navigator.of(context).pop(NewProjectSheetResult(project: project));
  }

  Widget _buildPresetCard(_SizePreset preset) {
    final selected = _selectedKey == preset.key;
    final maxDim = math.max(preset.width, preset.height);
    final boxW = (preset.width / maxDim) * 28.0;
    final boxH = (preset.height / maxDim) * 28.0;

    return Expanded(
      child: InkWell(
        onTap: () => _selectPreset(preset),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? _amberTintBg : _cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? _amber : _borderColor,
              width: selected ? 1.6 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: Container(
                    width: math.max(10.0, boxW),
                    height: math.max(10.0, boxH),
                    decoration: BoxDecoration(
                      color: selected
                          ? _amber.withOpacity(0.22)
                          : (_isDark ? const Color(0xFF262B36) : Colors.white),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: selected ? _amber : _subColor.withOpacity(0.55),
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                preset.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? _accentText : _textColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${preset.width.round()}×${preset.height.round()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _subColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: BoxDecoration(
        color: _panelBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: _borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'New Project',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: _textColor,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: _subColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Project Name',
                hintText: 'Untitled',
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Paper',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _subColor),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                _buildPresetCard(_paperPresets[0]),
                const SizedBox(width: 8),
                _buildPresetCard(_paperPresets[1]),
                const SizedBox(width: 8),
                _buildPresetCard(_paperPresets[2]),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Screen',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _subColor),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                _buildPresetCard(_screenPresets[0]),
                const SizedBox(width: 8),
                _buildPresetCard(_screenPresets[1]),
                const SizedBox(width: 8),
                _buildPresetCard(_screenPresets[2]),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Custom W / H (200–4096)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _subColor),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _wCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _onCustomChanged(),
                    decoration: const InputDecoration(labelText: 'Width'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _hCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _onCustomChanged(),
                    decoration: const InputDecoration(labelText: 'Height'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Paper Color',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _subColor),
            ),
            const SizedBox(height: 8),
            Row(
              children: _paperColors.map((c) {
                final sel = _paperColor.value == c.value;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () => setState(() => _paperColor = c),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: sel ? _amber : _borderColor,
                          width: sel ? 2.5 : 1.2,
                        ),
                      ),
                      child: sel
                          ? Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: c.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                            )
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 46,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: const Color(0xFF1C1917),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _createProject,
                child: const Text(
                  'Create',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop(const NewProjectSheetResult(openPdf: true));
                },
                icon: Icon(Icons.picture_as_pdf_outlined, size: 18, color: _accentText),
                label: Text(
                  'Open a PDF',
                  style: TextStyle(fontWeight: FontWeight.w700, color: _accentText),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
