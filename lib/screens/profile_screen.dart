import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:accident_report_system/providers/auth_provider.dart';
import 'package:accident_report_system/models/user_model.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isEditing = false;
  bool _isSaving = false;

  // Controllers for form fields
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    final user = Provider.of<AuthProvider>(context, listen: false).userModel;
    
    _nameController = TextEditingController(text: user?.name ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    _phoneController = TextEditingController(text: user?.phoneNumber ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.userModel;
      
      if (currentUser != null) {
        // Create updated user
        final updatedUser = UserModel(
          uid: currentUser.uid,
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          emergencyContacts: currentUser.emergencyContacts,
        );
        
        // Update in provider/database
        await authProvider.updateUserProfile(updatedUser);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated successfully')),
          );
          setState(() {
            _isEditing = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                setState(() {
                  _isEditing = true;
                });
              },
              tooltip: 'Edit Profile',
            )
          else
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                // Reset to original values
                final user = Provider.of<AuthProvider>(context, listen: false).userModel;
                _nameController.text = user?.name ?? '';
                _emailController.text = user?.email ?? '';
                _phoneController.text = user?.phoneNumber ?? '';
                
                setState(() {
                  _isEditing = false;
                });
              },
              tooltip: 'Cancel',
            ),
        ],
      ),
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, _) {
          final user = authProvider.userModel;
          
          if (user == null) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  
                  // Profile avatar
                  _buildProfileAvatar(user, theme),
                  
                  const SizedBox(height: 30),
                  
                  // User information form
                  _buildUserInfoForm(user, theme),
                  
                  const SizedBox(height: 30),
                  
                  // Save button (only visible in edit mode)
                  if (_isEditing)
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Save Changes'),
                    ),
                  
                  // Emergency contacts section
                  const SizedBox(height: 40),
                  _buildEmergencyContactsSection(user, theme),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileAvatar(UserModel user, ThemeData theme) {
    return Stack(
      alignment: Alignment.bottomRight,
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
            radius: 60,
            backgroundColor: theme.colorScheme.primary,
            child: CircleAvatar(
              radius: 57,
              backgroundColor: Colors.white,
              child: Text(
                user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
        
        // Edit avatar button (visible only in edit mode)
        if (_isEditing)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.camera_alt,
              color: Colors.white,
              size: 20,
            ),
          ),
      ],
    );
  }

  Widget _buildUserInfoForm(UserModel user, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Name field
        Text(
          'Full Name',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _nameController,
          readOnly: !_isEditing,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Name is required';
            }
            return null;
          },
          decoration: InputDecoration(
            filled: true,
            fillColor: _isEditing ? Colors.transparent : Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _isEditing ? theme.colorScheme.primary : Colors.transparent,
              ),
            ),
            prefixIcon: const Icon(Icons.person),
            enabled: _isEditing,
          ),
        ),
        
        const SizedBox(height: 20),
        
        // Email field
        Text(
          'Email',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _emailController,
          readOnly: !_isEditing,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Email is required';
            }
            // Email validation regex
            final emailRegExp = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,}$');
            if (!emailRegExp.hasMatch(value)) {
              return 'Please enter a valid email';
            }
            return null;
          },
          decoration: InputDecoration(
            filled: true,
            fillColor: _isEditing ? Colors.transparent : Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _isEditing ? theme.colorScheme.primary : Colors.transparent,
              ),
            ),
            prefixIcon: const Icon(Icons.email),
            enabled: _isEditing,
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        
        const SizedBox(height: 20),
        
        // Phone number field
        Text(
          'Phone Number',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _phoneController,
          readOnly: !_isEditing,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Phone number is required';
            }
            // Basic phone validation
            if (value.length < 10) {
              return 'Please enter a valid phone number';
            }
            return null;
          },
          decoration: InputDecoration(
            filled: true,
            fillColor: _isEditing ? Colors.transparent : Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _isEditing ? theme.colorScheme.primary : Colors.transparent,
              ),
            ),
            prefixIcon: const Icon(Icons.phone),
            enabled: _isEditing,
          ),
          keyboardType: TextInputType.phone,
        ),
      ],
    );
  }

  Widget _buildEmergencyContactsSection(UserModel user, ThemeData theme) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Emergency Contacts',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('Manage'),
                  onPressed: () {
                    Navigator.pushNamed(context, '/emergency_contacts');
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'People who will be notified in case of an accident',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            
            if (user.emergencyContacts.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(
                        Icons.contact_phone,
                        color: Colors.grey.shade400,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No emergency contacts added yet',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/emergency_contacts');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.error,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Add Contacts'),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: user.emergencyContacts.length > 3 
                    ? 3 
                    : user.emergencyContacts.length,
                itemBuilder: (context, index) {
                  final contact = user.emergencyContacts[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                      child: Icon(
                        Icons.person,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    title: Text(contact),
                    contentPadding: EdgeInsets.zero,
                  );
                },
              ),
              
            if (user.emergencyContacts.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Center(
                  child: Text(
                    'and ${user.emergencyContacts.length - 3} more...',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
} 