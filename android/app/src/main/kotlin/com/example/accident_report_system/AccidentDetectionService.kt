package com.example.accident_report_system

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import java.util.concurrent.atomic.AtomicBoolean

class AccidentDetectionService : Service() {
    private val TAG = "AccidentDetectionService"
    private val WAKELOCK_TAG = "AccidentDetection:WakeLock"
    private val CHANNEL_ID = "accident_detection_channel"
    private val SERVICE_ID = 1337
    private val BACKGROUND_CHANNEL = "com.example.accident_report_system/background"

    private var flutterEngine: FlutterEngine? = null
    private var methodChannel: MethodChannel? = null
    private var wakeLock: PowerManager.WakeLock? = null

    companion object {
        private val isServiceRunning = AtomicBoolean(false)

        @JvmStatic
        fun isRunning(): Boolean {
            return isServiceRunning.get()
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Only run once
        if (isServiceRunning.getAndSet(true)) {
            return START_STICKY
        }

        // Create notification
        val pendingIntent: PendingIntent =
                Intent(this, MainActivity::class.java).let { notificationIntent ->
                    PendingIntent.getActivity(
                            this,
                            0,
                            notificationIntent,
                            PendingIntent.FLAG_IMMUTABLE
                    )
                }

        val notification =
                NotificationCompat.Builder(this, CHANNEL_ID)
                        .setContentTitle("Accident Detection Active")
                        .setContentText("The app is monitoring for potential accidents")
                        .setSmallIcon(android.R.drawable.ic_dialog_alert) // Use system icon instead
                        .setContentIntent(pendingIntent)
                        .setPriority(NotificationCompat.PRIORITY_HIGH)
                        .build()

        // Start foreground service
        startForeground(SERVICE_ID, notification)

        // Acquire wake lock to keep CPU running
        acquireWakeLock()

        // Start Flutter execution
        startFlutterEngine(intent)

        return START_STICKY
    }

    private fun startFlutterEngine(intent: Intent?) {
        if (flutterEngine != null) {
            return
        }

        try {
            // Get callback handle from intent
            val callbackHandle = intent?.getLongExtra("callbackHandle", 0L) ?: return
            Log.d(TAG, "Starting Flutter engine with callback: $callbackHandle")

            // Ensure Flutter loader is initialized
            val flutterLoader = FlutterInjector.instance().flutterLoader()
            if (!flutterLoader.initialized()) {
                flutterLoader.startInitialization(applicationContext)
                flutterLoader.ensureInitializationComplete(applicationContext, null)
            }

            // Get callback info
            val callbackInfo =
                    FlutterCallbackInformation.lookupCallbackInformation(callbackHandle) ?: return

            // Create and start Flutter engine
            flutterEngine = FlutterEngine(this)

            // Get the default app bundle path
            val appBundlePath = flutterLoader.findAppBundlePath()

            flutterEngine?.dartExecutor?.executeDartCallback(
                    DartExecutor.DartCallback(assets, appBundlePath, callbackInfo)
            )

            // Set up method channel for communication with Dart
            methodChannel =
                    MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, BACKGROUND_CHANNEL)

            // Notify Flutter that service has started
            methodChannel?.invokeMethod("onServiceStarted", null)
        } catch (e: Exception) {
            Log.e(TAG, "Error starting Flutter engine", e)
        }
    }

    private fun acquireWakeLock() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKELOCK_TAG)
        wakeLock?.acquire()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Accident Detection Service"
            val descriptionText = "Monitors for potential accidents"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel =
                    NotificationChannel(CHANNEL_ID, name, importance).apply {
                        description = descriptionText
                    }
            val notificationManager =
                    getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        wakeLock?.release()
        flutterEngine?.destroy()
        isServiceRunning.set(false)
        super.onDestroy()
    }
}
