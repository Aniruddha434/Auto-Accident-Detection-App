import 'package:flutter/foundation.dart';

/// Message type enum for different kinds of messages
enum MessageType {
  userInput,
  aiResponse,
  error,
  info,
  warning
}

/// Model representing structured emergency guidance from the AI
class GuidanceMessage {
  /// Type of message
  final MessageType? type;
  
  /// Content of the message
  final String? content;

  /// Critical steps to take immediately
  final List<String> immediateActions;
  
  /// Steps to take after handling immediate concerns
  final List<String> secondarySteps;
  
  /// Important safety considerations
  final List<String> safetyWarnings;
  
  /// Raw response from the AI service
  final String rawResponse;
  
  /// Timestamp when the guidance was generated
  final DateTime timestamp;

  GuidanceMessage({
    this.type,
    this.content,
    this.immediateActions = const [],
    this.secondarySteps = const [],
    this.safetyWarnings = const [],
    this.rawResponse = '',
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Convert to a map for storage
  Map<String, dynamic> toMap() {
    return {
      'type': type?.toString(),
      'content': content,
      'immediateActions': immediateActions,
      'secondarySteps': secondarySteps,
      'safetyWarnings': safetyWarnings,
      'rawResponse': rawResponse,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Create from a map (for storage retrieval)
  factory GuidanceMessage.fromMap(Map<String, dynamic> map) {
    return GuidanceMessage(
      type: map['type'] != null ? 
          MessageType.values.firstWhere(
            (e) => e.toString() == map['type'],
            orElse: () => MessageType.info
          ) : null,
      content: map['content'],
      immediateActions: List<String>.from(map['immediateActions'] ?? []),
      secondarySteps: List<String>.from(map['secondarySteps'] ?? []),
      safetyWarnings: List<String>.from(map['safetyWarnings'] ?? []),
      rawResponse: map['rawResponse'] ?? '',
      timestamp: map['timestamp'] != null 
          ? DateTime.parse(map['timestamp']) 
          : DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'GuidanceMessage(type: $type, content: $content, immediateActions: $immediateActions, secondarySteps: $secondarySteps, safetyWarnings: $safetyWarnings)';
  }
} 