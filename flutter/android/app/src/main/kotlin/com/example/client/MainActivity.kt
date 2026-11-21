package com.example.client

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.telephony.SmsManager
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
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.SEND_SMS,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) {
            result.success(sendDirectOrComposer(phone, body))
            return
        }
        // Request runtime permission once; on denial, fall back cleanly to Option A composer.
        pendingPhone = phone
        pendingBody = body
        pendingResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.SEND_SMS),
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

        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted) {
            result.success(sendDirectOrComposer(phone, body))
        } else {
            result.success(openSmsComposer(phone, body))
        }
    }

    private fun sendDirectOrComposer(phone: String, body: String): String {
        return try {
            val manager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                applicationContext.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
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
