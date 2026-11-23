import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import '../models/design_project.dart';
import '../storage/local_project_store.dart';

const int kMaxPdfBytes = 30 * 1024 * 1024;
const int kMaxPdfPages = 15;

Future<DesignProject?> importPdfAsProject(
  BuildContext context,
  MethodChannel mediaChannel,
) async {
  dynamic res;
  try {
    res = await mediaChannel.invokeMethod<dynamic>('pickPdfFile');
  } on PlatformException catch (e) {
    if (context.mounted) {
      final msg = e.code == 'PDF_TOO_LARGE'
          ? 'PDF exceeds 30 MB limit.'
          : 'Could not open PDF file.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
    return null;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open PDF file.')),
      );
    }
    return null;
  }

  if (res is! Map) return null;
  final fileName = (res['name'] ?? 'Document.pdf').toString();
  final rawBytes = res['bytes'];
  if (rawBytes is! Uint8List || rawBytes.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected PDF is empty or unreadable.')),
      );
    }
    return null;
  }
  if (rawBytes.lengthInBytes > kMaxPdfBytes) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF exceeds 30 MB limit.')),
      );
    }
    return null;
  }

  BuildContext? loaderCtx;
  if (context.mounted) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) {
        loaderCtx = dCtx;
        final isDark = Theme.of(dCtx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E222B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.8,
                  color: Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Importing PDF pages...',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1C1917),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void closeLoader() {
    final c = loaderCtx;
    loaderCtx = null;
    if (c != null && c.mounted) {
      Navigator.of(c).pop();
    }
  }

  final writtenPaths = <String>[];
  try {
    final docsDir = await getApplicationDocumentsDirectory();
    final imgDir = Directory(p.join(docsDir.path, 'qalamix_images'));
    if (!imgDir.existsSync()) imgDir.createSync(recursive: true);

    final ts = DateTime.now().millisecondsSinceEpoch;
    final pages = <DocumentPage>[];
    var truncatedOver15 = false;
    var pageNum = 0;

    await for (final raster in Printing.raster(rawBytes, dpi: 120)) {
      if (pageNum >= kMaxPdfPages) {
        truncatedOver15 = true;
        break;
      }
      pageNum++;
      final pngBytes = await raster.toPng();
      if (pngBytes.isEmpty || raster.width <= 0 || raster.height <= 0) {
        throw const FormatException('Empty PDF raster page');
      }
      final outPath = p.join(imgDir.path, 'pdf_${ts}_p$pageNum.png');
      await File(outPath).writeAsBytes(pngBytes, flush: true);
      writtenPaths.add(outPath);

      final w = raster.width.toDouble();
      final h = raster.height.toDouble();
      pages.add(
        DocumentPage(
          id: 'pg_${ts}_$pageNum',
          title: 'Page $pageNum',
          width: w,
          height: h,
          backgroundColor: const Color(0xFFFFFFFF),
          layers: [
            DesignLayer(
              id: 'pdf_bg_${ts}_$pageNum',
              name: 'PDF page $pageNum',
              type: LayerType.image,
              x: 0,
              y: 0,
              width: w,
              height: h,
              locked: true,
              isCanvasBackground: true,
              aspectLocked: false,
              objectFit: BoxFit.cover,
              localImagePath: outPath,
            ),
          ],
        ),
      );
    }

    if (pages.isEmpty) {
      throw const FormatException('PDF has no pages');
    }

    final cleanName = p.basenameWithoutExtension(fileName).trim();
    final projectName = cleanName.isEmpty ? fileName.trim() : cleanName;
    final project = DesignProject(
      id: 'proj_pdf_$ts',
      name: projectName.isEmpty ? 'PDF Document' : projectName,
      updatedAt: ts,
      pages: pages,
    );

    await LocalProjectStore.instance.saveProject(project);
    closeLoader();

    if (truncatedOver15 && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF has more than 15 pages — imported the first 15 pages.')),
      );
    }
    return project;
  } catch (_) {
    for (final fp in writtenPaths) {
      try {
        final f = File(fp);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    closeLoader();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open PDF (password-protected or corrupt file).')),
      );
    }
    return null;
  }
}
