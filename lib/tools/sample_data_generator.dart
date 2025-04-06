import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:accident_report_system/models/accident_zone.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';

/// Utility class for generating and adding sample accident zone data to Firestore
/// This is for testing purposes only and should not be used in production
class SampleDataGenerator {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Random _random = Random();
  
  /// Generate sample accident zones around a given location
  /// [center] is the center point for generating zones
  /// [count] is the number of zones to generate
  /// [radiusKm] is the maximum distance in km from center to create zones
  Future<void> generateAccidentZones({
    required LatLng center,
    int count = 5,
    double radiusKm = 10.0,
  }) async {
    final batch = _firestore.batch();
    
    for (int i = 0; i < count; i++) {
      // Generate a random point within radiusKm of center
      final randomDist = _random.nextDouble() * radiusKm;
      final randomAngle = _random.nextDouble() * 2 * pi;
      
      // Convert distance and angle to lat/lng offset
      // Approximate 1 degree of latitude = 111 km
      final latOffset = (randomDist / 111.0) * sin(randomAngle);
      final lngOffset = (randomDist / (111.0 * cos(center.latitude * (pi / 180)))) * cos(randomAngle);
      
      final zoneCenter = LatLng(
        center.latitude + latOffset,
        center.longitude + lngOffset,
      );
      
      // Create random zone data
      final zoneData = {
        'latitude': zoneCenter.latitude,
        'longitude': zoneCenter.longitude,
        'radius': 0.2 + _random.nextDouble() * 0.8, // Random radius between 0.2 and 1.0 km
        'accidentCount': 5 + _random.nextInt(20), // Random count between 5 and 24
        'riskLevel': 1 + _random.nextInt(3), // Random level between 1 and 3
        'description': _getRandomDescription(),
        'lastUpdated': DateTime.now().subtract(Duration(days: _random.nextInt(30))).millisecondsSinceEpoch,
      };
      
      // Create a new document reference
      final docRef = _firestore.collection('accident_zones').doc();
      batch.set(docRef, zoneData);
      
      print('Generated zone at (${zoneCenter.latitude}, ${zoneCenter.longitude})');
    }
    
    // Commit the batch
    await batch.commit();
    print('Added $count sample accident zones to Firestore');
  }
  
  /// Generate random descriptions for accident zones
  String _getRandomDescription() {
    final descriptions = [
      'High-risk intersection with frequent collisions during peak hours.',
      'Dangerous curve with poor visibility, especially at night.',
      'Area with frequent rain-related accidents due to poor drainage.',
      'Construction zone with changing road conditions.',
      'High pedestrian traffic area with frequent accidents.',
      'School zone with increased traffic during pickup and drop-off times.',
      'Narrow bridge with limited visibility.',
      'Highway section with frequent lane merging accidents.',
      'Area with high incidence of distracted driving accidents.',
      'Zone with poor traffic signal visibility.',
    ];
    
    return descriptions[_random.nextInt(descriptions.length)];
  }
  
  /// Delete all sample accident zones
  Future<void> clearAccidentZones() async {
    final snapshot = await _firestore.collection('accident_zones').get();
    
    final batch = _firestore.batch();
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    
    await batch.commit();
    print('Cleared ${snapshot.docs.length} accident zones from Firestore');
  }
}

/// Example usage:
/// ```dart
/// final generator = SampleDataGenerator();
/// await generator.generateAccidentZones(
///   center: LatLng(37.7749, -122.4194), // San Francisco
///   count: 10,
/// );
/// ``` 