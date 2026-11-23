import 'dart:convert';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:qalam_studio/models/design_project.dart';

void main() {
  test('.qalamix import round-trips text styles and preserves legacy files', () async {
    final styledText = DesignLayer(
      id: 'txt_1',
      name: 'Styled Heading',
      type: LayerType.text,
      text: 'Qalamix',
      isRtl: true,
      blendMode: BlendMode.multiply,
      letterSpacing: 1.5,
      textStrokeColor: const Color(0xFFB91C1C),
      textStrokeWidth: 3.0,
      textShadowColor: const Color(0xAA000000),
      textShadowBlur: 8.0,
      textShadowOffsetX: 2.0,
      textShadowOffsetY: 4.0,
      filters: FilterSettings(brightness: 1.15, sepia: 0.2),
    );

    final project = DesignProject(
      id: 'proj_1',
      name: 'Styled Bundle Test',
      updatedAt: 1700000000000,
      pages: [
        DocumentPage(
          id: 'pg_1',
          title: 'Page 1',
          layers: [styledText],
        ),
      ],
    );

    final bundle = <String, dynamic>{
      'format': 'qalamix_project_v1',
      'exportedAt': 1700000000000,
      'project': jsonDecode(project.encode()),
      'embeddedImages': <String, String>{},
    };

    final imported = await parseImportedProjectBundle(
      jsonEncode(bundle),
      nowMs: 1700000001000,
    );

    expect(imported.pages, hasLength(1));
    expect(imported.pages.first.layers, hasLength(1));
    final layer = imported.pages.first.layers.first;
    expect(layer.letterSpacing, 1.5);
    expect(layer.textStrokeWidth, 3.0);
    expect(layer.textStrokeColor.value, 0xFFB91C1C);
    expect(layer.textShadowBlur, 8.0);
    expect(layer.textShadowColor.value, 0xAA000000);
    expect(layer.textShadowOffsetX, 2.0);
    expect(layer.textShadowOffsetY, 4.0);
    expect(layer.isRtl, isTrue);
    expect(layer.blendMode, BlendMode.multiply);
    expect(layer.filters.brightness, 1.15);

    // Legacy bundle omitting the 7 new text style keys must still parse cleanly
    final legacyBundle = {
      'format': 'qalamix_project_v1',
      'project': {
        'id': 'old_proj',
        'name': 'Legacy Project',
        'pages': [
          {
            'id': 'pg_old',
            'title': 'Page 1',
            'layers': [
              {
                'id': 'l_old',
                'name': 'Legacy Text',
                'type': 'text',
                'text': 'Hello',
                'x': 20,
                'y': 30,
              }
            ],
          }
        ],
      },
      'embeddedImages': <String, String>{},
    };

    final legacyImported = await parseImportedProjectBundle(
      jsonEncode(legacyBundle),
      nowMs: 1700000002000,
    );
    final oldLayer = legacyImported.pages.first.layers.first;
    expect(oldLayer.text, 'Hello');
    expect(oldLayer.letterSpacing, 0.0);
    expect(oldLayer.textStrokeWidth, 0.0);
    expect(oldLayer.textShadowBlur, 0.0);
  });
}
