import 'package:flutter/material.dart';
import 'package:accident_report_system/models/guidance_message.dart';
import 'package:accident_report_system/models/accident_context.dart';

/// A dashboard widget with quick access to emergency features
class EmergencyDashboard extends StatelessWidget {
  const EmergencyDashboard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.red.shade300, width: 2),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade600,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: const Text(
              'EMERGENCY RESOURCES',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildEmergencyButton(
                  context,
                  'AI Guidance Assistant',
                  Icons.support_agent,
                  Colors.blue.shade600,
                  () => _openAIGuidance(context),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildEmergencyButton(
                        context,
                        'Call Emergency',
                        Icons.call,
                        Colors.red,
                        () => _callEmergency(context),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildEmergencyButton(
                        context,
                        'Nearby Hospitals',
                        Icons.local_hospital,
                        Colors.green,
                        () => _findHospitals(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build a styled button for emergency actions
  Widget _buildEmergencyButton(
    BuildContext context,
    String text,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white),
      label: Text(
        text,
        style: const TextStyle(color: Colors.white),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// Open the AI guidance assistant with default context
  void _openAIGuidance(BuildContext context) {
    final accidentContext = AccidentContext(
      type: 'General',
      injuries: 'Unknown',
      locationDescription: 'Current location',
      weatherConditions: 'Unknown',
      timestamp: DateTime.now(),
      detectedSeverity: 1,
      airbagDeployed: false,
      vehicleType: 'Unknown',
    );

    Navigator.pushNamed(
      context,
      '/emergency_guidance',
      arguments: {'accidentContext': accidentContext},
    );
  }

  /// Navigate to nearby hospitals screen
  void _findHospitals(BuildContext context) {
    Navigator.pushNamed(context, '/nearby_hospitals');
  }

  /// Open emergency calling feature
  void _callEmergency(BuildContext context) {
    Navigator.pushNamed(context, '/emergency_contacts');
  }
}