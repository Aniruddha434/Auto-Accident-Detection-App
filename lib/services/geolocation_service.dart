import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// Service for handling geolocation functionality
class GeolocationService {
  // Singleton pattern
  static final GeolocationService instance = GeolocationService._internal();
  factory GeolocationService() => instance;
  GeolocationService._internal();
  
  /// Get current location
  Future<Position?> getCurrentLocation() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      debugPrint('Error getting location: $e');
      return null;
    }
  }
  
  /// Check if location permissions are granted
  Future<bool> checkLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return false;
    }
    
    return true;
  }
} 