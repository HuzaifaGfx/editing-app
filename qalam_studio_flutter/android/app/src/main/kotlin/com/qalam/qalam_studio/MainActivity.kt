package com.qalam.qalam_studio

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "com.qalam.studio/media"
    private val pickProjectReq = 9042
    private val pickFontReq = 9043
    private val pickPdfReq = 9044
    private var pendingPickResult: MethodChannel.Result? = null
    private var pendingFontResult: MethodChannel.Result? = null
    private var pendingPdfResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveImageToGallery" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val name = call.argument<String>("name") ?: "qalamix_export.png"
                    if (bytes == null) {
                        result.error("INVALID_ARGS", "Missing image bytes", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val mime = if (name.endsWith(".jpg", ignoreCase = true) || name.endsWith(".jpeg", ignoreCase = true)) {
                            "image/jpeg"
                        } else {
                            "image/png"
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val values = ContentValues().apply {
                                put(MediaStore.Images.Media.DISPLAY_NAME, name)
                                put(MediaStore.Images.Media.MIME_TYPE, mime)
                                put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Qalamix")
                                put(MediaStore.Images.Media.IS_PENDING, 1)
                            }
                            val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                                ?: throw Exception("MediaStore insert failed")
                            contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                            values.clear()
                            values.put(MediaStore.Images.Media.IS_PENDING, 0)
                            contentResolver.update(uri, values, null, null)
                            result.success("Pictures/Qalamix/$name")
                        } else {
                            val outDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "Qalamix")
                            if (!outDir.exists()) outDir.mkdirs()
                            val outFile = File(outDir, name)
                            FileOutputStream(outFile).use { it.write(bytes) }
                            MediaScannerConnection.scanFile(this, arrayOf(outFile.absolutePath), arrayOf(mime), null)
                            result.success(outFile.absolutePath)
                        }
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.message, null)
                    }
                }
                "savePdfToDownloads" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val name = call.argument<String>("name") ?: "qalamix_scan.pdf"
                    if (bytes == null) {
                        result.error("INVALID_ARGS", "Missing PDF bytes", null)
                        return@setMethodCallHandler
                    }
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val values = ContentValues().apply {
                                put(MediaStore.Downloads.DISPLAY_NAME, name)
                                put(MediaStore.Downloads.MIME_TYPE, "application/pdf")
                                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/Qalamix")
                                put(MediaStore.Downloads.IS_PENDING, 1)
                            }
                            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                                ?: throw Exception("MediaStore PDF insert failed")
                            contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                            values.clear()
                            values.put(MediaStore.Downloads.IS_PENDING, 0)
                            contentResolver.update(uri, values, null, null)
                            result.success("Downloads/Qalamix/$name")
                        } else {
                            val outDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "Qalamix")
                            if (!outDir.exists()) outDir.mkdirs()
                            val outFile = File(outDir, name)
                            FileOutputStream(outFile).use { it.write(bytes) }
                            MediaScannerConnection.scanFile(this, arrayOf(outFile.absolutePath), arrayOf("application/pdf"), null)
                            result.success(outFile.absolutePath)
                        }
                    } catch (e: Exception) {
                        result.error("SAVE_PDF_FAILED", e.message, null)
                    }
                }
                "saveFontToDownloads" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val name = call.argument<String>("name") ?: "font.ttf"
                    if (bytes == null) {
                        result.error("INVALID_ARGS", "Missing font bytes", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val mime = if (name.endsWith(".otf", ignoreCase = true)) "font/otf" else "font/ttf"
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val values = ContentValues().apply {
                                put(MediaStore.Downloads.DISPLAY_NAME, name)
                                put(MediaStore.Downloads.MIME_TYPE, mime)
                                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/Qalamix/Fonts")
                                put(MediaStore.Downloads.IS_PENDING, 1)
                            }
                            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                                ?: throw Exception("MediaStore font insert failed")
                            contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                            values.clear()
                            values.put(MediaStore.Downloads.IS_PENDING, 0)
                            contentResolver.update(uri, values, null, null)
                            result.success("Downloads/Qalamix/Fonts/$name")
                        } else {
                            val outDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "Qalamix/Fonts")
                            if (!outDir.exists()) outDir.mkdirs()
                            val outFile = File(outDir, name)
                            FileOutputStream(outFile).use { it.write(bytes) }
                            result.success(outFile.absolutePath)
                        }
                    } catch (e: Exception) {
                        result.error("SAVE_FONT_FAILED", e.message, null)
                    }
                }
                "pickProjectFile" -> {
                    if (pendingPickResult != null) {
                        result.error("BUSY", "File picker already open", null)
                        return@setMethodCallHandler
                    }
                    pendingPickResult = result
                    try {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                        }
                        startActivityForResult(intent, pickProjectReq)
                    } catch (e: Exception) {
                        pendingPickResult = null
                        result.error("PICK_FAILED", e.message, null)
                    }
                }
                "pickFontFile" -> {
                    if (pendingFontResult != null) {
                        result.error("BUSY", "Font picker already open", null)
                        return@setMethodCallHandler
                    }
                    pendingFontResult = result
                    try {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                        }
                        startActivityForResult(intent, pickFontReq)
                    } catch (e: Exception) {
                        pendingFontResult = null
                        result.error("PICK_FONT_FAILED", e.message, null)
                    }
                }
                "pickPdfFile" -> {
                    if (pendingPdfResult != null) {
                        result.error("BUSY", "PDF picker already open", null)
                        return@setMethodCallHandler
                    }
                    pendingPdfResult = result
                    try {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/pdf"
                        }
                        startActivityForResult(intent, pickPdfReq)
                    } catch (e: Exception) {
                        pendingPdfResult = null
                        result.error("PICK_PDF_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == pickProjectReq) {
            val res = pendingPickResult
            pendingPickResult = null
            if (res == null) return
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                res.success(null)
                return
            }
            try {
                val uri = data.data!!
                val text = contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
                res.success(text)
            } catch (e: Exception) {
                res.error("READ_FAILED", e.message, null)
            }
        } else if (requestCode == pickFontReq) {
            val res = pendingFontResult
            pendingFontResult = null
            if (res == null) return
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                res.success(null)
                return
            }
            try {
                val uri = data.data!!
                var displayName = "CustomFont.ttf"
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (idx >= 0) displayName = cursor.getString(idx) ?: displayName
                    }
                }
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                if (bytes == null || bytes.isEmpty()) {
                    res.success(null)
                    return
                }
                res.success(mapOf("name" to displayName, "bytes" to bytes))
            } catch (e: Exception) {
                res.error("READ_FONT_FAILED", e.message, null)
            }
        } else if (requestCode == pickPdfReq) {
            val res = pendingPdfResult
            pendingPdfResult = null
            if (res == null) return
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                res.success(null)
                return
            }
            try {
                val uri = data.data!!
                var displayName = "Document.pdf"
                var fileSize = -1L
                contentResolver.query(
                    uri,
                    arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                    null,
                    null,
                    null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (nameIdx >= 0) displayName = cursor.getString(nameIdx) ?: displayName
                        val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                        if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) {
                            fileSize = cursor.getLong(sizeIdx)
                        }
                    }
                }
                val maxBytes = 30L * 1024L * 1024L
                if (fileSize > maxBytes) {
                    res.error("PDF_TOO_LARGE", "PDF exceeds 30 MB limit", null)
                    return
                }
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                if (bytes == null || bytes.isEmpty()) {
                    res.success(null)
                    return
                }
                if (bytes.size.toLong() > maxBytes) {
                    res.error("PDF_TOO_LARGE", "PDF exceeds 30 MB limit", null)
                    return
                }
                res.success(mapOf("name" to displayName, "bytes" to bytes))
            } catch (e: Exception) {
                res.error("READ_PDF_FAILED", e.message, null)
            }
        }
    }
}
