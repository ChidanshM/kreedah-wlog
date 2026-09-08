package com.kreedah.workout_log

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Storage Access Framework bridge.
 *
 * Exports were previously written to the app's own external directory, which
 * scoped storage makes unreachable from a file manager on Android 11 and
 * later — the files existed but could not be retrieved. This lets the user
 * pick any folder once. The grant is persisted, so later exports go there
 * without asking again, and it survives a restart.
 *
 * Written against the platform APIs rather than through a plugin. They have
 * been stable since Android 5 and it keeps the dependency list at three.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "wlog/storage"
    private val pickRequest = 4711
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "pickFolder" -> pickFolder(result)
                "writeFile" -> writeFile(call, result)
                "listFiles" -> listFiles(call, result)
                "readFile" -> readFile(call, result)
                "folderName" -> result.success(
                    folderName(Uri.parse(call.argument<String>("tree")!!))
                )
                "hasAccess" -> result.success(hasAccess(call.argument<String>("tree")))
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("storage_error", e.message ?: e.toString(), null)
        }
    }

    // --------------------------------------------------------------- picking

    private fun pickFolder(result: MethodChannel.Result) {
        pending = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        startActivityForResult(intent, pickRequest)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickRequest) return
        val result = pending ?: return
        pending = null

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        // Without this the grant dies with the activity and the folder is
        // forgotten the next time the app starts.
        contentResolver.takePersistableUriPermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        )
        result.success(uri.toString())
    }

    private fun hasAccess(tree: String?): Boolean {
        if (tree.isNullOrEmpty()) return false
        return contentResolver.persistedUriPermissions.any {
            it.uri.toString() == tree && it.isWritePermission
        }
    }

    // ----------------------------------------------------------------- files

    private fun dirUri(tree: Uri): Uri = DocumentsContract.buildDocumentUriUsingTree(
        tree, DocumentsContract.getTreeDocumentId(tree)
    )

    private fun writeFile(call: MethodCall, result: MethodChannel.Result) {
        val tree = Uri.parse(call.argument<String>("tree")!!)
        val name = call.argument<String>("name")!!
        val mime = call.argument<String>("mime") ?: "application/octet-stream"
        val content = call.argument<String>("content")!!

        val file = DocumentsContract.createDocument(contentResolver, dirUri(tree), mime, name)
            ?: throw IllegalStateException("Could not create $name in the chosen folder")

        contentResolver.openOutputStream(file)?.use { it.write(content.toByteArray()) }
            ?: throw IllegalStateException("Could not write $name")

        result.success(file.toString())
    }

    private fun listFiles(call: MethodCall, result: MethodChannel.Result) {
        val tree = Uri.parse(call.argument<String>("tree")!!)
        val suffix = call.argument<String>("suffix") ?: ""
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree, DocumentsContract.getTreeDocumentId(tree)
        )
        val out = ArrayList<Map<String, String>>()
        contentResolver.query(
            children,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME
            ),
            null, null, null
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getString(0) ?: continue
                val name = cursor.getString(1) ?: continue
                if (suffix.isEmpty() || name.endsWith(suffix)) {
                    out.add(
                        mapOf(
                            "name" to name,
                            "uri" to DocumentsContract
                                .buildDocumentUriUsingTree(tree, id).toString()
                        )
                    )
                }
            }
        }
        out.sortByDescending { it["name"] }
        result.success(out)
    }

    private fun readFile(call: MethodCall, result: MethodChannel.Result) {
        val uri = Uri.parse(call.argument<String>("uri")!!)
        val text = contentResolver.openInputStream(uri)
            ?.use { it.readBytes().toString(Charsets.UTF_8) }
            ?: throw IllegalStateException("Could not read that file")
        result.success(text)
    }

    /** The trailing part of the tree id, which is what a person recognises. */
    private fun folderName(tree: Uri): String {
        val id = DocumentsContract.getTreeDocumentId(tree)
        val tail = id.substringAfterLast(':')
        return if (tail.isEmpty()) id else tail
    }
}
