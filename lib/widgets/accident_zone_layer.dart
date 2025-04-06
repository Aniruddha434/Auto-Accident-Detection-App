import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:accident_report_system/models/accident_zone.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';

/// A layer that displays accident zones as colored circles
class AccidentZoneLayer extends StatelessWidget {
  final List<AccidentZone> zones;
  final Function(AccidentZone)? onTap;
  
  const AccidentZoneLayer({
    Key? key,
    required this.zones,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CircleLayer(
      circles: zones.map((zone) {
        return CircleMarker(
          point: zone.center,
          radius: zone.radius * 1000, // Convert km to meters
          useRadiusInMeter: true,
          color: zone.getZoneColor(opacity: 0.3),
          borderColor: zone.getZoneColor(opacity: 0.7),
          borderStrokeWidth: 2.0,
        );
      }).toList(),
    );
  }
}

/// Custom widget to visualize a circle on the map
class CircleVizLayer extends StatelessWidget {
  final LatLng center;
  final double radiusKm;
  final Color color;
  final Color borderColor;
  final VoidCallback? onTap;
  
  const CircleVizLayer({
    Key? key,
    required this.center,
    required this.radiusKm,
    required this.color,
    required this.borderColor,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Use a transparent hit region that covers the circle
      onTap: onTap,
      child: CircleLayer(
        circles: [
          CircleMarker(
            point: center,
            radius: radiusKm * 1000, // km to meters
            useRadiusInMeter: true,
            color: color,
            borderColor: borderColor,
            borderStrokeWidth: 2.0,
          ),
        ],
      ),
    );
  }
}

class AccidentZoneMarkers extends StatelessWidget {
  final List<AccidentZone> zones;
  final Function(AccidentZone)? onTap;
  
  const AccidentZoneMarkers({
    Key? key,
    required this.zones,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Create markers that show in the center of each zone
    return MarkerLayer(
      markers: zones.map((zone) {
        return Marker(
          width: 90.0,
          height: 30.0,
          point: zone.center,
          child: GestureDetector(
            onTap: onTap != null ? () => onTap!(zone) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: zone.getZoneColor(opacity: 0.8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${zone.accidentCount} Accidents',
                    style: const TextStyle(
                      color: Colors.white, 
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Widget that shows both the zone circles and zone markers
class AccidentZoneMapLayers extends StatelessWidget {
  final List<AccidentZone> zones;
  final Function(AccidentZone)? onZoneTap;
  
  const AccidentZoneMapLayers({
    Key? key,
    required this.zones,
    this.onZoneTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AccidentZoneLayer(zones: zones, onTap: onZoneTap),
        AccidentZoneMarkers(zones: zones, onTap: onZoneTap),
      ],
    );
  }
} 