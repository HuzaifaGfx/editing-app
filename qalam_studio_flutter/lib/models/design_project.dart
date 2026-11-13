import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
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

  FilterSettings({
    this.brightness = 1.0,
    this.contrast = 1.0,
    this.saturate = 1.0,
    this.sepia = 0.0,
    this.grayscale = 0.0,
    this.removeWhite = 0.0,
    this.blackAndWhite = false,
  });

  FilterSettings copy() => FilterSettings(
        brightness: brightness,
        contrast: contrast,
        saturate: saturate,
        sepia: sepia,
        grayscale: grayscale,
        removeWhite: removeWhite,
        blackAndWhite: blackAndWhite,
      );

  Map<String, dynamic> toJson() => {
        'brightness': brightness,
        'contrast': contrast,
        'saturate': saturate,
        'sepia': sepia,
        'grayscale': grayscale,
        'removeWhite': removeWhite,
        'blackAndWhite': blackAndWhite,
      };

  factory FilterSettings.fromJson(Map<String, dynamic> json) => FilterSettings(
        brightness: (json['brightness'] ?? 1.0).toDouble(),
        contrast: (json['contrast'] ?? 1.0).toDouble(),
        saturate: (json['saturate'] ?? 1.0).toDouble(),
        sepia: (json['sepia'] ?? 0.0).toDouble(),
        grayscale: (json['grayscale'] ?? 0.0).toDouble(),
        removeWhite: (json['removeWhite'] ?? 0.0).toDouble(),
        blackAndWhite: json['blackAndWhite'] ?? false,
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

  // Text properties (Urdu & English)
  String text;
  bool isRtl;
  String fontFamily;
  double fontSize;
  double lineHeight;
  Color textColor;

  // Image overlay properties
  String? localImagePath;
  bool aspectLocked;
  BoxFit objectFit;
  double borderRadius;
  FilterSettings filters;

  // Runtime cache for white-removed PNG bytes
  Uint8List? processedWhiteRemovedBytes;

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
    this.text = '',
    this.isRtl = false,
    this.fontFamily = 'PlusJakartaSans',
    this.fontSize = 32,
    this.lineHeight = 1.4,
    this.textColor = const Color(0xFFFFFFFF),
    this.localImagePath,
    this.aspectLocked = true,
    this.objectFit = BoxFit.cover,
    this.borderRadius = 0,
    FilterSettings? filters,
    this.processedWhiteRemovedBytes,
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
        text: text,
        isRtl: isRtl,
        fontFamily: fontFamily,
        fontSize: fontSize,
        lineHeight: lineHeight,
        textColor: textColor,
        localImagePath: localImagePath,
        aspectLocked: aspectLocked,
        objectFit: objectFit,
        borderRadius: borderRadius,
        filters: filters.copy(),
        processedWhiteRemovedBytes: processedWhiteRemovedBytes,
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
        'text': text,
        'isRtl': isRtl,
        'fontFamily': fontFamily,
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'textColor': textColor.value,
        'localImagePath': localImagePath,
        'aspectLocked': aspectLocked,
        'objectFit': objectFit.index,
        'borderRadius': borderRadius,
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
        text: json['text'] ?? '',
        isRtl: json['isRtl'] ?? false,
        fontFamily: json['fontFamily'] ?? 'PlusJakartaSans',
        fontSize: (json['fontSize'] ?? 32).toDouble(),
        lineHeight: (json['lineHeight'] ?? 1.4).toDouble(),
        textColor: Color(json['textColor'] ?? 0xFFFFFFFF),
        localImagePath: json['localImagePath'],
        aspectLocked: json['aspectLocked'] ?? true,
        objectFit: BoxFit.values[json['objectFit'] ?? BoxFit.cover.index],
        borderRadius: (json['borderRadius'] ?? 0).toDouble(),
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
    this.backgroundColor = const Color(0xFF191C22),
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
        backgroundColor: Color(json['backgroundColor'] ?? 0xFF191C22),
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
