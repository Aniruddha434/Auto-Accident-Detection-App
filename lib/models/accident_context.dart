import 'package:flutter/foundation.dart';

/// Model representing accident context for AI prompting
class AccidentContext {
  final String type;
  final String location;
  final DateTime timestamp;
  final int severity;
  final String description;
  final String injuries;
  final String locationDescription;
  final String weatherConditions;
  final int detectedSeverity;
  final bool airbagDeployed;
  final String vehicleType;

  // Define getters to ensure compatibility with both naming conventions
  int get getSeverity => severity > 0 ? severity : detectedSeverity;
  String get getLocation => location.isNotEmpty ? location : locationDescription;
  String get getDescription => description.isNotEmpty ? description : '$type accident. $injuries. $weatherConditions';

  AccidentContext({
    required this.type,
    this.location = '',
    required this.timestamp,
    this.severity = 0,
    this.description = '',
    required this.injuries,
    required this.locationDescription,
    required this.weatherConditions,
    required this.detectedSeverity,
    required this.airbagDeployed,
    required this.vehicleType,
  });

  /// Convert to a map for storage and API requests
  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'location': getLocation,
      'timestamp': timestamp.toIso8601String(),
      'severity': getSeverity,
      'description': getDescription,
      'injuries': injuries,
      'locationDescription': locationDescription,
      'weatherConditions': weatherConditions,
      'detectedSeverity': detectedSeverity,
      'airbagDeployed': airbagDeployed,
      'vehicleType': vehicleType,
    };
  }

  /// Create from a map (for storage retrieval)
  factory AccidentContext.fromMap(Map<String, dynamic> map) {
    return AccidentContext(
      type: map['type'] ?? 'Unknown',
      location: map['location'] ?? '',
      timestamp: map['timestamp'] != null 
          ? DateTime.parse(map['timestamp']) 
          : DateTime.now(),
      severity: map['severity'] ?? 0,
      description: map['description'] ?? '',
      injuries: map['injuries'] ?? 'Unknown',
      locationDescription: map['locationDescription'] ?? 'Unknown',
      weatherConditions: map['weatherConditions'] ?? 'Unknown',
      detectedSeverity: map['detectedSeverity'] ?? 1,
      airbagDeployed: map['airbagDeployed'] ?? false,
      vehicleType: map['vehicleType'] ?? 'Unknown',
    );
  }

  @override
  String toString() {
    return 'AccidentContext(type: $type, location: $getLocation, severity: $getSeverity)';
  }
} 