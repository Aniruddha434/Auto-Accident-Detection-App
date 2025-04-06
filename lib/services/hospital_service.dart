import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:latlong2/latlong.dart';

class Hospital {
  final String name;
  final String address;
  final double distance; // in kilometers
  final LatLng location;
  final String? phone;
  final String? website;
  final bool isOpen; // Is currently open

  Hospital({
    required this.name,
    required this.address,
    required this.distance,
    required this.location,
    this.phone,
    this.website,
    this.isOpen = true,
  });
}

class HospitalService {
  static const int _maxResults = 10;
  static const int _searchRadiusKm = 10;

  // Find nearby hospitals using OpenStreetMap Nominatim API directly
  static Future<List<Hospital>> findNearbyHospitals(LatLng location) async {
    try {
      // Direct HTTP request to Nominatim API
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/search?'
          'format=json&'
          'q=hospital&'
          'limit=20&'
          'viewbox=${location.longitude - 0.1},${location.latitude - 0.1},${location.longitude + 0.1},${location.latitude + 0.1}&'
          'bounded=1&'
          'addressdetails=1'
        ),
        headers: {
          'User-Agent': 'accident_report_system',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        
        final hospitals = data.map((item) {
          final double lat = double.parse(item['lat']);
          final double lon = double.parse(item['lon']);
          final hospitalLocation = LatLng(lat, lon);
          
          final distance = const Distance().as(
            LengthUnit.Kilometer,
            location,
            hospitalLocation
          );
          
          return Hospital(
            name: item['display_name'].toString().split(',').first,
            address: item['display_name'],
            distance: distance,
            location: hospitalLocation,
            isOpen: true,
          );
        }).toList();

        // Sort by distance
        hospitals.sort((a, b) => a.distance.compareTo(b.distance));

        // Return top results
        return hospitals.take(_maxResults).toList();
      } else {
        throw Exception('Failed to load hospitals: ${response.statusCode}');
      }
    } catch (e) {
      print('Error finding hospitals: $e');
      return [];
    }
  }

  // Alternative implementation using direct Overpass API call if needed
  static Future<List<Hospital>> findNearbyHospitalsWithOverpass(LatLng location) async {
    final radius = _searchRadiusKm * 1000; // in meters
    
    // Overpass query to find hospitals and healthcare facilities
    final query = """
      [out:json];
      (
        node["amenity"="hospital"](around:$radius,${location.latitude},${location.longitude});
        way["amenity"="hospital"](around:$radius,${location.latitude},${location.longitude});
        node["amenity"="clinic"](around:$radius,${location.latitude},${location.longitude});
        way["amenity"="clinic"](around:$radius,${location.latitude},${location.longitude});
        node["healthcare"="hospital"](around:$radius,${location.latitude},${location.longitude});
        way["healthcare"="hospital"](around:$radius,${location.latitude},${location.longitude});
      );
      out body;
      >;
      out skel qt;
    """;

    try {
      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: {'data': query},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final elements = data['elements'] as List;
        
        final hospitals = <Hospital>[];
        
        for (final element in elements) {
          if (element['type'] == 'node' && element.containsKey('tags')) {
            final tags = element['tags'];
            final hospitalName = tags['name'] ?? 'Unknown Hospital';
            final lat = element['lat'] as double;
            final lon = element['lon'] as double;
            final hospitalLocation = LatLng(lat, lon);
            
            final distance = const Distance().as(
              LengthUnit.Kilometer, 
              location, 
              hospitalLocation
            );
            
            final address = tags['addr:street'] != null 
                ? '${tags['addr:housenumber'] ?? ''} ${tags['addr:street'] ?? ''}, ${tags['addr:city'] ?? ''}'
                : 'No address available';
                
            final hospital = Hospital(
              name: hospitalName,
              address: address,
              distance: distance,
              location: hospitalLocation,
              phone: tags['phone'],
              website: tags['website'],
              isOpen: tags['opening_hours'] == '24/7' || tags['opening_hours'] == null,
            );
            
            hospitals.add(hospital);
          }
        }
        
        // Sort by distance
        hospitals.sort((a, b) => a.distance.compareTo(b.distance));
        
        // Return top results
        return hospitals.take(_maxResults).toList();
      } else {
        throw Exception('Failed to load hospitals: ${response.statusCode}');
      }
    } catch (e) {
      print('Error finding hospitals with Overpass: $e');
      return [];
    }
  }
  
  // Get directions URL for navigation apps
  static String getDirectionsUrl(LatLng from, LatLng to) {
    return 'https://www.openstreetmap.org/directions?from=${from.latitude},${from.longitude}&to=${to.latitude},${to.longitude}&highway=yes';
  }
  
  // Get directions URL for Google Maps as a fallback
  static String getGoogleMapsDirectionsUrl(LatLng from, LatLng to) {
    return 'https://www.google.com/maps/dir/?api=1&origin=${from.latitude},${from.longitude}&destination=${to.latitude},${to.longitude}&travelmode=driving';
  }
} 