import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/range_point.dart';
import '../models/sent_transmission.dart';
import '../services/gps_service.dart';
import '../services/bluetooth_service.dart';
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
  final List<SentTransmission> _sentTransmissions = [];
  StreamSubscription<RangePoint>? _pointSubscription;
  StreamSubscription<SentTransmission>? _txSubscription;

  // Map settings
  bool _autoCenter = true;
  bool _showPath = true;
  bool _showFailed = true;
  bool _showGatewayLines = false;
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
    final bleService = context.read<BluetoothService>();

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

    // Subscribe to range point stream (successful deliveries from WebSocket)
    _pointSubscription = wsService.rangePointStream.listen(_onRangePointReceived);

    // Subscribe to TX notifications from watch (all transmissions)
    _txSubscription = bleService.txNotificationStream.listen(_onTxNotificationReceived);
  }

  void _onRangePointReceived(RangePoint point) {
    // Mark matching sent transmission as received
    _markTransmissionReceived(point.frameCount);

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

  void _onTxNotificationReceived(SentTransmission tx) {
    setState(() {
      _sentTransmissions.add(tx);

      // Limit list size
      if (_sentTransmissions.length > 300) {
        _sentTransmissions.removeRange(0, _sentTransmissions.length - 300);
      }
    });

    // Schedule check for failed transmission after a delay
    // If not matched within 10 seconds, consider it failed
    final sessionService = context.read<SessionService>();
    Future.delayed(const Duration(seconds: 10), () {
      if (!tx.received && tx.hasValidGps && mounted) {
        if (sessionService.isRecording) {
          sessionService.addFailedTransmission(tx);
        }
      }
    });
  }

  /// Mark a sent transmission as received when WebSocket data arrives
  void _markTransmissionReceived(int frameCount) {
    for (final tx in _sentTransmissions) {
      if (tx.frameCount == frameCount && !tx.received) {
        tx.received = true;
        break;
      }
    }
  }

  /// Get list of failed (not received) transmissions with valid GPS
  List<SentTransmission> get _failedTransmissions =>
      _sentTransmissions.where((tx) => !tx.received && tx.hasValidGps).toList();

  /// Get unique gateways from displayed points
  List<Map<String, dynamic>> _getUniqueGateways() {
    final seen = <String>{};
    final gateways = <Map<String, dynamic>>[];

    for (final p in _displayedPoints) {
      if (p.hasGatewayLocation && p.gatewayId != null) {
        if (!seen.contains(p.gatewayId)) {
          seen.add(p.gatewayId!);
          gateways.add({
            'id': p.gatewayId,
            'lat': p.gatewayLat,
            'lon': p.gatewayLon,
          });
        }
      }
    }
    return gateways;
  }

  void _toggleAutoCenter() async {
    setState(() {
      _autoCenter = !_autoCenter;
    });

    // If enabling auto-center, immediately center on the best available position
    if (_autoCenter) {
      // First try to center on the last displayed point with valid GPS
      final validPoints = _displayedPoints.where((p) => p.hasValidGps).toList();
      if (validPoints.isNotEmpty) {
        final lastPoint = validPoints.last;
        _mapController.move(
          LatLng(lastPoint.latitude, lastPoint.longitude),
          _currentZoom,
        );
        return;
      }

      // Otherwise, center on current phone GPS position
      final gpsService = context.read<GpsService>();
      final position = await gpsService.getCurrentPosition();
      if (position != null && mounted) {
        _mapController.move(
          LatLng(position.latitude, position.longitude),
          _currentZoom,
        );
      }
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
    _txSubscription?.cancel();
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
            onPressed: _toggleAutoCenter,
            tooltip: _autoCenter ? 'Auto-center on' : 'Auto-center off',
          ),
          // Show path toggle
          IconButton(
            icon: Icon(
              _showPath ? Icons.show_chart : Icons.show_chart_outlined,
              color: _showPath ? Theme.of(context).colorScheme.primary : null,
            ),
            onPressed: () {
              setState(() {
                _showPath = !_showPath;
              });
            },
            tooltip: _showPath ? 'Hide path' : 'Show path',
          ),
          // Show failed transmissions toggle
          IconButton(
            icon: Icon(
              _showFailed ? Icons.error : Icons.error_outline,
              color: _showFailed && _failedTransmissions.isNotEmpty ? Colors.grey : null,
            ),
            onPressed: () {
              setState(() {
                _showFailed = !_showFailed;
              });
            },
            tooltip: _showFailed
                ? 'Hide failed (${_failedTransmissions.length})'
                : 'Show failed (${_failedTransmissions.length})',
          ),
          // Show gateway lines toggle
          IconButton(
            icon: Icon(
              Icons.cell_tower,
              color: _showGatewayLines ? Colors.purple : null,
            ),
            onPressed: () {
              setState(() {
                _showGatewayLines = !_showGatewayLines;
              });
            },
            tooltip: _showGatewayLines ? 'Hide gateway lines' : 'Show gateway lines',
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

                // Gateway connection lines
                if (_showGatewayLines)
                  PolylineLayer(
                    polylines: _displayedPoints
                        .where((p) => p.hasValidGps && p.hasGatewayLocation)
                        .map((p) => Polyline(
                              points: [
                                LatLng(p.latitude, p.longitude),
                                LatLng(p.gatewayLat!, p.gatewayLon!),
                              ],
                              color: Colors.purple.withValues(alpha: 0.4),
                              strokeWidth: 1.5,
                            ))
                        .toList(),
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

                // Gateway markers (unique gateways)
                if (_showGatewayLines || (_displayedPoints.isNotEmpty && _displayedPoints.last.hasGatewayLocation))
                  MarkerLayer(
                    markers: _getUniqueGateways()
                        .map((gw) => Marker(
                              point: LatLng(gw['lat'] as double, gw['lon'] as double),
                              width: 40,
                              height: 40,
                              child: const Icon(
                                Icons.cell_tower,
                                color: Colors.purple,
                                size: 32,
                              ),
                            ))
                        .toList(),
                  ),

                // Failed transmission markers (gray)
                if (_showFailed && _failedTransmissions.isNotEmpty)
                  MarkerLayer(
                    markers: _failedTransmissions
                        .map((failed) => _buildFailedMarker(failed))
                        .toList(),
                  ),

                // Range point markers (successful)
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

  Marker _buildFailedMarker(SentTransmission failed) {
    const size = 12.0;

    return Marker(
      point: LatLng(failed.latitude, failed.longitude),
      width: size + 8,
      height: size + 8,
      child: GestureDetector(
        onTap: () => _showFailedDetails(failed),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.6),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.close,
              size: 8,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  void _showFailedDetails(SentTransmission failed) {
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
                  const Icon(
                    Icons.signal_cellular_off,
                    color: Colors.grey,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Failed Transmission',
                    style: theme.textTheme.titleLarge,
                  ),
                  const Spacer(),
                  Chip(
                    label: const Text('Not received'),
                    backgroundColor: Colors.grey.withValues(alpha: 0.2),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _detailRow('Frame', '#${failed.frameCount}'),
              const Divider(),
              _detailRow('Latitude', failed.latitude.toStringAsFixed(6)),
              _detailRow('Longitude', failed.longitude.toStringAsFixed(6)),
              _detailRow('Sent at', failed.sentTime.toLocal().toString().split('.')[0]),
              const SizedBox(height: 8),
              Text(
                'This transmission was sent by the watch but not received by the backend.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showPointDetails(RangePoint point) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.25,
          maxChildSize: 0.85,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
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
