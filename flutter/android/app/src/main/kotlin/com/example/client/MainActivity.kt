package com.example.client

import android.Manifest
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.telephony.SmsManager
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val SMS_CHANNEL = "buildpro/sms"
        private const val REQ_SEND_SMS = 4102
    }

    private var pendingPhone: String? = null
    private var pendingBody: String? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "sendSms") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val phone = (call.argument<String>("phone") ?: "").trim()
                val body = (call.argument<String>("body") ?: "").trim()
                if (phone.isEmpty() || body.isEmpty()) {
                    result.success("skipped")
                    return@setMethodCallHandler
                }
                handleSendSms(phone, body, result)
            }
    }

    private fun handleSendSms(phone: String, body: String, result: MethodChannel.Result) {
        val hasSms = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.SEND_SMS,
        ) == PackageManager.PERMISSION_GRANTED
        val hasPhoneState = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.READ_PHONE_STATE,
        ) == PackageManager.PERMISSION_GRANTED

        if (hasSms && hasPhoneState) {
            dispatchSms(phone, body, result)
            return
        }

        // Request both SEND_SMS and READ_PHONE_STATE (for Dual-SIM picker) together once.
        pendingPhone = phone
        pendingBody = body
        pendingResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.SEND_SMS, Manifest.permission.READ_PHONE_STATE),
            REQ_SEND_SMS,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_SEND_SMS) return
        val phone = pendingPhone
        val body = pendingBody
        val result = pendingResult
        pendingPhone = null
        pendingBody = null
        pendingResult = null
        if (phone == null || body == null || result == null) return

        val hasSms = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.SEND_SMS,
        ) == PackageManager.PERMISSION_GRANTED
        if (hasSms) {
            dispatchSms(phone, body, result)
        } else {
            result.success(openSmsComposer(phone, body))
        }
    }

    private fun dispatchSms(phone: String, body: String, result: MethodChannel.Result) {
        val sims = activeSims()
        if (sims.size <= 1) {
            val subId = sims.firstOrNull()?.subscriptionId
            result.success(sendDirectOrComposer(phone, body, subId))
            return
        }

        // Dual-SIM phone: let the checker tap which SIM (with load) should send the SMS.
        val labels = sims.mapIndexed { idx, info ->
            val slot = info.simSlotIndex + 1
            val carrier = info.carrierName?.toString()?.trim().orEmpty()
            val display = info.displayName?.toString()?.trim().orEmpty()
            val name = when {
                carrier.isNotEmpty() -> carrier
                display.isNotEmpty() -> display
                else -> "SIM ${idx + 1}"
            }
            "SIM $slot — $name"
        }.toTypedArray()

        runOnUiThread {
            AlertDialog.Builder(this)
                .setTitle("Choose SIM for offline SMS")
                .setItems(labels) { _, which ->
                    val chosen = sims[which]
                    result.success(sendDirectOrComposer(phone, body, chosen.subscriptionId))
                }
                .setNegativeButton("Open Messages app") { _, _ ->
                    result.success(openSmsComposer(phone, body))
                }
                .setOnCancelListener {
                    result.success("skipped")
                }
                .show()
        }
    }

    private fun activeSims(): List<SubscriptionInfo> {
        val hasPhoneState = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.READ_PHONE_STATE,
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasPhoneState) return emptyList()
        return try {
            val subManager = applicationContext.getSystemService(SubscriptionManager::class.java)
            subManager?.activeSubscriptionInfoList?.sortedBy { it.simSlotIndex } ?: emptyList()
        } catch (_: Throwable) {
            emptyList()
        }
    }

    private fun sendDirectOrComposer(phone: String, body: String, subscriptionId: Int?): String {
        return try {
            val manager = smsManagerFor(subscriptionId)
            if (manager == null) {
                openSmsComposer(phone, body)
            } else {
                manager.sendTextMessage(phone, null, body, null, null)
                "sent"
            }
        } catch (_: Throwable) {
            openSmsComposer(phone, body)
        }
    }

    private fun smsManagerFor(subscriptionId: Int?): SmsManager? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val base = applicationContext.getSystemService(SmsManager::class.java) ?: return null
            if (subscriptionId != null) base.createForSubscriptionId(subscriptionId) else base
        } else {
            @Suppress("DEPRECATION")
            if (subscriptionId != null) {
                SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
            } else {
                SmsManager.getDefault()
            }
        }
    }

    private fun openSmsComposer(phone: String, body: String): String {
        return try {
            val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$phone")).apply {
                putExtra("sms_body", body)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            "composer"
        } catch (_: Throwable) {
            "failed"
        }
    }
}
