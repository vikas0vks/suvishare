package com.suvishare.suvi_share

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    // Native zero-copy file picking. The file_picker plugin copies every
    // selection into the app cache before returning — a multi-GB video makes
    // that copy slow or fail, and failures drop the file silently. This picker
    // returns SAF content:// URIs immediately; the Dart side streams them with
    // uri_content, so nothing is ever duplicated on disk.
    private var pendingPick: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.suvishare/multicast_lock")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        try {
                            if (multicastLock == null) {
                                val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                                multicastLock = wifi.createMulticastLock("suvi_share").apply {
                                    setReferenceCounted(false)
                                }
                            }
                            if (multicastLock?.isHeld != true) multicastLock?.acquire()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("MULTICAST", e.message, null)
                        }
                    }
                    "release" -> {
                        try {
                            if (multicastLock?.isHeld == true) multicastLock?.release()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("MULTICAST", e.message, null)
                        }
                    }
                    "isHeld" -> result.success(multicastLock?.isHeld == true)
                    // High-performance Wi-Fi lock: keeps the Wi-Fi radio out of
                    // power-save during a transfer. Without it Android throttles
                    // Wi-Fi to save battery and throughput drops sharply.
                    "acquireWifi" -> {
                        try {
                            if (wifiLock == null) {
                                val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                                val mode = if (android.os.Build.VERSION.SDK_INT >= 29) {
                                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                                } else {
                                    @Suppress("DEPRECATION")
                                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                                }
                                wifiLock = wifi.createWifiLock(mode, "suvi_share:transfer").apply {
                                    setReferenceCounted(false)
                                }
                            }
                            if (wifiLock?.isHeld != true) wifiLock?.acquire()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("WIFILOCK", e.message, null)
                        }
                    }
                    "releaseWifi" -> {
                        try {
                            if (wifiLock?.isHeld == true) wifiLock?.release()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("WIFILOCK", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.suvishare/native_picker")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFiles" -> {
                        if (pendingPick != null) {
                            result.error("BUSY", "A pick is already in progress", null)
                            return@setMethodCallHandler
                        }
                        pendingPick = result
                        try {
                            @Suppress("UNCHECKED_CAST")
                            val mimeTypes =
                                (call.argument<List<String>>("mimeTypes") ?: listOf("*/*"))
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = if (mimeTypes.size == 1) mimeTypes[0] else "*/*"
                                if (mimeTypes.size > 1) {
                                    putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
                                }
                                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                            }
                            startActivityForResult(intent, PICK_REQUEST)
                        } catch (e: Exception) {
                            pendingPick = null
                            result.error("PICKER", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.suvishare/open_location")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openDirectory" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.success(false)
                        } else {
                            result.success(openDirectory(path))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openDirectory(path: String): Boolean {
        val root = "/storage/emulated/0"
        val normalized = path.replace('\\', '/').trimEnd('/')
        val documentId = when {
            normalized == root -> "primary:"
            normalized.startsWith("$root/") -> "primary:${normalized.removePrefix("$root/")}"
            else -> return false
        }
        val uri = DocumentsContract.buildDocumentUri(
            "com.android.externalstorage.documents",
            documentId,
        )
        val viewIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, DocumentsContract.Document.MIME_TYPE_DIR)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return try {
            startActivity(viewIntent)
            true
        } catch (_: Exception) {
            try {
                val pickerIntent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    putExtra(DocumentsContract.EXTRA_INITIAL_URI, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(pickerIntent)
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK_REQUEST) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingPick
        pendingPick = null
        if (result == null) return
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        val uris = mutableListOf<Uri>()
        data.clipData?.let { clip ->
            for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
        }
        if (uris.isEmpty()) data.data?.let { uris.add(it) }

        val files = uris.mapNotNull { uri ->
            try {
                contentResolver.takePersistableUriPermission(
                    uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: Exception) {
                // Transient grants still cover this app session.
            }
            try {
                var name: String? = null
                var size: Long = -1
                contentResolver.query(uri, null, null, null, null)?.use { c ->
                    if (c.moveToFirst()) {
                        val n = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (n >= 0) name = c.getString(n)
                        val s = c.getColumnIndex(OpenableColumns.SIZE)
                        if (s >= 0 && !c.isNull(s)) size = c.getLong(s)
                    }
                }
                mapOf(
                    "uri" to uri.toString(),
                    "name" to (name ?: uri.lastPathSegment ?: "file"),
                    "size" to size,
                )
            } catch (_: Exception) {
                null
            }
        }
        result.success(files)
    }

    override fun onDestroy() {
        try {
            if (multicastLock?.isHeld == true) multicastLock?.release()
        } catch (_: Exception) {}
        try {
            if (wifiLock?.isHeld == true) wifiLock?.release()
        } catch (_: Exception) {}
        super.onDestroy()
    }

    companion object {
        private const val PICK_REQUEST = 0x5501
    }
}
