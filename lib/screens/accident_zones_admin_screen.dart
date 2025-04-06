import 'package:flutter/material.dart';
import 'package:accident_report_system/tools/sample_data_generator.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:accident_report_system/services/accident_zone_service.dart';
import 'package:accident_report_system/models/accident_zone.dart';

class AccidentZonesAdminScreen extends StatefulWidget {
  const AccidentZonesAdminScreen({Key? key}) : super(key: key);

  @override
  State<AccidentZonesAdminScreen> createState() => _AccidentZonesAdminScreenState();
}

class _AccidentZonesAdminScreenState extends State<AccidentZonesAdminScreen> {
  final SampleDataGenerator _generator = SampleDataGenerator();
  final AccidentZoneService _zoneService = AccidentZoneService();
  
  bool _isLoading = false;
  String _statusMessage = '';
  List<AccidentZone> _existingZones = [];
  
  final TextEditingController _countController = TextEditingController(text: '5');
  final TextEditingController _radiusController = TextEditingController(text: '10.0');
  
  @override
  void initState() {
    super.initState();
    _loadExistingZones();
  }
  
  @override
  void dispose() {
    _countController.dispose();
    _radiusController.dispose();
    super.dispose();
  }
  
  Future<void> _loadExistingZones() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Loading existing zones...';
    });
    
    try {
      final zones = await _zoneService.getAllAccidentZones();
      
      setState(() {
        _existingZones = zones;
        _statusMessage = '${zones.length} zones found';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
        _isLoading = false;
      });
    }
  }
  
  Future<void> _generateSampleData() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Generating sample data...';
    });
    
    try {
      // Get current location
      final position = await Geolocator.getCurrentPosition();
      final center = LatLng(position.latitude, position.longitude);
      
      // Parse input values
      final count = int.tryParse(_countController.text) ?? 5;
      final radius = double.tryParse(_radiusController.text) ?? 10.0;
      
      // Generate sample data
      await _generator.generateAccidentZones(
        center: center,
        count: count,
        radiusKm: radius,
      );
      
      setState(() {
        _statusMessage = 'Generated $count sample zones';
      });
      
      // Reload zones
      await _loadExistingZones();
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _clearAllZones() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: const Text('Are you sure you want to delete all accident zones? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      setState(() {
        _isLoading = true;
        _statusMessage = 'Deleting all zones...';
      });
      
      try {
        await _generator.clearAccidentZones();
        
        setState(() {
          _statusMessage = 'All zones deleted';
        });
        
        // Reload zones
        await _loadExistingZones();
      } catch (e) {
        setState(() {
          _statusMessage = 'Error: $e';
        });
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accident Zones Admin'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadExistingZones,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Generate Sample Accident Zones',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _countController,
                            decoration: const InputDecoration(
                              labelText: 'Number of zones',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _radiusController,
                            decoration: const InputDecoration(
                              labelText: 'Radius (km)',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _generateSampleData,
                            icon: const Icon(Icons.add_location_alt),
                            label: const Text('Generate Sample Data'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Existing Zones (${_existingZones.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _clearAllZones,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Clear All'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              Text(
                _statusMessage,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            
            const SizedBox(height: 16),
            
            Expanded(
              child: _existingZones.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.location_off,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No accident zones found',
                          style: TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Generate sample data to get started',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _existingZones.length,
                    itemBuilder: (context, index) {
                      final zone = _existingZones[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: zone.getZoneColor(),
                            child: Text(
                              zone.riskLevel.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text('${zone.accidentCount} Accidents'),
                          subtitle: Text(zone.description),
                          trailing: Text('${zone.radius.toStringAsFixed(1)} km'),
                        ),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }
} 