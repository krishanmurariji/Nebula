package com.noor.music

import android.app.SearchManager
import android.content.ContentUris
import android.content.Intent
import android.os.Bundle
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
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

    /// What Noor was asked to play when it was opened: a voice request
    /// ("play X on Noor" sends MEDIA_PLAY_FROM_SEARCH) or a home-screen
    /// shortcut (noor://play?q=..., noor://resume). Flutter takes it once.
    private var pendingPlay: String? = null
    private var launch: MethodChannel? = null

    private fun playRequestOf(intent: Intent?): String? {
        if (intent == null) return null
        if (intent.action == MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH) {
            return intent.getStringExtra(SearchManager.QUERY) ?: ""
        }
        val data = intent.data ?: return null
        if (data.scheme != "noor") return null
        return when (data.host) {
            "resume" -> ""
            "play" -> data.getQueryParameter("q") ?: ""
            else -> null
        }
    }

    /// How Noor was opened, for the playback log (which app asked, and how).
    private var openedBy: String = ""

    private fun describe(intent: Intent?): String {
        if (intent == null) return "no intent"
        val keys = intent.extras?.keySet()?.joinToString(",") ?: ""
        return "action=${intent.action} data=${intent.data} from=${referrer?.host} extras=[$keys]"
    }

    // Coming back to the front while already running: Gemini's "open Noor",
    // the app icon or the recents screen only bring the app forward, with no
    // new intent. onResume tells Flutter, which plays if "Play when Noor
    // opens" is on (an explicit request in onNewIntent wins instead).
    private var stoppedAt = 0L
    private var returning = false
    private var askedOnReturn = false

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingPlay = playRequestOf(intent)
        openedBy = describe(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        openedBy = describe(intent)
        val q = playRequestOf(intent) ?: return
        askedOnReturn = true
        // Already running: hand it straight to Flutter.
        launch?.invokeMethod("play", q) ?: run { pendingPlay = q }
    }

    override fun onStop() {
        super.onStop()
        stoppedAt = SystemClock.elapsedRealtime()
    }

    override fun onRestart() {
        super.onRestart()
        returning = true
    }

    override fun onResume() {
        super.onResume()
        if (returning && !askedOnReturn) {
            val away = (SystemClock.elapsedRealtime() - stoppedAt) / 1000
            launch?.invokeMethod("opened", mapOf("away" to away, "how" to openedBy))
        }
        returning = false
        askedOnReturn = false
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "noor/launch").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "take" -> { result.success(pendingPlay); pendingPlay = null }
                    "how" -> result.success(openedBy)
                    else -> result.notImplemented()
                }
            }
        }
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
