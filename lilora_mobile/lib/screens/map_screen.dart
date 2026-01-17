import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/range_point.dart';
import '../services/gps_service.dart';
import '../services/websocket_service.dart';
import '../services/session_service.dart';
import '../utils/geo_utils.dart';
import '../widgets/metrics_panel.dart';
import 'settings_screen.dart';

/// Map screen displaying real-time range visualization.
/// Shows range points as colored markers and live metrics.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final List<RangePoint> _displayedPoints = [];
  StreamSubscription<RangePoint>? _pointSubscription;

  // Map settings
  bool _autoCenter = true;
  bool _showPath = true;
  double _currentZoom = 15.0;

  // Current center - will be updated with phone's GPS position
  LatLng _currentCenter = const LatLng(46.0569, 14.5058);
  bool _initialPositionSet = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeServices();
    });
  }

  Future<void> _initializeServices() async {
    final sessionService = context.read<SessionService>();
    final wsService = context.read<WebSocketService>();
    final gpsService = context.read<GpsService>();

    // Initialize session service
    if (!sessionService.isInitialized) {
      await sessionService.initialize();
    }

    // Center map on phone's current GPS position
    if (!_initialPositionSet) {
      final position = await gpsService.getCurrentPosition();
      if (position != null && mounted) {
        setState(() {
          _currentCenter = LatLng(position.latitude, position.longitude);
          _initialPositionSet = true;
        });
        _mapController.move(_currentCenter, _currentZoom);
      }
    }

    // Subscribe to range point stream
    _pointSubscription = wsService.rangePointStream.listen(_onRangePointReceived);
  }

  void _onRangePointReceived(RangePoint point) {
    setState(() {
      _displayedPoints.add(point);

      // Limit displayed points to prevent performance issues
      if (_displayedPoints.length > 500) {
        _displayedPoints.removeAt(0);
      }
    });

    // Auto-center map on new point
    if (_autoCenter && point.hasValidGps) {
      _mapController.move(
        LatLng(point.latitude, point.longitude),
        _currentZoom,
      );
    }

    // Add to active session if recording
    final sessionService = context.read<SessionService>();
    if (sessionService.isRecording) {
      sessionService.addPoint(point);
    }
  }

  void _toggleRecording() async {
    final sessionService = context.read<SessionService>();

    if (sessionService.isRecording) {
      await sessionService.stopSession();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording stopped')),
        );
      }
    } else {
      await sessionService.startSession();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording started')),
        );
      }
    }
  }

  @override
  void dispose() {
    _pointSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Range Map'),
        actions: [
          // Auto-center toggle
          IconButton(
            icon: Icon(_autoCenter ? Icons.gps_fixed : Icons.gps_not_fixed),
            onPressed: () {
              setState(() {
                _autoCenter = !_autoCenter;
              });
            },
            tooltip: _autoCenter ? 'Auto-center on' : 'Auto-center off',
          ),
          // Show path toggle
          IconButton(
            icon: Icon(_showPath ? Icons.timeline : Icons.timeline_outlined),
            onPressed: () {
              setState(() {
                _showPath = !_showPath;
              });
            },
            tooltip: _showPath ? 'Hide path' : 'Show path',
          ),
          // Settings
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection status bar
          Consumer<WebSocketService>(
            builder: (context, wsService, _) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                color: wsService.isConnected
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    Icon(
                      wsService.isConnected ? Icons.cloud_done : Icons.cloud_off,
                      size: 16,
                      color: wsService.isConnected ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      wsService.statusMessage,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    if (!wsService.isConnected && !wsService.isConnecting)
                      TextButton(
                        onPressed: () => wsService.resetReconnection(),
                        child: const Text('Reconnect'),
                      ),
                  ],
                ),
              );
            },
          ),

          // Map
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentCenter,
                initialZoom: _currentZoom,
                onPositionChanged: (position, hasGesture) {
                  if (hasGesture) {
                    // User manually moved map, disable auto-center
                    setState(() {
                      _autoCenter = false;
                      _currentZoom = position.zoom;
                    });
                  }
                },
              ),
              children: [
                // OpenStreetMap tiles
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.lilora.mobile',
                ),

                // Path line connecting points
                if (_showPath && _displayedPoints.length > 1)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _displayedPoints
                            .where((p) => p.hasValidGps)
                            .map((p) => LatLng(p.latitude, p.longitude))
                            .toList(),
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                        strokeWidth: 3,
                      ),
                    ],
                  ),

                // Gateway marker (if available)
                if (_displayedPoints.isNotEmpty && _displayedPoints.last.hasGatewayLocation)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(
                          _displayedPoints.last.gatewayLat!,
                          _displayedPoints.last.gatewayLon!,
                        ),
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.cell_tower,
                          color: Colors.purple,
                          size: 32,
                        ),
                      ),
                    ],
                  ),

                // Range point markers
                MarkerLayer(
                  markers: _displayedPoints
                      .where((p) => p.hasValidGps)
                      .map((point) => _buildMarker(point))
                      .toList(),
                ),
              ],
            ),
          ),

          // Metrics panel
          Consumer2<WebSocketService, SessionService>(
            builder: (context, wsService, sessionService, _) {
              return MetricsPanel(
                currentPoint: wsService.lastRangePoint,
                totalPoints: sessionService.isRecording
                    ? sessionService.currentSessionPoints.length
                    : _displayedPoints.length,
                maxDistance: sessionService.isRecording
                    ? sessionService.activeSession?.maxDistance
                    : _displayedPoints.isNotEmpty
                        ? _displayedPoints
                            .where((p) => p.distance != null)
                            .fold<double?>(
                              null,
                              (max, p) =>
                                  max == null || (p.distance ?? 0) > max ? p.distance : max,
                            )
                        : null,
                isRecording: sessionService.isRecording,
                onRecordTap: _toggleRecording,
              );
            },
          ),
        ],
      ),
    );
  }

  Marker _buildMarker(RangePoint point) {
    final color = getRssiColor(point.rssi);
    final size = getMarkerSize(point.snr);

    return Marker(
      point: LatLng(point.latitude, point.longitude),
      width: size + 8,
      height: size + 8,
      child: GestureDetector(
        onTap: () => _showPointDetails(point),
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.8),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPointDetails(RangePoint point) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    getSignalIcon(point.rssi),
                    color: getRssiColor(point.rssi),
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Range Point',
                    style: theme.textTheme.titleLarge,
                  ),
                  const Spacer(),
                  Chip(
                    label: Text(point.signalQualityText),
                    backgroundColor: getRssiColor(point.rssi).withValues(alpha: 0.2),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _detailRow('RSSI', formatRssi(point.rssi)),
              _detailRow('SNR', formatSnr(point.snr)),
              _detailRow('Distance', formatDistance(point.distance)),
              _detailRow('Spreading Factor', formatSpreadingFactor(point.spreadingFactor)),
              _detailRow('Frequency', formatFrequency(point.frequency)),
              const Divider(),
              _detailRow('Latitude', point.latitude.toStringAsFixed(6)),
              _detailRow('Longitude', point.longitude.toStringAsFixed(6)),
              _detailRow('Altitude', '${point.altitude} m'),
              _detailRow('Satellites', '${point.satellites}'),
              _detailRow('HDOP', point.hdop.toStringAsFixed(1)),
              const Divider(),
              _detailRow('Frame', '#${point.frameCount}'),
              _detailRow('Device', point.deviceEui),
              _detailRow('Time', point.timestamp.toLocal().toString().split('.')[0]),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }
}
