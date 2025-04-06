import 'package:flutter/material.dart';
import 'package:accident_report_system/models/guidance_message.dart';
import 'package:accident_report_system/models/accident_context.dart';
import 'package:accident_report_system/services/emergency_guidance_ai.dart';
import 'package:accident_report_system/widgets/loading_indicator.dart';
import 'package:accident_report_system/widgets/guidance_card.dart';

class EmergencyGuidanceScreen extends StatefulWidget {
  final AccidentContext accidentContext;

  const EmergencyGuidanceScreen({
    Key? key,
    required this.accidentContext,
  }) : super(key: key);

  @override
  State<EmergencyGuidanceScreen> createState() => _EmergencyGuidanceScreenState();
}

class _EmergencyGuidanceScreenState extends State<EmergencyGuidanceScreen> {
  final TextEditingController _messageController = TextEditingController();
  final EmergencyGuidanceAI _aiService = EmergencyGuidanceAI();
  
  bool _isLoading = true;
  GuidanceMessage? _initialGuidance;
  List<Map<String, dynamic>> _chatHistory = [];

  @override
  void initState() {
    super.initState();
    _initializeAI();
  }

  Future<void> _initializeAI() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Initialize the AI service
      await _aiService.initialize();
      
      // Get initial guidance based on accident context
      final guidance = await _aiService.getEmergencyGuidance(widget.accidentContext);
      
      setState(() {
        _initialGuidance = guidance;
        _chatHistory.add({
          'isUser': false,
          'message': 'Here\'s what you should do based on the accident information:',
          'guidance': guidance,
        });
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _chatHistory.add({
          'isUser': false,
          'message': 'I\'m having trouble providing guidance right now. Please call emergency services if needed.',
        });
        _isLoading = false;
      });
    }
  }

  void _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;
    
    setState(() {
      _chatHistory.add({
        'isUser': true,
        'message': message,
      });
      _messageController.clear();
      _isLoading = true;
    });

    try {
      // Create a modified context with the user's query
      final updatedContext = AccidentContext(
        type: widget.accidentContext.type,
        injuries: widget.accidentContext.injuries,
        locationDescription: widget.accidentContext.locationDescription,
        weatherConditions: widget.accidentContext.weatherConditions,
        timestamp: widget.accidentContext.timestamp,
        detectedSeverity: widget.accidentContext.detectedSeverity,
        airbagDeployed: widget.accidentContext.airbagDeployed,
        vehicleType: widget.accidentContext.vehicleType,
      );

      // Get AI response with the user's message included
      final guidance = await _aiService.getEmergencyGuidance(updatedContext, userQuery: message);
      
      setState(() {
        _chatHistory.add({
          'isUser': false,
          'message': message.startsWith('?') || message.endsWith('?') 
            ? 'Here\'s the answer to your question:' 
            : 'Here\'s what you should do:',
          'guidance': guidance,
          'userQuery': message, // Store the user's query for display
        });
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _chatHistory.add({
          'isUser': false,
          'message': 'I\'m having trouble responding to your question: "$message"',
          'errorMessage': 'Please try again or call emergency services if needed.'
        });
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor,
        title: const Text('Emergency Guidance', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.call, color: Colors.white),
            tooltip: 'Call Emergency Services',
            onPressed: () {
              // TODO: Implement emergency call functionality
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Calling emergency services...'),
                  backgroundColor: Colors.red,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).primaryColor.withOpacity(0.05),
              Colors.white,
            ],
          ),
        ),
        child: Column(
          children: [
            // Chat history
            Expanded(
              child: _isLoading && _chatHistory.isEmpty
                  ? const Center(child: LoadingIndicator())
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      itemCount: _chatHistory.length + (_isLoading ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _chatHistory.length) {
                          return const Padding(
                            padding: EdgeInsets.all(20.0),
                            child: Center(child: LoadingIndicator()),
                          );
                        }
                        
                        final chat = _chatHistory[index];
                        final isUser = chat['isUser'] as bool;
                        
                        return Align(
                          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.8,
                            ),
                            margin: EdgeInsets.only(
                              top: 12,
                              bottom: 12,
                              left: isUser ? 40 : 0,
                              right: isUser ? 0 : 40,
                            ),
                            decoration: BoxDecoration(
                              color: isUser 
                                  ? Theme.of(context).primaryColor.withOpacity(0.1) 
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  spreadRadius: 1,
                                  blurRadius: 5,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                              border: Border.all(
                                color: isUser 
                                    ? Theme.of(context).primaryColor.withOpacity(0.2) 
                                    : Colors.grey.withOpacity(0.1),
                                width: 1,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onLongPress: () {
                                    // Copy text to clipboard
                                    final textToCopy = chat.containsKey('guidance') 
                                        ? chat['guidance'].content ?? chat['message'] 
                                        : chat['message'];
                                    
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Message copied to clipboard'),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment: isUser 
                                          ? CrossAxisAlignment.end 
                                          : CrossAxisAlignment.start,
                                      children: [
                                        if (!isUser && !chat.containsKey('guidance') && !chat.containsKey('errorMessage'))
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.medical_services_outlined, 
                                                size: 18, 
                                                color: Theme.of(context).primaryColor,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Emergency Assistant',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: Theme.of(context).primaryColor,
                                                ),
                                              ),
                                            ],
                                          ),
                                        if (!isUser && !chat.containsKey('guidance') && !chat.containsKey('errorMessage'))
                                          const SizedBox(height: 8),
                                          
                                        Text(
                                          chat['message'] as String,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: isUser ? FontWeight.normal : FontWeight.w500,
                                            color: isUser ? Colors.black87 : Theme.of(context).primaryColor,
                                          ),
                                        ),
                                        
                                        if (chat.containsKey('userQuery'))
                                          Container(
                                            margin: const EdgeInsets.only(top: 8, bottom: 8),
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade50.withOpacity(0.5),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: Colors.blue.shade100),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.question_answer, size: 16, color: Colors.blue.shade600),
                                                const SizedBox(width: 8),
                                                Flexible(
                                                  child: Text(
                                                    'Query: "${chat['userQuery']}"',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontStyle: FontStyle.italic,
                                                      color: Colors.blue.shade800,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        
                                        if (!isUser && chat.containsKey('guidance'))
                                          Padding(
                                            padding: const EdgeInsets.only(top: 8.0),
                                            child: GuidanceCard(guidance: chat['guidance'] as GuidanceMessage),
                                          ),
                                          
                                        if (!isUser && chat.containsKey('errorMessage'))
                                          Padding(
                                            padding: const EdgeInsets.only(top: 12),
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: Colors.red.shade50,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: Colors.red.shade200),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      chat['errorMessage'] as String,
                                                      style: TextStyle(
                                                        color: Colors.red.shade700,
                                                        fontWeight: FontWeight.w500,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          
                                        Padding(
                                          padding: const EdgeInsets.only(top: 8.0),
                                          child: Text(
                                            _formatTimestamp(DateTime.now()),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            
            // Input field
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: 'Ask for guidance...',
                          hintStyle: TextStyle(color: Colors.grey.shade500),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        ),
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(fontSize: 16),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _sendMessage,
                      tooltip: 'Send message',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Helper method to format timestamps
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);
    
    if (messageDate == today) {
      return 'Today, ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday, ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}, ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }
  
  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }
} 