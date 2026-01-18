import 'package:hive/hive.dart';

part 'sent_transmission.g.dart';

/// Represents a LoRaWAN transmission sent by the watch.
/// Received via BLE notification from firmware after each uplink.
@HiveType(typeId: 3)
class SentTransmission extends HiveObject {
  @HiveField(0)
  final int frameCount;

  @HiveField(1)
  final double latitude;

  @HiveField(2)
  final double longitude;

  @HiveField(3)
  final bool hasValidGps;

  @HiveField(4)
  final DateTime sentTime;

  /// Whether this transmission was received by the backend (matched via WebSocket)
  @HiveField(5)
  bool received;

  /// Session ID this transmission belongs to (for storage)
  @HiveField(6)
  String? sessionId;

  SentTransmission({
    required this.frameCount,
    required this.latitude,
    required this.longitude,
    required this.hasValidGps,
    required this.sentTime,
    this.received = false,
    this.sessionId,
  });

  /// Parse from BLE TX notification string.
  /// Format: `TX,frameCount,lat,lon,hasGps`
  /// Example: `TX,42,46.056900,14.505800,1`
  static SentTransmission? fromBleNotification(String data) {
    try {
      final trimmed = data.trim();
      if (!trimmed.startsWith('TX,')) return null;

      final parts = trimmed.substring(3).split(',');
      if (parts.length < 4) return null;

      return SentTransmission(
        frameCount: int.parse(parts[0]),
        latitude: double.parse(parts[1]),
        longitude: double.parse(parts[2]),
        hasValidGps: parts[3] == '1',
        sentTime: DateTime.now(),
      );
    } catch (e) {
      return null;
    }
  }

  /// Storage key for Hive
  String get storageKey => '${sessionId}_tx_$frameCount';

  /// Convert to GeoJSON Feature for export
  Map<String, dynamic> toGeoJsonFeature() {
    return {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [longitude, latitude],
      },
      'properties': {
        'type': 'failed_transmission',
        'frame_count': frameCount,
        'sent_time': sentTime.toIso8601String(),
        'has_valid_gps': hasValidGps,
      },
    };
  }

  @override
  String toString() {
    return 'SentTransmission(frame: $frameCount, lat: $latitude, lon: $longitude, received: $received)';
  }
}
