import 'package:cloud_firestore/cloud_firestore.dart';

class AccidentModel {
  final String id;
  final String userId;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double impactForce;
  final bool helpSent;
  final String? notes;

  AccidentModel({
    required this.id,
    required this.userId,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.impactForce,
    required this.helpSent,
    this.notes,
  });

  factory AccidentModel.fromMap(Map<String, dynamic> map) {
    return AccidentModel(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      timestamp: map['timestamp'] != null 
        ? (map['timestamp'] is Timestamp 
            ? (map['timestamp'] as Timestamp).toDate() 
            : (map['timestamp'] is DateTime 
                ? map['timestamp'] 
                : DateTime.now()))
        : DateTime.now(),
      latitude: (map['latitude'] ?? 0.0).toDouble(),
      longitude: (map['longitude'] ?? 0.0).toDouble(),
      impactForce: (map['impactForce'] ?? 0.0).toDouble(),
      helpSent: map['helpSent'] ?? false,
      notes: map['notes'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'timestamp': Timestamp.fromDate(timestamp),
      'latitude': latitude,
      'longitude': longitude,
      'impactForce': impactForce,
      'helpSent': helpSent,
      'notes': notes,
    };
  }
} 