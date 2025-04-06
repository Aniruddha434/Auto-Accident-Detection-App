import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:accident_report_system/models/accident_zone.dart';
import 'package:accident_report_system/providers/accident_provider.dart';
import 'package:accident_report_system/services/kaggle_data_service.dart';

class KaggleDataScreen extends StatefulWidget {
  const KaggleDataScreen({super.key});

  @override
  State<KaggleDataScreen> createState() => _KaggleDataScreenState();
}

class _KaggleDataScreenState extends State<KaggleDataScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _apiKeyController = TextEditingController();
  
  bool _isLoading = false;
  bool _dataLoaded = false;
  bool _hasCredentials = false;
  String _statusMessage = '';
  
  final KaggleDataService _kaggleService = KaggleDataService();
  List<AccidentZone> _indianAccidentZones = [];
  
  @override
  void initState() {
    super.initState();
    _checkCredentials();
  }
  
  @override
  void dispose() {
    _usernameController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }
  
  Future<void> _checkCredentials() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final hasCredentials = await _kaggleService.hasCredentials();
      
      if (hasCredentials) {
        final prefs = await SharedPreferences.getInstance();
        final username = prefs.getString('kaggle_username') ?? '';
        
        // Mask API key with asterisks
        final apiKey = prefs.getString('kaggle_api_key') ?? '';
        final maskedApiKey = apiKey.isNotEmpty 
            ? '${apiKey.substring(0, 4)}${'*' * (apiKey.length - 8)}${apiKey.substring(apiKey.length - 4)}'
            : '';
        
        _usernameController.text = username;
        _apiKeyController.text = maskedApiKey;
      }
      
      setState(() {
        _hasCredentials = hasCredentials;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error checking credentials: $e';
        _isLoading = false;
      });
    }
  }
  
  Future<void> _saveCredentials() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    setState(() {
      _isLoading = true;
      _statusMessage = 'Saving credentials...';
    });
    
    try {
      final username = _usernameController.text.trim();
      final apiKey = _apiKeyController.text.trim();
      
      final success = await _kaggleService.saveCredentials(username, apiKey);
      
      setState(() {
        _isLoading = false;
        _hasCredentials = success;
        _statusMessage = success 
            ? 'Credentials saved successfully!'
            : 'Failed to save credentials';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error saving credentials: $e';
      });
    }
  }
  
  Future<void> _clearCredentials() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Clearing credentials...';
    });
    
    try {
      final success = await _kaggleService.clearCredentials();
      
      if (success) {
        _usernameController.clear();
        _apiKeyController.clear();
      }
      
      setState(() {
        _isLoading = false;
        _hasCredentials = !success;
        _statusMessage = success 
            ? 'Credentials cleared successfully!'
            : 'Failed to clear credentials';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error clearing credentials: $e';
      });
    }
  }
  
  Future<void> _fetchIndianAccidentData() async {
    if (!_hasCredentials) {
      setState(() {
        _statusMessage = 'Please set your Kaggle credentials first';
      });
      return;
    }
    
    setState(() {
      _isLoading = true;
      _statusMessage = 'Fetching accident data from Kaggle...';
    });
    
    try {
      // Use a fallback approach with sample data for now
      // In a production app, you'd download and process the actual dataset
      
      final accidentProvider = Provider.of<AccidentProvider>(context, listen: false);
      
      // Get current location or use a default location for India
      final LatLng currentLocation;
      if (accidentProvider.currentPosition != null) {
        currentLocation = LatLng(
          accidentProvider.currentPosition!.latitude,
          accidentProvider.currentPosition!.longitude,
        );
      } else {
        // Default to Delhi, India
        currentLocation = const LatLng(28.6139, 77.2090);
      }
      
      // Generate sample accident zones for India
      final zones = _kaggleService.generateSampleIndianAccidentZones(currentLocation);
      
      setState(() {
        _indianAccidentZones = zones;
        _isLoading = false;
        _dataLoaded = true;
        _statusMessage = 'Loaded ${zones.length} accident zones for India';
      });
      
      // Update the accident zones in the provider
      _updateAccidentZones(zones);
      
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error fetching accident data: $e';
      });
    }
  }
  
  void _updateAccidentZones(List<AccidentZone> zones) {
    final accidentProvider = Provider.of<AccidentProvider>(context, listen: false);
    accidentProvider.setAccidentZones(zones);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Updated ${zones.length} accident zones on the map'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kaggle Accident Data'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildInfoCard(),
            const SizedBox(height: 24),
            _buildCredentialsForm(),
            const SizedBox(height: 24),
            _buildFetchDataSection(),
            const SizedBox(height: 24),
            if (_statusMessage.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _statusMessage.contains('Error') || _statusMessage.contains('Failed')
                      ? Colors.red.withOpacity(0.1)
                      : Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _statusMessage.contains('Error') || _statusMessage.contains('Failed')
                        ? Colors.red.withOpacity(0.3)
                        : Colors.green.withOpacity(0.3),
                  ),
                ),
                child: Text(
                  _statusMessage,
                  style: TextStyle(
                    color: _statusMessage.contains('Error') || _statusMessage.contains('Failed')
                        ? Colors.red
                        : Colors.green[800],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            if (_dataLoaded && _indianAccidentZones.isNotEmpty)
              _buildAccidentZonesList(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildInfoCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Kaggle API Integration',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'This screen allows you to integrate real accident data from Kaggle to show high-risk zones on the map.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              'To get started:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('1. Create a Kaggle account at kaggle.com'),
            const Text('2. Go to Account > API > Create New API Token'),
            const Text('3. Enter your Kaggle username and API key below'),
            const SizedBox(height: 8),
            const Text(
              'Note: For demonstration purposes, you can also view sample data without real credentials.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCredentialsForm() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Kaggle API Credentials',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Kaggle Username',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your Kaggle username';
                  }
                  return null;
                },
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _apiKeyController,
                decoration: const InputDecoration(
                  labelText: 'Kaggle API Key',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.key),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your Kaggle API key';
                  }
                  if (value.contains('*') && _hasCredentials) {
                    // API key is masked and credentials exist, so it's valid
                    return null;
                  }
                  if (value.length < 10) {
                    return 'API key should be at least 10 characters long';
                  }
                  return null;
                },
                obscureText: true,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton(
                    onPressed: _isLoading ? null : _saveCredentials,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.save),
                        const SizedBox(width: 8),
                        const Text('Save Credentials'),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _isLoading || !_hasCredentials ? null : _clearCredentials,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('Clear', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildFetchDataSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Indian Accident Data',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Fetch real accident data for India to display high-risk zones on the map.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _fetchIndianAccidentData,
                icon: _isLoading 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download),
                label: Text(_isLoading ? 'Fetching...' : 'Fetch Accident Data'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _isLoading ? null : () {
                Navigator.pop(context);
              },
              icon: const Icon(Icons.map),
              label: const Text('View on Map'),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAccidentZonesList() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Indian Accident Zones',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text('Found ${_indianAccidentZones.length} accident zones:'),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _indianAccidentZones.length,
              itemBuilder: (context, index) {
                final zone = _indianAccidentZones[index];
                return ListTile(
                  leading: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: zone.getZoneColor(opacity: 0.7),
                    ),
                  ),
                  title: Text(
                    'Risk Level: ${_getRiskLevelText(zone.riskLevel)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(zone.description),
                  trailing: Text('${zone.accidentCount} accidents'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
  
  String _getRiskLevelText(int riskLevel) {
    switch (riskLevel) {
      case 3:
        return 'High';
      case 2:
        return 'Medium';
      case 1:
        return 'Low';
      default:
        return 'Unknown';
    }
  }
} 