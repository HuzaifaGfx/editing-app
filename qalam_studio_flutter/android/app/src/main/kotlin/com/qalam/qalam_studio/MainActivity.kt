package com.qalam.qalam_studio

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "com.qalam.studio/media"
    private val pickProjectReq = 9042
    private var pendingPickResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveImageToGallery" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val name = call.argument<String>("name") ?: "qalam_export.png"
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
                                put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/QalamStudio")
                                put(MediaStore.Images.Media.IS_PENDING, 1)
                            }
                            val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                                ?: throw Exception("MediaStore insert failed")
                            contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                            values.clear()
                            values.put(MediaStore.Images.Media.IS_PENDING, 0)
                            contentResolver.update(uri, values, null, null)
                            result.success("Pictures/QalamStudio/$name")
                        } else {
                            val outDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "QalamStudio")
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
                    val name = call.argument<String>("name") ?: "qalam_scan.pdf"
                    if (bytes == null) {
                        result.error("INVALID_ARGS", "Missing PDF bytes", null)
                        return@setMethodCallHandler
                    }
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val values = ContentValues().apply {
                                put(MediaStore.Downloads.DISPLAY_NAME, name)
                                put(MediaStore.Downloads.MIME_TYPE, "application/pdf")
                                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/QalamStudio")
                                put(MediaStore.Downloads.IS_PENDING, 1)
                            }
                            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                                ?: throw Exception("MediaStore PDF insert failed")
                            contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                            values.clear()
                            values.put(MediaStore.Downloads.IS_PENDING, 0)
                            contentResolver.update(uri, values, null, null)
                            result.success("Downloads/QalamStudio/$name")
                        } else {
                            val outDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "QalamStudio")
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
        }
    }
}
