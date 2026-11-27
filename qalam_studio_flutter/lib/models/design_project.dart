import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/painting.dart';

enum LayerType { text, image, shape }

typedef ImportedImageWriter = Future<String?> Function(
  String b64OrDataUri,
  String prefix,
);

/// Lenient JSON helpers: imported / hand-edited project files often carry
/// numbers as strings (e.g. "40" instead of 40) or omit ids. These accept
/// num-or-String and fall back instead of throwing.
double _asDouble(dynamic raw, double fallback) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.trim()) ?? fallback;
  return fallback;
}

int _asInt(dynamic raw, int fallback) {
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim()) ?? fallback;
  return fallback;
}

bool _asBool(dynamic raw, bool fallback) {
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  if (raw is String) {
    final v = raw.trim().toLowerCase();
    if (v == 'true' || v == '1' || v == 'yes') return true;
    if (v == 'false' || v == '0' || v == 'no') return false;
  }
  return fallback;
}

String _asString(dynamic raw, String fallback) {
  if (raw == null) return fallback;
  if (raw is String) return raw;
  return raw.toString();
}

Color parseColorAny(dynamic raw, Color fallback) {
  if (raw is int) return Color(raw);
  if (raw is num) return Color(raw.toInt());
  if (raw is String) {
    final clean = raw.trim().toLowerCase();
    if (clean == 'transparent') return const Color(0x00000000);
    if (clean.startsWith('#')) {
      var hex = clean.substring(1);
      if (hex.length == 3) {
        hex = '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}';
      }
      if (hex.length == 4) {
        // #RGBA -> #AARRGGBB.
        hex =
            '${hex[3]}${hex[3]}${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}';
      }
      // #RRGGBB gets an opaque alpha; #AARRGGBB (length 8) is used as-is.
      if (hex.length == 6) hex = 'ff$hex';
      final val = int.tryParse(hex, radix: 16);
      if (val != null) return Color(val);
    }
  }
  return fallback;
}

BlendMode parseBlendModeAny(dynamic raw) {
  if (raw is int && raw >= 0 && raw < BlendMode.values.length) {
    return BlendMode.values[raw];
  }
  if (raw is String) {
    switch (raw.toLowerCase().replaceAll('_', '-')) {
      case 'multiply':
        return BlendMode.multiply;
      case 'screen':
        return BlendMode.screen;
      case 'overlay':
        return BlendMode.overlay;
      case 'softlight':
      case 'soft-light':
        return BlendMode.softLight;
      case 'hardlight':
      case 'hard-light':
        return BlendMode.hardLight;
      case 'darken':
        return BlendMode.darken;
      case 'lighten':
        return BlendMode.lighten;
      case 'colordodge':
      case 'color-dodge':
        return BlendMode.colorDodge;
      case 'colorburn':
      case 'color-burn':
        return BlendMode.colorBurn;
      case 'difference':
        return BlendMode.difference;
      case 'exclusion':
        return BlendMode.exclusion;
      default:
        return BlendMode.srcOver;
    }
  }
  return BlendMode.srcOver;
}

class FilterSettings {
  double brightness;
  double contrast;
  double saturate;
  double sepia;
  double grayscale;
  double removeWhite; // 0 = off, 1..100 tolerance
  bool blackAndWhite;
  bool guilloche;
  double guillocheContrast; // 0..25 (% contrast boost, default 13)
  double guillocheBend; // 0..6 (px contour bend, default 3)
  double guillocheOpacity; // 75..100 (% skin opacity over paper, default 88)
  String guillochePattern; // 'banknote' | 'rosette' | 'mesh'
  double softGlow;
  double rosyTint;
  double skinSmooth;
  double portraitBlur;

  FilterSettings({
    this.brightness = 1.0,
    this.contrast = 1.0,
    this.saturate = 1.0,
    this.sepia = 0.0,
    this.grayscale = 0.0,
    this.removeWhite = 0.0,
    this.blackAndWhite = false,
    this.guilloche = false,
    this.guillocheContrast = 13.0,
    this.guillocheBend = 3.0,
    this.guillocheOpacity = 88.0,
    this.guillochePattern = 'banknote',
    this.softGlow = 0.0,
    this.rosyTint = 0.0,
    this.skinSmooth = 0.0,
    this.portraitBlur = 0.0,
  });

  FilterSettings copy() => FilterSettings(
        brightness: brightness,
        contrast: contrast,
        saturate: saturate,
        sepia: sepia,
        grayscale: grayscale,
        removeWhite: removeWhite,
        blackAndWhite: blackAndWhite,
        guilloche: guilloche,
        guillocheContrast: guillocheContrast,
        guillocheBend: guillocheBend,
        guillocheOpacity: guillocheOpacity,
        guillochePattern: guillochePattern,
        softGlow: softGlow,
        rosyTint: rosyTint,
        skinSmooth: skinSmooth,
        portraitBlur: portraitBlur,
      );

  Map<String, dynamic> toJson() => {
        'brightness': brightness,
        'contrast': contrast,
        'saturate': saturate,
        'sepia': sepia,
        'grayscale': grayscale,
        'removeWhite': removeWhite,
        'blackAndWhite': blackAndWhite,
        'guilloche': guilloche,
        'guillocheContrast': guillocheContrast,
        'guillocheBend': guillocheBend,
        'guillocheOpacity': guillocheOpacity,
        'guillochePattern': guillochePattern,
        'softGlow': softGlow,
        'rosyTint': rosyTint,
        'skinSmooth': skinSmooth,
        'portraitBlur': portraitBlur,
      };

  factory FilterSettings.fromJson(Map<String, dynamic> json) => FilterSettings(
        brightness: _asDouble(json['brightness'], 1.0),
        contrast: _asDouble(json['contrast'], 1.0),
        saturate: _asDouble(json['saturate'], 1.0),
        sepia: _asDouble(json['sepia'], 0.0),
        grayscale: _asDouble(json['grayscale'], 0.0),
        removeWhite: _asDouble(json['removeWhite'], 0.0),
        blackAndWhite: _asBool(json['blackAndWhite'], false),
        guilloche: _asBool(json['guilloche'], false),
        guillocheContrast: _asDouble(json['guillocheContrast'], 13.0),
        guillocheBend: _asDouble(json['guillocheBend'], 3.0),
        guillocheOpacity: _asDouble(json['guillocheOpacity'], 88.0),
        guillochePattern: _asString(json['guillochePattern'], 'banknote'),
        softGlow: _asDouble(json['softGlow'], 0.0),
        rosyTint: _asDouble(json['rosyTint'], 0.0),
        skinSmooth: _asDouble(json['skinSmooth'], 0.0),
        portraitBlur: _asDouble(json['portraitBlur'], 0.0),
      );
}

class DesignLayer {
  String id;
  String name;
  LayerType type;
  double x;
  double y;
  double width;
  double height;
  double rotation;
  double opacity;
  BlendMode blendMode;
  bool visible;
  bool locked;
  bool isCanvasBackground;

  // Text properties (Urdu & English)
  String text;
  bool isRtl;
  String fontFamily;
  double fontSize;
  int fontWeight;
  double lineHeight;
  Color textColor;
  TextAlign? textAlign;
  Color textBgColor;
  double letterSpacing;
  Color textStrokeColor;
  double textStrokeWidth; // 0 = off
  Color textShadowColor;
  double textShadowBlur; // 0 = off
  double textShadowOffsetX;
  double textShadowOffsetY;

  // Image & shape overlay properties
  String? localImagePath;
  bool aspectLocked;
  BoxFit objectFit;
  double borderRadius;
  String shapeKind;
  Color shapeStrokeColor;
  double shapeStrokeWidth;
  bool flipX;
  bool flipY;
  FilterSettings filters;

  // Runtime caches for processed PNG bytes
  Uint8List? processedWhiteRemovedBytes;
  Uint8List? processedGuillocheBytes;

  // Serialized AI outputs (file paths, so undo/redo snapshots and app
  // restarts keep them for free — the path lives inside the undo JSON).
  // Never overwrite the original [localImagePath]; the chain is
  // original -> enhanced -> background-removed.
  String? backgroundRemovedPath;
  String? enhancedPath;

  DesignLayer({
    required this.id,
    required this.name,
    required this.type,
    this.x = 40,
    this.y = 40,
    this.width = 300,
    this.height = 180,
    this.rotation = 0,
    this.opacity = 1.0,
    this.blendMode = BlendMode.srcOver,
    this.visible = true,
    this.locked = false,
    this.isCanvasBackground = false,
    this.text = '',
    this.isRtl = false,
    this.fontFamily = 'PlusJakartaSans',
    this.fontSize = 32,
    this.fontWeight = 400,
    this.lineHeight = 1.4,
    this.textColor = const Color(0xFF0F172A),
    this.textAlign,
    this.textBgColor = const Color(0x00000000),
    this.letterSpacing = 0.0,
    this.textStrokeColor = const Color(0xFF000000),
    this.textStrokeWidth = 0.0,
    this.textShadowColor = const Color(0x80000000),
    this.textShadowBlur = 0.0,
    this.textShadowOffsetX = 0.0,
    this.textShadowOffsetY = 0.0,
    this.localImagePath,
    this.aspectLocked = true,
    this.objectFit = BoxFit.cover,
    this.borderRadius = 0,
    this.shapeKind = 'rect',
    this.shapeStrokeColor = const Color(0xFFF59E0B),
    this.shapeStrokeWidth = 0.0,
    this.flipX = false,
    this.flipY = false,
    FilterSettings? filters,
    this.processedWhiteRemovedBytes,
    this.processedGuillocheBytes,
    this.backgroundRemovedPath,
    this.enhancedPath,
  }) : filters = filters ?? FilterSettings();

  DesignLayer cloneWithNewId(String newId) => DesignLayer(
        id: newId,
        name: '$name Copy',
        type: type,
        x: x + 20,
        y: y + 20,
        width: width,
        height: height,
        rotation: rotation,
        opacity: opacity,
        blendMode: blendMode,
        visible: visible,
        locked: locked,
        isCanvasBackground: false,
        text: text,
        isRtl: isRtl,
        fontFamily: fontFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        lineHeight: lineHeight,
        textColor: textColor,
        textAlign: textAlign,
        textBgColor: textBgColor,
        letterSpacing: letterSpacing,
        textStrokeColor: textStrokeColor,
        textStrokeWidth: textStrokeWidth,
        textShadowColor: textShadowColor,
        textShadowBlur: textShadowBlur,
        textShadowOffsetX: textShadowOffsetX,
        textShadowOffsetY: textShadowOffsetY,
        localImagePath: localImagePath,
        aspectLocked: aspectLocked,
        objectFit: objectFit,
        borderRadius: borderRadius,
        shapeKind: shapeKind,
        shapeStrokeColor: shapeStrokeColor,
        shapeStrokeWidth: shapeStrokeWidth,
        flipX: flipX,
        flipY: flipY,
        filters: filters.copy(),
        processedWhiteRemovedBytes: processedWhiteRemovedBytes,
        processedGuillocheBytes: processedGuillocheBytes,
        backgroundRemovedPath: backgroundRemovedPath,
        enhancedPath: enhancedPath,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'rotation': rotation,
        'opacity': opacity,
        'blendMode': blendMode.index,
        'visible': visible,
        'locked': locked,
        'isCanvasBackground': isCanvasBackground,
        'text': text,
        'isRtl': isRtl,
        'fontFamily': fontFamily,
        'fontSize': fontSize,
        'fontWeight': fontWeight,
        'lineHeight': lineHeight,
        'textColor': textColor.value,
        'textAlign': textAlign?.name,
        'textBgColor': textBgColor.value,
        'letterSpacing': letterSpacing,
        'textStrokeColor': textStrokeColor.value,
        'textStrokeWidth': textStrokeWidth,
        'textShadowColor': textShadowColor.value,
        'textShadowBlur': textShadowBlur,
        'textShadowOffsetX': textShadowOffsetX,
        'textShadowOffsetY': textShadowOffsetY,
        'localImagePath': localImagePath,
        'aspectLocked': aspectLocked,
        'objectFit': objectFit.index,
        'borderRadius': borderRadius,
        'shapeKind': shapeKind,
        'shapeStrokeColor': shapeStrokeColor.value,
        'shapeStrokeWidth': shapeStrokeWidth,
        'flipX': flipX,
        'flipY': flipY,
        'backgroundRemovedPath': backgroundRemovedPath,
        'enhancedPath': enhancedPath,
        'filters': filters.toJson(),
      };

  factory DesignLayer.fromJson(Map<String, dynamic> json) {
    final typeStr = (json['type'] ?? 'text').toString();
    final layerType = LayerType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => LayerType.text,
    );
    final isRtlVal = _asBool(json['isRtl'], json['direction'] == 'rtl');
    final rawFit = json['objectFit'];
    final fitIdx = rawFit is int
        ? rawFit
        : (rawFit is String ? int.tryParse(rawFit.trim()) ?? -1 : -1);
    final fit = fitIdx >= 0
        ? BoxFit.values[fitIdx.clamp(0, BoxFit.values.length - 1)]
        : BoxFit.cover;
    final filtersMap = json['filters'] is Map
        ? Map<String, dynamic>.from(json['filters'] as Map)
        : <String, dynamic>{};

    return DesignLayer(
      id: _asString(json['id'], ''),
      name: _asString(json['name'], 'Layer'),
      type: layerType,
      x: _asDouble(json['x'], 0),
      y: _asDouble(json['y'], 0),
      width: _asDouble(json['width'], 240),
      height: _asDouble(json['height'], 160),
      rotation: _asDouble(json['rotation'], 0),
      opacity: _asDouble(json['opacity'], 1.0),
      blendMode: parseBlendModeAny(json['blendMode']),
      visible: _asBool(json['visible'], true),
      locked: _asBool(json['locked'], false),
      isCanvasBackground: _asBool(json['isCanvasBackground'], false),
      text: _asString(json['text'], ''),
      isRtl: isRtlVal,
      fontFamily: _asString(json['fontFamily'], 'PlusJakartaSans'),
      fontSize: _asDouble(json['fontSize'], 32),
      fontWeight: _asInt(json['fontWeight'], 400),
      lineHeight: _asDouble(json['lineHeight'], 1.4),
      textColor: parseColorAny(
        json['textColor'] ?? json['color'] ?? json['fillColor'],
        const Color(0xFF0F172A),
      ),
      textAlign: json['textAlign'] is String
          ? TextAlign.values.firstWhere(
              (t) => t.name == json['textAlign'],
              orElse: () => isRtlVal ? TextAlign.right : TextAlign.left,
            )
          : null,
      textBgColor: parseColorAny(
        json['textBgColor'] ?? json['backgroundColor'],
        const Color(0x00000000),
      ),
      letterSpacing: _asDouble(json['letterSpacing'], 0.0),
      textStrokeColor: parseColorAny(
        json['textStrokeColor'],
        const Color(0xFF000000),
      ),
      textStrokeWidth: _asDouble(json['textStrokeWidth'], 0.0),
      textShadowColor: parseColorAny(
        json['textShadowColor'],
        const Color(0x80000000),
      ),
      textShadowBlur: _asDouble(json['textShadowBlur'], 0.0),
      textShadowOffsetX: _asDouble(json['textShadowOffsetX'], 0.0),
      textShadowOffsetY: _asDouble(json['textShadowOffsetY'], 0.0),
      localImagePath: json['localImagePath']?.toString(),
      aspectLocked: _asBool(json['aspectLocked'], true),
      objectFit: fit,
      borderRadius: _asDouble(json['borderRadius'], 0),
      shapeKind: _asString(json['shapeKind'], 'rect'),
      shapeStrokeColor: parseColorAny(
        json['shapeStrokeColor'] ?? json['strokeColor'],
        const Color(0xFFF59E0B),
      ),
      shapeStrokeWidth: _asDouble(
        json['shapeStrokeWidth'] ?? json['strokeWidth'],
        0.0,
      ),
      flipX: _asBool(json['flipX'], false),
      flipY: _asBool(json['flipY'], false),
      backgroundRemovedPath: json['backgroundRemovedPath']?.toString(),
      enhancedPath: json['enhancedPath']?.toString(),
      filters: FilterSettings.fromJson(filtersMap),
    );
  }
}

class DocumentPage {
  String id;
  String title;
  double width;
  double height;
  Color backgroundColor;
  List<DesignLayer> layers;

  DocumentPage({
    required this.id,
    required this.title,
    this.width = 900,
    this.height = 1200,
    this.backgroundColor = const Color(0xFFFAF9F6),
    required this.layers,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'width': width,
        'height': height,
        'backgroundColor': backgroundColor.value,
        'layers': layers.map((l) => l.toJson()).toList(),
      };

  factory DocumentPage.fromJson(Map<String, dynamic> json) => DocumentPage(
        id: _asString(json['id'], ''),
        title: _asString(json['title'], ''),
        width: _asDouble(json['width'], 900),
        height: _asDouble(json['height'], 1200),
        backgroundColor: parseColorAny(
          json['backgroundColor'],
          const Color(0xFFFAF9F6),
        ),
        layers: (json['layers'] as List? ?? [])
            .whereType<Map>()
            .map((e) => DesignLayer.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class DesignProject {
  String id;
  String name;
  int updatedAt;
  List<DocumentPage> pages;

  DesignProject({
    required this.id,
    required this.name,
    required this.updatedAt,
    required this.pages,
  });

  String encode() => jsonEncode({
        'id': id,
        'name': name,
        'updatedAt': updatedAt,
        'pages': pages.map((p) => p.toJson()).toList(),
      });

  factory DesignProject.decode(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return DesignProject(
      id: _asString(map['id'], ''),
      name: _asString(map['name'], 'Untitled'),
      updatedAt: _asInt(map['updatedAt'], 0),
      pages: (map['pages'] as List? ?? [])
          .whereType<Map>()
          .map((p) => DocumentPage.fromJson(Map<String, dynamic>.from(p)))
          .toList(),
    );
  }
}

Future<DesignProject> parseImportedProjectBundle(
  String raw, {
  ImportedImageWriter? writeImage,
  int? nowMs,
}) async {
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Invalid JSON object');
  }

  Map<String, dynamic> projMap;
  final embedded = <String, String>{};
  if ((decoded['format'] == 'qalamix_project_v1' ||
          decoded['format'] == ('qalam' '_project_v1')) &&
      decoded['project'] is Map) {
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
    throw const FormatException('Not a Qalamix project file');
  }

  final restoredPaths = <String, String>{};
  if (writeImage != null) {
    for (final entry in embedded.entries) {
      final local = await writeImage(entry.value, 'imp');
      if (local != null) restoredPaths[entry.key] = local;
    }
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
      lRaw.putIfAbsent('id', () => 'l_${pi}_$li');
      lRaw.putIfAbsent('name', () => 'Layer ${li + 1}');
      lRaw.putIfAbsent('x', () => 40);
      lRaw.putIfAbsent('y', () => 40);

      final layer = DesignLayer.fromJson(lRaw);
      String? imgPath = layer.localImagePath;
      if (imgPath != null && restoredPaths.containsKey(imgPath)) {
        imgPath = restoredPaths[imgPath];
      } else if (layer.type == LayerType.image &&
          lRaw['src'] is String &&
          writeImage != null) {
        final src = lRaw['src'] as String;
        if (src.startsWith('data:image')) {
          imgPath = await writeImage(src, 'webimg');
        }
      }
      layer.localImagePath = imgPath;
      layers.add(layer);
    }

    pages.add(DocumentPage(
      id: (pgRaw['id'] ?? 'pg_$pi').toString(),
      title: (pgRaw['title'] ?? 'Page ${pi + 1}').toString(),
      width: _asDouble(pgRaw['width'], 900),
      height: _asDouble(pgRaw['height'], 1200),
      backgroundColor:
          parseColorAny(pgRaw['backgroundColor'], const Color(0xFFFAF9F6)),
      layers: layers,
    ));
  }

  final ts = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  return DesignProject(
    id: 'proj_imp_$ts',
    name: (projMap['name'] ?? 'Imported Project').toString(),
    updatedAt: ts,
    pages: pages,
  );
}
