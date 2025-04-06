import 'package:flutter/material.dart';
import 'package:accident_report_system/models/accident_model.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class AccidentDetailsScreen extends StatefulWidget {
  final AccidentModel accident;

  const AccidentDetailsScreen({
    super.key,
    required this.accident,
  });

  @override
  State<AccidentDetailsScreen> createState() => _AccidentDetailsScreenState();
}

class _AccidentDetailsScreenState extends State<AccidentDetailsScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _markers.add(
      Marker(
        markerId: MarkerId(widget.accident.id),
        position: LatLng(
          widget.accident.latitude,
          widget.accident.longitude,
        ),
        infoWindow: InfoWindow(
          title: 'Accident Location',
          snippet: DateFormat('MMM d, yyyy • h:mm a').format(widget.accident.timestamp),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormatter = DateFormat('MMMM d, yyyy');
    final timeFormatter = DateFormat('h:mm a');
    final formattedDate = dateFormatter.format(widget.accident.timestamp);
    final formattedTime = timeFormatter.format(widget.accident.timestamp);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accident Details'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Map section
            SizedBox(
              height: 250,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(
                    widget.accident.latitude,
                    widget.accident.longitude,
                  ),
                  zoom: 15,
                ),
                markers: _markers,
                onMapCreated: (GoogleMapController controller) {
                  _mapController = controller;
                },
              ),
            ),
            
            Padding(
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
                            'Accident Information',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Divider(),
                          const SizedBox(height: 12),
                          _buildInfoRow('Date', formattedDate),
                          _buildInfoRow('Time', formattedTime),
                          _buildInfoRow(
                            'Impact Force',
                            '${widget.accident.impactForce.toStringAsFixed(2)}g',
                          ),
                          _buildInfoRow(
                            'Severity',
                            _getSeverityText(widget.accident.impactForce),
                          ),
                          _buildInfoRow(
                            'Help Status',
                            widget.accident.helpSent ? 'Emergency alerts sent' : 'No alerts sent',
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Location Details',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Divider(),
                          const SizedBox(height: 12),
                          _buildInfoRow(
                            'Latitude',
                            widget.accident.latitude.toStringAsFixed(6),
                          ),
                          _buildInfoRow(
                            'Longitude',
                            widget.accident.longitude.toStringAsFixed(6),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _openInGoogleMaps,
                            icon: const Icon(Icons.map),
                            label: const Text('Open in Google Maps'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  if (widget.accident.notes != null && widget.accident.notes!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Notes',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Divider(),
                            const SizedBox(height: 12),
                            Text(widget.accident.notes!),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getSeverityText(double impactForce) {
    if (impactForce > 8) {
      return 'High';
    } else if (impactForce > 6) {
      return 'Medium';
    } else {
      return 'Low';
    }
  }

  Future<void> _openInGoogleMaps() async {
    final url = 'https://www.google.com/maps/search/?api=1&query=${widget.accident.latitude},${widget.accident.longitude}';
    final uri = Uri.parse(url);
    
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Google Maps'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
} 