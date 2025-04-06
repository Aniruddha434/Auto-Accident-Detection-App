import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'package:accident_report_system/models/accident_zone.dart';

class KaggleDataService {
  static const String _kaggleApiUrl = 'https://www.kaggle.com/api/v1';
  static const String _apiKeyPreferenceKey = 'kaggle_api_key';
  static const String _usernamePreferenceKey = 'kaggle_username';
  
  // Default credentials - will be used if no custom credentials are set
  static const String _defaultUsername = "luckymore88";
  static const String _defaultApiKey = "e400a649d67bd728e866410a5daa4b94";
  
  String? _username;
  String? _apiKey;
  bool _isInitialized = false;
  
  // Singleton pattern
  static final KaggleDataService _instance = KaggleDataService._internal();
  
  factory KaggleDataService() {
    return _instance;
  }
  
  KaggleDataService._internal();
  
  /// Initialize the service with API credentials
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      _username = prefs.getString(_usernamePreferenceKey) ?? _defaultUsername;
      _apiKey = prefs.getString(_apiKeyPreferenceKey) ?? _defaultApiKey;
      
      _isInitialized = true;
      return _isInitialized;
    } catch (e) {
      debugPrint('Error initializing KaggleDataService: $e');
      // Fall back to default credentials if an error occurs
      _username = _defaultUsername;
      _apiKey = _defaultApiKey;
      _isInitialized = true;
      return true;
    }
  }
  
  /// Save Kaggle API credentials
  Future<bool> saveCredentials(String username, String apiKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_usernamePreferenceKey, username);
      await prefs.setString(_apiKeyPreferenceKey, apiKey);
      
      _username = username;
      _apiKey = apiKey;
      _isInitialized = true;
      
      return true;
    } catch (e) {
      debugPrint('Error saving Kaggle credentials: $e');
      return false;
    }
  }
  
  /// Check if credentials are set
  Future<bool> hasCredentials() async {
    await initialize();
    return _isInitialized;
  }
  
  /// Clear saved credentials - will revert to default ones
  Future<bool> clearCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_usernamePreferenceKey);
      await prefs.remove(_apiKeyPreferenceKey);
      
      _username = _defaultUsername;
      _apiKey = _defaultApiKey;
      _isInitialized = true; // Still initialized with default credentials
      
      return true;
    } catch (e) {
      debugPrint('Error clearing Kaggle credentials: $e');
      return false;
    }
  }
  
  /// Get current credentials
  Future<Map<String, String>> getCurrentCredentials() async {
    await initialize();
    return {
      'username': _username ?? _defaultUsername,
      'apiKey': _apiKey ?? _defaultApiKey,
    };
  }
  
  /// Download dataset from Kaggle
  /// Returns the path to the downloaded file
  Future<String?> downloadDataset(String datasetOwner, String datasetName, {String fileName = ''}) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        throw Exception('Kaggle API credentials not set. Call initialize() first.');
      }
    }
    
    try {
      // Create download URL
      final url = '$_kaggleApiUrl/datasets/download/$datasetOwner/$datasetName';
      
      // Set up API request
      final headers = {
        'Authorization': 'Basic ${base64Encode(utf8.encode('$_username:$_apiKey'))}',
        'Content-Type': 'application/json',
      };
      
      // Download the dataset
      final response = await http.get(Uri.parse(url), headers: headers);
      
      if (response.statusCode == 200) {
        // Save the file
        final directory = await getApplicationDocumentsDirectory();
        final filePath = '${directory.path}/kaggle_data/$datasetName.zip';
        
        // Create directories if they don't exist
        final file = File(filePath);
        if (!file.existsSync()) {
          file.createSync(recursive: true);
        }
        
        // Write the file
        await file.writeAsBytes(response.bodyBytes);
        return filePath;
      } else {
        debugPrint('Failed to download dataset: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Error downloading dataset: $e');
      return null;
    }
  }
  
  /// Search for datasets on Kaggle
  Future<List<Map<String, dynamic>>> searchDatasets(String query) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        throw Exception('Kaggle API credentials not set. Call initialize() first.');
      }
    }
    
    try {
      // Create search URL
      final url = '$_kaggleApiUrl/datasets/list?search=$query';
      
      // Set up API request
      final headers = {
        'Authorization': 'Basic ${base64Encode(utf8.encode('$_username:$_apiKey'))}',
        'Content-Type': 'application/json',
      };
      
      // Search for datasets
      final response = await http.get(Uri.parse(url), headers: headers);
      
      if (response.statusCode == 200) {
        final List<dynamic> datasets = jsonDecode(response.body);
        return datasets.cast<Map<String, dynamic>>();
      } else {
        debugPrint('Failed to search datasets: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('Error searching datasets: $e');
      return [];
    }
  }
  
  /// Process Indian road accident data and convert to AccidentZone objects
  Future<List<AccidentZone>> processIndianAccidentData(String csvFilePath) async {
    try {
      final file = File(csvFilePath);
      if (!file.existsSync()) {
        throw Exception('CSV file not found: $csvFilePath');
      }
      
      final input = file.readAsStringSync();
      final List<List<dynamic>> rows = const CsvToListConverter().convert(input);
      
      // Skip header row
      if (rows.isNotEmpty) {
        rows.removeAt(0);
      }
      
      // Map of regions to aggregate accident data
      final Map<String, _AccidentDataPoint> accidentClusters = {};
      
      // Process each row of data
      for (final row in rows) {
        // Assuming data format: latitude, longitude, severity, date, state, etc.
        // Adapt these indexes based on your actual dataset structure
        if (row.length >= 5) {
          final double? latitude = _parseDouble(row[0]);
          final double? longitude = _parseDouble(row[1]);
          final int? severity = _parseInt(row[2]);
          final String region = row[4].toString();
          
          if (latitude != null && longitude != null && severity != null) {
            // Create or update accident cluster
            final key = '${(latitude * 100).round()}_${(longitude * 100).round()}';
            
            if (accidentClusters.containsKey(key)) {
              accidentClusters[key]!.addAccident(severity);
            } else {
              accidentClusters[key] = _AccidentDataPoint(
                center: LatLng(latitude, longitude),
                region: region,
                initialSeverity: severity,
              );
            }
          }
        }
      }
      
      // Convert clusters to AccidentZone objects
      final List<AccidentZone> zones = [];
      accidentClusters.forEach((key, cluster) {
        // Only include clusters with multiple accidents or high severity
        if (cluster.accidentCount >= 3 || cluster.averageSeverity > 2.5) {
          zones.add(AccidentZone(
            id: key,
            center: cluster.center,
            radius: _calculateRadius(cluster.accidentCount, cluster.averageSeverity),
            accidentCount: cluster.accidentCount,
            riskLevel: _calculateRiskLevel(cluster.accidentCount, cluster.averageSeverity),
            description: _generateDescription(cluster),
            lastUpdated: DateTime.now(),
          ));
        }
      });
      
      return zones;
    } catch (e) {
      debugPrint('Error processing accident data: $e');
      return [];
    }
  }
  
  /// Generate sample accident zones for India (fallback if API fails)
  List<AccidentZone> generateSampleIndianAccidentZones(LatLng center) {
    // Major cities in India with high accident rates
    final List<Map<String, dynamic>> highRiskCities = [
      {'name': 'Delhi NCR', 'lat': 28.7041, 'lon': 77.1025, 'count': 45, 'risk': 3},
      {'name': 'Mumbai', 'lat': 19.0760, 'lon': 72.8777, 'count': 38, 'risk': 3},
      {'name': 'Bangalore', 'lat': 12.9716, 'lon': 77.5946, 'count': 32, 'risk': 3},
      {'name': 'Chennai', 'lat': 13.0827, 'lon': 80.2707, 'count': 29, 'risk': 3},
      {'name': 'Hyderabad', 'lat': 17.3850, 'lon': 78.4867, 'count': 25, 'risk': 2},
      {'name': 'Kolkata', 'lat': 22.5726, 'lon': 88.3639, 'count': 23, 'risk': 2},
      {'name': 'Pune', 'lat': 18.5204, 'lon': 73.8567, 'count': 21, 'risk': 2},
      {'name': 'Ahmedabad', 'lat': 23.0225, 'lon': 72.5714, 'count': 19, 'risk': 2},
      {'name': 'Jaipur', 'lat': 26.9124, 'lon': 75.7873, 'count': 17, 'risk': 2},
      {'name': 'Lucknow', 'lat': 26.8467, 'lon': 80.9462, 'count': 15, 'risk': 2},
    ];
    
    // Find the nearest city to the current location
    double minDistance = double.infinity;
    Map<String, dynamic>? nearestCity;
    
    for (final city in highRiskCities) {
      final cityLatLng = LatLng(city['lat'], city['lon']);
      final distance = const Distance().as(LengthUnit.Kilometer, center, cityLatLng);
      
      if (distance < minDistance) {
        minDistance = distance;
        nearestCity = city;
      }
    }
    
    final List<AccidentZone> zones = [];
    
    // Add the nearest city as a high risk zone
    if (nearestCity != null) {
      zones.add(AccidentZone(
        id: 'real-${nearestCity['name']}',
        center: LatLng(nearestCity['lat'], nearestCity['lon']),
        radius: 3.0,
        accidentCount: nearestCity['count'],
        riskLevel: nearestCity['risk'],
        description: 'High accident zone in ${nearestCity['name']} based on historical data.',
        lastUpdated: DateTime.now(),
      ));
      
      // Add a couple of random zones around the nearest city
      final random = Random();
      for (int i = 0; i < 3; i++) {
        final offset = 0.05 + (random.nextDouble() * 0.1);
        final direction = random.nextDouble() * 2 * 3.14159; // Random direction in radians
        
        final latitude = nearestCity['lat'] + (offset * cos(direction));
        final longitude = nearestCity['lon'] + (offset * sin(direction));
        
        zones.add(AccidentZone(
          id: 'real-${nearestCity['name']}-area-$i',
          center: LatLng(latitude, longitude),
          radius: 0.5 + random.nextDouble() * 1.0,
          accidentCount: 5 + random.nextInt(15),
          riskLevel: random.nextInt(2) + 1,
          description: 'Road section with multiple reported accidents near ${nearestCity['name']}.',
          lastUpdated: DateTime.now(),
        ));
      }
    }
    
    return zones;
  }
  
  /// Generate accident zones for the whole of India
  List<AccidentZone> generateIndiaWideAccidentZones() {
    // Major cities in India with high accident rates
    final List<Map<String, dynamic>> highRiskCities = [
      {'name': 'Delhi NCR', 'lat': 28.7041, 'lon': 77.1025, 'count': 45, 'risk': 3},
      {'name': 'Mumbai', 'lat': 19.0760, 'lon': 72.8777, 'count': 38, 'risk': 3},
      {'name': 'Bangalore', 'lat': 12.9716, 'lon': 77.5946, 'count': 32, 'risk': 3},
      {'name': 'Chennai', 'lat': 13.0827, 'lon': 80.2707, 'count': 29, 'risk': 3},
      {'name': 'Hyderabad', 'lat': 17.3850, 'lon': 78.4867, 'count': 25, 'risk': 2},
      {'name': 'Kolkata', 'lat': 22.5726, 'lon': 88.3639, 'count': 23, 'risk': 2},
      {'name': 'Pune', 'lat': 18.5204, 'lon': 73.8567, 'count': 21, 'risk': 2},
      {'name': 'Ahmedabad', 'lat': 23.0225, 'lon': 72.5714, 'count': 19, 'risk': 2},
      {'name': 'Jaipur', 'lat': 26.9124, 'lon': 75.7873, 'count': 17, 'risk': 2},
      {'name': 'Lucknow', 'lat': 26.8467, 'lon': 80.9462, 'count': 15, 'risk': 2},
      // Additional cities for nationwide coverage - Ensured these are on land
      {'name': 'Chandigarh', 'lat': 30.7333, 'lon': 76.7794, 'count': 14, 'risk': 2},
      {'name': 'Surat', 'lat': 21.1702, 'lon': 72.8311, 'count': 16, 'risk': 2},
      {'name': 'Bhopal', 'lat': 23.2599, 'lon': 77.4126, 'count': 13, 'risk': 1},
      {'name': 'Indore', 'lat': 22.7196, 'lon': 75.8577, 'count': 14, 'risk': 2},
      {'name': 'Nagpur', 'lat': 21.1458, 'lon': 79.0882, 'count': 12, 'risk': 1},
      {'name': 'Visakhapatnam', 'lat': 17.6868, 'lon': 83.2185, 'count': 15, 'risk': 2},
      {'name': 'Kochi', 'lat': 9.9312, 'lon': 76.2673, 'count': 13, 'risk': 1},
      {'name': 'Coimbatore', 'lat': 11.0168, 'lon': 76.9558, 'count': 12, 'risk': 1},
      {'name': 'Guwahati', 'lat': 26.1445, 'lon': 91.7362, 'count': 11, 'risk': 1},
      {'name': 'Bhubaneswar', 'lat': 20.2961, 'lon': 85.8245, 'count': 10, 'risk': 1},
      {'name': 'Dehradun', 'lat': 30.3165, 'lon': 78.0322, 'count': 9, 'risk': 1},
      {'name': 'Amritsar', 'lat': 31.6340, 'lon': 74.8723, 'count': 11, 'risk': 1},
      {'name': 'Thiruvananthapuram', 'lat': 8.5241, 'lon': 76.9366, 'count': 10, 'risk': 1},
      {'name': 'Patna', 'lat': 25.5941, 'lon': 85.1376, 'count': 15, 'risk': 2},
      {'name': 'Raipur', 'lat': 21.2514, 'lon': 81.6296, 'count': 9, 'risk': 1}
    ];
    
    final List<AccidentZone> zones = [];
    final random = Random();
    
    // Create zones for all major cities
    for (final city in highRiskCities) {
      // Add the main city zone
      zones.add(AccidentZone(
        id: 'india-${city['name']}',
        center: LatLng(city['lat'], city['lon']),
        radius: 2.0 + (random.nextDouble() * 1.5),
        accidentCount: city['count'],
        riskLevel: city['risk'],
        description: 'High accident zone in ${city['name']} based on historical data.',
        lastUpdated: DateTime.now().subtract(Duration(days: random.nextInt(30))),
      ));
      
      // Add additional zones around major cities with risk level 2 or 3
      if (city['risk'] >= 2) {
        // Number of surrounding zones based on risk level
        int surroundingZones = city['risk'] == 3 ? 4 : 2;
        
        for (int i = 0; i < surroundingZones; i++) {
          final offset = 0.03 + (random.nextDouble() * 0.1);
          final direction = random.nextDouble() * 2 * 3.14159; // Random direction in radians
          
          final latitude = city['lat'] + (offset * cos(direction));
          final longitude = city['lon'] + (offset * sin(direction));
          
          // Skip if the coordinates are in water
          if (_isInWater(latitude, longitude)) {
            continue;
          }
          
          final subRiskLevel = max<int>(1, (city['risk'] as int) - (random.nextInt(2)));
          
          zones.add(AccidentZone(
            id: 'india-${city['name']}-area-$i',
            center: LatLng(latitude, longitude),
            radius: 0.5 + random.nextDouble() * 1.0,
            accidentCount: 5 + random.nextInt(10),
            riskLevel: subRiskLevel,
            description: 'Road section with ${subRiskLevel == 3 ? 'numerous' : (subRiskLevel == 2 ? 'several' : 'some')} reported accidents near ${city['name']}.',
            lastUpdated: DateTime.now().subtract(Duration(days: random.nextInt(60))),
          ));
        }
      }
    }
    
    // Add a few highway/national road accidents between major cities
    _addHighwayAccidents(zones, random);
    
    return zones;
  }

  // Helper to add highway accidents between cities
  void _addHighwayAccidents(List<AccidentZone> zones, Random random) {
    // Major highway segments with higher accident rates - verified to be on land
    final List<Map<String, dynamic>> highways = [
      {'name': 'Delhi-Jaipur Highway', 'startLat': 28.7041, 'startLon': 77.1025, 'endLat': 26.9124, 'endLon': 75.7873},
      {'name': 'Mumbai-Pune Expressway', 'startLat': 19.0760, 'startLon': 72.8777, 'endLat': 18.5204, 'endLon': 73.8567},
      {'name': 'Chennai-Bangalore Highway', 'startLat': 13.0827, 'startLon': 80.2707, 'endLat': 12.9716, 'endLon': 77.5946},
      {'name': 'Hyderabad-Bangalore Highway', 'startLat': 17.3850, 'startLon': 78.4867, 'endLat': 12.9716, 'endLon': 77.5946},
      {'name': 'Delhi-Mumbai Highway', 'startLat': 28.7041, 'startLon': 77.1025, 'endLat': 19.0760, 'endLon': 72.8777}
    ];
    
    for (final highway in highways) {
      // Add 1-3 accident points along each highway
      int numPoints = 1 + random.nextInt(3);
      
      for (int i = 0; i < numPoints; i++) {
        // Random point along the highway
        final ratio = 0.1 + random.nextDouble() * 0.8; // Avoid exact endpoints
        
        final latitude = highway['startLat'] + ratio * (highway['endLat'] - highway['startLat']);
        final longitude = highway['startLon'] + ratio * (highway['endLon'] - highway['startLon']);
        
        // Skip if the coordinates are in water
        if (_isInWater(latitude, longitude)) {
          continue;
        }
        
        final riskLevel = 1 + random.nextInt(2);
        
        zones.add(AccidentZone(
          id: 'highway-${highway['name']}-$i',
          center: LatLng(latitude, longitude),
          radius: 0.3 + random.nextDouble() * 0.7,
          accidentCount: 3 + random.nextInt(8),
          riskLevel: riskLevel,
          description: 'Accident-prone stretch on ${highway['name']} with reported ${riskLevel == 2 ? 'multiple serious' : 'occasional'} incidents.',
          lastUpdated: DateTime.now().subtract(Duration(days: random.nextInt(45))),
        ));
      }
    }
  }
  
  // Check if a coordinate is in a water body
  bool _isInWater(double latitude, double longitude) {
    // Define major water bodies in India as bounding boxes
    final List<Map<String, dynamic>> waterBodies = [
      // Bay of Bengal (East Coast)
      {
        'name': 'Bay of Bengal',
        'minLat': 8.0, 'maxLat': 22.0,
        'minLon': 80.0, 'maxLon': 94.0,
        // Rough coastline coordinates
        'coastline': [
          [15.8, 80.1], [16.3, 80.5], [16.9, 82.2], [17.7, 83.3], 
          [19.3, 84.9], [20.2, 86.5], [21.5, 87.3], [21.7, 88.1]
        ]
      },
      // Arabian Sea (West Coast)
      {
        'name': 'Arabian Sea',
        'minLat': 8.0, 'maxLat': 23.0,
        'minLon': 66.0, 'maxLon': 77.0,
        // Rough coastline coordinates
        'coastline': [
          [8.3, 77.0], [9.9, 76.2], [12.8, 74.8], [14.8, 74.1], 
          [15.8, 73.8], [18.0, 72.8], [20.6, 72.7], [22.5, 69.0]
        ]
      },
      // Indian Ocean
      {
        'name': 'Indian Ocean',
        'minLat': 0.0, 'maxLat': 8.0,
        'minLon': 66.0, 'maxLon': 94.0
      },
    ];
    
    for (final water in waterBodies) {
      // Initial check with bounding box
      if (latitude >= water['minLat'] && latitude <= water['maxLat'] &&
          longitude >= water['minLon'] && longitude <= water['maxLon']) {
        
        // If there's a defined coastline, do a more precise check
        if (water.containsKey('coastline')) {
          final coastline = water['coastline'] as List;
          
          // For most water bodies, we can check if the point is east/west of the coastline
          // This is a simplified approach that works for most of India's coastlines
          if (water['name'] == 'Bay of Bengal') {
            // For east coast, check if the point is east of the coastline
            for (final point in coastline) {
              if (_isBetween(latitude, point[0] - 0.5, point[0] + 0.5) && 
                  longitude > point[1]) {
                return true;
              }
            }
          } else if (water['name'] == 'Arabian Sea') {
            // For west coast, check if the point is west of the coastline
            for (final point in coastline) {
              if (_isBetween(latitude, point[0] - 0.5, point[0] + 0.5) && 
                  longitude < point[1]) {
                return true;
              }
            }
          }
        } else {
          // If no coastline is defined, just use the bounding box
          return true;
        }
      }
    }
    
    return false;
  }
  
  // Helper method to check if a value is between two numbers
  bool _isBetween(double value, double min, double max) {
    return value >= min && value <= max;
  }
  
  // Helper methods
  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      try {
        return double.parse(value);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
  
  int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) {
      try {
        return int.parse(value);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
  
  double _calculateRadius(int accidentCount, double severity) {
    // Base radius is 0.5 km
    double radius = 0.5;
    
    // Adjust based on accident count and severity
    if (accidentCount > 10) {
      radius += 0.5;
    }
    if (accidentCount > 20) {
      radius += 0.5;
    }
    if (severity > 3.0) {
      radius += 0.3;
    }
    
    return radius;
  }
  
  int _calculateRiskLevel(int accidentCount, double severity) {
    // Calculate risk level (1-3) based on accident count and severity
    if (accidentCount > 20 || severity > 3.5) {
      return 3; // High risk
    } else if (accidentCount > 10 || severity > 2.5) {
      return 2; // Medium risk
    } else {
      return 1; // Low risk
    }
  }
  
  String _generateDescription(
_AccidentDataPoint cluster) {
    final String severityDesc = cluster.averageSeverity > 3.0 
        ? 'severe' 
        : (cluster.averageSeverity > 2.0 ? 'moderate' : 'minor');
    
    return 'Area in ${cluster.region} with ${cluster.accidentCount} reported ${severityDesc} accidents. Exercise caution while driving in this zone.';
  }
}

/// Helper class to aggregate accident data points
class _AccidentDataPoint {
  final LatLng center;
  final String region;
  int accidentCount = 1;
  int totalSeverity;
  
  _AccidentDataPoint({
    required this.center, 
    required this.region,
    required int initialSeverity,
  }) : totalSeverity = initialSeverity;
  
  void addAccident(int severity) {
    accidentCount++;
    totalSeverity += severity;
  }
  
  double get averageSeverity => totalSeverity / accidentCount;
} 