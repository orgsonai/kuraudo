package com.zerotoship.kuraudo

import android.app.assist.AssistStructure
import android.os.Build
import android.os.CancellationSignal
import android.service.autofill.*
import android.view.autofill.AutofillId
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import androidx.annotation.RequiresApi

data class AutofillEntry(
    val uuid: String,
    val title: String,
    val username: String,
    val password: String,
    val email: String,
    val url: String,
)

data class ParsedFields(
    val usernameId: AutofillId? = null,
    val passwordId: AutofillId? = null,
    val emailId: AutofillId? = null,
    val webDomain: String? = null,
)

@RequiresApi(Build.VERSION_CODES.O)
class KuraudoAutofillService : AutofillService() {

    companion object {
        @Volatile
        var cachedEntries: List<AutofillEntry> = emptyList()
    }

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback
    ) {
        val structure = request.fillContexts.lastOrNull()?.structure ?: run {
            callback.onSuccess(null)
            return
        }

        val fields = parseStructure(structure)
        if (fields.usernameId == null && fields.passwordId == null) {
            callback.onSuccess(null)
            return
        }

        val packageName = structure.activityComponent?.packageName ?: ""
        val webDomain = fields.webDomain ?: ""

        val matchingEntries = findMatches(packageName, webDomain)
        if (matchingEntries.isEmpty()) {
            callback.onSuccess(null)
            return
        }

        val responseBuilder = FillResponse.Builder()
        for (entry in matchingEntries.take(5)) {
            val presentation = RemoteViews(getPackageName(), android.R.layout.simple_list_item_1)
            presentation.setTextViewText(android.R.id.text1, "${entry.title} (${entry.username})")

            val datasetBuilder = Dataset.Builder()
            fields.usernameId?.let {
                datasetBuilder.setValue(it, AutofillValue.forText(entry.username), presentation)
            }
            fields.passwordId?.let {
                datasetBuilder.setValue(it, AutofillValue.forText(entry.password), presentation)
            }
            fields.emailId?.let {
                if (entry.email.isNotEmpty()) {
                    datasetBuilder.setValue(it, AutofillValue.forText(entry.email), presentation)
                }
            }
            responseBuilder.addDataset(datasetBuilder.build())
        }

        callback.onSuccess(responseBuilder.build())
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        callback.onSuccess()
    }

    private fun parseStructure(structure: AssistStructure): ParsedFields {
        var usernameId: AutofillId? = null
        var passwordId: AutofillId? = null
        var emailId: AutofillId? = null
        var webDomain: String? = null

        for (i in 0 until structure.windowNodeCount) {
            val windowNode = structure.getWindowNodeAt(i)
            traverseNode(windowNode.rootViewNode) { node ->
                val hints = node.autofillHints
                val inputType = node.inputType
                val htmlInfo = node.htmlInfo

                webDomain = webDomain ?: node.webDomain

                if (hints != null) {
                    for (hint in hints) {
                        when {
                            hint.contains("username", true) || hint.contains("login", true) ->
                                usernameId = usernameId ?: node.autofillId
                            hint.contains("password", true) ->
                                passwordId = passwordId ?: node.autofillId
                            hint.contains("email", true) ->
                                emailId = emailId ?: node.autofillId
                        }
                    }
                }

                if (usernameId == null || passwordId == null) {
                    val htmlType = htmlInfo?.attributes
                        ?.firstOrNull { it.first == "type" }?.second ?: ""
                    val htmlName = htmlInfo?.attributes
                        ?.firstOrNull { it.first == "name" }?.second ?: ""

                    when {
                        htmlType == "password" -> passwordId = passwordId ?: node.autofillId
                        htmlType == "email" -> emailId = emailId ?: node.autofillId
                        htmlType == "text" && (htmlName.contains("user", true) || htmlName.contains("login", true)) ->
                            usernameId = usernameId ?: node.autofillId
                    }
                }
            }
        }

        return ParsedFields(usernameId, passwordId, emailId, webDomain)
    }

    private fun traverseNode(node: AssistStructure.ViewNode, action: (AssistStructure.ViewNode) -> Unit) {
        action(node)
        for (i in 0 until node.childCount) {
            traverseNode(node.getChildAt(i), action)
        }
    }

    private fun findMatches(packageName: String, webDomain: String): List<AutofillEntry> {
        if (cachedEntries.isEmpty()) return emptyList()
        val domain = webDomain.lowercase().removePrefix("www.")

        return cachedEntries.filter { entry ->
            if (domain.isNotEmpty() && entry.url.isNotEmpty()) {
                val entryDomain = try {
                    java.net.URI(entry.url).host?.lowercase()?.removePrefix("www.") ?: ""
                } catch (_: Exception) { entry.url.lowercase() }
                entryDomain.contains(domain) || domain.contains(entryDomain)
            } else if (packageName.isNotEmpty()) {
                entry.title.lowercase().contains(packageName.split(".").lastOrNull()?.lowercase() ?: "")
            } else false
        }.take(5)
    }
}
