import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:latlong2/latlong.dart';
import 'dart:math';
import 'package:flutter_map/flutter_map.dart';

import 'package:accident_report_system/models/user_model.dart';
import 'package:accident_report_system/providers/auth_provider.dart';
import 'package:accident_report_system/providers/accident_provider.dart';
import 'package:accident_report_system/services/voice_command_service.dart';
import 'package:accident_report_system/screens/accident_history_screen.dart';
import 'package:accident_report_system/screens/emergency_contacts_screen.dart';
import 'package:accident_report_system/screens/nearby_hospitals_screen.dart';
import 'package:accident_report_system/widgets/emergency_dashboard.dart';
import 'package:accident_report_system/models/guidance_message.dart';
import 'package:accident_report_system/services/background_service.dart';
import 'package:accident_report_system/models/accident_context.dart';
import 'package:accident_report_system/services/emergency_service.dart';
import 'package:accident_report_system/services/accident_zone_service.dart';
import 'package:accident_report_system/models/accident_zone.dart';
import 'package:accident_report_system/widgets/accident_zone_layer.dart';
import 'package:accident_report_system/widgets/marker_layer.dart';
import 'package:accident_report_system/widgets/marker.dart';
import 'package:accident_report_system/services/kaggle_data_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _monitoringEnabled = false;
  bool _isBackgroundServiceRunning = false;
  bool _voiceCommandsEnabled = true;
  late TabController _tabController;
  List<AccidentZone> _nearbyAccidentZones = [];
  bool _isLoadingZones = false;
  final AccidentZoneService _zoneService = AccidentZoneService();
  int _selectedIndex = 0;
  bool _isLoading = false;
  bool _isLoadingKaggleData = false;
  final KaggleDataService _kaggleService = KaggleDataService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLocationAndLoadZones();
    });
    WidgetsBinding.instance.addObserver(this);
    _checkPermissionsAndStartServices();
    _loadIndianAccidentData(); // Automatically load Kaggle data on startup
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

  void _checkPermissionsAndStartServices() async {
    try {
      final accidentProvider = Provider.of<AccidentProvider>(context, listen: false);
      
      // Request permissions and start monitoring without requiring user login
      await accidentProvider.startMonitoring();
      setState(() {
        _monitoringEnabled = accidentProvider.isMonitoring;
      });
    } catch (e) {
      debugPrint('Error starting monitoring: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    debugPrint('HomeScreen build method called');
    
    return Scaffold(
      drawer: _buildSettingsDrawer(context),
      appBar: AppBar(
        title: const Text('SafeDrive', style: TextStyle(fontWeight: FontWeight.w600)),
        elevation: 0,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
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
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettingsDialog(),
            tooltip: 'Settings',
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
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withOpacity(0),
                    ],
                    stops: const [0.0, 0.9],
                  ),
                ),
              ),
              // Content
              SafeArea(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: MediaQuery.of(context).size.height - 100,
                    ),
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
                              _buildAccidentZoneCard(),
                              const SizedBox(height: 20),
                              const EmergencyDashboard(),
                              const SizedBox(height: 100), // Extra space for FAB and bottom nav
                            ],
                          ),
                        ),
                      ],
                    ),
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
        icon: const Icon(Icons.medical_services_outlined, size: 18),
        label: const Text('Emergency Guidance', style: TextStyle(fontSize: 12)),
        backgroundColor: theme.colorScheme.error,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11, // Reduced font size
        unselectedFontSize: 11, // Reduced font size
        selectedItemColor: theme.colorScheme.primary,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home, size: 20), // Reduced icon size
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history, size: 20), // Reduced icon size
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.contact_phone, size: 20), // Reduced icon size
            label: 'Contacts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person, size: 20), // Reduced icon size
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
              Navigator.pushNamed(context, '/profile');
              break;
          }
        },
      ),
    );
  }

  Widget _buildUserProfileCard(UserModel user, ThemeData theme) {
    final isDarkMode = theme.brightness == Brightness.dark;
    
    return Card(
      margin: EdgeInsets.zero,
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.2),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 34,
                backgroundColor: theme.colorScheme.primary,
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: isDarkMode ? theme.cardColor : Colors.white,
                  child: Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
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
                      color: isDarkMode ? Colors.grey.shade300 : Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    user.name,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.email ?? user.phoneNumber ?? 'No contact info',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withBlue(
                      (theme.colorScheme.primary.blue + 20).clamp(0, 255)
                    ),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.verified_user,
                    size: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'User',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
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
    final isDarkMode = theme.brightness == Brightness.dark;
    
    return Card(
      margin: EdgeInsets.zero,
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.1),
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
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'Accident Protection',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black87,
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
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isMonitoring
                    ? isDarkMode
                      ? [
                          theme.colorScheme.primary.withOpacity(0.25),
                          theme.colorScheme.primary.withOpacity(0.15),
                        ]
                      : [
                          theme.colorScheme.primary.withOpacity(0.12),
                          theme.colorScheme.primary.withOpacity(0.04),
                        ]
                    : isDarkMode
                      ? [
                          Colors.grey.shade800,
                          Colors.grey.shade900,
                        ]
                      : [
                          Colors.grey.shade100,
                          Colors.grey.shade50,
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isMonitoring 
                    ? theme.colorScheme.primary.withOpacity(0.3)
                    : isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300,
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isMonitoring
                          ? theme.colorScheme.primary
                          : isDarkMode ? Colors.grey.shade700 : Colors.grey.shade400,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: isMonitoring
                            ? theme.colorScheme.primary.withOpacity(0.3)
                            : Colors.grey.withOpacity(0.2),
                          blurRadius: 8,
                          spreadRadius: 0,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      isMonitoring ? Icons.sensors : Icons.sensors_off,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
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
                            fontSize: 16,
                            color: isMonitoring
                                ? theme.colorScheme.primary
                                : isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isMonitoring
                              ? 'Your safety is our priority. We\'re actively monitoring for potential accidents.'
                              : 'Turn on monitoring to enable automatic accident detection.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                        ),
                        if (isMonitoring)
                          Container(
                            margin: const EdgeInsets.only(top: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isDarkMode ? Colors.grey.shade800 : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 4,
                                  spreadRadius: 0,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.green.withOpacity(0.5),
                                        blurRadius: 4,
                                        spreadRadius: 0,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Monitoring active',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDarkMode ? Colors.grey.shade300 : Colors.grey.shade800,
                                    fontWeight: FontWeight.w500,
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
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceCommandsCard() {
    final voiceCommandService = VoiceCommandService.instance;
    final accidentProvider = Provider.of<AccidentProvider>(context, listen: false);
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    
    // Set application context for UI operations
    voiceCommandService.setApplicationContext(context);
    
    // Set accident provider for direct SMS sending
    voiceCommandService.setAccidentProvider(accidentProvider);
    
    return Card(
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.mic,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'Voice Commands',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: _voiceCommandsEnabled,
                  activeColor: theme.colorScheme.primary,
                  onChanged: (value) {
                    _toggleVoiceCommands(value);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDarkMode 
                    ? _voiceCommandsEnabled
                        ? theme.colorScheme.primary.withOpacity(0.15)
                        : Colors.grey.shade800 
                    : _voiceCommandsEnabled
                        ? theme.colorScheme.primary.withOpacity(0.05)
                        : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _voiceCommandsEnabled
                      ? theme.colorScheme.primary.withOpacity(0.3)
                      : isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _voiceCommandsEnabled ? Icons.mic : Icons.mic_off,
                        color: _voiceCommandsEnabled 
                            ? theme.colorScheme.primary 
                            : isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _voiceCommandsEnabled 
                            ? 'Voice Detection Enabled' 
                            : 'Voice Detection Disabled',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: _voiceCommandsEnabled 
                              ? theme.colorScheme.primary 
                              : isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _voiceCommandsEnabled
                        ? 'The app is actively listening for emergency voice commands. Try saying "Help me" or "Emergency" if you need assistance.'
                        : 'Enable voice detection to allow the app to respond to emergency voice commands.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600,
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

  Widget _buildQuickActionsSection(ThemeData theme) {
    final isDarkMode = theme.brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 12),
          child: Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _buildQuickActionItem(
                Colors.green.shade600,
                Icons.local_hospital,
                'Nearby Hospitals',
                onTap: () {
                  Navigator.pushNamed(context, '/nearby_hospitals');
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildQuickActionItem(
                Colors.orange.shade700,
                Icons.contact_phone,
                'Emergency Contacts',
                onTap: () {
                  Navigator.pushNamed(context, '/emergency_contacts');
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildQuickActionItem(
                Colors.blue.shade700,
                Icons.history,
                'Accident History',
                onTap: () {
                  Navigator.pushNamed(context, '/accident_history');
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActionItem(
    Color color, 
    IconData icon, 
    String label, 
    {required VoidCallback onTap}
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color,
              Color.fromARGB(
                color.alpha,
                (color.red - 20).clamp(0, 255),
                (color.green - 20).clamp(0, 255),
                (color.blue - 20).clamp(0, 255),
              ),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.white,
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
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.2),
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
                const Color(0xFFD32F2F),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE53935).withOpacity(0.3),
                blurRadius: 8,
                spreadRadius: 0,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.emergency,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Emergency Alert',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Tap to send alerts to your emergency contacts',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward,
                    color: Colors.white,
                    size: 20,
                  ),
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

  Widget _buildSettingsDrawer(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.person,
                      size: 35,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    authProvider.firebaseUser?.displayName ?? 'User',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    authProvider.firebaseUser?.email ?? '',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Accident History'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/accident_history');
              },
            ),
            ListTile(
              leading: const Icon(Icons.contacts),
              title: const Text('Emergency Contacts'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/emergency_contacts');
              },
            ),
            ListTile(
              leading: const Icon(Icons.local_hospital),
              title: const Text('Nearby Hospitals'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/nearby_hospitals');
              },
            ),
            ListTile(
              leading: const Icon(Icons.warning),
              title: const Text('Accident Zones Admin'),
              subtitle: const Text('Manage high-risk areas'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/accident_zones_admin');
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                _showSettingsDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                authProvider.signOut().then((_) {
                  Navigator.pushReplacementNamed(context, '/login');
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsDialog() {
    Navigator.pushNamed(context, '/settings');
  }

  Future<void> _checkLocationAndLoadZones() async {
    final accidentProvider = Provider.of<AccidentProvider>(context, listen: false);
    
    // If location is null, try to get it directly
    if (accidentProvider.currentPosition == null) {
      try {
        debugPrint('Current position is null, trying to get location directly');
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
        
        // Manually update the position in the provider
        accidentProvider.updatePosition(position);
        debugPrint('Successfully got position: ${position.latitude}, ${position.longitude}');
      } catch (e) {
        debugPrint('Error getting location directly: $e');
      }
    }
    
    // Load zones regardless of whether we got a location
    _loadNearbyAccidentZones();
  }

  Future<void> _loadNearbyAccidentZones() async {
    debugPrint('Loading nearby accident zones');
    if (_isLoadingZones) {
      debugPrint('Already loading zones, skipping');
      return;
    }
    
    setState(() {
      _isLoadingZones = true;
    });
    
    try {
      // Get current position
      final accidentProvider = Provider.of<AccidentProvider>(context, listen: false);
      debugPrint('Current position: ${accidentProvider.currentPosition}');
      
      // Use current location or a default location if null
      final LatLng currentLocation;
      
      if (accidentProvider.currentPosition != null) {
        currentLocation = LatLng(
          accidentProvider.currentPosition!.latitude,
          accidentProvider.currentPosition!.longitude,
        );
        debugPrint('Using actual device location: ${currentLocation.latitude}, ${currentLocation.longitude}');
      } else {
        // Default to a location in the center of a major city (this is New York City)
        currentLocation = LatLng(40.7128, -74.0060);
        debugPrint('Using default location (NYC): ${currentLocation.latitude}, ${currentLocation.longitude}');
      }
      
      debugPrint('Fetching accident zones near: ${currentLocation.latitude}, ${currentLocation.longitude}');
      
      // Try to get zones from Firestore
      final zones = await _zoneService.getAccidentZones(
        center: currentLocation,
        radiusKm: 10.0,
      );
      
      debugPrint('Fetched ${zones.length} zones from service');
      
      // If no zones found, generate some demo ones
      if (zones.isEmpty) {
        debugPrint('No zones found, generating default zones');
        _generateDefaultZones(currentLocation);
      } else {
        setState(() {
          _nearbyAccidentZones = zones;
          _isLoadingZones = false;
          debugPrint('Set ${_nearbyAccidentZones.length} zones in state');
        });
      }
    } catch (e) {
      debugPrint('Error loading accident zones: $e');
      setState(() {
        _isLoadingZones = false;
      });
    }
  }
  
  void _generateDefaultZones(LatLng center) {
    debugPrint('Generating default zones near: ${center.latitude}, ${center.longitude}');
    final random = Random();
    final List<AccidentZone> defaultZones = [];
    
    // Generate 3 random zones with different risk levels
    defaultZones.add(AccidentZone(
      id: 'home-high',
      center: LatLng(
        center.latitude + (random.nextDouble() - 0.5) * 0.01,
        center.longitude + (random.nextDouble() - 0.5) * 0.01,
      ),
      radius: 0.5 + random.nextDouble() * 0.5,
      accidentCount: 15 + random.nextInt(10),
      riskLevel: 3, // High risk
      description: 'High-risk intersection with frequent collisions during peak hours.',
      lastUpdated: DateTime.now().subtract(Duration(days: random.nextInt(30))),
    ));
    
    defaultZones.add(AccidentZone(
      id: 'home-medium',
      center: LatLng(
        center.latitude + (random.nextDouble() - 0.5) * 0.015,
        center.longitude + (random.nextDouble() - 0.5) * 0.015,
      ),
      radius: 0.3 + random.nextDouble() * 0.4,
      accidentCount: 8 + random.nextInt(7),
      riskLevel: 2, // Medium risk
      description: 'Area with frequent rain-related accidents due to poor drainage.',
      lastUpdated: DateTime.now().subtract(Duration(days: random.nextInt(60))),
    ));
    
    // Add low risk zone
    defaultZones.add(AccidentZone(
      id: 'home-low',
      center: LatLng(
        center.latitude + (random.nextDouble() - 0.5) * 0.02,
        center.longitude + (random.nextDouble() - 0.5) * 0.02,
      ),
      radius: 0.2 + random.nextDouble() * 0.3,
      accidentCount: 3 + random.nextInt(5),
      riskLevel: 1, // Low risk
      description: 'Moderate risk zone with occasional minor accidents.',
      lastUpdated: DateTime.now().subtract(Duration(days: random.nextInt(90))),
    ));
    
    debugPrint('Generated ${defaultZones.length} default zones');
    
    setState(() {
      _nearbyAccidentZones = defaultZones;
      _isLoadingZones = false;
      debugPrint('Set ${_nearbyAccidentZones.length} default zones in state');
    });
  }
  
  void _showAccidentZoneOnMap(AccidentZone zone) {
    Navigator.push(
      context, 
      MaterialPageRoute(
        builder: (context) => NearbyHospitalsScreen(
          location: zone.center,
        ),
      )
    );
  }
  
  Widget _buildAccidentZoneCard() {
    debugPrint('Building accident zone card, zones count: ${_nearbyAccidentZones.length}');
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    
    if (_nearbyAccidentZones.isEmpty) {
      debugPrint('No accident zones to display');
      return const SizedBox.shrink();
    }
    
    // Get current position from accident provider
    final accidentProvider = Provider.of<AccidentProvider>(context, listen: false);
    LatLng displayLocation;
    
    if (accidentProvider.currentPosition != null) {
      displayLocation = LatLng(
        accidentProvider.currentPosition!.latitude,
        accidentProvider.currentPosition!.longitude,
      );
      debugPrint('Using actual position for map: ${displayLocation.latitude}, ${displayLocation.longitude}');
    } else {
      // Use the center of the first accident zone if we have no GPS location
      displayLocation = _nearbyAccidentZones.first.center;
      debugPrint('Using accident zone position for map: ${displayLocation.latitude}, ${displayLocation.longitude}');
    }
      
    debugPrint('Display location for accident zone card: $displayLocation');
      
    // Sort zones by risk level (highest first)
    final sortedZones = List<AccidentZone>.from(_nearbyAccidentZones)
      ..sort((a, b) => b.riskLevel.compareTo(a.riskLevel));
      
    debugPrint('Sorted zones, highest risk zone: ${sortedZones.isNotEmpty ? sortedZones[0].riskLevel : "none"}');
    
    return Card(
      margin: EdgeInsets.zero,
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with title and refresh button
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.red.shade700,
                  Colors.red.shade600,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Accident Risk Zones Nearby',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20, color: Colors.white),
                  tooltip: 'Refresh location',
                  onPressed: () {
                    _checkLocationAndLoadZones();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Refreshing location and zones...'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          
          // Show location status (real or default)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: accidentProvider.currentPosition == null
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_off, size: 14, color: Colors.orange),
                      const SizedBox(width: 6),
                      Text(
                        'Using default location',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on, size: 14, color: Colors.green),
                      const SizedBox(width: 6),
                      Text(
                        'Using your current location',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
          ),
          
          // Mini map showing accident zones
          Container(
            height: 220,
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  spreadRadius: 0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: displayLocation,
                      initialZoom: 13.5,
                      maxZoom: 16.0,
                      minZoom: 12.0,
                      interactiveFlags: InteractiveFlag.none, // Disable interactions
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.accident_report_system',
                        maxZoom: 19,
                      ),
                      
                      // Add circular markers for accident zones
                      if (_nearbyAccidentZones.isNotEmpty)
                        CircleLayer(
                          circles: _nearbyAccidentZones.map((zone) {
                            final color = zone.getZoneColor(opacity: 0.4);
                            final borderColor = zone.getZoneColor(opacity: 0.8);
                            return CircleMarker(
                              point: zone.center,
                              radius: zone.radius * 1000, // Convert km to meters
                              useRadiusInMeter: true,
                              color: color,
                              borderColor: borderColor,
                              borderStrokeWidth: 2.0,
                            );
                          }).toList(),
                        ),
                      
                      // Current location marker
                      MarkerLayer(
                        markers: [
                          Marker(
                            width: 50,
                            height: 50,
                            point: displayLocation,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 4,
                                        spreadRadius: 0,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(top: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.3),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  // Add a subtle gradient overlay at the bottom
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 36, // Reduced height
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.2),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // Map attribution
                  Positioned(
                    bottom: 3, // Reduced position
                    right: 3, // Reduced position
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), // Reduced vertical padding
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        '© OpenStreetMap',
                        style: TextStyle(
                          fontSize: 9, // Reduced font size
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Legend for the map
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4), // Reduced vertical padding
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem(Colors.red.shade700, 'High Risk'),
                const SizedBox(width: 12), // Reduced width
                _buildLegendItem(Colors.orange, 'Medium Risk'),
                const SizedBox(width: 12), // Reduced width
                _buildLegendItem(Colors.yellow.shade700, 'Low Risk'),
              ],
            ),
          ),
          
          // Show the highest risk zone description
          if (sortedZones.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: _buildAccidentZoneItem(sortedZones[0]),
            ),
            
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pushNamed(context, '/nearby_hospitals');
                    },
                    icon: const Icon(Icons.map, size: 16), // Reduced icon size
                    label: const Text('View Full Map'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10), // Reduced vertical padding
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isLoadingKaggleData ? null : _loadIndianAccidentData,
                    icon: _isLoadingKaggleData 
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.red.shade700,
                            ),
                          )
                        : const Icon(Icons.refresh, size: 16),
                    label: Text(_isLoadingKaggleData ? 'Loading Data...' : 'Refresh Accident Data'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade700),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12, // Reduced size
          height: 12, // Reduced size
          decoration: BoxDecoration(
            color: color.withOpacity(0.7),
            shape: BoxShape.circle,
            border: Border.all(
              color: color,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 2,
                spreadRadius: 0,
              ),
            ],
          ),
        ),
        const SizedBox(width: 4), // Reduced spacing
        Text(
          label,
          style: TextStyle(
            fontSize: 11, // Reduced font size
            color: Colors.grey.shade800,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
  
  Widget _buildAccidentZoneItem(AccidentZone zone) {
    Color zoneColor = zone.getZoneColor();
    
    return GestureDetector(
      onTap: () => _showAccidentZoneOnMap(zone),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8), // Reduced margin
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // Reduced padding
        decoration: BoxDecoration(
          color: zoneColor.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12), // Reduced radius
          border: Border.all(
            color: zoneColor.withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), // Reduced padding
                  decoration: BoxDecoration(
                    color: zoneColor,
                    borderRadius: BorderRadius.circular(10), // Reduced radius
                    boxShadow: [
                      BoxShadow(
                        color: zoneColor.withOpacity(0.3),
                        blurRadius: 3, // Reduced blur
                        offset: const Offset(0, 1), // Reduced offset
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        zone.riskLevel == 3 
                          ? Icons.warning_amber_rounded 
                          : (zone.riskLevel == 2 
                            ? Icons.info_outline 
                            : Icons.remove_circle_outline),
                        color: Colors.white,
                        size: 14, // Reduced size
                      ),
                      const SizedBox(width: 3), // Reduced spacing
                      Text(
                        '${zone.accidentCount} Accidents',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11, // Reduced font size
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  'Tap for details',
                  style: TextStyle(
                    fontSize: 11, // Reduced font size
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(width: 3), // Reduced spacing
                Icon(
                  Icons.arrow_forward_ios,
                  size: 10, // Reduced size
                  color: Colors.grey.shade600,
                ),
              ],
            ),
            const SizedBox(height: 6), // Reduced spacing
            Text(
              zone.description,
              style: TextStyle(
                fontSize: 12, // Reduced font size
                color: Colors.grey.shade800,
                height: 1.3, // Reduced line height
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadIndianAccidentData() async {
    if (_isLoadingKaggleData) return;
    
    setState(() {
      _isLoadingKaggleData = true;
    });
    
    try {
      final accidentProvider = Provider.of<AccidentProvider>(context, listen: false);
      
      // Get current location or use a default location for India
      final LatLng currentLocation;
      if (accidentProvider.currentPosition != null) {
        currentLocation = LatLng(
          accidentProvider.currentPosition!.latitude,
          accidentProvider.currentPosition!.longitude,
        );
      } else {
        // Default to a location in India
        currentLocation = const LatLng(20.5937, 78.9629);
      }
      
      // Initialize Kaggle service with default credentials
      await _kaggleService.initialize();
      
      // Generate sample accident zones for India
      final zones = _kaggleService.generateSampleIndianAccidentZones(currentLocation);
      
      // Update the accident zones in the provider
      accidentProvider.setAccidentZones(zones);
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Loaded ${zones.length} accident hotspots in India'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error loading Kaggle accident data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error loading accident data. Try again later.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingKaggleData = false;
        });
      }
    }
  }
} 