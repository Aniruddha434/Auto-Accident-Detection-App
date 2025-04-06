import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';

class AccidentZone {
  final String id;
  final LatLng center;
  final double radius;
  final int accidentCount;
  final String description;
  final DateTime lastUpdated;

  /// Risk level enum representation as int
  /// 1 = Low, 2 = Medium, 3 = High
  final int riskLevel;
  
  AccidentZone({
    required this.id,
    required this.center,
    required this.radius,
    required this.accidentCount,
    required this.riskLevel,
    this.description = '',
    required this.lastUpdated,
  });

  /// Returns the appropriate color based on risk level
  Color getZoneColor({double opacity = 0.5}) {
    switch (riskLevel) {
      case 3:
        return Colors.red.withOpacity(opacity);
      case 2:
        return Colors.orange.withOpacity(opacity);
      case 1:
        return Colors.yellow.withOpacity(opacity);
      default:
        return Colors.blue.withOpacity(opacity);
    }
  }
  
  /// Returns a human-readable risk level
  String get riskLevelText {
    switch (riskLevel) {
      case 3:
        return 'High';
      case 2:
        return 'Medium';
      case 1:
        return 'Low';
      default:
        return 'Unknown';
    }
  }

  /// Factory method to create from Firestore data
  factory AccidentZone.fromMap(Map<String, dynamic> map, String id) {
    return AccidentZone(
      id: id,
      center: LatLng(
        map['latitude'] as double, 
        map['longitude'] as double,
      ),
      radius: map['radius'] as double,
      accidentCount: map['accidentCount'] as int,
      riskLevel: map['riskLevel'] as int,
      description: map['description'] as String? ?? '',
      lastUpdated: (map['lastUpdated'] as Map<String, dynamic>?)?.isEmpty == false
        ? DateTime.fromMillisecondsSinceEpoch(map['lastUpdated'])
        : DateTime.now(),
    );
  }

  /// Convert to a map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'latitude': center.latitude,
      'longitude': center.longitude,
      'radius': radius,
      'accidentCount': accidentCount,
      'riskLevel': riskLevel,
      'description': description,
      'lastUpdated': lastUpdated.millisecondsSinceEpoch,
    };
  }
} 