import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

/// Service for handling background monitoring functionality
class BackgroundService {
  // Singleton pattern
  static final BackgroundService instance = BackgroundService._internal();
  factory BackgroundService() => instance;
  BackgroundService._internal();
  
  // Isolate name for communication
  static const String _isolateName = 'AccidentDetectionIsolate';
  
  // Service state
  bool _isMonitoring = false;
  
  /// Check if monitoring is active
  bool get isMonitoring => _isMonitoring;
  
  /// Initialize the instance
  Future<void> _initializeInstance() async {
    final prefs = await SharedPreferences.getInstance();
    _isMonitoring = prefs.getBool('monitoring_active') ?? false;
    debugPrint('Background service initialized, monitoring: $_isMonitoring');
  }
  
  /// Static initialize method for application startup
  static Future<void> initialize() async {
    await instance._initializeInstance();
  }
  
  /// Start accident monitoring
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;
    
    try {
      debugPrint('Starting accident monitoring');
      
      // Save state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('monitoring_active', true);
      
      _isMonitoring = true;
      debugPrint('Accident monitoring started');
    } catch (e) {
      debugPrint('Error starting monitoring: $e');
    }
  }
  
  /// Stop accident monitoring
  Future<void> stopMonitoring() async {
    if (!_isMonitoring) return;
    
    try {
      debugPrint('Stopping accident monitoring');
      
      // Save state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('monitoring_active', false);
      
      _isMonitoring = false;
      debugPrint('Accident monitoring stopped');
    } catch (e) {
      debugPrint('Error stopping monitoring: $e');
    }
  }
  
  /// Start background service (static method for easier access)
  static Future<bool> startService() async {
    try {
      await instance.startMonitoring();
      return true;
    } catch (e) {
      debugPrint('Error starting background service: $e');
      return false;
    }
  }
  
  /// Stop background service (static method for easier access)
  static Future<bool> stopService() async {
    try {
      await instance.stopMonitoring();
      return true;
    } catch (e) {
      debugPrint('Error stopping background service: $e');
      return false;
    }
  }
}

/// This is the entry point for the background isolate.
/// This function will be invoked in a separate isolate when the service starts.
@pragma('vm:entry-point')
void backgroundMain() {
  // Initialize communication for the background isolate
  WidgetsFlutterBinding.ensureInitialized();
  
  // Register a port to allow communication with the main isolate
  final ReceivePort receivePort = ReceivePort();
  IsolateNameServer.registerPortWithName(
    receivePort.sendPort, 
    BackgroundService._isolateName
  );
  
  // Listen for messages from the main isolate
  receivePort.listen((dynamic message) {
    debugPrint('Background isolate received message: $message');
  });
  
  // Set up method channel to receive messages from the platform side
  const MethodChannel backgroundChannel = MethodChannel('com.example.accident_report_system/background');
  backgroundChannel.setMethodCallHandler((call) async {
    if (call.method == 'onServiceStarted') {
      debugPrint('Background service started, beginning accident monitoring');
      
      // Start your accident monitoring logic here
      try {
        await _startAccidentMonitoring();
      } catch (e) {
        debugPrint('Error starting accident monitoring: $e');
      }
      
      return null;
    }
    return null;
  });
  
  debugPrint('Background isolate initialized');
}

/// This function contains the actual accident monitoring logic
Future<void> _startAccidentMonitoring() async {
  debugPrint('Starting accident monitoring in background');
  
  // Initialize shared preferences for accessing settings and user data
  final prefs = await SharedPreferences.getInstance();
  final String? userId = prefs.getString('user_id');
  if (userId == null) {
    debugPrint('No user ID found, cannot start monitoring');
    return;
  }
  
  // Initialize Firebase (will need network connectivity)
  try {
    await Firebase.initializeApp();
    debugPrint('Firebase initialized in background service');
  } catch (e) {
    debugPrint('Error initializing Firebase in background: $e');
  }
  
  // Constants for accident detection
  const double accelerationThreshold = 20.0; // m/s²
  const double mediumAccidentThreshold = 35.0; // m/s²
  const double severeAccidentThreshold = 50.0; // m/s²
  
  // Initialize streaming controllers
  StreamSubscription<AccelerometerEvent>? accelerometerSubscription;
  
  // Track last known position
  Position? lastPosition;
  
  // Get current position periodically
  Timer.periodic(const Duration(minutes: 1), (timer) async {
    try {
      lastPosition = await Geolocator.getCurrentPosition();
      debugPrint('Background service updated position: ${lastPosition?.latitude}, ${lastPosition?.longitude}');
    } catch (e) {
      debugPrint('Error getting location in background: $e');
    }
  });
  
  // Start listening to accelerometer events
  accelerometerSubscription = accelerometerEvents.listen((AccelerometerEvent event) async {
    // Calculate total acceleration magnitude
    double acceleration = _calculateAcceleration(event.x, event.y, event.z);
    
    // Check if acceleration exceeds threshold for accident
    if (acceleration > accelerationThreshold) {
      debugPrint('Potential accident detected! Acceleration: $acceleration m/s²');
      
      // Determine severity
      int severity = 1; // Low by default
      if (acceleration > severeAccidentThreshold) {
        severity = 3; // Severe
      } else if (acceleration > mediumAccidentThreshold) {
        severity = 2; // Medium
      }
      
      // Try to get most recent position
      Position? position = lastPosition;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
      } catch (e) {
        debugPrint('Error getting current position for accident: $e, using last known position');
      }
      
      if (position != null) {
        // Report accident to Firestore
        try {
          final firestore = FirebaseFirestore.instance;
          final String accidentId = const Uuid().v4();
          
          await firestore.collection('accidents').doc(accidentId).set({
            'id': accidentId,
            'userId': userId,
            'timestamp': FieldValue.serverTimestamp(),
            'latitude': position.latitude,
            'longitude': position.longitude,
            'acceleration': acceleration,
            'severity': severity,
            'detected_by': 'background_service',
            'processed': false,
          });
          
          debugPrint('Accident reported to Firestore from background service');
          
          // Cancel the subscription after reporting to save battery
          // We'll rely on the platform channel to restart monitoring
          await accelerometerSubscription?.cancel();
          
          // Send SMS directly using native platform channel
          await _sendEmergencySMS(position, userId);
          
        } catch (e) {
          debugPrint('Error reporting accident to Firestore: $e');
        }
      } else {
        debugPrint('No position available, cannot report accident');
      }
    }
  });
}

/// Calculate acceleration magnitude from XYZ components
double _calculateAcceleration(double x, double y, double z) {
  // Remove gravity component (9.8 m/s²) and take magnitude
  double gX = x / 9.8;
  double gY = y / 9.8;
  double gZ = z / 9.8;
  
  // Calculate magnitude of the acceleration vector
  return _magnitude(gX, gY, gZ - 1.0); // Subtract 1G in Z direction (assuming device is vertical)
}

/// Calculate magnitude of a 3D vector
double _magnitude(double x, double y, double z) {
  return _sqrt(x * x + y * y + z * z);
}

/// Custom square root function for background isolate
double _sqrt(double value) {
  return value * 0.5 + value / (value * 0.5);
}

/// Send emergency SMS using platform channel
Future<void> _sendEmergencySMS(Position position, String userId) async {
  try {
    // Get emergency contacts from shared preferences
    final prefs = await SharedPreferences.getInstance();
    final List<String> contacts = prefs.getStringList('emergency_contacts') ?? [];
    final String userName = prefs.getString('user_name') ?? 'A user';
    
    if (contacts.isEmpty) {
      debugPrint('No emergency contacts found');
      return;
    }
    
    // Create the SMS message
    String message = 'EMERGENCY ALERT: $userName may have been in an accident. ' +
                 'Last known location: https://www.google.com/maps/search/?api=1&query=' +
                 '${position.latitude},${position.longitude}';
    
    // Use the platform channel to send SMS
    const platform = MethodChannel('com.example.accident_report_system/sms');
    
    for (final phoneNumber in contacts) {
      try {
        await platform.invokeMethod('sendSMS', {
          'phone': phoneNumber,
          'message': message,
        });
        debugPrint('Emergency SMS sent to $phoneNumber from background service');
      } catch (e) {
        debugPrint('Error sending SMS to $phoneNumber: $e');
      }
    }
  } catch (e) {
    debugPrint('Error in sending emergency SMS: $e');
  }
} 