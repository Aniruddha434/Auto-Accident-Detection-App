import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:accident_report_system/models/accident_zone.dart';
import 'dart:math';

class AccidentZoneService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collectionName = 'accident_zones';
  
  /// Singleton pattern implementation
  static final AccidentZoneService _instance = AccidentZoneService._internal();
  factory AccidentZoneService() => _instance;
  AccidentZoneService._internal();
  
  /// Fetch accident zones within a given distance from a location
  /// [center] is the location to search from
  /// [radiusKm] is the maximum distance in kilometers
  Future<List<AccidentZone>> getAccidentZones({
    required LatLng center,
    double radiusKm = 10.0,
  }) async {
    try {
      // Approximate 1 degree of latitude = 111 km
      // Calculate bounds for initial filtering
      final double latDelta = radiusKm / 111.0;
      final double lngDelta = radiusKm / (111.0 * cos(center.latitude * (pi / 180)));
      
      final double minLat = center.latitude - latDelta;
      final double maxLat = center.latitude + latDelta;
      final double minLng = center.longitude - lngDelta;
      final double maxLng = center.longitude + lngDelta;
      
      // Query Firestore for zones in the bounding box
      final snapshot = await _firestore.collection(_collectionName)
          .where('latitude', isGreaterThanOrEqualTo: minLat)
          .where('latitude', isLessThanOrEqualTo: maxLat)
          .get();
          
      // Additional filtering on longitude and exact distance
      final List<AccidentZone> zones = [];
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        
        // Check longitude manually since Firestore can't do compound queries on different fields
        if (data['longitude'] >= minLng && data['longitude'] <= maxLng) {
          final AccidentZone zone = AccidentZone.fromMap(data, doc.id);
          
          // Calculate exact distance to check if it's within the radius
          final double distance = calculateDistance(
            center.latitude, center.longitude,
            zone.center.latitude, zone.center.longitude,
          );
          
          if (distance <= radiusKm) {
            zones.add(zone);
          }
        }
      }
      
      return zones;
    } catch (e) {
      print('Error fetching accident zones: $e');
      return [];
    }
  }
  
  /// Get all accident zones (useful for admin purposes or initial data loading)
  Future<List<AccidentZone>> getAllAccidentZones() async {
    try {
      final snapshot = await _firestore.collection(_collectionName).get();
      
      return snapshot.docs.map((doc) {
        return AccidentZone.fromMap(doc.data(), doc.id);
      }).toList();
    } catch (e) {
      print('Error fetching all accident zones: $e');
      return [];
    }
  }
  
  /// Create or update an accident zone
  Future<bool> saveAccidentZone(AccidentZone zone) async {
    try {
      if (zone.id.isEmpty) {
        // Create new zone
        await _firestore.collection(_collectionName).add(zone.toMap());
      } else {
        // Update existing zone
        await _firestore.collection(_collectionName).doc(zone.id).update(zone.toMap());
      }
      return true;
    } catch (e) {
      print('Error saving accident zone: $e');
      return false;
    }
  }
  
  /// Delete an accident zone
  Future<bool> deleteAccidentZone(String zoneId) async {
    try {
      await _firestore.collection(_collectionName).doc(zoneId).delete();
      return true;
    } catch (e) {
      print('Error deleting accident zone: $e');
      return false;
    }
  }
  
  /// Calculate distance between two points using Haversine formula
  /// Returns distance in kilometers
  double calculateDistance(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    const double earthRadius = 6371; // in kilometers
    
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    
    final double a = sin(dLat / 2) * sin(dLat / 2) +
                     cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * 
                     sin(dLon / 2) * sin(dLon / 2);
    
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }
  
  double _toRadians(double degree) {
    return degree * (pi / 180);
  }
} 