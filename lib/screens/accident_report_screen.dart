import 'package:accident_report_system/models/guidance_message.dart';

class _AccidentReportScreenState extends State<AccidentReportScreen> {
  // ... existing code ...

  void _openEmergencyGuidance() {
    // Create accident context from current report data
    final accidentContext = AccidentContext(
      type: _selectedAccidentType ?? 'Vehicle collision',
      injuries: _injuriesController.text.isNotEmpty ? _injuriesController.text : 'None reported',
      locationDescription: _locationController.text.isNotEmpty ? _locationController.text : 'Unknown location',
      weatherConditions: _weatherController.text.isNotEmpty ? _weatherController.text : 'Unknown weather',
      timestamp: DateTime.now(),
      detectedSeverity: _calculateSeverity(),
      airbagDeployed: _airbagDeployed ?? false,
      vehicleType: _vehicleTypeController.text.isNotEmpty ? _vehicleTypeController.text : 'Car',
    );
    
    // Navigate to emergency guidance screen
    Navigator.pushNamed(
      context, 
      '/emergency_guidance',
      arguments: {'accidentContext': accidentContext},
    );
  }

  int _calculateSeverity() {
    int severity = 1; // Default: minor
    
    // Increase severity based on various factors
    if (_airbagDeployed ?? false) severity += 2;
    
    // Check for severe injury descriptions
    final injuryText = _injuriesController.text.toLowerCase();
    if (injuryText.contains('severe') || 
        injuryText.contains('serious') || 
        injuryText.contains('blood') ||
        injuryText.contains('unconscious')) {
      severity += 2;
    } else if (injuryText.isNotEmpty && injuryText != 'none') {
      severity += 1;
    }
    
    // Cap at maximum severity of 5
    return severity > 5 ? 5 : severity;
  }

  // ... existing code ...

  @override
  Widget build(BuildContext context) {
    // ... existing code ...

    return Scaffold(
      // ... existing code ...

      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openEmergencyGuidance,
        label: Text('Get Emergency Guidance'),
        icon: Icon(Icons.support_agent),
      ),
    );
  }
} 