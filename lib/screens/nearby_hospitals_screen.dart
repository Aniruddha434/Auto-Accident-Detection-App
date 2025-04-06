import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:accident_report_system/services/hospital_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:accident_report_system/providers/accident_provider.dart';
import 'package:accident_report_system/services/accident_zone_service.dart';
import 'package:accident_report_system/models/accident_zone.dart';
import 'package:accident_report_system/widgets/accident_zone_layer.dart';
import 'package:accident_report_system/widgets/kaggle_accident_layer.dart';
import 'package:accident_report_system/services/kaggle_data_service.dart';
import 'dart:math';
import 'package:geolocator/geolocator.dart';

class NearbyHospitalsScreen extends StatefulWidget {
  final LatLng? location;

  const NearbyHospitalsScreen({
    Key? key,
    this.location,
  }) : super(key: key);

  @override
  State<NearbyHospitalsScreen> createState() => _NearbyHospitalsScreenState();
}

class _NearbyHospitalsScreenState extends State<NearbyHospitalsScreen> {
  final MapController _mapController = MapController();
  List<Hospital> _hospitals = [];
  bool _isLoading = true;
  Hospital? _selectedHospital;
  final double _initialZoom = 14.0;
  
  // Add accident zone related variables
  List<AccidentZone> _accidentZones = [];
  bool _showAccidentZones = true;
  bool _isLoadingZones = false;
  AccidentZone? _selectedZone;
  final AccidentZoneService _zoneService = AccidentZoneService();
  
  // Add Kaggle data related variables
  List<AccidentZone> _kaggleAccidentZones = [];
  bool _showKaggleData = true;
  bool _isLoadingKaggleData = false;
  final KaggleDataService _kaggleService = KaggleDataService();
  
  @override
  void initState() {
    super.initState();
    _loadHospitals();
    _loadAccidentZones();
    _loadKaggleData(); // Load Kaggle data automatically
  }
  
  Future<void> _loadHospitals() async {
    setState(() {
      _isLoading = true;
    });
    
    debugPrint('Loading hospitals, location from widget: ${widget.location}');
    LatLng? currentLocation = widget.location;
    
    // If location not provided, try to get it from the accident provider
    if (currentLocation == null) {
      debugPrint('No location provided, trying to get from AccidentProvider');
      final accidentProvider = Provider.of<AccidentProvider>(context, listen: false);
      if (accidentProvider.currentPosition != null) {
        currentLocation = LatLng(
          accidentProvider.currentPosition!.latitude,
          accidentProvider.currentPosition!.longitude,
        );
        debugPrint('Got location from AccidentProvider: ${currentLocation.latitude}, ${currentLocation.longitude}');
      } else {
        debugPrint('No location available in AccidentProvider');
        
        // Try to get location directly
        try {
          debugPrint('Attempting to get location directly via Geolocator');
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 5),
          );
          
          currentLocation = LatLng(position.latitude, position.longitude);
          debugPrint('Successfully got location directly: ${currentLocation.latitude}, ${currentLocation.longitude}');
          
          // Update the accident provider with this position
          accidentProvider.updatePosition(position);
        } catch (e) {
          debugPrint('Failed to get location directly: $e');
          
          // Use a default location (center of India) as fallback
          currentLocation = const LatLng(23.2599, 77.4126);
          debugPrint('Using default location (center of India)');
        }
      }
    }
    
    if (currentLocation != null) {
      try {
        debugPrint('Searching for hospitals near: ${currentLocation.latitude}, ${currentLocation.longitude}');
        // First try Nominatim
        var hospitals = await HospitalService.findNearbyHospitals(currentLocation);
        debugPrint('Found ${hospitals.length} hospitals via Nominatim');
        
        // If Nominatim returns no results, try Overpass API
        if (hospitals.isEmpty) {
          debugPrint('No hospitals found via Nominatim, trying Overpass API');
          hospitals = await HospitalService.findNearbyHospitalsWithOverpass(currentLocation);
          debugPrint('Found ${hospitals.length} hospitals via Overpass API');
        }
        
        setState(() {
          _hospitals = hospitals;
          _isLoading = false;
        });
        
        if (_hospitals.isNotEmpty) {
          // Make sure we wait for the map controller to be initialized
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try {
              _mapController.move(currentLocation!, _initialZoom);
            } catch (e) {
              debugPrint('Error moving map: $e');
            }
          });
        }
      } catch (e) {
        debugPrint('Error finding hospitals: $e');
        setState(() {
          _isLoading = false;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error finding hospitals: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      debugPrint('Still no location available, cannot load hospitals');
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not determine your location'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _loadAccidentZones() async {
    if (_isLoadingZones) return;
    
    setState(() {
      _isLoadingZones = true;
    });
    
    LatLng? currentLocation = widget.location;
    
    // If location not provided, try to get it from the accident provider
    if (currentLocation == null) {
      final accidentProvider = Provider.of<AccidentProvider>(context, listen: false);
      if (accidentProvider.currentPosition != null) {
        currentLocation = LatLng(
          accidentProvider.currentPosition!.latitude,
          accidentProvider.currentPosition!.longitude,
        );
      }
    }
    
    if (currentLocation != null) {
      try {
        // First try to get real accident zones from Firestore
        final zones = await _zoneService.getAccidentZones(
          center: currentLocation,
          radiusKm: 20.0,
        );
        
        // If no zones found, generate some default ones for demonstration
        if (zones.isEmpty) {
          // Create some default zones around the current location
          _generateDefaultZones(currentLocation);
        } else {
          setState(() {
            _accidentZones = zones;
            _isLoadingZones = false;
          });
        }
      } catch (e) {
        // On error, create default zones
        _generateDefaultZones(currentLocation);
        
        setState(() {
          _isLoadingZones = false;
        });
      }
    } else {
      setState(() {
        _isLoadingZones = false;
      });
    }
  }
  
  // Generate default accident zones for demonstration purposes
  void _generateDefaultZones(LatLng center) {
    final random = Random();
    final List<AccidentZone> defaultZones = [];
    
    // Add a high-risk zone near the user
    defaultZones.add(AccidentZone(
      id: 'default-high',
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
    
    // Add medium-risk zone
    defaultZones.add(AccidentZone(
      id: 'default-medium',
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
    
    // Add low-risk zone
    defaultZones.add(AccidentZone(
      id: 'default-low',
      center: LatLng(
        center.latitude + (random.nextDouble() - 0.5) * 0.02,
        center.longitude + (random.nextDouble() - 0.5) * 0.02,
      ),
      radius: 0.2 + random.nextDouble() * 0.3,
      accidentCount: 3 + random.nextInt(5),
      riskLevel: 1, // Low risk
      description: 'School zone with increased traffic during pickup and drop-off times.',
      lastUpdated: DateTime.now().subtract(Duration(days: random.nextInt(90))),
    ));
    
    setState(() {
      _accidentZones = defaultZones;
      _isLoadingZones = false;
    });
  }
  
  void _selectHospital(Hospital hospital) {
    setState(() {
      _selectedHospital = hospital;
    });
    
    // Center the map on the selected hospital
    _mapController.move(hospital.location, _initialZoom);
  }
  
  void _onZoneTap(AccidentZone zone) {
    setState(() {
      _selectedZone = zone;
      _selectedHospital = null; // Clear hospital selection
    });
    
    // Show zone info
    _showZoneInfoBottomSheet(zone);
  }
  
  void _showZoneInfoBottomSheet(AccidentZone zone) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: zone.getZoneColor(),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Accident Risk Zone',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        'Risk Level: ${zone.riskLevelText}',
                        style: TextStyle(
                          color: zone.getZoneColor(),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            ListTile(
              leading: const Icon(Icons.report),
              title: Text('${zone.accidentCount} Accidents Reported'),
              subtitle: Text('Last updated: ${_formatDate(zone.lastUpdated)}'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Zone Information'),
              subtitle: Text(zone.description.isNotEmpty 
                ? zone.description 
                : 'Drive carefully in this area as it has a history of accidents.'),
            ),
            ListTile(
              leading: const Icon(Icons.location_on),
              title: const Text('Location'),
              subtitle: Text('${zone.center.latitude.toStringAsFixed(6)}, ${zone.center.longitude.toStringAsFixed(6)}'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Close'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()} months ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} days ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours ago';
    } else {
      return '${difference.inMinutes} minutes ago';
    }
  }
  
  Future<void> _openDirections(Hospital hospital) async {
    final currentLocation = widget.location ?? LatLng(
      Provider.of<AccidentProvider>(context, listen: false).currentPosition!.latitude,
      Provider.of<AccidentProvider>(context, listen: false).currentPosition!.longitude,
    );
    
    // Try to open in default navigation app via OSM
    final osmUrl = HospitalService.getDirectionsUrl(currentLocation, hospital.location);
    if (await canLaunchUrl(Uri.parse(osmUrl))) {
      await launchUrl(Uri.parse(osmUrl), mode: LaunchMode.externalApplication);
    } else {
      // Fallback to Google Maps
      final gmapsUrl = HospitalService.getGoogleMapsDirectionsUrl(currentLocation, hospital.location);
      if (await canLaunchUrl(Uri.parse(gmapsUrl))) {
        await launchUrl(Uri.parse(gmapsUrl), mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open directions'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadKaggleData() async {
    if (_isLoadingKaggleData) return;
    
    setState(() {
      _isLoadingKaggleData = true;
    });
    
    try {
      // Initialize Kaggle service with provided credentials
      await _kaggleService.initialize();
      
      // Generate accident zones for all of India instead of just near the user location
      final zones = _kaggleService.generateIndiaWideAccidentZones();
      
      setState(() {
        _kaggleAccidentZones = zones;
        _isLoadingKaggleData = false;
      });
      
      // Save zones to provider for use in other screens
      final accidentProvider = Provider.of<AccidentProvider>(context, listen: false);
      accidentProvider.setAccidentZones(zones);
      
    } catch (e) {
      setState(() {
        _isLoadingKaggleData = false;
      });
      debugPrint('Error loading Kaggle data: $e');
    }
  }

  void _showZoneDetails(AccidentZone zone) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: zone.getZoneColor(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Risk Level: ${_getRiskLevelText(zone.riskLevel)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                zone.description,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                '${zone.accidentCount} accidents recorded',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Text(
                'Last updated: ${_formatDate(zone.lastUpdated)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // Center map on this zone
                    _mapController.move(zone.center, 15);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: zone.getZoneColor(),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Center on Map'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showHospitalDetails(Hospital hospital) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.local_hospital, color: Colors.red, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hospital.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                hospital.address,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Distance: ${hospital.distance.toStringAsFixed(1)} km',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (hospital.phone != null)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          launchUrl(Uri.parse('tel:${hospital.phone}'));
                        },
                        icon: const Icon(Icons.phone),
                        label: const Text('Call'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _openDirections(hospital);
                      },
                      icon: const Icon(Icons.directions),
                      label: const Text('Directions'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
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

  @override
  Widget build(BuildContext context) {
    // Get current location or fallback to center of India
    LatLng centerPosition = widget.location ?? 
      (Provider.of<AccidentProvider>(context).currentPosition != null
        ? LatLng(
            Provider.of<AccidentProvider>(context).currentPosition!.latitude,
            Provider.of<AccidentProvider>(context).currentPosition!.longitude,
          )
        : const LatLng(23.2599, 77.4126)); // Center of India (around Bhopal)
    
    // Use a lower zoom level to show more of the country when displaying nationwide data
    final double mapZoom = _showKaggleData && widget.location == null ? 5.0 : _initialZoom;
        
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Hospitals'),
        actions: [
          // Toggle Kaggle data visibility
          IconButton(
            icon: Icon(_showKaggleData ? Icons.visibility : Icons.visibility_off),
            tooltip: _showKaggleData ? 'Hide Risk Data' : 'Show Risk Data',
            onPressed: () {
              setState(() {
                _showKaggleData = !_showKaggleData;
              });
            },
          ),
          // Toggle accident zones visibility
          IconButton(
            icon: Icon(_showAccidentZones ? Icons.layers : Icons.layers_clear),
            tooltip: _showAccidentZones ? 'Hide Zones' : 'Show Zones',
            onPressed: () {
              setState(() {
                _showAccidentZones = !_showAccidentZones;
              });
            },
          ),
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Data',
            onPressed: () {
              _loadHospitals();
              _loadAccidentZones();
              _loadKaggleData();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Map takes top 50% of screen
          Expanded(
            flex: 1,
            child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: centerPosition,
                    initialZoom: mapZoom,
                    onTap: (tapPosition, point) {
                      setState(() {
                        _selectedHospital = null;
                        _selectedZone = null;
                      });
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    ),
                    // Current location marker
                    CurrentLocationLayer(
                      style: const LocationMarkerStyle(
                        marker: DefaultLocationMarker(
                          color: Colors.blue,
                          child: Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 15,
                          ),
                        ),
                        accuracyCircleColor: Colors.blue,
                      ),
                    ),
                    // Show Kaggle data layer if enabled
                    if (_showKaggleData && _kaggleAccidentZones.isNotEmpty)
                      KaggleAccidentLayer(
                        accidentZones: _kaggleAccidentZones,
                        onTap: _showZoneDetails,
                      ),
                    // Show regular accident zones if enabled
                    if (_showAccidentZones && _accidentZones.isNotEmpty)
                      AccidentZoneLayer(
                        zones: _accidentZones,
                        onTap: _showZoneDetails,
                      ),
                    // Hospital markers
                    MarkerLayer(
                      markers: _hospitals.map((hospital) {
                        return Marker(
                          point: hospital.location,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedHospital = hospital;
                              });
                              _mapController.move(hospital.location, _initialZoom);
                            },
                            child: Icon(
                              Icons.local_hospital,
                              color: _selectedHospital == hospital ? Colors.red : Colors.red.shade800,
                              size: 30,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
          ),
          
          // Hospital list takes bottom 50% of screen
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Nearby Hospitals (${_hospitals.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _hospitals.isEmpty
                      ? const Center(child: Text('No hospitals found nearby'))
                      : ListView.builder(
                          itemCount: _hospitals.length,
                          itemBuilder: (context, index) {
                            final hospital = _hospitals[index];
                            return ListTile(
                              title: Text(
                                hospital.name,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text('${hospital.distance.toStringAsFixed(1)} km away'),
                              leading: const Icon(Icons.local_hospital, color: Colors.red),
                              trailing: ElevatedButton.icon(
                                onPressed: () => _openDirections(hospital),
                                icon: const Icon(Icons.directions),
                                label: const Text('Directions'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                              onTap: () {
                                setState(() {
                                  _selectedHospital = hospital;
                                });
                                _mapController.move(hospital.location, _initialZoom);
                              },
                            );
                          },
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          try {
            _mapController.move(centerPosition, _initialZoom);
          } catch (e) {
            debugPrint('Error moving map: $e');
          }
        },
        child: const Icon(Icons.my_location),
      ),
    );
  }
} 