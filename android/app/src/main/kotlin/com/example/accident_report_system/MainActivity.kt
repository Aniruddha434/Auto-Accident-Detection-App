package com.example.accident_report_system

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager
import android.telephony.TelephonyManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val SMS_CHANNEL = "com.example.accident_report_system/sms"
    private val SERVICE_CHANNEL = "com.example.accident_report_system/service"
    private val VOICE_SERVICE_CHANNEL = "com.example.accident_report_system/voice_service"
    private val SMS_PERMISSION_CODE = 123
    private val VOICE_PERMISSION_CODE = 456

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

        // Voice Recognition Service Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOICE_SERVICE_CHANNEL)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "startVoiceService" -> {
                            val callbackHandle = call.argument<Long>("callbackHandle")
                            if (callbackHandle != null) {
                                startVoiceRecognitionService(callbackHandle)
                                result.success(true)
                            } else {
                                result.error("INVALID_ARGUMENT", "callbackHandle is required", null)
                            }
                        }
                        "stopVoiceService" -> {
                            stopVoiceRecognitionService()
                            result.success(true)
                        }
                        "isVoiceServiceRunning" -> {
                            result.success(isVoiceServiceRunning())
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
            println("🚨🚨 EMERGENCY: SMS request received for $phoneNumber")
            println("📱 Android: Message length: ${message.length} chars")
            println("📱 Android: Phone number: $phoneNumber")
            println("📱 Android: Thread ID: ${Thread.currentThread().id}")
            println("📱 Android: API Level: ${Build.VERSION.SDK_INT}")

            // CRITICAL: Dump device info for debugging
            println("📱 Device Manufacturer: ${Build.MANUFACTURER}")
            println("📱 Device Model: ${Build.MODEL}")
            println("📱 Android Version: ${Build.VERSION.RELEASE}")

            // Log SIM and telephony info
            try {
                val telephonyManager =
                        getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
                println("📱 SIM State: ${getSimStateString(telephonyManager.simState)}")
                println("📱 Network Operator: ${telephonyManager.networkOperatorName}")
                println("📱 Phone Type: ${getPhoneTypeString(telephonyManager.phoneType)}")

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    println("📱 Has Carrier Privileges: ${telephonyManager.hasCarrierPrivileges()}")
                }
            } catch (e: Exception) {
                println("❌ Error getting telephony info: ${e.message}")
            }

            // IMPORTANT FLAG - Check result on main thread
            var resultHandled = false

            // Check for SMS permission - CRITICAL PART
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val hasPermission =
                        ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) ==
                                PackageManager.PERMISSION_GRANTED

                println("📱 Android: Initial SMS permission status: $hasPermission")

                if (!hasPermission) {
                    println("🔑 Android: SMS permission not granted - requesting permission")
                    // Request permission and return pending permission status
                    ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.SEND_SMS),
                            SMS_PERMISSION_CODE
                    )

                    // Set a pending result flag - we'll respond once permission is granted
                    println("⚠️ Android: Permission requested - will retry after granted")
                    resultHandled = true

                    // Return error to Flutter side can retry
                    result.error(
                            "PERMISSION_DENIED",
                            "SMS permission not granted",
                            "Permission has been requested, please try again"
                    )

                    // Store this request to retry after permission
                    _pendingNumber = phoneNumber
                    _pendingMessage = message
                    return
                }
            }

            println("✅ Android: SMS permission verified, proceeding with sending")

            // Try multiple SMS sending approaches
            var sent = false
            var error: Exception? = null

            // Approach 1: Use SmsManager (primary approach)
            try {
                println("🔄 Android: Using direct SmsManager (PRIMARY METHOD)")

                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                    println("📱 Android: Using legacy SmsManager")
                    val smsManager = SmsManager.getDefault()

                    // Check if message is too long and split if necessary
                    if (message.length > 160) {
                        println("📊 Android: Message is long (${message.length} chars), splitting")
                        val messageParts = smsManager.divideMessage(message)
                        println("📊 Android: Split into ${messageParts.size} parts")

                        smsManager.sendMultipartTextMessage(
                                phoneNumber,
                                null,
                                messageParts,
                                null,
                                null
                        )
                        println("✅ Android: Multipart SMS initiated successfully")
                    } else {
                        smsManager.sendTextMessage(phoneNumber, null, message, null, null)
                        println("✅ Android: Single SMS initiated successfully")
                    }

                    sent = true
                    println("✅ Android: SmsManager successfully used")
                } else {
                    println("📱 Android: Using modern SmsManager API")
                    val smsManager = this.getSystemService(SmsManager::class.java)

                    // Check if message is too long and split if necessary
                    if (message.length > 160) {
                        println("📊 Android: Message is long (${message.length} chars), splitting")
                        val messageParts = smsManager.divideMessage(message)
                        println("📊 Android: Split into ${messageParts.size} parts")

                        smsManager.sendMultipartTextMessage(
                                phoneNumber,
                                null,
                                messageParts,
                                null,
                                null
                        )
                        println("✅ Android: Multipart SMS initiated successfully")
                    } else {
                        smsManager.sendTextMessage(phoneNumber, null, message, null, null)
                        println("✅ Android: Single SMS initiated successfully")
                    }

                    sent = true
                    println("✅ Android: Modern SmsManager successfully used")
                }
            } catch (e: Exception) {
                println("❌ Android: Error with SmsManager: ${e.message}")
                e.printStackTrace()
                error = e

                // Log permission-related errors in detail
                if (e.toString().contains("permission")) {
                    println("⚠️⚠️ PERMISSION ISSUE: ${e.message}")

                    // Even if we checked permissions, get the current status again
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val hasPermission =
                                ContextCompat.checkSelfPermission(
                                        this,
                                        Manifest.permission.SEND_SMS
                                ) == PackageManager.PERMISSION_GRANTED
                        println("📱 Re-checking SMS permission: $hasPermission")

                        if (!hasPermission) {
                            println("🔑 Requesting SMS permission again...")
                            ActivityCompat.requestPermissions(
                                    this,
                                    arrayOf(Manifest.permission.SEND_SMS),
                                    SMS_PERMISSION_CODE
                            )
                        }
                    }
                }
            }

            // Approach 2: Try SMS Intent if SmsManager failed
            if (!sent) {
                try {
                    println("🔄 Android: FALLBACK 1 - Using SMS Intent")
                    val smsIntent =
                            Intent(Intent.ACTION_SENDTO).apply {
                                data = Uri.parse("smsto:$phoneNumber")
                                putExtra("sms_body", message)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }

                    // Check if intent can be handled
                    if (smsIntent.resolveActivity(packageManager) != null) {
                        startActivity(smsIntent)
                        println("✅ Android: SMS Intent launched successfully")
                        sent = true
                    } else {
                        println("⚠️ Android: No app can handle SMS Intent")
                    }
                } catch (e: Exception) {
                    println("❌ Android: Error with SMS Intent: ${e.message}")
                    error = e
                }
            }

            // Approach 3: Try VIEW intent with SMS scheme
            if (!sent) {
                try {
                    println("🔄 Android: FALLBACK 2 - Using VIEW intent with SMS scheme")
                    val uri = Uri.parse("sms:$phoneNumber?body=${Uri.encode(message)}")
                    val intent = Intent(Intent.ACTION_VIEW, uri)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

                    startActivity(intent)
                    println("✅ Android: VIEW intent launched for SMS")
                    sent = true
                } catch (e: Exception) {
                    println("❌ Android: Error with VIEW intent: ${e.message}")
                    error = e
                }
            }

            // Approach 4: Try generic text sharing intent as last resort
            if (!sent) {
                try {
                    println("🔄 Android: FALLBACK 3 - Using Share Intent")
                    val shareIntent =
                            Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, "To: $phoneNumber\n\n$message")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }

                    startActivity(Intent.createChooser(shareIntent, "Share Emergency Message"))
                    println("✅ Android: Share Intent launched successfully")
                    sent = true
                } catch (e: Exception) {
                    println("❌ Android: Error with Share Intent: ${e.message}")
                    error = e
                }
            }

            // Final result
            if (sent) {
                println("✅✅ ANDROID SMS: Successfully initiated message sending")
                if (!resultHandled) {
                    result.success(true)
                }
            } else {
                println("❌❌ ANDROID SMS: All SMS methods failed")
                if (!resultHandled) {
                    result.error(
                            "SMS_FAILED",
                            "Failed to send SMS: ${error?.message ?: "Unknown error"}",
                            null
                    )
                }
            }
        } catch (e: Exception) {
            println("❌❌ ANDROID SMS: Unexpected error: ${e.message}")
            e.printStackTrace()
            result.error("SMS_FAILED", "Unexpected error: ${e.message}", null)
        }
    }

    // Store pending SMS details to retry after permission
    private var _pendingNumber: String? = null
    private var _pendingMessage: String? = null

    override fun onRequestPermissionsResult(
            requestCode: Int,
            permissions: Array<String>,
            grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode == SMS_PERMISSION_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                println("✅ Android: SMS permission granted in onRequestPermissionsResult")

                // If we have pending SMS, try to send it now
                if (_pendingNumber != null && _pendingMessage != null) {
                    println("🔄 Android: Retrying pending SMS")

                    // Create a handler to retry on main thread
                    Handler(Looper.getMainLooper()).post {
                        try {
                            // Create a new result to handle this retry
                            val retryResult =
                                    object : MethodChannel.Result {
                                        override fun success(result: Any?) {
                                            println("✅ Android: Retry SMS succeeded")
                                        }

                                        override fun error(
                                                errorCode: String,
                                                errorMessage: String?,
                                                errorDetails: Any?
                                        ) {
                                            println("❌ Android: Retry SMS failed: $errorMessage")
                                        }

                                        override fun notImplemented() {
                                            println("⚠️ Android: Retry SMS not implemented")
                                        }
                                    }

                            sendSMS(_pendingNumber!!, _pendingMessage!!, retryResult)

                            // Clear pending message
                            _pendingNumber = null
                            _pendingMessage = null
                        } catch (e: Exception) {
                            println("❌ Android: Error retrying SMS: ${e.message}")
                        }
                    }
                }
            } else {
                println("❌ Android: SMS permission denied in onRequestPermissionsResult")
            }
        }
    }

    // Helper methods for debug logging
    private fun getSimStateString(state: Int): String {
        return when (state) {
            TelephonyManager.SIM_STATE_ABSENT -> "ABSENT"
            TelephonyManager.SIM_STATE_NETWORK_LOCKED -> "NETWORK_LOCKED"
            TelephonyManager.SIM_STATE_PIN_REQUIRED -> "PIN_REQUIRED"
            TelephonyManager.SIM_STATE_PUK_REQUIRED -> "PUK_REQUIRED"
            TelephonyManager.SIM_STATE_READY -> "READY"
            TelephonyManager.SIM_STATE_UNKNOWN -> "UNKNOWN"
            else -> "UNDEFINED ($state)"
        }
    }

    private fun getPhoneTypeString(type: Int): String {
        return when (type) {
            TelephonyManager.PHONE_TYPE_NONE -> "NONE"
            TelephonyManager.PHONE_TYPE_GSM -> "GSM"
            TelephonyManager.PHONE_TYPE_CDMA -> "CDMA"
            TelephonyManager.PHONE_TYPE_SIP -> "SIP"
            else -> "UNDEFINED ($type)"
        }
    }

    private fun startVoiceRecognitionService(callbackHandle: Long) {
        // Check for record audio permission
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val hasPermission =
                    ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
                            PackageManager.PERMISSION_GRANTED

            if (!hasPermission) {
                ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.RECORD_AUDIO),
                        VOICE_PERMISSION_CODE
                )
                return
            }
        }

        // Create and start the service
        val serviceIntent =
                Intent(this, VoiceRecognitionService::class.java).apply {
                    putExtra("callbackHandle", callbackHandle)
                }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    private fun stopVoiceRecognitionService() {
        val serviceIntent = Intent(this, VoiceRecognitionService::class.java)
        stopService(serviceIntent)
    }

    private fun isVoiceServiceRunning(): Boolean {
        return VoiceRecognitionService.isRunning()
    }
}
