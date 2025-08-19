package com.justpixel.studio


import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.DownloadManager
import android.content.Intent

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.justpixel.studio/downloads"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        val filename = call.argument<String>("filename") ?: "download.bin"
                        val mime = call.argument<String>("mime") ?: "application/octet-stream"
                        val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)

                        try {
                            val resolver = contentResolver
                            val values = ContentValues().apply {
                                put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
                                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                    // Android 10+ : 공용 Downloads
                                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                                    // 대용량 저장 중 외부에서 보이지 않도록
                                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                                }
                            }

                            val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                MediaStore.Downloads.EXTERNAL_CONTENT_URI
                            } else {
                                // Q 미만도 Downloads 컬렉션 사용 (권한 이슈 있을 수 있음)
                                MediaStore.Downloads.EXTERNAL_CONTENT_URI
                            }

                            val uri = resolver.insert(collection, values)
                                ?: throw IllegalStateException("Failed to create new MediaStore record")

                            resolver.openOutputStream(uri)?.use { os ->
                                os.write(bytes)
                                os.flush()
                            }

                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                val done = ContentValues().apply {
                                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                                }
                                resolver.update(uri, done, null, null)
                            }

                            result.success(uri.toString())  // content:// 반환
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }
                    "openDownloads" -> {
                        try {
                            val intent = Intent(DownloadManager.ACTION_VIEW_DOWNLOADS).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OPEN_DL_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
