import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import 'package:accident_report_system/models/accident_model.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:accident_report_system/services/sms_service.dart';
import 'package:accident_report_system/services/notification_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:accident_report_system/models/accident_zone.dart';
import 'package:accident_report_system/services/emergency_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccidentProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final double _accidentThreshold = 8.0; // Increased from 4.0 to 8.0 for higher sensitivity threshold
  final SmsService _smsService = SmsService(); // Create an instance
  final NotificationService _notificationService = NotificationService(); // For notifications
  final EmergencyService _emergencyService = EmergencyService();
  
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<Position>? _positionSubscription;
  Position? _currentPosition;
  bool _isMonitoring = false;
  bool _isInAccident = false;
  bool _isCancelled = false;
  Timer? _alertTimer;
  int _countdownSeconds = 15; // 15 seconds countdown before sending alerts
  int _remainingSeconds = 15;
  String? _currentUserId; // Store current user ID
  
  // Buffer to store recent accelerometer readings for pattern detection
  List<double> _recentForces = [];
  int _requiredHighForceCount = 3; // Number of consecutive high force readings required
  bool _detectionDebounceActive = false;
  
  // Navigation key for showing hospital screen
  final GlobalKey<NavigatorState>? _navigatorKey;
  
  List<AccidentZone> _accidentZones = [];
  List<AccidentModel> _accidents = [];
  
  Position? get currentPosition => _currentPosition;
  bool get isMonitoring => _isMonitoring;
  bool get isInAccident => _isInAccident;
  int get remainingSeconds => _remainingSeconds;
  List<AccidentZone> get accidentZones => _accidentZones;
  List<AccidentModel> get accidents => _accidents;

  // Constructor now takes a navigator key to enable navigation
  AccidentProvider({GlobalKey<NavigatorState>? navigatorKey}) : _navigatorKey = navigatorKey {
    _notificationService.init();
  }

  // Start monitoring for accidents - no userId required now
  Future<void> startMonitoring([String? userId]) async {
    if (_isMonitoring) return;
    
    _isMonitoring = true;
    _currentUserId = userId; // Store the user ID if provided, can be null
    
    // Request necessary permissions
    await _requestPermissions();
    _startLocationTracking();
    
    // Only start accelerometer on mobile platforms
    if (!kIsWeb) {
      _startAccelerometerListening(userId ?? 'anonymous');
    }
    
    notifyListeners();
  }

  void stopMonitoring() async {
    _isMonitoring = false;
    _isInAccident = false;
    _isCancelled = true;
    _alertTimer?.cancel();
    _accelerometerSubscription?.cancel();
    _positionSubscription?.cancel();
    
    notifyListeners();
  }

  void cancelAlert() {
    if (_isInAccident) {
      _isCancelled = true;
      _isInAccident = false;
      _alertTimer?.cancel();
      _notificationService.cancelAllNotifications(); // Cancel any active notifications
      notifyListeners();
    }
  }

  Future<void> _requestPermissions() async {
    // Request all required permissions
    await Permission.locationAlways.request();
    await Permission.location.request();
    await Permission.sms.request();
    await Permission.notification.request();
    
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied
        return Future.error('Location permissions are denied');
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever
      return Future.error('Location permissions are permanently denied.');
    }
  }

  void _startLocationTracking() {
    // For web, we need to handle positioning differently
    LocationSettings locationSettings;
    
    if (kIsWeb) {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
    }
    
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      _currentPosition = position;
      notifyListeners();
    });
  }

  void _startAccelerometerListening(String userId) {
    try {
      // Clear any existing readings
      _recentForces = [];
      
      _accelerometerSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
        final double x = event.x;
        final double y = event.y;
        final double z = event.z;
        
        // Calculate total force (vector magnitude)
        final double force = _calculateForce(x, y, z);
        
        // Add to recent forces buffer (keep only last 5 readings)
        _recentForces.add(force);
        if (_recentForces.length > 5) {
          _recentForces.removeAt(0);
        }
        
        // Only proceed if we're not currently in debounce period
        if (!_detectionDebounceActive && !_isInAccident) {
          // Check for accident pattern - multiple consecutive high force readings
          if (_detectAccidentPattern()) {
            print('Potential accident detected: Force pattern = $_recentForces');
            
            // Set debounce flag to prevent multiple triggers
            _detectionDebounceActive = true;
            
            // Reset debounce after 5 seconds
            Future.delayed(const Duration(seconds: 5), () {
              _detectionDebounceActive = false;
            });
            
            // Use maximum force value in the pattern
            double maxForce = _recentForces.reduce((curr, next) => curr > next ? curr : next);
            _handleAccidentDetected(userId, maxForce);
          }
        }
      });
    } catch (e) {
      print('Error starting accelerometer: $e');
    }
  }

  double _calculateForce(double x, double y, double z) {
    // Calculate the magnitude of the acceleration vector
    // Subtract 1g (9.8 m/s²) to account for gravity
    double force = (((x * x) + (y * y) + (z * z)) / (9.8 * 9.8));
    return force;
  }
  
  bool _detectAccidentPattern() {
    // Need at least 4 readings to determine a pattern
    if (_recentForces.length < 4) return false;
    
    // Check for a sudden spike followed by sustained forces above medium threshold
    int highForceCount = 0;
    double mediumThreshold = _accidentThreshold * 0.7; // 70% of high threshold
    
    // Count how many recent readings are above the high threshold
    for (double force in _recentForces) {
      if (force > _accidentThreshold) {
        highForceCount++;
      }
    }
    
    // Check if we have at least one reading above high threshold
    bool hasHighForce = highForceCount > 0;
    
    // Check if all readings are above medium threshold (sustained impact)
    bool allAboveMedium = _recentForces.every((force) => force > mediumThreshold);
    
    // Pattern detected if we have at least one high force and all readings above medium threshold
    return hasHighForce && allAboveMedium;
  }

  Future<void> _handleAccidentDetected(String userId, double force) async {
    _isInAccident = true;
    _isCancelled = false;
    _remainingSeconds = _countdownSeconds;
    
    // Log accident detection for debugging
    debugPrint('🚨 AUTOMATIC ACCIDENT DETECTED! Force: $force, UserID: $userId');
    debugPrint('⏱️ Countdown started: $_countdownSeconds seconds');
    
    // Store accident info for emergency handling
    final String accidentId = const Uuid().v4();
    debugPrint('⚠️ Generated accident ID: $accidentId');
    
    // Get current position if null
    if (_currentPosition == null) {
      try {
        debugPrint('📍 Getting position for accident detection...');
        _currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
        debugPrint('✅ Position obtained for accident: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
      } catch (e) {
        debugPrint('❌ Failed to get position during accident detection: $e');
      }
    }
    
    // Log position
    if (_currentPosition != null) {
      debugPrint('📍 Accident location: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
    } else {
      debugPrint('⚠️ No position available for accident detection');
    }
    
    // Show notification for accident detection 
    try {
      await _notificationService.showAccidentDetectionNotification(
        title: 'Potential Accident Detected',
        body: 'Emergency contacts will be alerted in $_countdownSeconds seconds if not cancelled.',
        payload: 'accident_detected',
      );
      debugPrint('✅ Accident detection notification shown');
    } catch (e) {
      debugPrint('❌ Error showing notification: $e');
      // Continue even if notification fails
    }
    
    notifyListeners();
    debugPrint('⏱️ Starting countdown timer for: $_countdownSeconds seconds');
    
    // Store relevant data in shared preferences for recovery if app crashes
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_accident_id', accidentId);
      await prefs.setString('pending_accident_user_id', userId);
      await prefs.setDouble('pending_accident_force', force);
      await prefs.setInt('pending_accident_time', DateTime.now().millisecondsSinceEpoch);
      debugPrint('✅ Saved accident data to recovery storage');
    } catch (e) {
      debugPrint('❌ Failed to save accident data to recovery storage: $e');
    }
    
    // Create immutable copies for timer to close over
    final String timerUserId = userId;
    final double timerForce = force;
    final String timerAccidentId = accidentId;
    
    // Start countdown timer for sending alerts
    _alertTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _remainingSeconds--;
      debugPrint('⏱️ Countdown: $_remainingSeconds seconds remaining');
      notifyListeners();
      
      if (_remainingSeconds <= 0 || _isCancelled) {
        timer.cancel();
        
        // If alert wasn't cancelled, proceed with sending alerts
        if (!_isCancelled) {
          debugPrint('🚨 Countdown finished - proceeding with accident alert');
          // Process accident with immutable copies
          _processAccident(timerUserId, timerForce, timerAccidentId);
        } else {
          // Reset state if cancelled
          debugPrint('🛑 Alert cancelled by user');
          _isInAccident = false;
          notifyListeners();
          
          // Clear recovery data 
          // Use a separate function to handle the async code
          _clearRecoveryData();
        }
      }
    });
  }
  
  Future<void> _processAccident(String userId, double force, String accidentId) async {
    debugPrint('🔄 Processing accident for user $userId with force $force');
    debugPrint('🔑 Using accident ID: $accidentId');
    
    try {
      // Get position for accident if not already available
      if (_currentPosition == null) {
        try {
          debugPrint('📍 Getting position for accident processing...');
          _currentPosition = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 5),
          );
          debugPrint('✅ Position obtained: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
        } catch (e) {
          debugPrint('❌ Could not get position for accident: $e');
          debugPrint('⚠️ Using fallback position');
          
          // Default position as last resort
          _currentPosition = Position(
            latitude: 40.7128,
            longitude: -74.0060,
            timestamp: DateTime.now(),
            accuracy: 10.0,
            altitude: 0.0,
            heading: 0.0,
            speed: 0.0,
            speedAccuracy: 0.0,
            altitudeAccuracy: 0.0,
            headingAccuracy: 0.0,
          );
        }
      }
      
      // Create the accident model
      final AccidentModel accident = AccidentModel(
        id: accidentId,
        userId: userId,
        timestamp: DateTime.now(),
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        impactForce: force,
        helpSent: false,
      );
      
      debugPrint('📝 Created accident model with data: ${accident.toMap()}');
      
      // Save accident in Firestore ONLY if not anonymous
      if (userId != 'anonymous') {
        try {
          debugPrint('💾 Saving accident to Firestore...');
          await _firestore.collection('accidents').doc(accidentId).set(accident.toMap());
          
          // Mark this as an automatic detection for debugging
          await _firestore.collection('accidents').doc(accidentId).update({
            'automaticDetection': true,
            'processingStarted': FieldValue.serverTimestamp(),
          });
          debugPrint('✅ Accident saved to Firestore');
        } catch (e) {
          debugPrint('❌ Failed to save accident to Firestore: $e');
          // Continue processing even if Firestore save fails
        }
      } else {
        debugPrint('ℹ️ Anonymous user - not saving accident to Firestore');
      }
      
      // Send SMS alerts
      debugPrint('📱 CRITICAL: Sending emergency alerts for automatic accident');
      bool alertSuccess = false;
      
      try {
        debugPrint('🚀 Sending emergency alerts for user $userId');
        alertSuccess = await _sendEmergencyAlerts(userId, accident);
        if (alertSuccess) {
          debugPrint('✅ Emergency alerts sent successfully');
        } else {
          debugPrint('❌ SMS sending failed but no exception was thrown');
        }
      } catch (e) {
        debugPrint('❌ CRITICAL ERROR sending emergency alerts: $e');
        
        // Retry once
        try {
          debugPrint('🔄 Retrying emergency alerts');
          alertSuccess = await _sendEmergencyAlerts(userId, accident);
          if (alertSuccess) {
            debugPrint('✅ Emergency alerts sent successfully on retry');
          } else {
            debugPrint('❌ SMS sending failed on retry but no exception was thrown');
          }
        } catch (e2) {
          debugPrint('❌ Emergency alerts failed after retry: $e2');
        }
      }
      
      // Update accident record if user is logged in
      if (userId != 'anonymous') {
        try {
          await _firestore.collection('accidents').doc(accidentId).update({
            'helpSent': alertSuccess,
            'alertAttempted': true,
            'processingCompleted': FieldValue.serverTimestamp(),
          });
          debugPrint('✅ Updated accident record status in Firestore');
        } catch (e) {
          debugPrint('❌ Failed to update accident record: $e');
        }
      }
      
      // Show notification about alerts being sent
      try {
        await _notificationService.showEmergencyAlertNotification(
          title: alertSuccess ? 'Emergency Contacts Notified' : 'Emergency Alert Status',
          body: alertSuccess 
            ? 'Your emergency contacts have been sent your location information.'
            : 'We tried to alert your emergency contacts. Please check the SMS app.',
          payload: alertSuccess ? 'emergency_sent' : 'emergency_attempted',
        );
        debugPrint('✅ Showed emergency notification to user');
      } catch (e) {
        debugPrint('❌ Failed to show notification: $e');
      }
      
      // Show nearby hospitals
      debugPrint('🏥 Showing nearby hospitals');
      showNearbyHospitals();
      
      // Reset status
      _isInAccident = false;
      notifyListeners();
      
      // Clear recovery data
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('pending_accident_id');
        await prefs.remove('pending_accident_user_id');
        await prefs.remove('pending_accident_force');
        await prefs.remove('pending_accident_time');
        debugPrint('✅ Cleared accident recovery data');
      } catch (e) {
        debugPrint('❌ Failed to clear recovery data: $e');
      }
      
      debugPrint('✅ Accident processing completed successfully');
      
    } catch (e) {
      debugPrint('❌ CRITICAL: Error in accident processing: $e');
      
      // Reset status even if there was an error
      _isInAccident = false;
      notifyListeners();
      
      // Show error notification
      try {
        await _notificationService.showEmergencyAlertNotification(
          title: 'Problem Processing Accident',
          body: 'There was an issue sending alerts. Please manually contact emergency services if needed.',
          payload: 'accident_processing_failed',
        );
      } catch (notifError) {
        debugPrint('❌ Failed to show error notification: $notifError');
      }
    }
  }

  Future<bool> _sendEmergencyAlerts(String userId, AccidentModel accident) async {
    try {
      debugPrint('🚨🚨 CRITICAL: Starting SMS alerts for user: $userId');
      debugPrint('📍 Accident location: ${accident.latitude}, ${accident.longitude}');
      
      List<String> emergencyContacts = [];
      
      // Special handling for anonymous users - add your test number here
      if (userId == 'anonymous') {
        debugPrint('⚠️ User is anonymous - using test mode for SMS');
        
        // Add a test number directly instead of showing dialog
        // REPLACE THE NUMBER BELOW WITH YOUR ACTUAL PHONE NUMBER FOR TESTING
        const String testNumber = "9322548977"; // Replace with your actual phone number including country code
        emergencyContacts.add(testNumber);
        debugPrint('✅ Added direct test emergency contact for anonymous user: $testNumber');
        
        // If we have a navigator context, also show the dialog as a backup
        if (_navigatorKey?.currentContext != null) {
          try {
            String? dialogNumber = await _showTestPhoneDialog(_navigatorKey!.currentContext!);
            if (dialogNumber != null && dialogNumber.isNotEmpty && dialogNumber != testNumber) {
              emergencyContacts.add(dialogNumber);
              debugPrint('✅ Added additional test contact from dialog: $dialogNumber');
            }
          } catch (e) {
            debugPrint('❌ Error showing test phone dialog: $e');
            // Continue with the hardcoded number if dialog fails
          }
        } else {
          debugPrint('ℹ️ No context available for dialog - using hardcoded number');
        }
      } else {
        // Normal flow for authenticated users
        // Get user's emergency contacts
        debugPrint('📋 Fetching user data from Firestore...');
        DocumentSnapshot userDoc = await _firestore.collection('users').doc(userId).get();
        
        if (!userDoc.exists) {
          debugPrint('❌❌ CRITICAL: User document not found in Firestore for SMS sending');
          debugPrint('⚠️ This is likely why SMS alerts are failing - no user data');
          
          // Add a fallback test number even for logged-in users if no contacts found
          const String fallbackNumber = "9322548977"; // Use the same test number
          emergencyContacts.add(fallbackNumber);
          debugPrint('✅ Added fallback emergency contact for user with no data: $fallbackNumber');
          
          // Continue with the fallback number
        } else {
          Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
          debugPrint('📄 User data retrieved: ${userData['name'] ?? 'unnamed'}');
          
          // Try to get emergency contacts from two possible locations in Firestore
          
          // 1. Try getting contacts from the 'emergencyContacts' field (main approach)
          if (userData.containsKey('emergencyContacts')) {
            emergencyContacts = List<String>.from(userData['emergencyContacts'] ?? []);
            debugPrint('📱 Found ${emergencyContacts.length} contacts in emergencyContacts field');
          }
          
          // 2. If no contacts found, try getting them from the subcollection
          if (emergencyContacts.isEmpty) {
            try {
              debugPrint('🔎 Looking for contacts in emergency_contacts subcollection...');
              QuerySnapshot contactsSnapshot = await _firestore
                  .collection('users')
                  .doc(userId)
                  .collection('emergency_contacts')
                  .get();
              
              emergencyContacts = contactsSnapshot.docs
                  .map((doc) => (doc.data() as Map<String, dynamic>)['phoneNumber'] as String)
                  .where((phone) => phone.isNotEmpty)
                  .toList();
              
              debugPrint('📱 Found ${emergencyContacts.length} contacts in subcollection');
            } catch (e) {
              debugPrint('❌ Error fetching emergency contacts from subcollection: $e');
            }
          }
          
          // 3. If both methods failed, check if there's a single phone field
          if (emergencyContacts.isEmpty && userData.containsKey('phoneNumber')) {
            final String? phone = userData['phoneNumber'] as String?;
            if (phone != null && phone.isNotEmpty) {
              debugPrint('📱 No emergency contacts found, using user\'s own phone number as fallback');
              emergencyContacts.add(phone);
            }
          }
          
          // 4. If still no contacts, add a fallback test number
          if (emergencyContacts.isEmpty) {
            const String fallbackNumber = "9322548977"; // Use the same test number
            emergencyContacts.add(fallbackNumber);
            debugPrint('✅ Added fallback emergency contact for user with no contacts: $fallbackNumber');
          }
        }
      }
      
      // Final check - if STILL no contacts, log error and return
      if (emergencyContacts.isEmpty) {
        debugPrint('❌❌ CRITICAL ERROR: No emergency contacts found for this user');
        
        // Log this to Firestore for debugging
        try {
          await _firestore.collection('debug_logs').add({
            'userId': userId,
            'error': 'No emergency contacts found',
            'timestamp': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          debugPrint('❌ Error logging to Firestore: $e');
        }
        
        // Last attempt - add a test number as final fallback
        const String lastResortNumber = "9322548977"; // Use the same test number
        emergencyContacts.add(lastResortNumber);
        debugPrint('✅ LAST RESORT: Added emergency contact as final fallback: $lastResortNumber');
      }
      
      debugPrint('🚨 Accident detected for user $userId - emergency contacts: $emergencyContacts');
      
      // Format the user name for the message
      String userName = userId == 'anonymous' ? 'A user' : 'Driver';
      
      // Create the emergency SMS message with coordinates
      String message = 'EMERGENCY ALERT: $userName may have been in an accident. ' +
                     'Last known location: https://www.google.com/maps/search/?api=1&query=' +
                     '${accident.latitude},${accident.longitude}';
      
      debugPrint('📝 SMS message created: $message');
      
      // Ensure SMS permission is granted before proceeding
      debugPrint('🔑 Checking and requesting SMS permission directly...');
      PermissionStatus smsPermission = await Permission.sms.status;
      debugPrint('📱 Current SMS permission status: $smsPermission');
      
      if (smsPermission != PermissionStatus.granted) {
        debugPrint('🔑 SMS permission not granted, requesting...');
        smsPermission = await Permission.sms.request();
        debugPrint('📱 SMS permission after request: $smsPermission');
        
        // Force a small delay to ensure permission is registered
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Check again to make sure
        smsPermission = await Permission.sms.status;
        debugPrint('📱 Final SMS permission status: $smsPermission');
      }
      
      // SIMPLIFIED SMS SENDING APPROACH - Same as voice command method
      debugPrint('🚨🚨 USING DIRECT SMS APPROACH - Sending to ${emergencyContacts.length} contacts');
      
      if (!kIsWeb) {
        bool anySuccess = false;
        
        for (String phoneNumber in emergencyContacts) {
          debugPrint('📲 SENDING SMS TO: $phoneNumber');
          
          // Try direct send - same as manual accident and voice command
          try {
            bool sent = await _smsService.sendSms(phoneNumber, message);
            if (sent) {
              anySuccess = true;
              debugPrint('✅ DIRECT SMS SUCCEEDED to $phoneNumber');
            } else {
              debugPrint('❌ DIRECT SMS FAILED to $phoneNumber - no exception thrown');
            }
          } catch (e) {
            debugPrint('❌ DIRECT SMS ERROR to $phoneNumber: $e');
            
            // Try again if it's a permission error
            if (e.toString().contains('permission')) {
              debugPrint('⚠️ Permission error detected. Requesting permission again...');
              var smsPermission = await Permission.sms.request();
              debugPrint('📱 SMS permission re-request result: $smsPermission');
              
              // Try one more time after permission request
              try {
                debugPrint('🔄 Trying SMS send again after permission request');
                bool sent = await _smsService.sendSms(phoneNumber, message);
                if (sent) {
                  anySuccess = true;
                  debugPrint('✅ DIRECT SMS SUCCEEDED on second attempt to $phoneNumber');
                }
              } catch (e2) {
                debugPrint('❌ Second SMS attempt also failed: $e2');
              }
            }
          }
        }
        
        debugPrint('📱 FINAL RESULT: SMS sending ${anySuccess ? 'SUCCEEDED ✅' : 'FAILED ❌'}');
        if (!anySuccess) {
          debugPrint('⚠️ All SMS sending attempts failed. Check Android logs for details.');
        }
        
        return anySuccess; // Return whether any SMS was actually sent
      } else {
        debugPrint('⚠️ Running on web platform, SMS not supported');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error sending emergency alerts: $e');
      throw e; // Re-throw to allow retry in calling code
    }
  }

  // Show a dialog to get a test phone number for anonymous users
  Future<String?> _showTestPhoneDialog(BuildContext context) async {
    final phoneController = TextEditingController();
    
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Enter Emergency Contact'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  hintText: 'Enter a phone number for testing',
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              const Text(
                'This number will receive the emergency SMS test',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(phoneController.text.trim()),
              child: const Text('Send SMS'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> fetchUserAccidents(String userId) async {
    try {
      print('Fetching accidents for user: $userId');
      QuerySnapshot snapshot = await _firestore
          .collection('accidents')
          .where('userId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .get();
      
      print('Found ${snapshot.docs.length} accidents');
      
      _accidents = snapshot.docs
          .map((doc) {
            try {
              return AccidentModel.fromMap(doc.data() as Map<String, dynamic>);
            } catch (e) {
              print('Error parsing accident doc: $e');
              return null;
            }
          })
          .where((accident) => accident != null)
          .cast<AccidentModel>()
          .toList();
      
      notifyListeners();
    } catch (e) {
      print('Error fetching user accidents: $e');
    }
  }

  // Manually report an accident (for testing or non-sensor reporting)
  Future<void> reportManualAccident(String userId) async {
    try {
      debugPrint('🚨 MANUAL accident alert initiated for user: $userId');
      
      // Get current location
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        
        // Update the current position so it's available for showNearbyHospitals
        _currentPosition = position;
        debugPrint('✅ Position obtained for manual alert: ${position.latitude}, ${position.longitude}');
      } catch (e) {
        debugPrint('❌ Failed to get position for manual alert: $e');
        // Continue without position - we'll try to use the last known position
      }
      
      if (position == null && _currentPosition != null) {
        debugPrint('⚠️ Using cached position for manual alert: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
        position = _currentPosition;
      } else if (position == null) {
        debugPrint('⚠️ No position available for manual alert, using default position');
        // Use a default position as fallback
        position = Position(
          latitude: 40.7128, 
          longitude: -74.0060,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0,
        );
      }
      
      // Create an accident model
      final String accidentId = const Uuid().v4();
      final AccidentModel accident = AccidentModel(
        id: accidentId,
        userId: userId,
        timestamp: DateTime.now(),
        latitude: position!.latitude,
        longitude: position.longitude,
        impactForce: 10.0, // Default value for manual report
        helpSent: false,
      );
      
      debugPrint('✅ Created manual accident record: ${accident.toMap()}');
      
      // Log to Firestore
      try {
        await _firestore.collection('accidents').doc(accidentId).set(accident.toMap());
        
        // Special debug flag to identify manual alerts
        await _firestore.collection('accidents').doc(accidentId).update({
          'manualAlert': true,
          'processingStarted': FieldValue.serverTimestamp(),
        });
        debugPrint('✅ Saved accident to Firestore');
      } catch (e) {
        debugPrint('❌ Error saving accident to Firestore: $e');
        // Continue even if Firestore save fails
      }
      
      // Check if user has emergency contacts configured
      try {
        DocumentSnapshot userDoc = await _firestore.collection('users').doc(userId).get();
        
        if (userDoc.exists) {
          Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
          List<String> emergencyContacts = [];
          
          if (userData.containsKey('emergencyContacts')) {
            emergencyContacts = List<String>.from(userData['emergencyContacts'] ?? []);
          }
          
          // Check emergency contacts subcollection if needed
          if (emergencyContacts.isEmpty) {
            try {
              QuerySnapshot contactsSnapshot = await _firestore
                  .collection('users')
                  .doc(userId)
                  .collection('emergency_contacts')
                  .get();
              
              for (var doc in contactsSnapshot.docs) {
                final contactData = doc.data() as Map<String, dynamic>;
                if (contactData.containsKey('phoneNumber')) {
                  emergencyContacts.add(contactData['phoneNumber'].toString());
                }
              }
            } catch (e) {
              debugPrint('❌ Error fetching emergency contacts: $e');
            }
          }
          
          debugPrint('📱 Found emergency contacts: $emergencyContacts');
          if (emergencyContacts.isEmpty) {
            debugPrint('⚠️ WARNING: No emergency contacts found for user $userId');
          }
        } else {
          debugPrint('⚠️ WARNING: User document not found for $userId');
        }
      } catch (e) {
        debugPrint('❌ Error checking emergency contacts: $e');
      }
      
      // Show notification about the manual alert
      try {
        await _notificationService.showAccidentDetectionNotification(
          title: 'Manual Alert Triggered',
          body: 'Sending your location to emergency contacts...',
          payload: 'manual_alert',
        );
        debugPrint('✅ Showed manual alert notification');
      } catch (e) {
        debugPrint('❌ Error showing manual alert notification: $e');
        // Continue even if notification fails
      }
      
      // DIRECT SMS SENDING - This is the critical part
      debugPrint('📱 CRITICAL: Sending emergency alerts for manual accident');
      bool alertSuccess = false;
      
      // Send emergency alerts
      try {
        alertSuccess = await _sendEmergencyAlerts(userId, accident);
        if (alertSuccess) {
          debugPrint('✅ Emergency alerts sent successfully');
        } else {
          debugPrint('❌ SMS sending failed but no exception was thrown');
        }
      } catch (e) {
        debugPrint('❌ CRITICAL ERROR: Failed to send emergency alerts: $e');
        
        // Try one more time if first attempt failed
        try {
          debugPrint('🔄 First attempt failed - trying emergency alerts again');
          alertSuccess = await _sendEmergencyAlerts(userId, accident);
          if (alertSuccess) {
            debugPrint('✅ Emergency alerts sent successfully on second attempt');
          } else {
            debugPrint('❌ SMS sending failed on retry but no exception was thrown');
          }
        } catch (e2) {
          debugPrint('❌ Second attempt to send alerts also failed: $e2');
        }
      }
      
      // Update accident record
      try {
        await _firestore.collection('accidents').doc(accidentId).update({
          'helpSent': alertSuccess,
          'alertsAttempted': true,
          'processingCompleted': FieldValue.serverTimestamp(),
        });
        debugPrint('✅ Updated accident record in Firestore');
      } catch (e) {
        debugPrint('❌ Error updating accident record: $e');
      }
      
      // Show notification that emergency contacts were notified
      try {
        await _notificationService.showEmergencyAlertNotification(
          title: alertSuccess ? 'Emergency Contacts Notified' : 'Emergency Alert Status',
          body: alertSuccess 
            ? 'Your emergency contacts have been sent your location information.'
            : 'We tried to alert your emergency contacts. Please check the SMS app.',
          payload: alertSuccess ? 'emergency_sent' : 'emergency_attempted',
        );
        debugPrint('✅ Showed emergency notification');
      } catch (e) {
        debugPrint('❌ Error showing contacts notified notification: $e');
      }
      
      debugPrint('✅ About to show nearby hospitals after accident report');
      // Show nearby hospitals
      showNearbyHospitals();
      
      // Refresh accidents list
      await fetchUserAccidents(userId);
    } catch (e) {
      debugPrint('❌ Error reporting manual accident: $e');
      
      // Show error notification
      try {
        await _notificationService.showEmergencyAlertNotification(
          title: 'Alert Failed',
          body: 'There was a problem sending alerts. Please manually contact emergency services if needed.',
          payload: 'emergency_failed',
        );
      } catch (notifError) {
        debugPrint('❌ Error showing error notification: $notifError');
      }
    }
  }
  
  // Navigate to nearby hospitals screen
  void showNearbyHospitals() {
    debugPrint('🏥🏥🏥 NAVIGATION: Showing nearby hospitals screen');
    debugPrint('🧭 Navigator key: ${_navigatorKey != null}, current position: ${_currentPosition != null}');
    
    try {
      // First check if we have a valid navigator
      if (_navigatorKey == null) {
        debugPrint('❌ Navigator key is null - cannot navigate!');
        return;
      }
      
      // Now check if we have a valid navigator state
      final navigatorState = _navigatorKey!.currentState;
      if (navigatorState == null) {
        debugPrint('❌ Navigator state is null - ensure initState is complete');
        
        // Try to use a delay as last resort
        Future.delayed(const Duration(milliseconds: 500), () {
          final delayedState = _navigatorKey!.currentState;
          if (delayedState != null) {
            _pushNearbyHospitalsRoute(delayedState);
          } else {
            debugPrint('❌ Navigator state still null after delay');
          }
        });
        return;
      }
      
      // Use the separate method to push the route
      _pushNearbyHospitalsRoute(navigatorState);
    } catch (e) {
      debugPrint('❌ Unexpected error in showNearbyHospitals: $e');
    }
  }
  
  // Helper method to push the route
  void _pushNearbyHospitalsRoute(NavigatorState navigatorState) {
    try {
      // Make sure position is not null, fallback to default if needed
      if (_currentPosition == null) {
        debugPrint('⚠️ Position missing for hospital navigation, using default');
        _currentPosition = Position(
          latitude: 40.7128,
          longitude: -74.0060,
          timestamp: DateTime.now(),
          accuracy: 10.0,
          altitude: 0.0,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          altitudeAccuracy: 0.0,
          headingAccuracy: 0.0,
        );
      }
      
      // Extract the coordinates to ensure we send them correctly
      final double lat = _currentPosition!.latitude;
      final double lng = _currentPosition!.longitude;
      debugPrint('🏥 Navigating to nearby hospitals with location: $lat, $lng');
      
      navigatorState.pushNamed(
        '/nearby_hospitals',
        arguments: LatLng(lat, lng),
      ).then((_) {
        debugPrint('✅ Navigation to hospitals screen completed');
      }).catchError((e) {
        debugPrint('❌ Error during navigation: $e');
        
        // Try a simpler navigation if that fails
        try {
          debugPrint('🔄 Trying simpler navigation without arguments');
          navigatorState.pushNamed('/nearby_hospitals');
        } catch (e2) {
          debugPrint('❌ Even simpler navigation failed: $e2');
        }
      });
    } catch (e) {
      debugPrint('❌ Error pushing navigation route: $e');
    }
  }

  // Method to immediately confirm emergency without waiting for countdown
  void confirmEmergency() {
    if (_isInAccident && _currentUserId != null) {
      _alertTimer?.cancel();
      _remainingSeconds = 0;
      _isCancelled = false;
      
      // Process the accident immediately
      if (_currentPosition != null) {
        _processAccident(_currentUserId!, 10.0, const Uuid().v4()); // Use a default force value
      }
      
      notifyListeners();
    }
  }
  
  // Simulate an accident detection event with sensor data
  Future<void> simulateAccidentDetection(String userId) async {
    debugPrint('🔄 Simulating accident detection for user: $userId');
    
    if (_isInAccident) {
      debugPrint('⚠️ Cannot simulate accident detection - already in accident state');
      return;
    }
    
    // Ensure we have a position
    if (_currentPosition == null) {
      try {
        debugPrint('📍 Getting position for accident simulation...');
        _currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
        debugPrint('✅ Position obtained for simulation: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
      } catch (e) {
        debugPrint('❌ Failed to get position for simulation: $e');
        
        // Use a default position if we couldn't get a real one
        _currentPosition = Position(
          latitude: 40.7128,
          longitude: -74.0060,
          timestamp: DateTime.now(),
          accuracy: 10.0,
          altitude: 0.0,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          altitudeAccuracy: 0.0,
          headingAccuracy: 0.0,
        );
        debugPrint('📍 Using default position for simulation: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
      }
    }
    
    // Store current userId if needed
    if (_currentUserId == null) {
      _currentUserId = userId;
    }
    
    // Log simulation to Firestore for debugging
    final String simulationId = const Uuid().v4();
    try {
      await _firestore.collection('test_logs').doc(simulationId).set({
        'id': simulationId,
        'userId': userId,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'sensor_simulation',
        'location': {
          'latitude': _currentPosition!.latitude,
          'longitude': _currentPosition!.longitude,
        },
      });
      debugPrint('✅ Simulation logged to Firestore with ID: $simulationId');
    } catch (e) {
      debugPrint('❌ Failed to log simulation to Firestore: $e');
    }
    
    // Generate simulated sensor data - create a pattern that would trigger detection
    _recentForces = [
      _accidentThreshold * 0.8,  // Below threshold but elevated
      _accidentThreshold * 1.5,  // Above threshold - peak 
      _accidentThreshold * 1.2,  // Still high
      _accidentThreshold * 0.9,  // Coming down but still elevated
      _accidentThreshold * 0.75, // Sustained above medium threshold
    ];
    
    // Calculate the max force for the simulated event
    double maxForce = _recentForces.reduce((curr, next) => curr > next ? curr : next);
    debugPrint('📊 Simulated sensor readings: $_recentForces');
    debugPrint('📊 Maximum force for simulation: $maxForce');
    
    // Directly trigger the accident detection flow
    await _handleAccidentDetected(userId, maxForce);
    debugPrint('✅ Accident detection simulation started');
  }
  
  // Method to call emergency services (911)
  Future<void> callEmergencyServices() async {
    final Uri phoneUri = Uri(scheme: 'tel', path: '911');
    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        debugPrint('Could not launch phone dialer');
      }
    } catch (e) {
      debugPrint('Error launching phone dialer: $e');
    }
  }

  void updatePosition(Position position) {
    _currentPosition = position;
    notifyListeners();
    debugPrint('Position updated manually: ${position.latitude}, ${position.longitude}');
  }

  // Set accident zones (for Kaggle data integration)
  void setAccidentZones(List<AccidentZone> zones) {
    _accidentZones = zones;
    notifyListeners();
  }

  // Helper method to clear recovery data
  Future<void> _clearRecoveryData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_accident_id');
      await prefs.remove('pending_accident_user_id');
      await prefs.remove('pending_accident_force');
      await prefs.remove('pending_accident_time');
      debugPrint('✅ Cleared accident recovery data');
    } catch (e) {
      debugPrint('❌ Failed to clear recovery data: $e');
    }
  }

  void _startAlertCountdown(String userId) {
    if (_alertTimer != null && _alertTimer!.isActive) {
      _alertTimer!.cancel();
    }
    
    _countdownSeconds = 15;
    _remainingSeconds = _countdownSeconds;
    _isInAccident = true;
    _isCancelled = false;
    
    notifyListeners();
    
    _alertTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_isCancelled) {
        debugPrint('Alert cancelled by user.');
        timer.cancel();
        _isInAccident = false;
        notifyListeners();
        return;
      }
      
      _remainingSeconds--;
      debugPrint('⏱️ Alert countdown: $_remainingSeconds seconds remaining');
      notifyListeners();
      
      if (_remainingSeconds <= 0) {
        timer.cancel();
        debugPrint('🚨🚨 COUNTDOWN REACHED ZERO - EMERGENCY ALERT TRIGGERED 🚨🚨');
        
        try {
          // Show notification
          await _notificationService.showAccidentDetectionNotification(
            title: 'Emergency Alert Activated',
            body: 'Sending emergency alerts to your contacts...',
            payload: 'emergency_alerts_sending',
          );
          
          // Process the accident detection
          await _processAccidentDetection(userId);
          
          debugPrint('✅ Emergency alert processing completed');
        } catch (e) {
          debugPrint('❌ CRITICAL ERROR in alert processing: $e');
          
          // Reset the alert state
          _isInAccident = false;
          notifyListeners();
          
          // Show error notification
          try {
            await _notificationService.showAccidentDetectionNotification(
              title: 'Emergency Alert Error',
              body: 'There was a problem sending emergency alerts.',
              payload: 'emergency_alerts_error',
            );
          } catch (e2) {
            debugPrint('Error showing notification: $e2');
          }
        }
      }
    });
  }

  // Create the _processAccidentDetection method that's called from the countdown but doesn't exist
  Future<void> _processAccidentDetection(String userId) async {
    debugPrint('🚨 _processAccidentDetection called for user: $userId');
    
    try {
      // Generate a new accident ID
      final String accidentId = const Uuid().v4();
      debugPrint('🆔 Generated new accident ID: $accidentId');
      
      // Calculate a reasonable force value (we don't have actual sensors here)
      final double simulatedForce = 10.0; // Higher than threshold
      
      // Call the existing method that does the actual processing
      await _processAccident(userId, simulatedForce, accidentId);
      
      debugPrint('✅ _processAccidentDetection completed successfully');
    } catch (e) {
      debugPrint('❌ ERROR in _processAccidentDetection: $e');
      throw e; // Re-throw to allow proper error handling upstream
    }
  }

  /// Handle an emergency command from voice
  Future<void> handleEmergencyCommand() async {
    debugPrint('Handling emergency command from voice command service');
    
    try {
      // Check if we have a user ID
      String? userId = _auth.currentUser?.uid;
      
      if (userId == null || userId.isEmpty) {
        // Use anonymous ID if not signed in
        userId = 'anonymous';
        debugPrint('Using anonymous user ID for emergency command');
      }
      
      // Get the current position
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
        debugPrint('Got position for emergency command: ${position.latitude}, ${position.longitude}');
      } catch (e) {
        debugPrint('Error getting position for emergency command: $e');
        // Continue without position
      }
      
      // Report a manual accident with low priority
      await reportManualAccident(
        userId: userId,
        forceValue: 10.0, // Low force for voice commands
        position: position,
        testMode: userId == 'anonymous',
      );
      
      debugPrint('Emergency command processed successfully');
      return;
    } catch (e) {
      debugPrint('Error processing emergency command: $e');
      rethrow;
    }
  }
} 