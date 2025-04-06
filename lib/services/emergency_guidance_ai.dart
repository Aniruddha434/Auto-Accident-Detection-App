import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:accident_report_system/models/accident_context.dart';
import 'package:accident_report_system/models/guidance_message.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Service class for providing AI-powered emergency guidance
class EmergencyGuidanceAI {
  // API constants - replace with your actual key
  // In production, use a secure method to retrieve the API key
  static const String _apiKey = 'AIzaSyBdjSRS72by6TQ32Gc54JIWzQzQAB3-RAQ'; // Replace with your actual API key
  
  // Singleton pattern
  static final EmergencyGuidanceAI _instance = EmergencyGuidanceAI._internal();
  factory EmergencyGuidanceAI() => _instance;
  EmergencyGuidanceAI._internal();
  
  // AI model client
  late final GenerativeModel _model;
  
  // Track initialization state
  bool _isInitialized = false;
  
  /// Initialize the AI service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      debugPrint('Initializing EmergencyGuidanceAI with API key: ${_apiKey.substring(0, 5)}...');
      _model = GenerativeModel(
        model: 'gemini-2.0-flash',
        apiKey: _apiKey,
        safetySettings: [
          SafetySetting(
            HarmCategory.dangerousContent,
            HarmBlockThreshold.medium,
          ),
          SafetySetting(
            HarmCategory.harassment,
            HarmBlockThreshold.medium,
          ),
        ],
      );
      _isInitialized = true;
      debugPrint('EmergencyGuidanceAI initialized successfully');
    } catch (e) {
      debugPrint('Error initializing EmergencyGuidanceAI: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }
  
  /// Verify that the API key is valid by making a test query
  Future<bool> verifyApiKey() async {
    if (_apiKey == 'AIzaSyBdjSRS72by6TQ32Gc54JIWzQzQAB3-RAQE') {
      debugPrint('Using test mode - API key not configured');
      return true; // Return true to allow the app to work in test mode
    }
    
    if (!_isInitialized) {
      await initialize();
    }
    
    try {
      debugPrint('Verifying API key with test query...');
      final testPrompt = 'Test connection';
      final content = [Content.text(testPrompt)];
      final response = await _model.generateContent(content);
      final isValid = response.text != null;
      debugPrint('API key verification ${isValid ? 'successful' : 'failed'}');
      return isValid;
    } catch (e) {
      debugPrint('Error verifying API key: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      return false;
    }
  }
  
  /// Get emergency guidance based on the accident context
  Future<GuidanceMessage> getEmergencyGuidance(AccidentContext context, {String? userQuery}) async {
    if (_apiKey == 'YAIzaSyBdjSRS72by6TQ32Gc54JIWzQzQAB3-RAQ') {
      debugPrint('Using fallback guidance - API key not configured');
      return _getFallbackGuidance(context, userQuery: userQuery);
    }
    
    if (!_isInitialized) {
      debugPrint('AI service not initialized, initializing now...');
      await initialize();
    }
    
    try {
      final prompt = userQuery != null 
          ? _buildFollowUpPrompt(userQuery, context)
          : _buildPrompt(context);
      
      debugPrint('Generated prompt: ${prompt.substring(0, min(100, prompt.length))}...');
      
      // Create content list for newer API version
      final content = [Content.text(prompt)];
      debugPrint('Sending request to Gemini API...');
      
      // First verify the API key is working
      final isValid = await verifyApiKey();
      if (!isValid) {
        debugPrint('API key verification failed, using fallback guidance');
        return _getFallbackGuidance(context, userQuery: userQuery);
      }
      
      final response = await _model.generateContent(content);
      
      if (response.text == null) {
        debugPrint('Received null response from AI');
        throw Exception('No response from AI');
      }

      final responseText = response.text!;
      debugPrint('Received AI response: ${responseText.substring(0, min(100, responseText.length))}...');
      
      // Log this interaction
      await _logInteraction(context, responseText);
      
      return _structureGuidance(responseText, context);
    } catch (e) {
      debugPrint('Error getting emergency guidance: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      return _getFallbackGuidance(context, userQuery: userQuery);
    }
  }
  
  /// Build a detailed prompt for the AI based on the accident context
  String _buildPrompt(AccidentContext context) {
    return '''
You are an emergency response AI assistant. Provide immediate guidance for the following situation:

Accident Type: ${context.type}
Location: ${context.getLocation}
Time: ${context.timestamp}
Severity: ${context.getSeverity}
Description: ${context.getDescription}

Please provide:
1. Immediate actions to take
2. Safety precautions
3. Emergency contact information
4. Next steps

Keep the response clear, concise, and focused on immediate safety.
''';
  }
  
  /// Process the raw AI response into a structured guidance message
  GuidanceMessage _structureGuidance(String response, AccidentContext context) {
    // For an API response, create a conversational format
    if (response.isNotEmpty) {
      return GuidanceMessage(
        type: MessageType.aiResponse,
        content: response,
        // Use empty lists for structured data since we're using content field
        immediateActions: ['AI RESPONSE'],
        secondarySteps: _formatResponseAsParagraphs(response),
        safetyWarnings: [],
        rawResponse: response,
        timestamp: DateTime.now(),
      );
    }

    // Original code for structured responses
    final sections = response.split('\n\n');
    final structuredResponse = StringBuffer();

    structuredResponse.writeln('🚨 EMERGENCY GUIDANCE 🚨\n');
    structuredResponse.writeln('Based on your reported ${context.type.toLowerCase()} accident:\n');

    for (var section in sections) {
      if (section.trim().isEmpty) continue;
      
      if (section.toLowerCase().contains('immediate actions')) {
        structuredResponse.writeln('🆘 IMMEDIATE ACTIONS:');
        structuredResponse.writeln(section.replaceAll('Immediate actions:', '').trim());
      } else if (section.toLowerCase().contains('safety precautions')) {
        structuredResponse.writeln('\n⚠️ SAFETY PRECAUTIONS:');
        structuredResponse.writeln(section.replaceAll('Safety precautions:', '').trim());
      } else if (section.toLowerCase().contains('emergency contact')) {
        structuredResponse.writeln('\n📞 EMERGENCY CONTACTS:');
        structuredResponse.writeln(section.replaceAll('Emergency contact information:', '').trim());
      } else if (section.toLowerCase().contains('next steps')) {
        structuredResponse.writeln('\n➡️ NEXT STEPS:');
        structuredResponse.writeln(section.replaceAll('Next steps:', '').trim());
      } else {
        structuredResponse.writeln('\n$section');
      }
    }

    return GuidanceMessage(
      type: MessageType.aiResponse,
      content: structuredResponse.toString(),
      timestamp: DateTime.now(),
    );
  }
  
  /// Format a text response into paragraphs suitable for display
  List<String> _formatResponseAsParagraphs(String response) {
    List<String> paragraphs = [];
    
    // Split by double newlines to get paragraphs
    final rawParagraphs = response.split('\n\n');
    
    for (var paragraph in rawParagraphs) {
      // Clean up extra whitespace
      paragraph = paragraph.trim();
      
      // Skip empty paragraphs
      if (paragraph.isEmpty) continue;
      
      // Handle bullet points
      if (paragraph.contains('\n')) {
        // Process multi-line paragraphs or lists
        final lines = paragraph.split('\n');
        String formattedParagraph = '';
        
        for (var line in lines) {
          line = line.trim();
          
          // Add bullet points to list items if they don't already have them
          if (line.startsWith('-') || line.startsWith('*')) {
            line = '• ${line.substring(1).trim()}';
          } else if (RegExp(r'^\d+\.').hasMatch(line)) {
            // Convert numbered lists to bullet points for consistency
            line = '• ${line.replaceFirst(RegExp(r'^\d+\.'), '').trim()}';
          }
          
          if (formattedParagraph.isNotEmpty) {
            formattedParagraph += '\n$line';
          } else {
            formattedParagraph = line;
          }
        }
        
        paragraphs.add(formattedParagraph);
      } else {
        paragraphs.add(paragraph);
      }
    }
    
    // For short responses, still provide at least one paragraph
    if (paragraphs.isEmpty) {
      paragraphs.add(response.trim());
    }
    
    return paragraphs;
  }
  
  /// Log the interaction for improvement and analytics
  Future<void> _logInteraction(AccidentContext context, String response) async {
    try {
      // Log anonymized data to Firebase (if available)
      await FirebaseFirestore.instance.collection('ai_interactions').add({
        'contextType': context.type,
        'severity': context.getSeverity,
        'hasInjuries': context.injuries.toLowerCase() != 'none' && context.injuries.isNotEmpty,
        'responseLength': response.length,
        'timestamp': FieldValue.serverTimestamp(),
      });
      
      // Also store locally for offline access to previous guidance
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList('guidance_history') ?? [];
      
      final interaction = json.encode({
        'context': context.toMap(),
        'response': response,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      // Keep the last 10 interactions
      if (history.length >= 10) history.removeAt(0);
      history.add(interaction);
      
      await prefs.setStringList('guidance_history', history);
    } catch (e) {
      debugPrint('Failed to log AI interaction: $e');
    }
  }
  
  /// Provide fallback guidance if AI generation fails
  GuidanceMessage _getFallbackGuidance(AccidentContext context, {String? userQuery}) {
    // Determine if the accident is severe based on context
    final isSevere = context.getSeverity >= 3 || 
                    context.airbagDeployed || 
                    context.injuries.toLowerCase().contains('serious') ||
                    context.injuries.toLowerCase().contains('bleeding');
    
    // If this is a follow-up question, provide a specific response
    if (userQuery != null && userQuery.isNotEmpty) {
      return _getFollowUpFallbackResponse(userQuery, context, isSevere);
    }
    
    List<String> immediateActions;
    List<String> secondarySteps;
    List<String> safetyWarnings;
    
    if (isSevere) {
      // Guidance for severe accidents
      immediateActions = [
        'Call emergency services (911) immediately',
        'Don\'t move injured people unless there is immediate danger',
        'Turn on hazard lights and set up warning triangles if available',
        'Keep injured persons warm and still',
      ];
      
      secondarySteps = [
        'Exchange information with other involved parties',
        'Take photos of the scene, vehicles, and injuries',
        'Get contact information from witnesses',
        'Contact your insurance company',
      ];
      
      safetyWarnings = [
        'Never leave the scene of an accident',
        'Be aware of traffic and stay clear of the roadway',
        'Watch for fuel leaks or fire hazards',
      ];
    } else {
      // Guidance for minor accidents
      immediateActions = [
        'Move vehicles to a safe location if possible',
        'Check for injuries and call for medical help if needed',
        'Turn on hazard lights',
        'Exchange information with other drivers',
      ];
      
      secondarySteps = [
        'Take photos of the vehicles and accident scene',
        'Get contact information from witnesses',
        'Call your insurance company to report the accident',
        'File a police report if required in your area',
      ];
      
      safetyWarnings = [
        'Stay clear of traffic',
        'Don\'t discuss fault or liability at the scene',
        'Beware of delayed symptoms of injury',
      ];
    }
    
    final structured = _structureDefaultGuidance(immediateActions, secondarySteps, safetyWarnings, context);
    
    return GuidanceMessage(
      type: MessageType.aiResponse,
      content: structured,
      timestamp: DateTime.now(),
    );
  }
  
  /// Generate a structured response from default guidance lists
  String _structureDefaultGuidance(List<String> immediateActions, List<String> secondarySteps, 
      List<String> safetyWarnings, AccidentContext context) {
    
    final structuredResponse = StringBuffer();
    structuredResponse.writeln('🚨 EMERGENCY GUIDANCE 🚨\n');
    structuredResponse.writeln('Based on your reported ${context.type.toLowerCase()} accident:\n');
    
    structuredResponse.writeln('🆘 IMMEDIATE ACTIONS:');
    for (var action in immediateActions) {
      structuredResponse.writeln('• $action');
    }
    
    structuredResponse.writeln('\n⚠️ SAFETY PRECAUTIONS:');
    for (var warning in safetyWarnings) {
      structuredResponse.writeln('• $warning');
    }
    
    structuredResponse.writeln('\n➡️ NEXT STEPS:');
    for (var step in secondarySteps) {
      structuredResponse.writeln('• $step');
    }
    
    structuredResponse.writeln('\n📞 EMERGENCY CONTACTS:');
    structuredResponse.writeln('• Emergency Services: 911');
    structuredResponse.writeln('• Police (non-emergency): Local police department');
    structuredResponse.writeln('• Your Insurance: Check your insurance card');
    
    return structuredResponse.toString();
  }

  /// Generate a response for follow-up questions when AI fails
  GuidanceMessage _getFollowUpFallbackResponse(String question, AccidentContext context, bool isSevere) {
    // Convert question to lowercase for easier matching
    final lowerQuestion = question.toLowerCase();
    String response;
    
    // Match common question patterns
    if (lowerQuestion.contains('injur') || lowerQuestion.contains('hurt') || lowerQuestion.contains('pain')) {
      response = 'For injuries:\n\n• Always prioritize medical attention for injuries\n• Call 911 for serious injuries\n• Don\'t move injured people unless there\'s immediate danger\n• Apply first aid if you are trained to do so\n• Keep injured persons warm and monitor their condition';
    } 
    else if (lowerQuestion.contains('police') || lowerQuestion.contains('report')) {
      response = 'Regarding police reports:\n\n• Call the police for accidents with injuries or significant damage\n• In minor accidents without injuries, you may not need police (check local laws)\n• Get the officer\'s name and badge number\n• Ask how to obtain a copy of the police report\n• Provide factual information only';
    }
    else if (lowerQuestion.contains('insur') || lowerQuestion.contains('claim')) {
      response = 'For insurance claims:\n\n• Contact your insurance company as soon as possible\n• Provide all documentation from the accident\n• Take photos of all damage and the accident scene\n• Get contact and insurance information from all involved parties\n• Don\'t admit fault at the scene';
    }
    else if (lowerQuestion.contains('witness') || lowerQuestion.contains('statement')) {
      response = 'About witnesses:\n\n• Get contact information from all witnesses\n• Ask them to describe what they saw\n• Don\'t influence their statements\n• Share witness information with police and insurance\n• Consider recording witness statements if possible (with permission)';
    }
    else if (lowerQuestion.contains('tow') || lowerQuestion.contains('car') || lowerQuestion.contains('vehicle')) {
      response = 'Regarding your vehicle:\n\n• Move it to a safe location if possible and if it\'s drivable\n• Turn on hazard lights\n• Set up emergency triangles if available\n• Call a tow truck if the vehicle is not drivable\n• Don\'t accept towing services you didn\'t request';
    }
    else {
      // Generic response for other types of questions
      response = 'In case of ${context.type.toLowerCase()} accident:\n\n• Always prioritize safety and medical attention first\n• Follow instructions from emergency personnel\n• Document the scene with photos and notes\n• Exchange information with other involved parties\n• Report to insurance as soon as possible\n\nRegarding your question about "${question}":\nPlease contact emergency services at 911 for immediate assistance with specific concerns.';
    }
    
    // Add a reminder about severity if applicable
    if (isSevere) {
      response += '\n\n⚠️ Your accident appears to be severe. Please call emergency services immediately if you haven\'t already done so.';
    }
    
    return GuidanceMessage(
      type: MessageType.aiResponse,
      content: response,
      timestamp: DateTime.now(),
    );
  }
  
  /// Clean up markdown symbols from text
  String _cleanMarkdownSymbols(String text) {
    // Replace * bullet points with proper bullet symbols
    String cleaned = text.replaceAll(RegExp(r'^\s*\*\s+'), '• ');
    
    // Replace - bullet points
    cleaned = cleaned.replaceAll(RegExp(r'^\s*\-\s+'), '• ');
    
    // Replace numbered list items (1., 2., etc.)
    cleaned = cleaned.replaceAll(RegExp(r'^\s*\d+\.\s+'), '• ');
    
    // Clean up multi-line bullet points
    cleaned = cleaned.replaceAll(RegExp(r'\n\s*\*\s+'), '\n• ');
    cleaned = cleaned.replaceAll(RegExp(r'\n\s*\-\s+'), '\n• ');
    cleaned = cleaned.replaceAll(RegExp(r'\n\s*\d+\.\s+'), '\n• ');
    
    // Remove any markdown bold/italic markers
    cleaned = cleaned.replaceAll('**', '');
    cleaned = cleaned.replaceAll('__', '');
    cleaned = cleaned.replaceAll('*', '');
    cleaned = cleaned.replaceAll('_', '');
    
    return cleaned;
  }

  Future<GuidanceMessage> handleFollowUpQuestion(String question, AccidentContext context) async {
    debugPrint('Handling follow-up question: $question');
    
    if (_apiKey == 'YAIzaSyBdjSRS72by6TQ32Gc54JIWzQzQAB3-RAQ') {
      debugPrint('Using test response for follow-up question - API key not configured');
      return _getFollowUpFallbackResponse(question, context, context.getSeverity >= 3);
    }
    
    if (!_isInitialized) {
      debugPrint('AI service not initialized, initializing now...');
      await initialize();
    }

    try {
      final prompt = _buildFollowUpPrompt(question, context);
      debugPrint('Generated prompt: ${prompt.substring(0, min(100, prompt.length))}...');
      
      // Create content list for newer API version
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      
      if (response.text == null) {
        debugPrint('Received null response from AI');
        throw Exception('No response from AI');
      }

      final responseText = response.text!;
      debugPrint('Received AI response: ${responseText.substring(0, min(100, responseText.length))}...');

      // Use the same structured format for consistency
      return GuidanceMessage(
        type: MessageType.aiResponse,
        content: responseText,
        immediateActions: ['AI RESPONSE'], // Signal that this is a conversational response
        secondarySteps: _formatResponseAsParagraphs(responseText),
        safetyWarnings: [],
        rawResponse: responseText,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      debugPrint('Error handling follow-up question: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      return _getFollowUpFallbackResponse(question, context, context.getSeverity >= 3);
    }
  }

  String _buildFollowUpPrompt(String question, AccidentContext context) {
    return '''
Based on the following accident context, please answer the user's question:

Accident Type: ${context.type}
Location: ${context.getLocation}
Time: ${context.timestamp}
Severity: ${context.getSeverity}
Description: ${context.getDescription}

User Question: $question

Please provide a clear, concise, and relevant answer focused on safety and emergency response.
''';
  }
} 