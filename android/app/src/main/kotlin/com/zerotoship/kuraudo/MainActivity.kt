package com.zerotoship.kuraudo

import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.view.autofill.AutofillManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val AUTOFILL_CHANNEL = "com.zerotoship.kuraudo/autofill"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUTOFILL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAutofillEnabled" -> {
                        result.success(isAutofillEnabled())
                    }
                    "openAutofillSettings" -> {
                        openAutofillSettings()
                        result.success(null)
                    }
                    "updateEntries" -> {
                        val entries = call.argument<List<Map<String, Any?>>>("entries")
                        if (entries != null) {
                            updateCachedEntries(entries)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }

    private fun isAutofillEnabled(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val afm = getSystemService(AutofillManager::class.java) ?: return false
        return afm.hasEnabledAutofillServices()
    }

    private fun openAutofillSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val intent = Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE)
            intent.data = android.net.Uri.parse("package:$packageName")
            try {
                startActivity(intent)
            } catch (e: Exception) {
                startActivity(Intent(Settings.ACTION_SETTINGS))
            }
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun updateCachedEntries(entries: List<Map<String, Any?>>) {
        KuraudoAutofillService.cachedEntries = entries.map { map ->
            AutofillEntry(
                uuid = map["uuid"] as? String ?: "",
                title = map["title"] as? String ?: "",
                username = map["username"] as? String ?: "",
                password = map["password"] as? String ?: "",
                email = map["email"] as? String ?: "",
                url = map["url"] as? String ?: "",
            )
        }
    }
}
