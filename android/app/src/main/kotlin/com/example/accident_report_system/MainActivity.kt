package com.example.accident_report_system

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
    private val SMS_CHANNEL = "com.example.accident_report_system/sms"
    private val SERVICE_CHANNEL = "com.example.accident_report_system/service"
    private val SMS_PERMISSION_CODE = 123

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // SMS Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL)
                .setMethodCallHandler { call, result ->
                    if (call.method == "sendSMS") {
                        val phoneNumber = call.argument<String>("phone")
                        val message = call.argument<String>("message")

                        if (phoneNumber != null && message != null) {
                            sendSMS(phoneNumber, message, result)
                        } else {
                            result.error(
                                    "INVALID_ARGUMENTS",
                                    "Phone number and message are required",
                                    null
                            )
                        }
                    } else {
                        result.notImplemented()
                    }
                }

        // Background Service Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SERVICE_CHANNEL)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "startService" -> {
                            val callbackHandle = call.argument<Long>("callbackHandle")
                            if (callbackHandle != null) {
                                startAccidentDetectionService(callbackHandle)
                                result.success(true)
                            } else {
                                result.error("INVALID_ARGUMENT", "callbackHandle is required", null)
                            }
                        }
                        "stopService" -> {
                            stopAccidentDetectionService()
                            result.success(true)
                        }
                        "isServiceRunning" -> {
                            result.success(isServiceRunning())
                        }
                        else -> {
                            result.notImplemented()
                        }
                    }
                }
    }

    private fun startAccidentDetectionService(callbackHandle: Long) {
        // Create and start the service
        val serviceIntent =
                Intent(this, AccidentDetectionService::class.java).apply {
                    putExtra("callbackHandle", callbackHandle)
                }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    private fun stopAccidentDetectionService() {
        val serviceIntent = Intent(this, AccidentDetectionService::class.java)
        stopService(serviceIntent)
    }

    private fun isServiceRunning(): Boolean {
        // This is a simple check, in a real app you might want to implement
        // a more robust service state tracking mechanism
        return AccidentDetectionService.isRunning()
    }

    private fun sendSMS(phoneNumber: String, message: String, result: MethodChannel.Result) {
        try {
            // Check for SMS permission
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) !=
                            PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.SEND_SMS),
                        SMS_PERMISSION_CODE
                )
                result.error("PERMISSION_DENIED", "SMS permission not granted", null)
                return
            }

            // Try using SmsManager first
            val smsManager = SmsManager.getDefault()
            smsManager.sendTextMessage(phoneNumber, null, message, null, null)
            result.success(true)
        } catch (e: Exception) {
            // If SmsManager fails, try intent
            try {
                val intent =
                        Intent(Intent.ACTION_SENDTO).apply {
                            data = Uri.parse("smsto:$phoneNumber")
                            putExtra("sms_body", message)
                        }
                startActivity(intent)
                result.success(true)
            } catch (e: Exception) {
                result.error("SMS_FAILED", "Failed to send SMS: ${e.message}", null)
            }
        }
    }
}
