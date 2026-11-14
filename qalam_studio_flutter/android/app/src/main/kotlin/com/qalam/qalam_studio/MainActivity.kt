package com.qalam.qalam_studio

import android.content.ContentValues
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            if (call.method == "saveImageToGallery") {
                val bytes = call.argument<ByteArray>("bytes")
                val name = call.argument<String>("name") ?: "qalam_export.png"
                if (bytes == null) {
                    result.error("INVALID_ARGS", "Missing image bytes", null)
                    return@setMethodCallHandler
                }
                try {
                    val mime = if (name.endsWith(".jpg", ignoreCase = true) || name.endsWith(".jpeg", ignoreCase = true)) "image/jpeg" else "image/png"
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
            } else {
                result.notImplemented()
            }
        }
    }
}
