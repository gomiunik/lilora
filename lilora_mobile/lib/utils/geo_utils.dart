import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Utility functions for geographic calculations and signal visualization.

/// Get color based on RSSI value.
/// Returns a color gradient from green (strong) to red (weak).
Color getRssiColor(double rssi) {
  if (rssi > -80) return Colors.green;
  if (rssi > -100) return Colors.lightGreen;
  if (rssi > -110) return Colors.orange;
  if (rssi > -120) return Colors.deepOrange;
  return Colors.red;
}

/// Get marker size based on SNR value.
/// SNR typically ranges from -20 to +20 dB.
/// Returns marker size between 8 and 20 pixels.
double getMarkerSize(double snr) {
  // Normalize SNR from -20..+20 to 0..1
  final normalized = ((snr + 20) / 40).clamp(0.0, 1.0);
  // Map to size 8..20
  return 8 + (normalized * 12);
}

/// Get a descriptive text for signal quality based on RSSI.
String getRssiQualityText(double rssi) {
  if (rssi > -80) return 'Excellent';
  if (rssi > -100) return 'Good';
  if (rssi > -110) return 'Fair';
  if (rssi > -120) return 'Poor';
  return 'Very Poor';
}

/// Calculate distance between two geographic points using Haversine formula.
/// Returns distance in meters.
double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const earthRadius = 6371000.0; // Earth's radius in meters

  final dLat = _toRadians(lat2 - lat1);
  final dLon = _toRadians(lon2 - lon1);

  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRadians(lat1)) *
          math.cos(_toRadians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);

  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

  return earthRadius * c;
}

double _toRadians(double degrees) {
  return degrees * math.pi / 180;
}

/// Format distance for display.
/// Shows meters for distances < 1000m, otherwise kilometers.
String formatDistance(double? meters) {
  if (meters == null) return '-';
  if (meters < 1000) {
    return '${meters.toStringAsFixed(0)} m';
  } else {
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }
}

/// Format RSSI value for display.
String formatRssi(double rssi) {
  return '${rssi.toStringAsFixed(1)} dBm';
}

/// Format SNR value for display.
String formatSnr(double snr) {
  return '${snr.toStringAsFixed(1)} dB';
}

/// Format spreading factor for display.
String formatSpreadingFactor(int sf) {
  return 'SF$sf';
}

/// Format frequency for display.
String formatFrequency(double freq) {
  return '${freq.toStringAsFixed(1)} MHz';
}

/// Get icon for signal quality.
IconData getSignalIcon(double rssi) {
  if (rssi > -80) return Icons.signal_cellular_4_bar;
  if (rssi > -100) return Icons.signal_cellular_alt;
  if (rssi > -110) return Icons.signal_cellular_alt_2_bar;
  if (rssi > -120) return Icons.signal_cellular_alt_1_bar;
  return Icons.signal_cellular_0_bar;
}

/// Get color gradient stops for RSSI legend.
List<Color> get rssiGradientColors => [
      Colors.green,
      Colors.lightGreen,
      Colors.orange,
      Colors.deepOrange,
      Colors.red,
    ];

/// Get RSSI thresholds for legend.
List<int> get rssiThresholds => [-80, -100, -110, -120];
