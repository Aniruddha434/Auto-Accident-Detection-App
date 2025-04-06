import 'package:flutter/material.dart';
import 'package:accident_report_system/models/guidance_message.dart';

/// A widget that displays structured guidance from the AI
class GuidanceCard extends StatelessWidget {
  final GuidanceMessage guidance;

  const GuidanceCard({
    Key? key,
    required this.guidance,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    // Check if this is a conversational response
    final isConversational = guidance.immediateActions.isNotEmpty && 
                             guidance.immediateActions[0] == 'AI RESPONSE';
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isConversational 
              ? isDarkMode ? Colors.blue.shade700 : Colors.blue.shade200
              : isDarkMode ? Colors.grey.shade700 : Colors.grey.shade200,
          width: 1,
        ),
      ),
      color: isConversational 
          ? isDarkMode ? Colors.blue.shade900.withOpacity(0.3) : Colors.blue.shade50.withOpacity(0.5) 
          : isDarkMode ? Theme.of(context).cardColor : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title bar for AI Response
            if (isConversational)
              _buildConversationalResponse(context, isDarkMode)
            else
              _buildStructuredGuidance(context, isDarkMode),
          ],
        ),
      ),
    );
  }
  
  /// Builds the conversational response display
  Widget _buildConversationalResponse(BuildContext context, bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: isDarkMode 
                ? Colors.blue.shade800.withOpacity(0.4) 
                : Colors.blue.shade100.withOpacity(0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.smart_toy_outlined, 
                color: isDarkMode ? Colors.blue.shade300 : Colors.blue.shade700, 
                size: 18
              ),
              const SizedBox(width: 8),
              Text(
                'AI ASSISTANT',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.blue.shade300 : Colors.blue.shade800,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // Response paragraphs
        ...guidance.secondarySteps.map((paragraph) {
          // Check if the paragraph starts with a bullet point
          final bool isBulletPoint = paragraph.trimLeft().startsWith('•');
          
          return Padding(
            padding: EdgeInsets.only(
              bottom: 12, 
              left: isBulletPoint ? 4 : 0 // Add indent for bullet points
            ),
            child: Text(
              paragraph,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
          );
        }),
      ],
    );
  }
  
  /// Builds the structured guidance display (immediate actions, next steps, warnings)
  Widget _buildStructuredGuidance(BuildContext context, bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Immediate actions section
        if (guidance.immediateActions.isNotEmpty) ...[
          _buildSectionHeader(
            context, 
            'DO IMMEDIATELY', 
            isDarkMode ? Colors.red.shade300 : Colors.red.shade700
          ),
          const SizedBox(height: 8),
          ...guidance.immediateActions.map((action) => _buildActionItem(
            context, 
            action,
            Icons.priority_high,
            isDarkMode ? Colors.red.shade300 : Colors.red.shade400,
            isDarkMode,
          )),
          const SizedBox(height: 16),
        ],
        
        // Secondary steps section
        if (guidance.secondarySteps.isNotEmpty) ...[
          _buildSectionHeader(
            context, 
            'NEXT STEPS', 
            isDarkMode ? Colors.blue.shade300 : Colors.blue.shade700
          ),
          const SizedBox(height: 8),
          ...guidance.secondarySteps.map((step) => _buildActionItem(
            context, 
            step,
            Icons.arrow_forward,
            isDarkMode ? Colors.blue.shade300 : Colors.blue.shade400,
            isDarkMode,
          )),
          const SizedBox(height: 16),
        ],
        
        // Safety warnings section
        if (guidance.safetyWarnings.isNotEmpty) ...[
          _buildSectionHeader(
            context, 
            'SAFETY WARNINGS', 
            isDarkMode ? Colors.orange.shade300 : Colors.orange.shade700
          ),
          const SizedBox(height: 8),
          ...guidance.safetyWarnings.map((warning) => _buildActionItem(
            context, 
            warning,
            Icons.warning_amber,
            isDarkMode ? Colors.orange.shade300 : Colors.orange.shade400,
            isDarkMode,
          )),
        ],
      ],
    );
  }

  /// Builds a section header with an accent color
  Widget _buildSectionHeader(BuildContext context, String title, Color color) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(isDarkMode ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(isDarkMode ? 0.4 : 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            title.contains('IMMEDIATELY') ? Icons.flash_on :
            title.contains('NEXT') ? Icons.arrow_forward_ios :
            Icons.warning_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds an action item with an icon
  Widget _buildActionItem(BuildContext context, String text, IconData icon, Color color, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
} 