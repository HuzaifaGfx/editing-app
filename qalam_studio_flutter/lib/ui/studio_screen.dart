import 'package:flutter/material.dart';
import '../engine/layer_canvas.dart';
import '../models/design_project.dart';
import '../storage/local_project_store.dart';

class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key});

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  late DesignProject _project;
  String? _selectedLayerId;

  @override
  void initState() {
    super.initState();
    _project = DesignProject(
      id: 'default_poster',
      name: 'Urdu & English Poster',
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      pages: [
        DocumentPage(
          id: 'p1',
          title: 'Page 1',
          layers: [
            DesignLayer(
              id: 't1',
              name: 'Urdu Headline',
              type: LayerType.text,
              text: 'ہر لفظ ایک تصویر ہے',
              isRtl: true,
              fontFamily: 'NotoNastaliqUrdu',
              fontSize: 36,
              lineHeight: 2.3,
            ),
          ],
        ),
      ],
    );
  }

  DesignLayer? get _activeLayer {
    for (final l in _project.pages.first.layers) {
      if (l.id == _selectedLayerId) return l;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final page = _project.pages.first;
    final layer = _activeLayer;

    return Scaffold(
      appBar: AppBar(
        title: Text(_project.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined),
            onPressed: () async {
              _project.updatedAt = DateTime.now().millisecondsSinceEpoch;
              await LocalProjectStore.instance.saveProject(_project);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Project saved offline')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayerCanvas(
              page: page,
              selectedLayerId: _selectedLayerId,
              onSelectLayer: (id) => setState(() => _selectedLayerId = id),
              onUpdateLayer: (_) => setState(() {}),
            ),
          ),
          if (layer != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: const Color(0xFF191C22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text('Opacity', style: TextStyle(fontSize: 13)),
                      Expanded(
                        child: Slider(
                          value: layer.opacity,
                          onChanged: (v) => setState(() => layer.opacity = v),
                        ),
                      ),
                      Text('${(layer.opacity * 100).round()}%'),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
