import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';

import 'package:accident_report_system/models/user_model.dart';
import 'package:accident_report_system/providers/auth_provider.dart';
import 'package:accident_report_system/providers/accident_provider.dart';
import 'package:accident_report_system/services/voice_command_service.dart';
import 'package:accident_report_system/screens/accident_history_screen.dart';
import 'package:accident_report_system/screens/emergency_contacts_screen.dart';
import 'package:accident_report_system/widgets/emergency_dashboard.dart';
import 'package:accident_report_system/models/guidance_message.dart';
import 'package:accident_report_system/services/background_service.dart';
import 'package:accident_report_system/models/accident_context.dart';
import 'package:accident_report_system/services/emergency_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  bool _monitoringEnabled = false;
  bool _isBackgroundServiceRunning = false;
  bool _voiceCommandsEnabled = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    await _requestPermissions();
    
    // Initialize voice command service with proper context
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeVoiceCommandService();
    });
    
    _fetchEmergencyContacts();
  }

  Future<void> _initializeVoiceCommandService() async {
    debugPrint('Initializing voice command service...');
    final voiceCommandService = VoiceCommandService();
    
    // Set the application context first
    voiceCommandService.setApplicationContext(context);
    
    // Add a delay to ensure context is fully ready
    await Future.delayed(const Duration(milliseconds: 500));
    
    bool initialized = await voiceCommandService.initialize();
    
    if (initialized) {
      // Load saved settings and start listening if enabled
      await voiceCommandService.loadSettings();
      
    setState(() {
        _voiceCommandsEnabled = voiceCommandService.isListening;
      });
      
      // Make sure the context is set again after initialization
      voiceCommandService.setApplicationContext(context);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voice commands initialized'),
          duration: Duration(seconds: 2),
        ),
      );
      
      // Add a tap handler to the voice command card to reinitialize
      debugPrint('Voice commands initialized. Listening status: ${voiceCommandService.isListening}');
    } else {
      setState(() {
        _voiceCommandsEnabled = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to initialize voice commands'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.orange,
        )
      );
      debugPrint('Voice command initialization failed');
    }
  }

  Future<void> _toggleVoiceCommands(bool enabled) async {
    final voiceCommandService = VoiceCommandService();
    
    if (enabled) {
      // Set context first, then start listening
      voiceCommandService.setApplicationContext(context);
      await voiceCommandService.startListening();
    } else {
      await voiceCommandService.stopListening();
    }

    // Save the new setting
    await voiceCommandService.saveSettings(enabled);
    
    setState(() {
      _voiceCommandsEnabled = enabled;
    });
  }

  Future<void> _requestPermissions() async {
    try {
      // Request location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are needed to detect accidents')),
          );
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permissions are permanently denied. Please enable in settings.'),
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }
      
      // Request SMS permissions for sending emergency messages
      final smsPermissionStatus = await Permission.sms.status;
      if (!smsPermissionStatus.isGranted) {
        final smsResult = await Permission.sms.request();
        if (!smsResult.isGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('SMS permissions are needed to send emergency messages'),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
      
      // Request microphone permission for voice commands
      final micPermissionStatus = await Permission.microphone.status;
      if (!micPermissionStatus.isGranted) {
        final micResult = await Permission.microphone.request();
        if (!micResult.isGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Microphone permission is needed for voice commands'),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error requesting permissions: $e')),
      );
    }
  }

  Future<void> _fetchEmergencyContacts() async {
    // Add implementation if needed
  }
  
  Future<void> _startBackgroundService() async {
    try {
    bool started = await BackgroundService.startService();
    if (started) {
      setState(() {
        _isBackgroundServiceRunning = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Accident detection is running in the background'),
            duration: Duration(seconds: 2),
        ),
      );
      }
    } catch (e) {
      debugPrint('Error starting background service: $e');
    }
  }
  
  Future<void> _stopBackgroundService() async {
    try {
    bool stopped = await BackgroundService.stopService();
    if (stopped) {
      setState(() {
        _isBackgroundServiceRunning = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Background accident detection stopped'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error stopping background service: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeDrive', style: TextStyle(fontWeight: FontWeight.w600)),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_isBackgroundServiceRunning 
              ? Icons.notifications_active 
              : Icons.notifications_off),
            onPressed: () {
              if (_isBackgroundServiceRunning) {
                _stopBackgroundService();
              } else {
                _startBackgroundService();
              }
            },
            tooltip: _isBackgroundServiceRunning 
              ? 'Stop background monitoring' 
              : 'Start background monitoring',
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: () => _handleSignOut(context),
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: Consumer2<AuthProvider, AccidentProvider>(
        builder: (context, authProvider, accidentProvider, _) {
          final user = authProvider.userModel;
          
          if (user == null) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
          
          _monitoringEnabled = accidentProvider.isMonitoring;
          
          return Stack(
            children: [
              // Header background gradient
              Container(
                height: 150,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withOpacity(0.8),
                    ],
                  ),
                ),
              ),
              SafeArea(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                        _buildUserProfileCard(user, theme),
                            const SizedBox(height: 20),
                            _buildStatusCard(accidentProvider, user, theme),
                            const SizedBox(height: 20),
                            _buildVoiceCommandsCard(),
                            const SizedBox(height: 20),
                        _buildQuickActionsSection(theme),
                            const SizedBox(height: 20),
                        _buildManualAlertButton(theme, user.uid),
                            const SizedBox(height: 20),
                        const EmergencyDashboard(),
                      ],
                    ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Accident Alert Overlay
              if (accidentProvider.isInAccident)
                _buildAccidentAlert(context, accidentProvider),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.pushNamed(
            context,
            '/emergency_guidance',
            arguments: {
              'accidentContext': AccidentContext(
                type: 'General',
                injuries: 'Unknown',
                locationDescription: 'Current location',
                weatherConditions: 'Unknown',
                timestamp: DateTime.now(),
                detectedSeverity: 1,
                airbagDeployed: false,
                vehicleType: 'Unknown',
              ),
            },
          );
        },
        icon: const Icon(Icons.medical_services_outlined),
        label: const Text('Emergency Guidance'),
        backgroundColor: theme.colorScheme.secondary,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.contact_phone),
            label: 'Contacts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
        onTap: (index) {
          switch (index) {
            case 0: // Home - already here
              break;
            case 1: // History
              Navigator.push(
                context, 
                MaterialPageRoute(builder: (_) => const AccidentHistoryScreen())
              );
              break;
            case 2: // Contacts
              Navigator.push(
                context, 
                MaterialPageRoute(builder: (_) => const EmergencyContactsScreen())
              );
              break;
            case 3: // Profile
              // TODO: Navigate to profile screen
              break;
          }
        },
      ),
    );
  }

  Widget _buildUserProfileCard(UserModel user, ThemeData theme) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                child: Text(
                user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 24,
                    fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                  ),
                ),
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back,',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    user.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.email ?? user.phoneNumber ?? 'No contact info',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                    Icons.verified_user,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                    'Premium',
                          style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
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

  Widget _buildStatusCard(AccidentProvider accidentProvider, UserModel user, ThemeData theme) {
    final isMonitoring = accidentProvider.isMonitoring;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                  Icons.shield,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Accident Protection',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: isMonitoring,
                  activeColor: theme.colorScheme.primary,
                  onChanged: (value) {
                    if (value) {
                      accidentProvider.startMonitoring(user.uid);
                    } else {
                      accidentProvider.stopMonitoring();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                      color: isMonitoring 
                    ? theme.colorScheme.primary.withOpacity(0.1)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: isMonitoring
                        ? theme.colorScheme.primary
                        : Colors.grey.shade400,
                    child: Icon(
                      isMonitoring ? Icons.sensors : Icons.sensors_off,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                Text(
                          isMonitoring
                              ? 'Accident Detection Active'
                              : 'Accident Detection Inactive',
                          style: TextStyle(
                    fontWeight: FontWeight.bold,
                        color: isMonitoring
                                ? theme.colorScheme.primary
                                : Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isMonitoring
                              ? 'Your safety is our priority. We\'re actively monitoring for potential accidents.'
                              : 'Turn on monitoring to enable automatic accident detection.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                      ),
                  ),
                  ],
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

  Widget _buildVoiceCommandsCard() {
    final voiceCommandService = VoiceCommandService.instance;
    final accidentProvider = Provider.of<AccidentProvider>(context, listen: false);
    
    // Set application context for UI operations
    voiceCommandService.setApplicationContext(context);
    
    // Set accident provider for direct SMS sending
    voiceCommandService.setAccidentProvider(accidentProvider);
    
    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.mic, color: Colors.red),
                    SizedBox(width: 8),
            Text(
                      'Emergency Voice Commands',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: voiceCommandService.isListening,
                  activeColor: Colors.red,
                  onChanged: (value) async {
                    if (value) {
                      final success = await voiceCommandService.startListening();
                      if (!success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to start voice recognition'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } else {
                      await voiceCommandService.stopListening();
                    }
                    setState(() {});
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            AnimatedContainer(
              duration: Duration(milliseconds: 300),
              height: 50,
              width: double.infinity,
                decoration: BoxDecoration(
                color: voiceCommandService.isListening 
                    ? Colors.red.withOpacity(0.2) 
                    : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      voiceCommandService.isListening 
                          ? Icons.mic : Icons.mic_off,
                      color: voiceCommandService.isListening 
                          ? Colors.red : Colors.grey,
                    ),
                    SizedBox(width: 8),
              Text(
                      voiceCommandService.isListening 
                          ? 'Listening for emergency words...' 
                          : 'Voice recognition inactive',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: voiceCommandService.isListening 
                            ? Colors.red : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Say any of these words for immediate emergency assistance:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildKeywordChip('Help', Colors.red),
                _buildKeywordChip('Emergency', Colors.red),
                _buildKeywordChip('Accident', Colors.red),
                _buildKeywordChip('Crash', Colors.red),
                _buildKeywordChip('Hurt', Colors.red),
                _buildKeywordChip('Injured', Colors.red),
                _buildKeywordChip('Danger', Colors.red),
                _buildKeywordChip('Ambulance', Colors.red),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                // Test emergency command
                voiceCommandService.simulateWakeWord('emergency');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                minimumSize: Size(double.infinity, 48),
              ),
              child: Text('Test Emergency Alert'),
            ),
            // Debug button - only visible in debug mode
            if (kDebugMode)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton(
                  onPressed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Direct emergency test starting...'),
                        backgroundColor: Colors.purple,
                      ),
                    );
                    try {
                      await EmergencyService.instance.sendEmergencyAlert();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Direct test completed'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.purple,
                    side: BorderSide(color: Colors.purple),
                  ),
                  child: Text('Direct Emergency Test'),
                ),
              ),
            // Direct SMS Test button
            if (kDebugMode)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton(
                  onPressed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Testing SMS directly...'),
                        backgroundColor: Colors.blue,
                      ),
                    );
                    
                    // Get current location
                    Position? position;
                    try {
                      position = await Geolocator.getCurrentPosition(
                        desiredAccuracy: LocationAccuracy.high,
                        timeLimit: const Duration(seconds: 5),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Location: ${position.latitude}, ${position.longitude}'),
                          backgroundColor: Colors.green,
                        )
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Location error: $e'),
                          backgroundColor: Colors.orange,
                        )
                      );
                    }
                    
                    // Test phone number - replace with your test number
                    String testNumber = '1234567890';
                    
                    // Create message
                    String message = 'TEST EMERGENCY ALERT';
                    if (position != null) {
                      message += ' Location: ${position.latitude},${position.longitude}';
                    }
                    
                    // Methods to try
                    bool success = false;
                    
                    // Method 1: Direct tel URI
                    try {
                      final uri = Uri.parse('tel:$testNumber');
                      success = await launchUrl(uri, mode: LaunchMode.externalApplication);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Phone call test: $success'),
                          backgroundColor: success ? Colors.green : Colors.red,
                        )
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Phone call error: $e'),
                          backgroundColor: Colors.red,
                        )
                      );
                    }
                    
                    // Wait a moment before trying SMS
                    await Future.delayed(Duration(seconds: 2));
                    
                    // Method 2: Simple sms URI
                    try {
                      // This is the most basic SMS URI that should open the SMS app
                      final uri = Uri.parse('sms:');
                      success = await launchUrl(uri, mode: LaunchMode.externalApplication);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Basic SMS app open test: $success'),
                          backgroundColor: success ? Colors.green : Colors.red,
                        )
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Basic SMS app error: $e'),
                          backgroundColor: Colors.red,
                        )
                      );
                    }
                    
                    // Add a button to manually compose an emergency message
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: Text('Emergency SMS Results'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('The direct SMS methods might not be working due to platform restrictions.'),
                              SizedBox(height: 16),
                              Text('Would you like to manually compose an emergency message?'),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () async {
                                Navigator.of(context).pop();
                                
                                // Open default SMS app
                                String locationText = position != null 
                                    ? ' Location: https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}'
                                    : '';
                                
                                String messageBody = 'EMERGENCY ALERT: I need help!' + locationText;
                                
                                // Try to open SMS app with pre-filled message
                                try {
                                  final uri = Uri.parse('sms:?body=${Uri.encodeComponent(messageBody)}');
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                } catch (e) {
                                  // Show error
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Failed to open SMS app: $e'),
                                      backgroundColor: Colors.red,
                                    )
                                  );
                                }
                              },
                              child: Text('Compose SMS'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                    side: BorderSide(color: Colors.blue),
                  ),
                  child: Text('SMS/Phone Direct Test'),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildKeywordChip(String label, Color color) {
    return Chip(
      label: Text(label),
      backgroundColor: color.withOpacity(0.1),
      side: BorderSide(color: color),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildQuickActionsSection(ThemeData theme) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
            Row(
              children: [
                Icon(
                  Icons.flash_on,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
          'Quick Actions',
                  style: TextStyle(
                    fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
                ),
              ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
                  child: _buildQuickActionButton(
                icon: Icons.history,
                    label: 'History',
                    color: const Color(0xFF4A6FFF),
                    onTap: () {
                      Navigator.pushNamed(context, '/accident_history');
                    },
                  ),
                ),
                const SizedBox(width: 12),
            Expanded(
                  child: _buildQuickActionButton(
                    icon: Icons.contact_phone,
                    label: 'Contacts',
                    color: const Color(0xFF00C853),
                    onTap: () {
                      Navigator.pushNamed(context, '/emergency_contacts');
                    },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                  child: _buildQuickActionButton(
                icon: Icons.local_hospital,
                    label: 'Hospitals',
                    color: const Color(0xFFE53935),
                onTap: () {
                      Navigator.pushNamed(context, '/nearby_hospitals');
                },
              ),
            ),
                const SizedBox(width: 12),
            Expanded(
                  child: _buildQuickActionButton(
                    icon: Icons.settings,
                    label: 'Settings',
                    color: const Color(0xFF757575),
                    onTap: () {
                      // TODO: Navigate to settings screen
                    },
              ),
            ),
          ],
        ),
      ],
        ),
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 1,
          ),
        ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
            Icon(
                  icon,
              color: color,
              size: 28,
                ),
            const SizedBox(height: 8),
              Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualAlertButton(ThemeData theme, String userId) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: InkWell(
        onTap: () => _handleManualAlert(context, userId),
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFFFF5252),
                const Color(0xFFE53935),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
        child: Padding(
            padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.emergency,
                    color: Colors.white,
                    size: 36,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                    Text(
                        'Emergency Alert',
                        style: TextStyle(
                          fontSize: 18,
                        fontWeight: FontWeight.bold,
                          color: Colors.white,
                      ),
                    ),
                      SizedBox(height: 4),
                    Text(
                        'Tap to send alerts to your emergency contacts',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
                const Icon(
                Icons.arrow_forward_ios,
                  color: Colors.white,
                  size: 16,
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleManualAlert(BuildContext context, String userId) async {
    final accidentProvider = Provider.of<AccidentProvider>(context, listen: false);
    final theme = Theme.of(context);
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 8),
            const Text('Send Emergency Alert'),
          ],
        ),
        content: const Text(
          'This will send an emergency alert with your current location to all your emergency contacts. Continue?',
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: theme.colorScheme.primary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Send Alert'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      // Show loading indicator
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sending emergency alert...'),
          duration: Duration(seconds: 2),
        ),
      );
      
      // Send the manual alert
      await accidentProvider.reportManualAccident(userId);
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              const Text('Emergency alert sent successfully'),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _handleSignOut(BuildContext context) async {
    final theme = Theme.of(context);
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: theme.colorScheme.primary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final accidentProvider = Provider.of<AccidentProvider>(context, listen: false);
      
      // Stop monitoring
      accidentProvider.stopMonitoring();
      
      // Sign out
      await authProvider.signOut();
    }
  }

  Widget _buildAccidentAlert(BuildContext context, AccidentProvider accidentProvider) {
    return Container(
      color: Colors.black.withOpacity(0.85),
      width: double.infinity,
      height: double.infinity,
      child: SafeArea(
      child: Center(
        child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
                // Animated pulsing icon
                _buildPulsingAlertIcon(),
                
                const SizedBox(height: 24),
                
                const Text(
                  'ACCIDENT DETECTED',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFE53935),
                    letterSpacing: 1.5,
                  ),
                textAlign: TextAlign.center,
              ),
                
              const SizedBox(height: 16),
                
                const Text(
                  'Are you okay? Emergency contacts will be notified in:',
                style: TextStyle(
                    fontSize: 16,
                  fontWeight: FontWeight.w500,
                    color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
                
                const SizedBox(height: 16),
                
                // Countdown timer
              Text(
                  '${accidentProvider.remainingSeconds} seconds',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFE53935),
                  ),
                ),
                
              const SizedBox(height: 24),
                
                Row(
                  children: [
                    Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    accidentProvider.cancelAlert();
                  },
                  style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF2D6FF2),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                    shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(
                              color: Color(0xFF2D6FF2),
                              width: 2,
                            ),
                          ),
                        ),
                        child: const Text("I'M OKAY"),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          accidentProvider.confirmEmergency();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE53935),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                  ),
                        ),
                        child: const Text("EMERGENCY"),
                ),
              ),
            ],
                ),
                
                const SizedBox(height: 16),
                
                TextButton.icon(
                  onPressed: () {
                    accidentProvider.callEmergencyServices();
                  },
                  icon: const Icon(Icons.call),
                  label: const Text('CALL 911'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFE53935),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildPulsingAlertIcon() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeInOut,
      builder: (_, value, child) {
        return Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red.withOpacity(0.1 + 0.1 * (1.0 - value)),
            border: Border.all(
              color: Colors.red.withOpacity(0.5 + 0.5 * (1.0 - value)),
              width: 2,
            ),
          ),
          child: Center(
            child: Container(
              width: 70 - 10 * value,
              height: 70 - 10 * value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withOpacity(0.8),
              ),
              child: const Icon(
                Icons.car_crash,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
        );
      },
      onEnd: () => setState(() {}), // Trigger rebuild to continue animation
    );
  }

  void _showHowItWorksDialog(BuildContext context) {
    final theme = Theme.of(context);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.info_outline, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text('How It Works'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHowItWorksItem(
              theme,
              icon: Icons.sensors,
              title: 'Accident Detection',
              description: 'The app uses your device\'s sensors to detect sudden impacts and changes in acceleration that may indicate a car accident.',
            ),
            const SizedBox(height: 16),
            _buildHowItWorksItem(
              theme,
              icon: Icons.timer,
              title: 'Countdown Timer',
              description: 'When a potential accident is detected, a 15-second countdown begins. You can cancel this if it\'s a false alarm.',
            ),
            const SizedBox(height: 16),
            _buildHowItWorksItem(
              theme,
              icon: Icons.sms,
              title: 'Emergency Contacts',
              description: 'If the countdown expires, your emergency contacts will automatically receive an SMS with your location.',
            ),
            const SizedBox(height: 16),
            _buildHowItWorksItem(
              theme,
              icon: Icons.local_hospital,
              title: 'Nearby Hospitals',
              description: 'The app will show nearby hospitals on a map to help you or your emergency contacts locate medical help quickly.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Got it',
              style: TextStyle(color: theme.colorScheme.primary),
            ),
          ),
        ],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildHowItWorksItem(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: theme.colorScheme.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showVoiceCommandDemoDialog(BuildContext context) {
    final voiceCommandService = VoiceCommandService();
    final accidentProvider = Provider.of<AccidentProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    // Ensure the application context is set correctly
    voiceCommandService.setApplicationContext(context);
    
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.touch_app, color: Colors.blue),
              SizedBox(width: 8),
              Text('Command Simulator'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Select a command to simulate:'),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        // Close dialog first to avoid navigation context issues
                        Navigator.of(dialogContext).pop();
                        
                        // Execute the command directly using providers
                        voiceCommandService.simulateWakeWord('emergency');
                        Navigator.pushNamed(context, '/emergency_guidance');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('EMERGENCY'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        // Close dialog first to avoid navigation context issues
                        Navigator.of(dialogContext).pop();
                        
                        // Launch emergency call
                        voiceCommandService.simulateWakeWord('help');
                        _launchEmergencyCall();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('HELP ME'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        // Close dialog first to avoid navigation context issues
                        Navigator.of(dialogContext).pop();
                        
                        // Report manual accident
                        voiceCommandService.simulateWakeWord('accident');
                        if (authProvider.firebaseUser != null) {
                          accidentProvider.reportManualAccident(authProvider.firebaseUser!.uid);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('ACCIDENT'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        // Close dialog first to avoid navigation context issues
                        Navigator.of(dialogContext).pop();
                        
                        // Start monitoring
                        voiceCommandService.simulateWakeWord('start');
                        if (authProvider.firebaseUser != null) {
                          accidentProvider.startMonitoring(authProvider.firebaseUser!.uid);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('START'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        // Close dialog first to avoid navigation context issues
                        Navigator.of(dialogContext).pop();
                        
                        // Stop monitoring
                        voiceCommandService.simulateWakeWord('stop');
                        accidentProvider.stopMonitoring();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('STOP'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('CLOSE'),
            ),
          ],
        );
      },
    );
  }

  /// Launch emergency call directly from the home screen
  Future<void> _launchEmergencyCall() async {
    const emergencyNumber = '911'; // Emergency number in the US
    final Uri phoneUri = Uri(scheme: 'tel', path: emergencyNumber);
    try {
      await launchUrl(phoneUri);
    } catch (e) {
      debugPrint('Could not launch phone dialer: $e');
      // Show fallback message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not launch phone dialer. Please call emergency services manually.'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
} 