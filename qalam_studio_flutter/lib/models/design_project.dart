import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/painting.dart';

enum LayerType { text, image, shape }

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
  double guillocheBend;     // 0..6 (px contour bend, default 3)
  double guillocheOpacity;  // 75..100 (% skin opacity over paper, default 88)
  String guillochePattern;  // 'banknote' | 'rosette' | 'mesh'
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
        brightness: (json['brightness'] ?? 1.0).toDouble(),
        contrast: (json['contrast'] ?? 1.0).toDouble(),
        saturate: (json['saturate'] ?? 1.0).toDouble(),
        sepia: (json['sepia'] ?? 0.0).toDouble(),
        grayscale: (json['grayscale'] ?? 0.0).toDouble(),
        removeWhite: (json['removeWhite'] ?? 0.0).toDouble(),
        blackAndWhite: json['blackAndWhite'] ?? false,
        guilloche: json['guilloche'] ?? false,
        guillocheContrast: (json['guillocheContrast'] ?? 13.0).toDouble(),
        guillocheBend: (json['guillocheBend'] ?? 3.0).toDouble(),
        guillocheOpacity: (json['guillocheOpacity'] ?? 88.0).toDouble(),
        guillochePattern: (json['guillochePattern'] ?? 'banknote').toString(),
        softGlow: (json['softGlow'] ?? 0.0).toDouble(),
        rosyTint: (json['rosyTint'] ?? 0.0).toDouble(),
        skinSmooth: (json['skinSmooth'] ?? 0.0).toDouble(),
        portraitBlur: (json['portraitBlur'] ?? 0.0).toDouble(),
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
        'localImagePath': localImagePath,
        'aspectLocked': aspectLocked,
        'objectFit': objectFit.index,
        'borderRadius': borderRadius,
        'shapeKind': shapeKind,
        'shapeStrokeColor': shapeStrokeColor.value,
        'shapeStrokeWidth': shapeStrokeWidth,
        'flipX': flipX,
        'flipY': flipY,
        'filters': filters.toJson(),
      };

  factory DesignLayer.fromJson(Map<String, dynamic> json) => DesignLayer(
        id: json['id'],
        name: json['name'],
        type: LayerType.values.byName(json['type']),
        x: (json['x'] ?? 0).toDouble(),
        y: (json['y'] ?? 0).toDouble(),
        width: (json['width'] ?? 240).toDouble(),
        height: (json['height'] ?? 160).toDouble(),
        rotation: (json['rotation'] ?? 0).toDouble(),
        opacity: (json['opacity'] ?? 1.0).toDouble(),
        blendMode: BlendMode.values[json['blendMode'] ?? BlendMode.srcOver.index],
        visible: json['visible'] ?? true,
        locked: json['locked'] ?? false,
        isCanvasBackground: json['isCanvasBackground'] ?? false,
        text: json['text'] ?? '',
        isRtl: json['isRtl'] ?? false,
        fontFamily: json['fontFamily'] ?? 'PlusJakartaSans',
        fontSize: (json['fontSize'] ?? 32).toDouble(),
        fontWeight: (json['fontWeight'] ?? 400).toInt(),
        lineHeight: (json['lineHeight'] ?? 1.4).toDouble(),
        textColor: Color(json['textColor'] ?? 0xFF0F172A),
        textAlign: json['textAlign'] != null
            ? TextAlign.values.firstWhere(
                (t) => t.name == json['textAlign'],
                orElse: () => (json['isRtl'] ?? false) ? TextAlign.right : TextAlign.left,
              )
            : null,
        textBgColor: Color(json['textBgColor'] ?? 0x00000000),
        localImagePath: json['localImagePath'],
        aspectLocked: json['aspectLocked'] ?? true,
        objectFit: BoxFit.values[json['objectFit'] ?? BoxFit.cover.index],
        borderRadius: (json['borderRadius'] ?? 0).toDouble(),
        shapeKind: (json['shapeKind'] ?? 'rect').toString(),
        shapeStrokeColor: Color(json['shapeStrokeColor'] ?? 0xFFF59E0B),
        shapeStrokeWidth: (json['shapeStrokeWidth'] ?? 0.0).toDouble(),
        flipX: json['flipX'] ?? false,
        flipY: json['flipY'] ?? false,
        filters: FilterSettings.fromJson(json['filters'] ?? {}),
      );
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
        id: json['id'],
        title: json['title'],
        width: (json['width'] ?? 900).toDouble(),
        height: (json['height'] ?? 1200).toDouble(),
        backgroundColor: Color(json['backgroundColor'] ?? 0xFFFAF9F6),
        layers: (json['layers'] as List? ?? [])
            .map((e) => DesignLayer.fromJson(e))
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
      id: map['id'],
      name: map['name'],
      updatedAt: map['updatedAt'] ?? 0,
      pages: (map['pages'] as List? ?? [])
          .map((p) => DocumentPage.fromJson(p))
          .toList(),
    );
  }
}
