# Accident Report System with AI Emergency Guidance

A Flutter mobile app that automatically detects accidents and sends emergency alerts with the user's live location.

## Features

- **Automatic Accident Detection**: Uses device accelerometer sensors to detect sudden impacts. If the impact force exceeds 4g, it triggers an emergency alert.
- **Emergency Alerts**: Sends SMS with Google Maps location link to emergency contacts when an accident is detected.
- **User Authentication**: Sign in via Google, Email/Password.
- **Live Location Tracking**: Fetches and displays the user's live location when an accident is detected.
- **Accident History**: Stores and displays accident timestamps, location, and severity.

## Emergency AI Guidance Feature

The Accident Report System now includes an AI-powered Emergency Guidance Assistant that provides real-time guidance during accident situations. This feature is designed to:

1. Provide immediate post-accident guidance based on accident context
2. Answer questions about what to do in emergency situations
3. Offer structured advice categorized by priority

### Key Components

- **EmergencyGuidanceAI Service**: Core service that handles AI interactions using Google's Gemini AI
- **GuidanceMessage Model**: Structured representation of AI guidance with immediate actions, secondary steps, and safety warnings
- **AccidentContext Model**: Captures accident details for contextually relevant guidance
- **EmergencyGuidanceScreen**: Interactive UI for communicating with the AI assistant
- **Emergency Dashboard**: Quick access widget for emergency resources

### How It Works

1. The system creates an `AccidentContext` with details from the accident report
2. The AI generates structured guidance based on this context
3. Guidance is displayed in a user-friendly format with priority-based sections
4. Users can ask follow-up questions through the chat interface

### Fallback Mechanisms

The AI system includes robust fallback mechanisms to ensure guidance is available even if:

- API connections fail
- The AI response format is unexpected
- The device is offline

### Data Privacy

- AI interactions are logged anonymously for system improvement
- No personally identifiable information is sent to the AI service
- Recent guidance is stored locally for offline access

## Setup Instructions

### Prerequisites

- Flutter SDK (3.7.2 or later)
- Firebase account
- Android Studio or VS Code
- Android device or emulator (API Level 33 recommended)

### Firebase Setup

1. Create a new Firebase project at [Firebase Console](https://console.firebase.google.com/)
2. Add an Android app to your Firebase project
   - Use package name: `com.example.accident_report_system`
   - Download the `google-services.json` file
3. Place the `google-services.json` file in the `android/app` directory
4. Enable Firebase Authentication methods:
   - Email/Password
   - Google Sign-in
5. Create Firestore Database with the following collections:
   - `users` - To store user data and emergency contacts
   - `accidents` - To store accident reports
6. Set up Firestore security rules:

   ```
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       // Allow authenticated users to read and write their own user data
       match /users/{userId} {
         allow read, write: if request.auth != null && request.auth.uid == userId;
       }

       // Allow authenticated users to read and write their own accident reports
       match /accidents/{accidentId} {
         allow read, write: if request.auth != null &&
                             resource.data.userId == request.auth.uid;
         allow create: if request.auth != null &&
                        request.resource.data.userId == request.auth.uid;
       }
     }
   }
   ```

### Google Maps Setup

1. Create a Google Maps API key in the [Google Cloud Console](https://console.cloud.google.com/)
2. Add the API key to `android/app/src/main/AndroidManifest.xml`:

```xml
<meta-data android:name="com.google.android.geo.API_KEY"
           android:value="YOUR_API_KEY"/>
```

### App Permissions

The app requires the following permissions:

- Location (for tracking user's position)
- SMS (for sending emergency alerts)
- Sensors (for detecting accidents)

### Running the App

1. Clone the repository
2. Install dependencies:
   ```
   flutter pub get
   ```
3. Run the app:
   ```
   flutter run
   ```

## Usage Guide

1. **Sign in/Register**: Create an account using email or Google sign-in.
2. **Add Emergency Contacts**: Add phone numbers of emergency contacts in the Emergency Contacts screen.
3. **Enable Accident Monitoring**: On the home screen, toggle the monitoring switch to start accident detection.
4. **View Accident History**: Check past accidents in the Accident History screen.
5. **Manual Alert**: Send a manual emergency alert with your current location.

## Tech Stack

- **Flutter (Dart)**: Frontend UI
- **Firebase Auth**: User authentication
- **Firebase Firestore**: Database for storing user data and accident reports
- **Google Maps API**: Display accident locations
- **sensors_plus**: Accelerometer data for accident detection
- **geolocator**: Access device GPS coordinates
- **flutter_sms**: Send emergency SMS alerts

## Notes

- For testing, you can use the "Send Manual Alert" button instead of simulating an actual accident.
- The app is optimized for Android devices and may require additional setup for iOS.
- Ensure emergency contacts have valid phone numbers that can receive SMS messages.

### Setup Instructions

1. Replace `YOUR_GEMINI_API_KEY` in the `EmergencyGuidanceAI` service with a valid API key
2. Make sure all required dependencies are installed:
   ```bash
   flutter pub add google_generative_ai cloud_firestore shared_preferences
   ```

### Future Enhancements

- Integration with telematics data for more accurate accident detection
- Multi-language support for international users
- Voice interface for hands-free operation

## Demo

View a demonstration of the app in action: [App Demo Video](https://drive.google.com/file/d/1ICGSGmNlDQ2NZ3KhuuY0yNbuYQoaKl-J/view?usp=sharing)
