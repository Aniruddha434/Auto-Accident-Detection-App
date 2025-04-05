import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:accident_report_system/providers/auth_provider.dart';
import 'package:accident_report_system/providers/accident_provider.dart';
import 'package:accident_report_system/screens/login_screen.dart';
import 'package:accident_report_system/screens/home_screen.dart';
import 'package:accident_report_system/screens/accident_history_screen.dart';
import 'package:accident_report_system/screens/emergency_contacts_screen.dart';
import 'package:accident_report_system/screens/nearby_hospitals_screen.dart';
import 'package:accident_report_system/screens/emergency_guidance_screen.dart';
import 'package:latlong2/latlong.dart';
import 'package:accident_report_system/models/guidance_message.dart';
import 'package:accident_report_system/models/accident_context.dart';
import 'package:accident_report_system/services/background_service.dart';
import 'package:accident_report_system/services/voice_command_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Initialize the background service
  await BackgroundService.initialize();
  
  // Initialize the voice command service
  final voiceService = VoiceCommandService();
  await voiceService.initialize();
  await voiceService.loadSettings();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Create a navigator key for accessing the navigator from the accident provider
    final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
    
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => AccidentProvider(navigatorKey: navigatorKey)),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, authProvider, _) {
          return MaterialApp(
            title: 'SafeDrive',
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF2D6FF2), // Modern blue primary color
                primary: const Color(0xFF2D6FF2),
                secondary: const Color(0xFF00C853), // Vibrant green for accent
                tertiary: const Color(0xFF735BF2), // Soft purple
                background: const Color(0xFFF8F9FA), // Light background color
                surface: Colors.white,
                error: const Color(0xFFE53935),
                onPrimary: Colors.white,
                onSecondary: Colors.white,
                onBackground: Colors.black87,
                onSurface: Colors.black87,
                brightness: Brightness.light,
              ),
              useMaterial3: true,
              fontFamily: 'Inter', // More modern, clean font
              textTheme: const TextTheme(
                displayLarge: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.5,
                ),
                displayMedium: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
                displaySmall: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.0,
                ),
                headlineLarge: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.25,
                ),
                headlineMedium: TextStyle(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.0,
                ),
                titleLarge: TextStyle(
                  fontWeight: FontWeight.w600, 
                  fontSize: 20.0,
                  letterSpacing: 0.15,
                ),
                titleMedium: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16.0,
                  letterSpacing: 0.15,
                ),
                titleSmall: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14.0,
                  letterSpacing: 0.1,
                ),
                bodyLarge: TextStyle(
                  fontWeight: FontWeight.w400,
                  fontSize: 16.0,
                  letterSpacing: 0.5,
                ),
                bodyMedium: TextStyle(
                  fontWeight: FontWeight.w400,
                  fontSize: 14.0,
                  letterSpacing: 0.25,
                ),
              ),
              cardTheme: CardTheme(
                elevation: 2, // Reduced elevation for cleaner look
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20), // More rounded corners
                ),
                shadowColor: Colors.black.withOpacity(0.1), // Softer shadow
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              ),
              appBarTheme: AppBarTheme(
                backgroundColor: const Color(0xFF2D6FF2),
                foregroundColor: Colors.white,
                elevation: 0,
                centerTitle: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(20),
                  ),
                ),
                titleTextStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 18, // Smaller for cleaner look
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              bottomNavigationBarTheme: BottomNavigationBarThemeData(
                backgroundColor: Colors.white,
                selectedItemColor: const Color(0xFF2D6FF2),
                unselectedItemColor: Colors.black38, // Lighter for less visual noise
                type: BottomNavigationBarType.fixed,
                elevation: 8,
                selectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: const Color(0xFF2D6FF2),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16), // More rounded corners
                  ),
                  elevation: 0, // No elevation for cleaner look
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2D6FF2),
                  side: const BorderSide(color: Color(0xFF2D6FF2), width: 1.5), // Thinner border
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFF2D6FF2), width: 1.5),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE53935), width: 1),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE53935), width: 1.5),
                ),
                labelStyle: const TextStyle(color: Colors.black54),
                hintStyle: TextStyle(color: Colors.grey.shade400),
                prefixIconColor: const Color(0xFF2D6FF2),
                suffixIconColor: Colors.black54,
                errorStyle: const TextStyle(fontWeight: FontWeight.w500),
              ),
              iconTheme: const IconThemeData(
                color: Color(0xFF2D6FF2),
                size: 24,
              ),
              chipTheme: ChipThemeData(
                backgroundColor: Colors.grey.shade100,
                disabledColor: Colors.grey.shade200,
                selectedColor: const Color(0xFF2D6FF2).withOpacity(0.1),
                secondarySelectedColor: const Color(0xFF2D6FF2),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                labelStyle: const TextStyle(fontSize: 14),
                secondaryLabelStyle: const TextStyle(color: Colors.white),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20), // More rounded for modern look
                ),
              ),
              dividerTheme: const DividerThemeData(
                color: Color(0xFFEEEEEE),
                thickness: 1,
                indent: 20,
                endIndent: 20,
              ),
              dialogTheme: DialogTheme(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24), // More rounded corners
                ),
                elevation: 4,
                backgroundColor: Colors.white,
                titleTextStyle: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                contentTextStyle: const TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
              snackBarTheme: SnackBarThemeData(
                backgroundColor: Colors.grey.shade900,
                contentTextStyle: const TextStyle(color: Colors.white),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                behavior: SnackBarBehavior.floating,
              ),
            ),
            routes: {
              '/': (context) => authProvider.isLoggedIn
                  ? const HomeScreen()
                  : const LoginScreen(),
              '/home': (context) => const HomeScreen(),
              '/accident_history': (context) => const AccidentHistoryScreen(),
              '/emergency_contacts': (context) => const EmergencyContactsScreen(),
              '/nearby_hospitals': (context) => const NearbyHospitalsScreen(),
              '/emergency_guidance': (context) => EmergencyGuidanceScreen(
                    accidentContext: AccidentContext(
                      type: 'Manual',
                      timestamp: DateTime.now(),
                      injuries: 'Unknown',
                      locationDescription: 'Unknown location',
                      weatherConditions: 'Unknown',
                      detectedSeverity: 2,
                      airbagDeployed: false,
                      vehicleType: 'Unknown',
                      description: 'Emergency requested via voice command',
                    ),
                  ),
            },
            // Register the application context with the voice command service when the app is built
            builder: (context, child) {
              // Set the application context for voice commands
              VoiceCommandService().setApplicationContext(context);
              return child!;
            },
          );
        },
      ),
    );
  }
}
