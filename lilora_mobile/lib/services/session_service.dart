import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../models/range_point.dart';
import '../models/session.dart';

/// Service for managing range testing sessions.
/// Handles session creation, recording, storage, and export.
class SessionService extends ChangeNotifier {
  static const String _sessionBoxName = 'sessions';
  static const String _rangePointBoxName = 'range_points';

  Box<Session>? _sessionBox;
  Box<RangePoint>? _rangePointBox;
  bool _isInitialized = false;

  // Active session state
  Session? _activeSession;
  final List<RangePoint> _currentSessionPoints = [];

  // All sessions (cached)
  List<Session> _sessions = [];

  // Getters
  bool get isInitialized => _isInitialized;
  Session? get activeSession => _activeSession;
  bool get isRecording => _activeSession != null;
  List<RangePoint> get currentSessionPoints => List.unmodifiable(_currentSessionPoints);
  List<Session> get sessions => List.unmodifiable(_sessions);

  /// Initialize Hive boxes for storage
  Future<void> initialize() async {
    if (_isInitialized) return;

    _sessionBox = await Hive.openBox<Session>(_sessionBoxName);
    _rangePointBox = await Hive.openBox<RangePoint>(_rangePointBoxName);

    // Load all sessions
    _sessions = _sessionBox!.values.toList();
    _sessions.sort((a, b) => b.startTime.compareTo(a.startTime)); // Most recent first

    _isInitialized = true;
    notifyListeners();
  }

  /// Start a new recording session
  Future<Session> startSession({String? name, String? notes}) async {
    if (!_isInitialized) throw StateError('SessionService not initialized');
    if (_activeSession != null) throw StateError('Session already active');

    final sessionName = name ?? 'Session ${DateFormat('MMM d, HH:mm').format(DateTime.now())}';

    _activeSession = Session(
      id: const Uuid().v4(),
      name: sessionName,
      startTime: DateTime.now(),
      notes: notes,
    );

    // Save to Hive
    await _sessionBox!.put(_activeSession!.id, _activeSession!);

    // Add to local list
    _sessions.insert(0, _activeSession!);
    _currentSessionPoints.clear();

    notifyListeners();
    return _activeSession!;
  }

  /// Stop the active recording session
  Future<Session?> stopSession() async {
    if (_activeSession == null) return null;

    _activeSession!.stop();
    await _activeSession!.save();

    final stoppedSession = _activeSession;
    _activeSession = null;
    _currentSessionPoints.clear();

    notifyListeners();
    return stoppedSession;
  }

  /// Add a range point to the active session
  Future<void> addPoint(RangePoint point) async {
    if (!_isInitialized) return;
    if (_activeSession == null) return;

    // Create a new point with the session ID
    final sessionPoint = RangePoint(
      timestamp: point.timestamp,
      deviceEui: point.deviceEui,
      frameCount: point.frameCount,
      latitude: point.latitude,
      longitude: point.longitude,
      altitude: point.altitude,
      fixQuality: point.fixQuality,
      hdop: point.hdop,
      satellites: point.satellites,
      rssi: point.rssi,
      snr: point.snr,
      spreadingFactor: point.spreadingFactor,
      frequency: point.frequency,
      gatewayId: point.gatewayId,
      gatewayLat: point.gatewayLat,
      gatewayLon: point.gatewayLon,
      distance: point.distance,
      sessionId: _activeSession!.id,
    );

    // Save to Hive
    await _rangePointBox!.put(sessionPoint.storageKey, sessionPoint);

    // Update session statistics
    _activeSession!.updateStats(
      rssi: point.rssi,
      snr: point.snr,
      distance: point.distance,
      deviceEui: point.deviceEui,
    );
    await _activeSession!.save();

    // Add to current session points
    _currentSessionPoints.add(sessionPoint);

    notifyListeners();
  }

  /// Get all points for a specific session
  Future<List<RangePoint>> getSessionPoints(String sessionId) async {
    if (!_isInitialized) return [];

    final points = _rangePointBox!.values
        .where((p) => p.sessionId == sessionId)
        .toList();

    // Sort by timestamp
    points.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return points;
  }

  /// Delete a session and its points
  Future<void> deleteSession(String sessionId) async {
    if (!_isInitialized) return;

    // Delete all points for this session
    final pointKeys = _rangePointBox!.keys
        .where((key) => key.toString().startsWith('${sessionId}_'))
        .toList();

    for (final key in pointKeys) {
      await _rangePointBox!.delete(key);
    }

    // Delete the session
    await _sessionBox!.delete(sessionId);

    // Remove from local list
    _sessions.removeWhere((s) => s.id == sessionId);

    notifyListeners();
  }

  /// Rename a session
  Future<void> renameSession(String sessionId, String newName) async {
    if (!_isInitialized) return;

    final session = _sessionBox!.get(sessionId);
    if (session != null) {
      session.name = newName;
      await session.save();
      notifyListeners();
    }
  }

  /// Export session to GeoJSON format
  Future<String> exportToGeoJson(String sessionId) async {
    final points = await getSessionPoints(sessionId);
    final session = _sessionBox!.get(sessionId);

    final features = points.map((p) => p.toGeoJsonFeature()).toList();

    final geoJson = {
      'type': 'FeatureCollection',
      'properties': {
        'name': session?.name ?? 'Unknown Session',
        'startTime': session?.startTime.toIso8601String(),
        'endTime': session?.endTime?.toIso8601String(),
        'pointCount': points.length,
        'maxDistance': session?.maxDistance,
        'avgRssi': session?.avgRssi,
      },
      'features': features,
    };

    return const JsonEncoder.withIndent('  ').convert(geoJson);
  }

  /// Export session to KML format
  Future<String> exportToKml(String sessionId) async {
    final points = await getSessionPoints(sessionId);
    final session = _sessionBox!.get(sessionId);
    final sessionName = session?.name ?? 'Unknown Session';

    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
    buffer.writeln('  <Document>');
    buffer.writeln('    <name>$sessionName</name>');
    buffer.writeln('    <description>LiLoRa Range Test Session</description>');

    // Define styles for different signal qualities
    _writeKmlStyles(buffer);

    // Add placemarks for each point
    for (final point in points) {
      final styleId = _getKmlStyleId(point.rssi);
      buffer.writeln('    <Placemark>');
      buffer.writeln('      <name>Frame ${point.frameCount}</name>');
      buffer.writeln('      <description>');
      buffer.writeln('        RSSI: ${point.rssi.toStringAsFixed(1)} dBm');
      buffer.writeln('        SNR: ${point.snr.toStringAsFixed(1)} dB');
      buffer.writeln('        SF: ${point.spreadingFactor}');
      buffer.writeln('        Distance: ${point.distance?.toStringAsFixed(0) ?? "N/A"} m');
      buffer.writeln('        Time: ${point.timestamp.toIso8601String()}');
      buffer.writeln('      </description>');
      buffer.writeln('      <styleUrl>#$styleId</styleUrl>');
      buffer.writeln('      <Point>');
      buffer.writeln('        <coordinates>${point.longitude},${point.latitude},${point.altitude}</coordinates>');
      buffer.writeln('      </Point>');
      buffer.writeln('    </Placemark>');
    }

    // Add path line
    if (points.length > 1) {
      buffer.writeln('    <Placemark>');
      buffer.writeln('      <name>Path</name>');
      buffer.writeln('      <LineString>');
      buffer.writeln('        <coordinates>');
      for (final point in points) {
        buffer.writeln('          ${point.longitude},${point.latitude},${point.altitude}');
      }
      buffer.writeln('        </coordinates>');
      buffer.writeln('      </LineString>');
      buffer.writeln('    </Placemark>');
    }

    buffer.writeln('  </Document>');
    buffer.writeln('</kml>');

    return buffer.toString();
  }

  void _writeKmlStyles(StringBuffer buffer) {
    final styles = {
      'excellent': 'ff00ff00', // Green
      'good': 'ff00ff80', // Light green
      'fair': 'ff00a5ff', // Orange (BGR format)
      'poor': 'ff0045ff', // Deep orange
      'very_poor': 'ff0000ff', // Red
    };

    for (final entry in styles.entries) {
      buffer.writeln('    <Style id="${entry.key}">');
      buffer.writeln('      <IconStyle>');
      buffer.writeln('        <color>${entry.value}</color>');
      buffer.writeln('        <scale>0.8</scale>');
      buffer.writeln('        <Icon>');
      buffer.writeln('          <href>http://maps.google.com/mapfiles/kml/shapes/placemark_circle.png</href>');
      buffer.writeln('        </Icon>');
      buffer.writeln('      </IconStyle>');
      buffer.writeln('    </Style>');
    }
  }

  String _getKmlStyleId(double rssi) {
    if (rssi > -80) return 'excellent';
    if (rssi > -100) return 'good';
    if (rssi > -110) return 'fair';
    if (rssi > -120) return 'poor';
    return 'very_poor';
  }

  /// Save exported content to a file and return the file path
  Future<String> saveExportFile(String content, String filename) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$filename');
    await file.writeAsString(content);
    return file.path;
  }

  /// Get statistics summary for a session
  Future<Map<String, dynamic>> getSessionStats(String sessionId) async {
    final session = _sessionBox!.get(sessionId);
    final points = await getSessionPoints(sessionId);

    return {
      'name': session?.name,
      'startTime': session?.startTime,
      'endTime': session?.endTime,
      'duration': session?.durationText,
      'pointCount': points.length,
      'maxDistance': session?.maxDistance,
      'minRssi': session?.minRssi,
      'maxRssi': session?.maxRssi,
      'avgRssi': session?.avgRssi,
      'minSnr': session?.minSnr,
      'maxSnr': session?.maxSnr,
      'avgSnr': session?.avgSnr,
    };
  }

  @override
  void dispose() {
    _sessionBox?.close();
    _rangePointBox?.close();
    super.dispose();
  }
}
