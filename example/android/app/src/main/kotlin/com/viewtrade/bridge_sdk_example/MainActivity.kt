package com.viewtrade.bridge_sdk_example

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Implements Bridge SDK download channel (`bridge_flutter_sdk/downloads`)
 * so blob/PDF downloads land in the public Downloads folder.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bridge_flutter_sdk/downloads",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToDownloads" -> try {
                    saveToDownloads(
                        call.argument<ByteArray>("bytes")!!,
                        call.argument<String>("fileName")!!,
                        call.argument<String>("mimeType") ?: "application/octet-stream",
                    )
                    result.success(null)
                } catch (e: Exception) {
                    result.error("save_failed", e.message, null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun saveToDownloads(bytes: ByteArray, fileName: String, mimeType: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("could not create the file in Downloads")
            contentResolver.openOutputStream(uri)!!.use { it.write(bytes) }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
        } else {
            @Suppress("DEPRECATION")
            val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            dir.mkdirs()
            FileOutputStream(File(dir, fileName)).use { it.write(bytes) }
        }
    }
}
