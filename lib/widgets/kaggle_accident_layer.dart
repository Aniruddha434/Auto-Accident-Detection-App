import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:accident_report_system/models/accident_zone.dart';

class KaggleAccidentLayer extends StatelessWidget {
  final List<AccidentZone> accidentZones;
  final Function(AccidentZone)? onTap;

  const KaggleAccidentLayer({
    super.key,
    required this.accidentZones,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Create the circles layer
        CircleLayer(
          circles: accidentZones.map((zone) {
            // Calculate color based on risk level
            final Color color = zone.getZoneColor();
            // Calculate border color - slightly darker than the main color
            final Color borderColor = HSLColor.fromColor(color)
                .withLightness((HSLColor.fromColor(color).lightness - 0.1).clamp(0.0, 1.0))
                .toColor();

            return CircleMarker(
              point: zone.center,
              radius: zone.radius * 1000, // Convert km to meters
              color: color.withOpacity(0.35), // Semi-transparent fill
              borderColor: borderColor.withOpacity(0.7), // More opaque border
              borderStrokeWidth: 2.0,
              useRadiusInMeter: true,
            );
          }).toList(),
        ),
        
        // Create a separate marker layer for tap interactions
        if (onTap != null)
          MarkerLayer(
            markers: accidentZones.map((zone) {
              return Marker(
                width: zone.radius * 2000, // Make marker cover the entire circle
                height: zone.radius * 2000,
                point: zone.center,
                child: GestureDetector(
                  onTap: () => onTap!(zone),
                  child: Container(
                    color: Colors.transparent,
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
} 