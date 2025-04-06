class UserModel {
  final String uid;
  final String name;
  final String email;
  final String phoneNumber;
  final List<String> emergencyContacts;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phoneNumber,
    required this.emergencyContacts,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',
      emergencyContacts: List<String>.from(map['emergencyContacts'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'phoneNumber': phoneNumber,
      'emergencyContacts': emergencyContacts,
    };
  }
} 