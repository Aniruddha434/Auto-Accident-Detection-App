import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:accident_report_system/providers/auth_provider.dart';
import 'package:accident_report_system/providers/accident_provider.dart';
import 'package:accident_report_system/services/voice_command_service.dart';
import 'package:accident_report_system/services/background_service.dart';
import 'package:accident_report_system/services/sms_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _darkModeEnabled = false;
  bool _voiceCommandsEnabled = true;
  bool _backgroundMonitoringEnabled = false;
  bool _crashDetectionEnabled = true;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTesting = false;
  String _appVersion = '1.0.0';

  final VoiceCommandService _voiceCommandService = VoiceCommandService();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _getAppVersion();
  }

  Future<void> _getAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _appVersion = '${packageInfo.version} (${packageInfo.buildNumber})';
      });
    } catch (e) {
      debugPrint('Error getting app version: $e');
    }
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load all settings
      setState(() {
        _darkModeEnabled = prefs.getBool('dark_mode_enabled') ?? false;
        _backgroundMonitoringEnabled = prefs.getBool('background_monitoring_enabled') ?? false;
        _crashDetectionEnabled = prefs.getBool('crash_detection_enabled') ?? true;
        
        // For voice commands, we'll use the actual state from the service
        _voiceCommandsEnabled = _voiceCommandService.isListening;
      });
      
    } catch (e) {
      debugPrint('Error loading settings: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Save all settings
      await prefs.setBool('dark_mode_enabled', _darkModeEnabled);
      await prefs.setBool('background_monitoring_enabled', _backgroundMonitoringEnabled);
      await prefs.setBool('crash_detection_enabled', _crashDetectionEnabled);
      
      // Update the voice command service
      if (_voiceCommandService.isListening != _voiceCommandsEnabled) {
        _voiceCommandsEnabled 
            ? await _voiceCommandService.startListening()
            : await _voiceCommandService.stopListening();
        
        await _voiceCommandService.saveSettings(_voiceCommandsEnabled);
      }
      
      // Update background service
      if (_backgroundMonitoringEnabled) {
        await BackgroundService.startService();
      } else {
        await BackgroundService.stopService();
      }
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved successfully')),
        );
      }
    } catch (e) {
      debugPrint('Error saving settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving settings: $e')),
        );
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _testAccidentAlert() async {
    if (_isTesting) return;
    
    setState(() {
      _isTesting = true;
    });
    
    try {
      await _voiceCommandService.simulateAccidentAlert();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Test alert sent successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  void _testSensorDetection() async {
    // Get the accident provider
    final accidentProvider = Provider.of<AccidentProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.firebaseUser?.uid;
    
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: You must be signed in to test accident detection'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    // Show initial feedback
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Simulating accident sensor readings...'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ),
    );
    
    // Trigger a simulated accident detection
    try {
      accidentProvider.simulateAccidentDetection(userId);
      
      // Show feedback that simulation started
      Future.delayed(Duration(seconds: 3), () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Simulation started - check for countdown notification'),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 4),
            ),
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error simulating sensor detection: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
      
      // Get the accident provider
      final accidentProvider = Provider.of<AccidentProvider>(context, listen: false);
      
      // Get test number - normally we'd retrieve from Firestore
      const String testNumber = '1234567890'; // REPLACE WITH YOUR TEST NUMBER for testing
      
      // Get the SMS service
      final smsService = SmsService();
      
      // Create a test message
      final String message = 'TEST ALERT from AccidentPre app. This is a test message sent at ${DateTime.now().toString()}';
      
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
  
  // Test direct navigation to hospitals screen
  void _testDirectNavigation() {
    setState(() {
      _isTesting = true;
    });
    
    try {
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Testing navigation to hospitals screen...'),
          duration: Duration(seconds: 2),
        ),
      );
      
      // Get the accident provider
      final accidentProvider = Provider.of<AccidentProvider>(context, listen: false);
      
      // Direct call to the navigation method
      accidentProvider.showNearbyHospitals();
      
      // Check after a short delay if navigation was successful
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _isTesting = false;
          });
          
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('Navigation test completed'),
              backgroundColor: Colors.green,
            ),
          );
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error in navigation test: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader('General Settings', Icons.settings, theme),
                  _buildSettingsCard(
                    children: [
                      _buildSwitchTile(
                        title: 'Dark Mode',
                        subtitle: 'Enable dark theme for the app',
                        value: _darkModeEnabled,
                        onChanged: (value) {
                          setState(() {
                            _darkModeEnabled = value;
                          });
                        },
                      ),
                      const Divider(),
                      _buildSwitchTile(
                        title: 'Voice Commands',
                        subtitle: 'Enable emergency voice detection',
                        value: _voiceCommandsEnabled,
                        onChanged: (value) {
                          setState(() {
                            _voiceCommandsEnabled = value;
                          });
                        },
                      ),
                      const Divider(),
                      _buildSwitchTile(
                        title: 'Background Monitoring',
                        subtitle: 'Monitor for accidents when app is closed',
                        value: _backgroundMonitoringEnabled,
                        onChanged: (value) {
                          setState(() {
                            _backgroundMonitoringEnabled = value;
                          });
                        },
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  _buildSectionHeader('Accident Detection', Icons.car_crash, theme),
                  _buildSettingsCard(
                    children: [
                      _buildSwitchTile(
                        title: 'Crash Detection',
                        subtitle: 'Automatically detect accidents using sensors',
                        value: _crashDetectionEnabled,
                        onChanged: (value) {
                          setState(() {
                            _crashDetectionEnabled = value;
                          });
                        },
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  _buildSectionHeader('Account', Icons.person, theme),
                  _buildSettingsCard(
                    children: [
                      _buildNavigationTile(
                        title: 'Edit Profile',
                        subtitle: 'Change your name, email, and other details',
                        icon: Icons.person,
                        onTap: () {
                          Navigator.pushNamed(context, '/profile');
                        },
                      ),
                      const Divider(),
                      _buildNavigationTile(
                        title: 'Emergency Contacts',
                        subtitle: 'Manage people to notify in case of accident',
                        icon: Icons.contact_phone,
                        onTap: () {
                          Navigator.pushNamed(context, '/emergency_contacts');
                        },
                      ),
                      const Divider(),
                      _buildNavigationTile(
                        title: 'Sign Out',
                        subtitle: 'Log out of your account',
                        icon: Icons.logout,
                        iconColor: Colors.red,
                        textColor: Colors.red,
                        onTap: () {
                          _confirmSignOut(context);
                        },
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  _buildSectionHeader('About', Icons.info_outline, theme),
                  _buildSettingsCard(
                    children: [
                      ListTile(
                        title: const Text('App Version'),
                        subtitle: Text(_appVersion),
                        leading: const Icon(Icons.info),
                      ),
                      const Divider(),
                      ListTile(
                        title: const Text('Privacy Policy'),
                        subtitle: const Text('View our privacy policy'),
                        leading: const Icon(Icons.privacy_tip),
                        onTap: () {
                          // TODO: Implement privacy policy navigation
                        },
                      ),
                      const Divider(),
                      ListTile(
                        title: const Text('Terms of Service'),
                        subtitle: const Text('View our terms of service'),
                        leading: const Icon(Icons.description),
                        onTap: () {
                          // TODO: Implement terms of service navigation
                        },
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  _buildSectionHeader('Testing', Icons.bug_report, theme),
                  _buildSettingsCard(
                    children: [
                      ListTile(
                        title: const Text('Test Accident Alert'),
                        subtitle: const Text('Simulates a manual accident report'),
                        trailing: _isTesting
                            ? const CircularProgressIndicator()
                            : const Icon(Icons.send),
                        onTap: _isTesting ? null : _testAccidentAlert,
                      ),
                      ListTile(
                        title: const Text('Test Sensor Detection'),
                        subtitle: const Text('Simulates accelerometer readings for detection'),
                        trailing: _isTesting
                            ? const CircularProgressIndicator()
                            : const Icon(Icons.sensors),
                        onTap: _isTesting ? null : _testSensorDetection,
                      ),
                      const Divider(),
                      ListTile(
                        title: const Text('Direct SMS Test'),
                        subtitle: const Text('Directly tests SMS functionality'),
                        trailing: _isTesting
                            ? const CircularProgressIndicator()
                            : const Icon(Icons.message),
                        onTap: _isTesting ? null : _testDirectSms,
                      ),
                      ListTile(
                        title: const Text('Direct Navigation Test'),
                        subtitle: const Text('Directly navigate to hospitals screen'),
                        trailing: _isTesting
                            ? const CircularProgressIndicator()
                            : const Icon(Icons.local_hospital),
                        onTap: _isTesting ? null : _testDirectNavigation,
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Save Settings'),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, bottom: 12.0),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard({required List<Widget> children}) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          children: children,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 13),
      ),
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }

  Widget _buildNavigationTile({
    required String title,
    required String subtitle,
    required IconData icon,
    Color? iconColor,
    Color? textColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      title: Text(
        title,
        style: TextStyle(color: textColor),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 13),
      ),
      leading: Icon(
        icon,
        color: iconColor,
      ),
      onTap: onTap,
      trailing: const Icon(Icons.chevron_right),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final accidentProvider = Provider.of<AccidentProvider>(context, listen: false);
      
      // Stop monitoring
      accidentProvider.stopMonitoring();
      
      // Sign out
      await authProvider.signOut();
      
      // Redirect to login screen
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    }
  }
} 