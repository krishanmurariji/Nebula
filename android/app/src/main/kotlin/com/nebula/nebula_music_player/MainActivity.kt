package com.nebula.nebula_music_player

import android.content.ContentUris
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Size
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * Exposes the phone's music library to Flutter ("My Music"):
 *  - list: every music file Android's media library knows (30 s or longer)
 *  - art:  a small JPEG of a song's album art, or null
 * Both run off the main thread. Reading needs READ_MEDIA_AUDIO (Android 13+)
 * or READ_EXTERNAL_STORAGE (older), asked for from Flutter.
 *
 * Extends AudioServiceActivity so background playback keeps sharing the
 * same Flutter engine; the manifest must launch this class, not the
 * plugin's activity, or the channel above never exists.
 */
class MainActivity : AudioServiceActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "noor/local_music")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "list" -> io.execute {
                        val songs = try { listSongs() } catch (e: Exception) { null }
                        main.post {
                            if (songs == null) result.error("query_failed", "Could not read the music library", null)
                            else result.success(songs)
                        }
                    }
                    "art" -> {
                        val id = (call.argument<Number>("id"))?.toLong()
                        if (id == null) { result.success(null); return@setMethodCallHandler }
                        io.execute {
                            val bytes = try { albumArt(id) } catch (e: Exception) { null }
                            main.post { result.success(bytes) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun listSongs(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.DURATION,
        )
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0 AND ${MediaStore.Audio.Media.DURATION} >= 30000"
        contentResolver.query(
            collection, projection, selection, null,
            "${MediaStore.Audio.Media.DATE_ADDED} DESC"
        )?.use { c ->
            val idCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val durCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            while (c.moveToNext() && out.size < 2000) {
                val id = c.getLong(idCol)
                out.add(mapOf(
                    "id" to id,
                    "title" to (c.getString(titleCol) ?: "Unknown"),
                    "artist" to (c.getString(artistCol)?.takeUnless { it == "<unknown>" } ?: ""),
                    "durationMs" to c.getLong(durCol),
                    "uri" to ContentUris.withAppendedId(collection, id).toString(),
                ))
            }
        }
        return out
    }

    private fun albumArt(id: Long): ByteArray? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val uri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
        val bmp = contentResolver.loadThumbnail(uri, Size(320, 320), null)
        val stream = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, 85, stream)
        return stream.toByteArray()
    }
}
