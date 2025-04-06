import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:accident_report_system/models/user_model.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  User? _firebaseUser;
  UserModel? _userModel;
  bool _isLoading = false;
  
  User? get firebaseUser => _firebaseUser;
  UserModel? get userModel => _userModel;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _firebaseUser != null;
  
  AuthProvider() {
    _initializeUser();
  }
  
  Future<void> _initializeUser() async {
    _firebaseUser = _auth.currentUser;
    if (_firebaseUser != null) {
      await _fetchUserData();
    }
    notifyListeners();
  }
  
  Future<void> _fetchUserData() async {
    try {
      _isLoading = true;
      notifyListeners();
      
      if (_firebaseUser == null) {
        print('Cannot fetch user data: Firebase user is null');
        _isLoading = false;
        notifyListeners();
        return;
      }
      
      print('Fetching user data for uid: ${_firebaseUser!.uid}');
      DocumentSnapshot doc = await _firestore.collection('users').doc(_firebaseUser!.uid).get();
      
      if (doc.exists) {
        print('User document exists');
        try {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          _userModel = UserModel.fromMap(data);
          print('Successfully parsed user data');
        } catch (parseError) {
          print('Error parsing user data: $parseError');
          // Create a minimal user model if parsing fails
          _userModel = UserModel(
            uid: _firebaseUser!.uid,
            name: _firebaseUser!.displayName ?? '',
            email: _firebaseUser!.email ?? '',
            phoneNumber: _firebaseUser!.phoneNumber ?? '',
            emergencyContacts: [],
          );
        }
      } else {
        print('User document does not exist. Creating new document...');
        // Create a new user document if it doesn't exist
        _userModel = UserModel(
          uid: _firebaseUser!.uid,
          name: _firebaseUser!.displayName ?? '',
          email: _firebaseUser!.email ?? '',
          phoneNumber: _firebaseUser!.phoneNumber ?? '',
          emergencyContacts: [],
        );
        
        try {
          await _firestore.collection('users').doc(_firebaseUser!.uid).set(_userModel!.toMap());
          print('Created new user document');
        } catch (createError) {
          print('Failed to create user document: $createError');
        }
      }
    } catch (e) {
      print('Error fetching user data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  Future<bool> signUpWithEmailAndPassword(
    String email, 
    String password, 
    String name, 
    String phoneNumber,
  ) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      // Log the attempt for debugging
      print('Attempting to create user with email: $email');
      
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      _firebaseUser = result.user;
      
      if (_firebaseUser != null) {
        // Create the user model
        _userModel = UserModel(
          uid: _firebaseUser!.uid,
          name: name,
          email: email,
          phoneNumber: phoneNumber,
          emergencyContacts: [],
        );
        
        // Save to Firestore
        print('Saving user data to Firestore for uid: ${_firebaseUser!.uid}');
        await _firestore.collection('users').doc(_firebaseUser!.uid).set(_userModel!.toMap());
        
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      // Provide more detailed error logging
      print('Error during sign up: $e');
      if (e is FirebaseAuthException) {
        print('FirebaseAuthException code: ${e.code}');
        print('FirebaseAuthException message: ${e.message}');
      }
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  Future<bool> signInWithEmailAndPassword(String email, String password) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      _firebaseUser = result.user;
      
      if (_firebaseUser != null) {
        await _fetchUserData();
        return true;
      }
      return false;
    } catch (e) {
      print('Error during sign in: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  Future<bool> signInWithGoogle() async {
    try {
      _isLoading = true;
      notifyListeners();
      
      print('Attempting Google Sign-in');
      
      // On web, the sign-in method needs to handle differently
      if (kIsWeb) {
        print('Performing Google Sign-in for Web platform');
        
        // Web sign-in
        GoogleAuthProvider googleProvider = GoogleAuthProvider();
        UserCredential result = await _auth.signInWithPopup(googleProvider);
        _firebaseUser = result.user;
      } else {
        // Mobile sign-in
        print('Performing Google Sign-in for Mobile platform');
        try {
          final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
          print('Google SignIn result: ${googleUser != null ? "Success" : "User cancelled or error"}');
          
          if (googleUser == null) {
            print('Google Sign-In: User cancelled the sign-in flow or error occurred');
            _isLoading = false;
            notifyListeners();
            return false;
          }
          
          try {
            print('Getting Google Auth tokens');
            final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
            print('Got accessToken: ${googleAuth.accessToken != null}');
            print('Got idToken: ${googleAuth.idToken != null}');
            
            final credential = GoogleAuthProvider.credential(
              accessToken: googleAuth.accessToken,
              idToken: googleAuth.idToken,
            );
            
            print('Signing in with Firebase using Google credential');
            UserCredential result = await _auth.signInWithCredential(credential);
            _firebaseUser = result.user;
            print('Firebase sign in successful: ${_firebaseUser?.uid}');
          } catch (authError) {
            print('Error in Google authentication or Firebase sign-in: $authError');
            rethrow;
          }
        } catch (signInError) {
          print('Error in Google sign-in process: $signInError');
          rethrow;
        }
      }
      
      if (_firebaseUser != null) {
        // Check if user already exists in Firestore
        print('Checking if user exists in Firestore');
        try {
          DocumentSnapshot doc = await _firestore.collection('users').doc(_firebaseUser!.uid).get();
          
          if (!doc.exists) {
            // Create a new user model
            print('Creating new user record in Firestore');
            print('User display name: ${_firebaseUser!.displayName}');
            print('User email: ${_firebaseUser!.email}');
            print('User phone number: ${_firebaseUser!.phoneNumber}');
            
            _userModel = UserModel(
              uid: _firebaseUser!.uid,
              name: _firebaseUser!.displayName ?? '',
              email: _firebaseUser!.email ?? '',
              phoneNumber: _firebaseUser!.phoneNumber ?? '',
              emergencyContacts: [],
            );
            
            // Save to Firestore
            try {
              await _firestore.collection('users').doc(_firebaseUser!.uid).set(_userModel!.toMap());
              print('Successfully created user document in Firestore');
            } catch (firestoreError) {
              print('Error creating user document: $firestoreError');
              if (firestoreError is FirebaseException) {
                print('Firestore error code: ${firestoreError.code}');
                print('Firestore error message: ${firestoreError.message}');
              }
              // Continue even if there's an error saving to Firestore
            }
          } else {
            print('User exists, fetching user data');
            await _fetchUserData();
          }
        } catch (firestoreQueryError) {
          print('Error querying Firestore: $firestoreQueryError');
          // Create a minimal user model even if Firestore fails
          _userModel = UserModel(
            uid: _firebaseUser!.uid,
            name: _firebaseUser!.displayName ?? '',
            email: _firebaseUser!.email ?? '',
            phoneNumber: _firebaseUser!.phoneNumber ?? '',
            emergencyContacts: [],
          );
        }
        
        notifyListeners();
        return true;
      }
      print('Firebase user is null after sign-in');
      return false;
    } catch (e) {
      print('Error during Google sign in: $e');
      if (e is FirebaseAuthException) {
        print('FirebaseAuthException code: ${e.code}');
        print('FirebaseAuthException message: ${e.message}');
      } else if (e is Exception) {
        print('Exception type: ${e.runtimeType}');
      }
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  Future<bool> signOut() async {
    try {
      await _auth.signOut();
      await _googleSignIn.signOut();
      _firebaseUser = null;
      _userModel = null;
      
      // Clear user data from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_id');
      await prefs.remove('user_name');
      await prefs.remove('emergency_contacts');
      
      notifyListeners();
      return true;
    } catch (e) {
      print('Error during sign out: $e');
      return false;
    }
  }
  
  Future<bool> updateEmergencyContacts(List<String> emergencyContacts) async {
    try {
      if (_firebaseUser == null) {
        print('Cannot update emergency contacts: User is not logged in');
        return false;
      }

      print('Updating emergency contacts for user: ${_firebaseUser!.uid}');
      print('Number of contacts to update: ${emergencyContacts.length}');
      
      // Simple approach instead of transaction
      try {
        // First try to create a complete user document if one doesn't exist
        await _firestore.collection('users').doc(_firebaseUser!.uid).set({
          'uid': _firebaseUser!.uid,
          'name': _userModel?.name ?? _firebaseUser!.displayName ?? '',
          'email': _userModel?.email ?? _firebaseUser!.email ?? '',
          'phoneNumber': _userModel?.phoneNumber ?? _firebaseUser!.phoneNumber ?? '',
          'emergencyContacts': emergencyContacts,
        }, SetOptions(merge: true));
        
        print('Successfully updated document');
        
        // Update local model
        if (_userModel != null) {
          _userModel = UserModel(
            uid: _userModel!.uid,
            name: _userModel!.name,
            email: _userModel!.email,
            phoneNumber: _userModel!.phoneNumber,
            emergencyContacts: emergencyContacts,
          );
        } else {
          _userModel = UserModel(
            uid: _firebaseUser!.uid,
            name: _firebaseUser!.displayName ?? '',
            email: _firebaseUser!.email ?? '',
            phoneNumber: _firebaseUser!.phoneNumber ?? '',
            emergencyContacts: emergencyContacts,
          );
        }
        
        notifyListeners();
        return true;
      } catch (e) {
        print('Error with direct document update: $e');
        if (e is FirebaseException) {
          print('FirebaseException code: ${e.code}');
          print('FirebaseException message: ${e.message}');
        }
        return false;
      }
    } catch (e) {
      print('Error updating emergency contacts: $e');
      if (e is FirebaseException) {
        print('FirebaseException code: ${e.code}');
        print('FirebaseException message: ${e.message}');
      }
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Updates user model after successful sign in
  Future<void> _updateUserModel(String uid) async {
    try {
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(uid).get();
      
      if (userDoc.exists) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        _userModel = UserModel.fromMap(userData);
        
        // Store user ID and name in SharedPreferences for background service
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', uid);
        await prefs.setString('user_name', _userModel?.name ?? 'User');
        
        // Also store emergency contacts for background service
        List<String> contactNumbers = [];
        final contacts = prefs.getStringList('emergency_contacts') ?? [];
        for (var contact in contacts) {
          final contactData = json.decode(contact);
          contactNumbers.add(contactData['phone'] as String);
        }
        
        await prefs.setStringList('emergency_contacts', contactNumbers);
      } else {
        debugPrint('User document does not exist for UID: $uid');
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating user model: $e');
    }
  }

  Future<bool> updateUserProfile(UserModel updatedUser) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      if (_firebaseUser == null) {
        print('Cannot update user profile: User is not logged in');
        _isLoading = false;
        notifyListeners();
        return false;
      }
      
      // Update in Firestore
      await _firestore.collection('users').doc(_firebaseUser!.uid).update({
        'name': updatedUser.name,
        'email': updatedUser.email,
        'phoneNumber': updatedUser.phoneNumber,
      });
      
      // Update local user model
      _userModel = updatedUser;
      
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      print('Error updating user profile: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
} 