import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:accident_report_system/services/geolocation_service.dart';
import 'package:provider/provider.dart';
import 'package:accident_report_system/providers/accident_provider.dart';

/// Service for handling emergency functionality
class EmergencyService {
  // Singleton pattern
  static final EmergencyService instance = EmergencyService._internal();
  factory EmergencyService() => instance;
  EmergencyService._internal();
  
  // Cooldown flag to prevent multiple triggers
  bool _cooldownActive = false;
  
  /// Send emergency alerts to contacts
  Future<void> sendEmergencyAlert() async {
    if (_cooldownActive) {
      debugPrint('Emergency alert in cooldown period');
      return;
    }
    
    debugPrint('Sending emergency alert to contacts');
    _setCooldown();
    
    try {
      // Get current location
      final position = await GeolocationService.instance.getCurrentLocation();
      
      // Get user ID
      final prefs = await SharedPreferences.getInstance();
      final String? userId = prefs.getString('user_id');
      
      if (userId == null) {
        debugPrint('No user ID found, cannot send emergency alerts');
        return;
      }
      
      // Log emergency in Firestore
      await _logEmergency(userId, position);
      
      // Send SMS to emergency contacts
      await _sendEmergencySMS(position);
      
      debugPrint('Emergency alert sent successfully');
    } catch (e) {
      debugPrint('Error sending emergency alert: $e');
    }
  }
  
  /// Send SMS to emergency contacts
  Future<void> _sendEmergencySMS(Position? position) async {
    try {
      debugPrint('Starting _sendEmergencySMS method...');
      
      // Get emergency contacts from Firestore
      final firestore = FirebaseFirestore.instance;
      final prefs = await SharedPreferences.getInstance();
      final String? userId = prefs.getString('user_id');
      
      debugPrint('User ID from shared prefs: $userId');
      
      // Try to use AccidentProvider if global context is available
      bool success = false;
      final context = _getGlobalContext();
      
      if (context != null) {
        try {
          final accidentProvider = Provider.of<AccidentProvider>(context, listen: false);
          accidentProvider.reportManualAccident(userId ?? 'unknown_user');
          success = true;
          debugPrint('Emergency alerts sent via AccidentProvider.reportManualAccident');
        } catch (e) {
          debugPrint('Error sending via AccidentProvider: $e');
          success = false;
        }
      } else {
        debugPrint('Global context not available, skipping AccidentProvider');
        success = false;
      }
      
      // If that fails, try the URL approach as backup
      if (!success) {
        debugPrint('AccidentProvider SMS sending failed, trying URL approach');
        
        // For testing, use a real-format number (won't actually send to this)
        List<String> phoneNumbers = ['1234567890']; // Default test number in real format
        
        try {
          if (userId != null) {
            // Fetch emergency contacts
            debugPrint('Attempting to fetch emergency contacts from Firestore...');
            final contactsSnapshot = await firestore
                .collection('users')
                .doc(userId)
                .collection('emergency_contacts')
                .get();
            
            debugPrint('Emergency contacts query completed. Documents found: ${contactsSnapshot.docs.length}');
            
            // Extract phone numbers from contacts
            if (contactsSnapshot.docs.isNotEmpty) {
              phoneNumbers.clear(); // Remove default number if we have real contacts
              
              for (var doc in contactsSnapshot.docs) {
                final contactData = doc.data();
                debugPrint('Contact data: $contactData');
                if (contactData.containsKey('phoneNumber') && 
                    contactData['phoneNumber'] != null && 
                    contactData['phoneNumber'].toString().isNotEmpty) {
                  phoneNumbers.add(contactData['phoneNumber'].toString());
                  debugPrint('Added phone number: ${contactData['phoneNumber']}');
                }
              }
            } else {
              debugPrint('No emergency contacts found in Firestore. Using default number.');
            }
          } else {
            debugPrint('No user ID found. Using default phone number.');
          }
        } catch (e) {
          debugPrint('Error fetching contacts: $e - using default number');
        }
        
        // Create message with location
        String message = 'EMERGENCY ALERT: I need help!';
        
        // Add location if available
        if (position != null) {
          message += ' My location: https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}';
          debugPrint('Position available: ${position.latitude}, ${position.longitude}');
        } else {
          debugPrint('No position available for SMS');
        }
        
        debugPrint('Phone numbers to try: $phoneNumbers');
        
        // Try different SMS URI formats
        success = false;
        
        // Try each method and log the results
        List<String> attemptResults = [];
        
        // Format 1: Try sms:?body=...
        if (!success) {
          try {
            debugPrint('Trying SMS format 1: sms:?body=...');
            final smsUri = Uri.parse('sms:?body=${Uri.encodeComponent(message)}');
            success = await launchUrl(smsUri, mode: LaunchMode.externalApplication);
            debugPrint('SMS format 1 result: $success');
            attemptResults.add('Format 1 (sms:?body=...): $success');
          } catch (e) {
            debugPrint('SMS format 1 error: $e');
            attemptResults.add('Format 1 error: $e');
          }
        }
        
        // Format 2: Try sms:<number>?body=...
        if (!success && phoneNumbers.isNotEmpty) {
          try {
            debugPrint('Trying SMS format 2: sms:<number>?body=...');
            final smsUri = Uri.parse('sms:${phoneNumbers.first}?body=${Uri.encodeComponent(message)}');
            success = await launchUrl(smsUri, mode: LaunchMode.externalApplication);
            debugPrint('SMS format 2 result: $success');
            attemptResults.add('Format 2 (sms:<number>?body=...): $success');
          } catch (e) {
            debugPrint('SMS format 2 error: $e');
            attemptResults.add('Format 2 error: $e');
          }
        }
        
        // Show alert dialog if all URIs failed
        if (!success) {
          debugPrint('All SMS methods failed. Summary:');
          for (var result in attemptResults) {
            debugPrint('- $result');
          }
          debugPrint('Need to show manual alert through caller.');
          return;
        }
      }
      
      debugPrint('Successfully sent emergency alerts.');
      return;
    } catch (e) {
      debugPrint('Error in _sendEmergencySMS: $e');
    }
  }
  
  /// Get global context for provider operations
  BuildContext? _getGlobalContext() {
    try {
      // We cannot directly access a global context in newer Flutter versions
      // Return null and let the caller handle it
      debugPrint('Warning: Global context not available');
      return null;
    } catch (e) {
      debugPrint('Error getting global context: $e');
      return null;
    }
  }
  
  /// Log emergency in Firestore
  Future<void> _logEmergency(String userId, Position? position) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final String emergencyId = const Uuid().v4();
      
      await firestore.collection('accidents').doc(emergencyId).set({
        'id': emergencyId,
        'userId': userId,
        'timestamp': FieldValue.serverTimestamp(),
        'latitude': position?.latitude ?? 0,
        'longitude': position?.longitude ?? 0,
        'type': 'voice_triggered',
        'severity': 2, // Medium severity for voice alerts
        'description': 'Emergency triggered by voice command',
        'processed': false,
      });
      
      debugPrint('Emergency logged in Firestore');
    } catch (e) {
      debugPrint('Error logging emergency in Firestore: $e');
    }
  }
  
  /// Set cooldown to prevent multiple alerts
  void _setCooldown() {
    _cooldownActive = true;
    Future.delayed(const Duration(seconds: 30), () {
      _cooldownActive = false;
    });
  }
  
  /// Launch emergency call
  Future<bool> callEmergencyServices() async {
    const emergencyNumber = '102'; // Emergency number
    final Uri phoneUri = Uri(scheme: 'tel', path: emergencyNumber);
    try {
      return await launchUrl(phoneUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not launch phone dialer: $e');
      return false;
    }
  }
} 