package com.example.accident_report_system

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.PowerManager
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean

class VoiceRecognitionService : Service() {
    private val TAG = "VoiceRecognitionService"
    private val WAKELOCK_TAG = "VoiceRecognition:WakeLock"
    private val CHANNEL_ID = "voice_recognition_channel"
    private val SERVICE_ID = 1338
    private val VOICE_CHANNEL = "com.example.accident_report_system/voice"

    private var flutterEngine: FlutterEngine? = null
    private var methodChannel: MethodChannel? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var speechRecognizer: SpeechRecognizer? = null

    // Emergency keywords to listen for
    private val emergencyKeywords =
            listOf("emergency", "help", "accident", "crash", "sos", "injured", "hurt")

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
                        .setContentTitle("Voice Recognition Active")
                        .setContentText("Listening for emergency commands")
                        .setSmallIcon(android.R.drawable.ic_lock_silent_mode_off) // Microphone icon
                        .setContentIntent(pendingIntent)
                        .setPriority(NotificationCompat.PRIORITY_HIGH)
                        .build()

        // Start foreground service
        startForeground(SERVICE_ID, notification)

        // Acquire wake lock to keep CPU running
        acquireWakeLock()

        // Start Flutter execution
        startFlutterEngine(intent)

        // Start voice recognition
        startVoiceRecognition()

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
                    MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, VOICE_CHANNEL)

            // Notify Flutter that service has started
            methodChannel?.invokeMethod("onVoiceServiceStarted", null)
        } catch (e: Exception) {
            Log.e(TAG, "Error starting Flutter engine", e)
        }
    }

    private fun startVoiceRecognition() {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            Log.e(TAG, "Speech recognition is not available on this device")
            return
        }

        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
        speechRecognizer?.setRecognitionListener(
                object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {
                        Log.d(TAG, "Ready for speech")
                    }

                    override fun onBeginningOfSpeech() {
                        Log.d(TAG, "Beginning of speech")
                    }

                    override fun onRmsChanged(rmsdB: Float) {
                        // Ignore RMS changes
                    }

                    override fun onBufferReceived(buffer: ByteArray?) {
                        // Ignore buffer events
                    }

                    override fun onEndOfSpeech() {
                        Log.d(TAG, "End of speech")
                    }

                    override fun onError(error: Int) {
                        Log.d(TAG, "Speech recognition error: $error")
                        // Restart listening on error
                        restartSpeechRecognition()
                    }

                    override fun onResults(results: Bundle?) {
                        val matches =
                                results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        if (matches != null && matches.isNotEmpty()) {
                            val recognizedText = matches[0].toLowerCase(Locale.getDefault())
                            Log.d(TAG, "Speech recognized: $recognizedText")

                            // Check for emergency keywords
                            for (keyword in emergencyKeywords) {
                                if (recognizedText.contains(keyword)) {
                                    Log.d(TAG, "Emergency keyword detected: $keyword")

                                    // Send detected emergency to Flutter
                                    methodChannel?.invokeMethod(
                                            "onEmergencyDetected",
                                            mapOf("text" to recognizedText, "keyword" to keyword)
                                    )

                                    break
                                }
                            }
                        }

                        // Restart listening
                        restartSpeechRecognition()
                    }

                    override fun onPartialResults(partialResults: Bundle?) {
                        // Ignore partial results
                    }

                    override fun onEvent(eventType: Int, params: Bundle?) {
                        // Ignore other events
                    }
                }
        )

        startListening()
    }

    private fun startListening() {
        try {
            val intent =
                    Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                        putExtra(
                                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                        )
                        putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
                        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                        putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
                        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 1500L)
                        putExtra(
                                RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,
                                1500L
                        )
                    }

            speechRecognizer?.startListening(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Error starting speech recognition", e)
        }
    }

    private fun restartSpeechRecognition() {
        // Small delay before restarting
        android.os.Handler()
                .postDelayed(
                        {
                            if (isServiceRunning.get()) {
                                startListening()
                            }
                        },
                        1000
                )
    }

    private fun acquireWakeLock() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKELOCK_TAG)
        wakeLock?.acquire()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Voice Recognition Service"
            val descriptionText = "Listens for emergency voice commands"
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
        speechRecognizer?.destroy()
        wakeLock?.release()
        flutterEngine?.destroy()
        isServiceRunning.set(false)
        super.onDestroy()
    }
}
