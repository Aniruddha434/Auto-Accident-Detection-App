import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:safedrive_app/providers/auth_provider.dart';
import 'package:safedrive_app/services/sms_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isTesting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Test direct SMS functionality
            ElevatedButton(
              onPressed: _testDirectSms,
              child: const Text('Test Direct SMS'),
            ),
          ],
        ),
      ),
    );
  }

  // Test direct SMS functionality
  Future<void> _testDirectSms() async {
    setState(() {
      _isTesting = true;
    });
    
    try {
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Starting direct SMS test...'),
          duration: Duration(seconds: 2),
        ),
      );
      
      // Get the current user
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final String userId = auth.firebaseUser?.uid ?? 'anonymous';
      
      if (userId == 'anonymous') {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Please sign in to test SMS functionality'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      // Get the SMS service
      final smsService = SmsService();
      
      // First check permission explicitly
      final bool permissionGranted = await smsService.checkSmsPermission();
      if (!permissionGranted) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('SMS permission not granted. Requesting permission...'),
            backgroundColor: Colors.orange,
          ),
        );
        
        final bool permissionRequested = await smsService.requestSmsPermission();
        if (!permissionRequested) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('SMS permission denied. Cannot send test SMS.'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _isTesting = false;
          });
          return;
        }
      }
      
      // Request phone number through dialog
      String? testNumber = await _showPhoneNumberDialog();
      
      // If user cancelled the dialog
      if (testNumber == null || testNumber.isEmpty) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Test cancelled - no phone number provided'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() {
          _isTesting = false;
        });
        return;
      }
      
      // Create a test message
      final String message = 'TEST ALERT from SafeDrive app. This is a test message sent at ${DateTime.now().toString()}';
      
      // Show in-progress indication
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Sending test SMS to $testNumber...'),
          duration: const Duration(seconds: 3),
        ),
      );
      
      // Attempt to send SMS directly
      try {
        final bool sentOk = await smsService.sendSms(testNumber, message);
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(sentOk 
              ? 'SMS test initiated successfully to $testNumber' 
              : 'SMS test failed, but no exception was thrown'),
            backgroundColor: sentOk ? Colors.green : Colors.orange,
          ),
        );
      } catch (e) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('SMS test failed with error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error in SMS test: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }
  
  // Show a dialog to get the test phone number
  Future<String?> _showPhoneNumberDialog() async {
    final TextEditingController phoneController = TextEditingController();
    
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Enter Test Phone Number'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  hintText: 'Enter a valid phone number to test SMS',
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              const Text(
                'Make sure this is a valid number that can receive SMS.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(phoneController.text.trim()),
              child: const Text('Test SMS'),
            ),
          ],
        );
      },
    );
  }
} 