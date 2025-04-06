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
  int _selectedCategoryIndex = 0;
  List<String> _guidanceCategories = ['General', 'Medical', 'Safety', 'Vehicle'];

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

  // Method to handle category toggle change
  void _onCategorySelected(int index) {
    if (index == _selectedCategoryIndex) return;
    
    setState(() {
      _selectedCategoryIndex = index;
      _isLoading = true;
    });
    
    // Get guidance for the selected category
    _getGuidanceForCategory(_guidanceCategories[index]);
  }
  
  // Fetch guidance for a specific category
  Future<void> _getGuidanceForCategory(String category) async {
    try {
      // Create a modified context with the selected category
      final updatedContext = AccidentContext(
        type: category,
        injuries: widget.accidentContext.injuries,
        locationDescription: widget.accidentContext.locationDescription,
        weatherConditions: widget.accidentContext.weatherConditions,
        timestamp: widget.accidentContext.timestamp,
        detectedSeverity: widget.accidentContext.detectedSeverity,
        airbagDeployed: widget.accidentContext.airbagDeployed,
        vehicleType: widget.accidentContext.vehicleType,
      );

      // Get category-specific guidance
      final guidance = await _aiService.getEmergencyGuidance(updatedContext);
      
      setState(() {
        _chatHistory.add({
          'isUser': false,
          'message': 'Here\'s guidance for $category:',
          'guidance': guidance,
          'category': category,
        });
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _chatHistory.add({
          'isUser': false,
          'message': 'I\'m having trouble providing $category guidance.',
          'errorMessage': 'Please try another category or call emergency services if needed.'
        });
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode 
        ? Theme.of(context).scaffoldBackgroundColor 
        : Colors.white;
    
    // Get device padding including system navigation
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    
    return WillPopScope(
      onWillPop: () async {
        // Handle back button press - might navigate to home or previous screen
        Navigator.of(context).pop();
        return false; // We handle the navigation ourselves
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).primaryColor,
          title: const Text('Emergency Guidance', style: TextStyle(fontWeight: FontWeight.bold)),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
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
        body: SafeArea(
          bottom: false,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDarkMode
                    ? [
                        Theme.of(context).primaryColor.withOpacity(0.05),
                        Theme.of(context).scaffoldBackgroundColor,
                      ]
                    : [
                        Theme.of(context).primaryColor.withOpacity(0.05),
                        Colors.white,
                      ],
              ),
            ),
            child: Column(
              children: [
                // Category toggle buttons
                _buildCategoryToggleButtons(context, isDarkMode),
                
                // Chat history
                Expanded(
                  child: _isLoading && _chatHistory.isEmpty
                      ? const Center(child: LoadingIndicator())
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                  top: 8,
                                  bottom: 8,
                                  left: isUser ? 40 : 0,
                                  right: isUser ? 0 : 40,
                                ),
                                decoration: BoxDecoration(
                                  color: isUser 
                                      ? Theme.of(context).primaryColor.withOpacity(0.1) 
                                      : isDarkMode 
                                          ? Theme.of(context).cardColor 
                                          : Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      spreadRadius: 1,
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                  border: Border.all(
                                    color: isUser 
                                        ? Theme.of(context).primaryColor.withOpacity(0.2) 
                                        : isDarkMode
                                            ? Colors.grey.withOpacity(0.3)
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
                                        padding: const EdgeInsets.all(14.0),
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
                                              const SizedBox(height: 6),
                                              
                                            Text(
                                              chat['message'] as String,
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: isUser ? FontWeight.normal : FontWeight.w500,
                                                color: isUser 
                                                    ? isDarkMode ? Colors.white : Colors.black87 
                                                    : Theme.of(context).primaryColor,
                                              ),
                                            ),
                                            
                                            if (chat.containsKey('userQuery'))
                                              Container(
                                                margin: const EdgeInsets.only(top: 8, bottom: 8),
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: isDarkMode 
                                                      ? Colors.blue.shade900.withOpacity(0.3)
                                                      : Colors.blue.shade50.withOpacity(0.5),
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: isDarkMode 
                                                        ? Colors.blue.shade800
                                                        : Colors.blue.shade100
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.question_answer, 
                                                      size: 16, 
                                                      color: isDarkMode 
                                                          ? Colors.blue.shade300
                                                          : Colors.blue.shade600
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Flexible(
                                                      child: Text(
                                                        'Query: "${chat['userQuery']}"',
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          fontStyle: FontStyle.italic,
                                                          color: isDarkMode 
                                                              ? Colors.blue.shade200
                                                              : Colors.blue.shade800,
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
                                                    color: isDarkMode
                                                        ? Colors.red.shade900.withOpacity(0.3)
                                                        : Colors.red.shade50,
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(
                                                      color: isDarkMode
                                                          ? Colors.red.shade800
                                                          : Colors.red.shade200
                                                    ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons.error_outline, 
                                                        color: isDarkMode
                                                            ? Colors.red.shade300
                                                            : Colors.red.shade700, 
                                                        size: 18
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          chat['errorMessage'] as String,
                                                          style: TextStyle(
                                                            color: isDarkMode
                                                                ? Colors.red.shade300
                                                                : Colors.red.shade700,
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
                                                  color: isDarkMode
                                                      ? Colors.grey.shade400
                                                      : Colors.grey.shade600,
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
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 12,
                    // Add extra padding at the bottom for system navigation
                    bottom: bottomPadding > 0 ? bottomPadding + 12 : 16
                  ),
                  decoration: BoxDecoration(
                    color: isDarkMode ? 
                      Theme.of(context).cardColor.withOpacity(0.95) : 
                      Colors.white.withOpacity(0.95),
                    border: Border(
                      top: BorderSide(
                        color: isDarkMode ? 
                          Colors.grey.shade800 : 
                          Colors.grey.shade300,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDarkMode 
                                ? Theme.of(context).scaffoldBackgroundColor 
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: isDarkMode
                                  ? Colors.grey.shade700
                                  : Colors.grey.shade300
                            ),
                          ),
                          child: TextField(
                            controller: _messageController,
                            decoration: InputDecoration(
                              hintText: 'Ask for guidance...',
                              hintStyle: TextStyle(
                                color: isDarkMode
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade500
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            ),
                            minLines: 1,
                            maxLines: 3,
                            textCapitalization: TextCapitalization.sentences,
                            style: TextStyle(
                              fontSize: 16,
                              color: isDarkMode ? Colors.white : Colors.black,
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Material(
                        color: Theme.of(context).primaryColor,
                        shape: const CircleBorder(),
                        child: InkWell(
                          onTap: _sendMessage,
                          customBorder: const CircleBorder(),
                          child: Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: Icon(
                              Icons.send,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
  
  // Build category toggle buttons
  Widget _buildCategoryToggleButtons(BuildContext context, bool isDarkMode) {
    return Container(
      height: 50,
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: _guidanceCategories.asMap().entries.map((entry) {
          final index = entry.key;
          final category = entry.value;
          final isSelected = index == _selectedCategoryIndex;
          
          // Determine icon based on category
          IconData icon;
          switch (category) {
            case 'Medical':
              icon = Icons.medical_services;
              break;
            case 'Safety':
              icon = Icons.shield;
              break;
            case 'Vehicle':
              icon = Icons.directions_car;
              break;
            case 'General':
            default:
              icon = Icons.info;
          }
          
          return Container(
            margin: const EdgeInsets.only(right: 8.0),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isLoading ? null : () => _onCategorySelected(index),
                borderRadius: BorderRadius.circular(20),
                child: Ink(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? Theme.of(context).primaryColor
                        : isDarkMode
                            ? Theme.of(context).cardColor
                            : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).primaryColor
                          : isDarkMode
                              ? Colors.grey.shade700
                              : Colors.grey.shade300,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: isSelected
                            ? Colors.white
                            : Theme.of(context).primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        category,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected
                              ? Colors.white
                              : isDarkMode
                                  ? Colors.white
                                  : Theme.of(context).primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
  
  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }
} 