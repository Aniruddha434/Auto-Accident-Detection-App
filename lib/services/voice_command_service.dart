import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:accident_report_system/providers/accident_provider.dart';
import 'package:accident_report_system/providers/auth_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter/services.dart';
import '../services/geolocation_service.dart';
import '../services/emergency_service.dart';
import '../services/background_service.dart';

/// A service for handling voice commands in the application
class VoiceCommandService {
  // Singleton pattern
  static final VoiceCommandService _instance = VoiceCommandService._internal();
  factory VoiceCommandService() => _instance;
  VoiceCommandService._internal();
  
  /// Get the singleton instance
  static VoiceCommandService get instance => _instance;
  
  // Instance of speech to text
  final stt.SpeechToText _speech = stt.SpeechToText();
  
  // Service state
  bool _isInitialized = false;
  bool _isListening = false;
  bool _emergencyCooldown = false;
  bool _isBackgroundServiceRunning = false;
  
  // Method channels for native service communication
  static const MethodChannel _voiceServiceChannel = MethodChannel('com.example.accident_report_system/voice_service');
  static const MethodChannel _voiceChannel = MethodChannel('com.example.accident_report_system/voice');
  
  // Context for UI operations
  BuildContext? _applicationContext;
  
  // Provider for accident handling
  AccidentProvider? _accidentProvider;
  
  // Timer for continuous listening
  Timer? _listeningTimer;
  
  // Last emergency command time to prevent multiple triggers
  DateTime? _lastEmergencyCommandTime;

  // Emergency keywords to detect
  final List<String> _emergencyKeywords = [
    'emergency', 'help', 'accident', 'crash', 'sos', 'injured', 'hurt'
  ];
  final List<String> _startKeywords = ['start', 'enable', 'activate', 'begin', 'monitor'];
  final List<String> _stopKeywords = ['stop', 'disable', 'deactivate', 'halt', 'cancel'];
  
  /// Whether the service is currently listening for voice commands
  bool get isListening => _isListening || _isBackgroundServiceRunning;
  
  /// Set the accident provider for direct SMS sending
  void setAccidentProvider(AccidentProvider provider) {
    _accidentProvider = provider;
    debugPrint('AccidentProvider set in VoiceCommandService');
  }
  
  /// Initialize the voice command service
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    try {
      debugPrint('Initializing VoiceCommandService with speech recognition...');
      
      // Initialize speech recognition
      bool available = await _speech.initialize(
        onError: (error) => debugPrint('Speech recognition error: $error'),
        onStatus: (status) => debugPrint('Speech recognition status: $status'),
        debugLogging: true,
      );
      
      if (available) {
        debugPrint('Speech recognition is available on this device');
        _isInitialized = true;
        
        // Set up the callback method channel for voice events from native side
        _setupBackgroundCallbackChannel();
        
        // Check if the background service is already running
        await _checkBackgroundServiceStatus();
        
        debugPrint('Voice command service initialized successfully.');
        return true;
      } else {
        debugPrint('Speech recognition is NOT available on this device');
        return false;
      }
    } catch (e) {
      debugPrint('Error initializing VoiceCommandService: $e');
      return false;
    }
  }
  
  /// Set up the callback method channel to receive voice events from native side
  void _setupBackgroundCallbackChannel() {
    _voiceChannel.setMethodCallHandler((call) async {
      debugPrint('Received voice channel call: ${call.method}');
      
      if (call.method == 'onVoiceServiceStarted') {
        debugPrint('Voice service has started in background');
        _isBackgroundServiceRunning = true;
      } else if (call.method == 'onEmergencyDetected') {
        final text = call.arguments['text'] as String?;
        final keyword = call.arguments['keyword'] as String?;
        
        debugPrint('Emergency detected in background: $text (keyword: $keyword)');
        
        // Handle the emergency detection
        _handleBackgroundEmergencyDetection(text, keyword);
      }
      
      return null;
    });
  }
  
  /// Handle emergency detection from the background service
  Future<void> _handleBackgroundEmergencyDetection(String? text, String? keyword) async {
    if (_lastEmergencyCommandTime != null &&
        DateTime.now().difference(_lastEmergencyCommandTime!).inSeconds < 10) {
      debugPrint('Ignoring emergency detection due to cooldown period');
      return;
    }
    
    _lastEmergencyCommandTime = DateTime.now();
    
    // Use the accident provider to send emergency alerts
    if (_accidentProvider != null) {
      try {
        debugPrint('Handling background emergency detection...');
        await _accidentProvider!.handleEmergencyCommand();
      } catch (e) {
        debugPrint('Error handling background emergency command: $e');
      }
    } else {
      debugPrint('Cannot handle emergency - no accident provider available');
    }
  }
  
  /// Check the current status of the background voice service
  Future<void> _checkBackgroundServiceStatus() async {
    try {
      final isRunning = await _voiceServiceChannel.invokeMethod<bool>('isVoiceServiceRunning') ?? false;
      _isBackgroundServiceRunning = isRunning;
      debugPrint('Background voice service running status: $_isBackgroundServiceRunning');
    } catch (e) {
      debugPrint('Error checking background voice service status: $e');
      _isBackgroundServiceRunning = false;
    }
  }
  
  /// Get the Dart callback for background execution
  static Future<int> _getBackgroundCallbackHandle() async {
    final CallbackHandle handle = PluginUtilities.getCallbackHandle(_backgroundVoiceEntrypoint)!;
    return handle.toRawHandle();
  }
  
  /// Start the background voice recognition service
  Future<bool> startBackgroundVoiceService() async {
    if (_isBackgroundServiceRunning) {
      debugPrint('Background voice service already running');
      return true;
    }
    
    try {
      final callbackHandle = await _getBackgroundCallbackHandle();
      
      final result = await _voiceServiceChannel.invokeMethod<bool>(
        'startVoiceService',
        {'callbackHandle': callbackHandle}
      ) ?? false;
      
      if (result) {
        _isBackgroundServiceRunning = true;
        debugPrint('Background voice service started successfully');
      } else {
        debugPrint('Failed to start background voice service');
      }
      
      return result;
    } catch (e) {
      debugPrint('Error starting background voice service: $e');
      return false;
    }
  }
  
  /// Stop the background voice recognition service
  Future<bool> stopBackgroundVoiceService() async {
    if (!_isBackgroundServiceRunning) {
      debugPrint('Background voice service not running');
      return true;
    }
    
    try {
      final result = await _voiceServiceChannel.invokeMethod<bool>('stopVoiceService') ?? false;
      
      if (result) {
        _isBackgroundServiceRunning = false;
        debugPrint('Background voice service stopped successfully');
      } else {
        debugPrint('Failed to stop background voice service');
      }
      
      return result;
    } catch (e) {
      debugPrint('Error stopping background voice service: $e');
      return false;
    }
  }
  
  /// Set the application context for UI operations
  void setApplicationContext(BuildContext context) {
    _applicationContext = context;
    debugPrint('Application context set in VoiceCommandService');
  }
  
  /// Starts listening for voice commands
  Future<bool> startListening() async {
    // Try to start the background service first
    final backgroundStarted = await startBackgroundVoiceService();
    
    if (backgroundStarted) {
      debugPrint('Using background service for voice recognition');
      return true;
    }
    
    // Fall back to foreground recognition if background service fails
    debugPrint('Falling back to foreground voice recognition');
    
    if (!_isInitialized) {
      _isInitialized = await _speech.initialize(
        onStatus: (status) => debugPrint('Speech recognition status: $status'),
        onError: (error) => debugPrint('Speech recognition error: $error'),
      );
      
      if (!_isInitialized) {
        debugPrint('Failed to initialize speech recognition');
        return false;
      }
    }
    
    if (!_isListening) {
      _isListening = true;
      _startSpeechRecognition();
      debugPrint('Started listening for voice commands');
      
      // Set up a timer to restart listening periodically
      _listeningTimer = Timer.periodic(Duration(seconds: 5), (timer) {
        if (_isListening && !_speech.isListening) {
          _startSpeechRecognition();
        }
      });
      
      return true;
    }
    
    return false;
  }
  
  /// Stops listening for voice commands
  Future<void> stopListening() async {
    // Stop the background service if running
    if (_isBackgroundServiceRunning) {
      await stopBackgroundVoiceService();
    }
    
    // Stop foreground listening
    _isListening = false;
    _speech.stop();
    _listeningTimer?.cancel();
    _listeningTimer = null;
    debugPrint('Stopped listening for voice commands');
  }
  
  /// Start the speech recognition process
  void _startSpeechRecognition() {
    if (!_isInitialized || !_isListening) return;
    
    _speech.listen(
      onResult: _handleSpeechResult,
      listenFor: Duration(seconds: 30),
      pauseFor: Duration(seconds: 3),
      partialResults: true,
      localeId: 'en_US',
      cancelOnError: false,
      listenMode: stt.ListenMode.confirmation,
    );
  }
  
  /// Handle speech recognition results
  void _handleSpeechResult(SpeechRecognitionResult result) {
    if (result.finalResult) {
      String recognizedWords = result.recognizedWords.toLowerCase();
      debugPrint('Recognized: $recognizedWords');
      
      // Check for emergency keywords
      if (recognizedWords.contains('emergency') || 
          recognizedWords.contains('help') || 
          recognizedWords.contains('accident') ||
          recognizedWords.contains('crash') ||
          recognizedWords.contains('hurt') ||
          recognizedWords.contains('injured') ||
          recognizedWords.contains('danger') ||
          recognizedWords.contains('ambulance')) {
        
        // Prevent multiple emergency commands in quick succession
        if (_lastEmergencyCommandTime == null || 
            DateTime.now().difference(_lastEmergencyCommandTime!).inSeconds > 10) {
          _lastEmergencyCommandTime = DateTime.now();
          _executeCommand('emergency');
        }
      }
    }
  }
  
  /// Clean up resources
  Future<void> dispose() async {
    try {
      await stopListening();
      await stopBackgroundVoiceService();
      _listeningTimer?.cancel();
      _isListening = false;
      _isInitialized = false;
    } catch (e) {
      debugPrint('Error disposing voice service: $e');
    }
  }
  
  /// Show a visual feedback message
  void _showVisualFeedback(String message, [Color? backgroundColor]) {
    debugPrint(message);
    
    if (_applicationContext != null) {
      try {
        ScaffoldMessenger.of(_applicationContext!).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
            backgroundColor: backgroundColor,
          ),
        );
      } catch (e) {
        debugPrint('Error showing visual feedback: $e');
      }
    }
  }
  
  /// Simulate a wake word for testing purposes
  void simulateWakeWord(String command) {
    debugPrint('Wake word simulated: $command');
    
    if (!isListening) {
      _showVisualFeedback(
        'Voice commands are not active. Please enable voice commands first.',
        Colors.red
      );
      return;
    }
    
    // All commands now trigger emergency alerts
    String feedbackMessage = 'Emergency guidance activated';
    Color feedbackColor = Colors.red;
    
    // Provide visual feedback
    _showVisualFeedback(feedbackMessage, feedbackColor);
    
    // Handle emergency command
    if (_applicationContext != null) {
      // Use WidgetsBinding to ensure we're not in the middle of a build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _executeCommand('emergency');
      });
    }
  }
  
  /// Execute a command directly
  void _executeCommand(String command) {
    if (_applicationContext == null) {
      debugPrint('Cannot execute command: No application context');
      return;
    }

    BuildContext context = _applicationContext!;
    
    if (command == 'emergency') {
      // Show emergency feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Emergency Alert Triggered!'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      
      // Get emergency service and trigger alert
      try {
        debugPrint('Executing emergency alert command...');
        _handleEmergencyCommand(); // This will send the SMS
      } catch (e) {
        debugPrint('Failed to send emergency alert: $e');
      }
    }
  }
  
  /// Handle emergency-related wake words by sending alerts
  Future<void> _handleEmergencyCommand() async {
    if (_accidentProvider != null) {
      await _accidentProvider!.handleEmergencyCommand();
    } else {
      debugPrint('AccidentProvider not available for emergency command');
    }
  }
  
  /// Show manual emergency options dialog
  void _showManualEmergencyOptions(BuildContext context) async {
    // Get current location
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 5),
      );
    } catch (e) {
      debugPrint('Error getting location for manual options: $e');
    }
    
    // Create message with location
    String message = 'EMERGENCY ALERT: I need help!';
    String locationText = '';
    
    if (position != null) {
      locationText = ' My location: https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}';
      message += locationText;
    }
    
    // Show dialog with options
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.red),
              SizedBox(width: 8),
              Text('Emergency Alert', style: TextStyle(color: Colors.red)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Automatic emergency alerts failed.', 
                style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              Text('Please choose an action:'),
              SizedBox(height: 16),
              if (position != null)
                Text('Your location: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
          actions: [
            ElevatedButton.icon(
              icon: Icon(Icons.call),
              label: Text('Call 911'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _launchEmergencyCall(context);
              },
            ),
            ElevatedButton.icon(
              icon: Icon(Icons.message),
              label: Text('Send SMS'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                
                // Try to open SMS app with pre-filled message
                try {
                  final uri = Uri.parse('sms:?body=${Uri.encodeComponent(message)}');
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (e) {
                  // Show error
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to open SMS app: $e'),
                      backgroundColor: Colors.red,
                    )
                  );
                }
              },
            ),
            TextButton(
              child: Text('Close'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }
  
  /// Process a voice command in the application context
  static void processCommand(String command, BuildContext context) {
    debugPrint('Processing command: $command');
    
    final instance = VoiceCommandService();
    instance.setApplicationContext(context);
    instance.simulateWakeWord(command);
  }
  
  /// Simulate an accident alert for testing purposes
  Future<void> simulateAccidentAlert() async {
    debugPrint('🚨 Simulating accident alert for testing');
    
    if (_applicationContext == null) {
      debugPrint('❌ Cannot simulate accident alert: No application context');
      throw Exception('Application context not available');
    }
    
    if (_accidentProvider == null) {
      debugPrint('❌ Cannot simulate accident alert: Accident provider not available');
      
      // Try to get the accident provider from the context
      try {
        _accidentProvider = Provider.of<AccidentProvider>(_applicationContext!, listen: false);
        debugPrint('✅ Successfully retrieved accident provider from context');
      } catch (e) {
        debugPrint('❌ Failed to get accident provider from context: $e');
        throw Exception('Accident provider not available');
      }
    }
    
    // Show immediate feedback
    ScaffoldMessenger.of(_applicationContext!).showSnackBar(
      const SnackBar(
        content: Text('TEST MODE - Simulating accident detection'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ),
    );
    
    // Get the current user ID
    final authProvider = Provider.of<AuthProvider>(_applicationContext!, listen: false);
    final userId = authProvider.firebaseUser?.uid;
    
    if (userId == null) {
      debugPrint('❌ Cannot simulate accident alert: User not signed in');
      throw Exception('User not signed in');
    }
    
    debugPrint('📱 Simulating accident for user: $userId');
    
    try {
      // Create test accident data for Firestore logging
      final accidentTime = DateTime.now();
      final accidentId = const Uuid().v4();
      
      // Log that we're starting the test
      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      await firestore.collection('test_logs').doc(accidentId).set({
        'id': accidentId,
        'userId': userId,
        'timestamp': accidentTime,
        'testInitiated': true,
        'type': 'manual_test',
      });
      
      debugPrint('✅ Test recorded in Firestore with ID: $accidentId');
      
      // Use the accident provider to report a manual accident
      await _accidentProvider!.reportManualAccident(userId);
      
      // Update the test log
      await firestore.collection('test_logs').doc(accidentId).update({
        'testCompleted': true,
        'completedAt': FieldValue.serverTimestamp(),
      });
      
      debugPrint('✅ Accident simulation completed');
      
      // Show success feedback after a small delay
      Future.delayed(const Duration(seconds: 2), () {
        if (_applicationContext != null) {
          ScaffoldMessenger.of(_applicationContext!).showSnackBar(
            const SnackBar(
              content: Text('Test accident alert processed successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      });
    } catch (e) {
      debugPrint('❌ Error during accident simulation: $e');
      
      // Show error feedback
      if (_applicationContext != null) {
        ScaffoldMessenger.of(_applicationContext!).showSnackBar(
          SnackBar(
            content: Text('Error simulating accident: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      
      // Re-throw the exception so the caller knows it failed
      throw Exception('Failed to simulate accident: $e');
    }
    
    return;
  }
  
  /// Launch phone call to emergency services
  static Future<void> _launchEmergencyCall(BuildContext context) async {
    const emergencyNumber = '911'; // Emergency number in the US
    final Uri phoneUri = Uri(scheme: 'tel', path: emergencyNumber);
    try {
      await launchUrl(phoneUri);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dialing emergency services...'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      debugPrint('Could not launch phone dialer: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not launch phone dialer. Please call emergency services manually.'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  /// Load saved settings for voice commands
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final voiceCommandsEnabled = prefs.getBool('voice_commands_enabled') ?? false;
    final backgroundVoiceEnabled = prefs.getBool('background_voice_enabled') ?? false;
    
    debugPrint('Loading voice command settings: enabled=$voiceCommandsEnabled, background=$backgroundVoiceEnabled');
    
    if (voiceCommandsEnabled) {
      if (backgroundVoiceEnabled) {
        await startBackgroundVoiceService();
      } else {
        await startListening();
      }
    }
  }
  
  /// Save settings for voice commands
  Future<void> saveSettings(bool enabled, {bool useBackground = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_commands_enabled', enabled);
    await prefs.setBool('background_voice_enabled', useBackground);
    
    if (enabled) {
      if (useBackground) {
        await startBackgroundVoiceService();
      } else {
        await startListening();
      }
    } else {
      await stopListening();
      await stopBackgroundVoiceService();
    }
  }
}

/// Background entrypoint for voice recognition service
@pragma('vm:entry-point')
void _backgroundVoiceEntrypoint() {
  debugPrint('Background voice detection started');
  
  // Initialize communication for the background isolate
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set up method channel
  const MethodChannel voiceChannel = MethodChannel('com.example.accident_report_system/voice');
  
  // Listen for method calls from native platform
  voiceChannel.setMethodCallHandler((call) async {
    debugPrint('Received background voice call: ${call.method}');
    
    if (call.method == 'onEmergencyDetected') {
      // Handle emergency detection in background
      final text = call.arguments['text'] as String?;
      final keyword = call.arguments['keyword'] as String?;
      
      debugPrint('Background voice detection triggered: $text (keyword: $keyword)');
      
      // We could trigger emergency SMS here, but we'll send it back to main isolate instead
      // to handle it properly with all the user context
    }
    
    return null;
  });
  
  debugPrint('Background voice detection initialized');
} 