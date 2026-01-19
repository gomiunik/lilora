import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/range_point.dart';
import '../models/session.dart';
import '../models/sent_transmission.dart';
import '../services/session_service.dart';
import '../utils/geo_utils.dart';

/// Screen displaying detailed view of a single session with map and export options.
class SessionDetailScreen extends StatefulWidget {
  final String sessionId;

  const SessionDetailScreen({super.key, required this.sessionId});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  Session? _session;
  List<RangePoint> _points = [];
  List<SentTransmission> _failedTx = [];
  bool _isLoading = true;
  final MapController _mapController = MapController();

  // Display toggles
  bool _showFailed = true;
  bool _showGatewayLines = false;
  bool _showPath = true;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final sessionService = context.read<SessionService>();

    final session = sessionService.sessions.firstWhere(
      (s) => s.id == widget.sessionId,
      orElse: () => throw Exception('Session not found'),
    );

    final points = await sessionService.getSessionPoints(widget.sessionId);
    final failedTx = await sessionService.getSessionFailedTx(widget.sessionId);

    setState(() {
      _session = session;
      _points = points;
      _failedTx = failedTx;
      _isLoading = false;
    });

    // Center map on points
    if (points.isNotEmpty) {
      final validPoints = points.where((p) => p.hasValidGps).toList();
      if (validPoints.isNotEmpty) {
        // Calculate center of all points
        final avgLat = validPoints.map((p) => p.latitude).reduce((a, b) => a + b) / validPoints.length;
        final avgLon = validPoints.map((p) => p.longitude).reduce((a, b) => a + b) / validPoints.length;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mapController.move(LatLng(avgLat, avgLon), 14);
        });
      }
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  /// Get unique gateways from points with aggregated stats
  List<Map<String, dynamic>> _getUniqueGateways() {
    final gatewayStats = <String, Map<String, dynamic>>{};

    for (final p in _points) {
      // First, check best gateway (backward compatibility)
      if (p.hasGatewayLocation && p.gatewayId != null) {
        _updateGatewayStats(gatewayStats, p.gatewayId!, p.gatewayLat!, p.gatewayLon!, p.rssi, p.snr);
      }

      // Then, check all gateways if available
      if (p.gateways != null) {
        for (final gw in p.gateways!) {
          if (gw.hasLocation) {
            _updateGatewayStats(gatewayStats, gw.gatewayId, gw.latitude!, gw.longitude!, gw.rssi, gw.snr);
          }
        }
      }
    }

    return gatewayStats.values.toList();
  }

  void _updateGatewayStats(
    Map<String, Map<String, dynamic>> stats,
    String id,
    double lat,
    double lon,
    double rssi,
    double snr,
  ) {
    if (!stats.containsKey(id)) {
      stats[id] = {
        'id': id,
        'lat': lat,
        'lon': lon,
        'receptionCount': 0,
        'rssiSum': 0.0,
        'snrSum': 0.0,
        'minRssi': rssi,
        'maxRssi': rssi,
      };
    }

    final gw = stats[id]!;
    gw['receptionCount'] = (gw['receptionCount'] as int) + 1;
    gw['rssiSum'] = (gw['rssiSum'] as double) + rssi;
    gw['snrSum'] = (gw['snrSum'] as double) + snr;
    gw['avgRssi'] = gw['rssiSum'] / gw['receptionCount'];
    gw['avgSnr'] = gw['snrSum'] / gw['receptionCount'];
    if (rssi < (gw['minRssi'] as double)) gw['minRssi'] = rssi;
    if (rssi > (gw['maxRssi'] as double)) gw['maxRssi'] = rssi;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Session')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final session = _session;
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Session')),
        body: const Center(child: Text('Session not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(session.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _renameSession(session),
            tooltip: 'Rename',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _showExportOptions(),
            tooltip: 'Export',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _deleteSession(session),
            tooltip: 'Delete',
          ),
        ],
      ),
      body: Column(
        children: [
          // Display toggle bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: theme.colorScheme.surfaceContainerHighest,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('Path'),
                    selected: _showPath,
                    onSelected: (v) => setState(() => _showPath = v),
                    avatar: Icon(
                      Icons.show_chart,
                      size: 16,
                      color: _showPath ? theme.colorScheme.primary : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text('Failed (${_failedTx.length})'),
                    selected: _showFailed,
                    onSelected: (v) => setState(() => _showFailed = v),
                    avatar: Icon(
                      Icons.error_outline,
                      size: 16,
                      color: _showFailed ? Colors.grey : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Gateways'),
                    selected: _showGatewayLines,
                    onSelected: (v) => setState(() => _showGatewayLines = v),
                    avatar: Icon(
                      Icons.cell_tower,
                      size: 16,
                      color: _showGatewayLines ? Colors.purple : null,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Map showing all session points
          Expanded(
            flex: 2,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _points.isNotEmpty && _points.first.hasValidGps
                    ? LatLng(_points.first.latitude, _points.first.longitude)
                    : const LatLng(46.0569, 14.5058),
                initialZoom: 14,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.lilora.mobile',
                ),

                // Gateway connection lines
                if (_showGatewayLines)
                  PolylineLayer(
                    polylines: _points
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

                // Path line
                if (_showPath && _points.length > 1)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _points
                            .where((p) => p.hasValidGps)
                            .map((p) => LatLng(p.latitude, p.longitude))
                            .toList(),
                        color: theme.colorScheme.primary.withValues(alpha: 0.5),
                        strokeWidth: 3,
                      ),
                    ],
                  ),

                // Gateway markers
                if (_showGatewayLines)
                  MarkerLayer(
                    markers: _getUniqueGateways()
                        .map((gw) => Marker(
                              point: LatLng(gw['lat'] as double, gw['lon'] as double),
                              width: 40,
                              height: 40,
                              child: GestureDetector(
                                onTap: () => _showGatewayDetails(gw),
                                child: const Icon(
                                  Icons.cell_tower,
                                  color: Colors.purple,
                                  size: 32,
                                ),
                              ),
                            ))
                        .toList(),
                  ),

                // Failed transmission markers (gray)
                if (_showFailed && _failedTx.isNotEmpty)
                  MarkerLayer(
                    markers: _failedTx
                        .where((tx) => tx.hasValidGps)
                        .map((tx) => Marker(
                              point: LatLng(tx.latitude, tx.longitude),
                              width: 20,
                              height: 20,
                              child: GestureDetector(
                                onTap: () => _showFailedDetails(tx),
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
                                    child: Icon(Icons.close, size: 8, color: Colors.white),
                                  ),
                                ),
                              ),
                            ))
                        .toList(),
                  ),

                // Point markers (successful)
                MarkerLayer(
                  markers: _points
                      .where((p) => p.hasValidGps)
                      .map((point) => _buildMarker(point))
                      .toList(),
                ),
              ],
            ),
          ),

          // Statistics panel
          Expanded(
            flex: 1,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Statistics', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _buildStatsGrid(session),
                  const SizedBox(height: 16),
                  Text('Details', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _buildDetailsCard(session),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(Session session) {
    final totalTx = session.pointCount + session.failedCount;
    final successRate = totalTx > 0
        ? (session.pointCount / totalTx * 100).toStringAsFixed(1)
        : '-';

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _StatTile(
          icon: Icons.pin_drop,
          label: 'Received',
          value: '${session.pointCount}',
          color: Colors.green,
        ),
        _StatTile(
          icon: Icons.error_outline,
          label: 'Failed',
          value: '${session.failedCount}',
          color: Colors.grey,
        ),
        _StatTile(
          icon: Icons.percent,
          label: 'Success',
          value: '$successRate%',
          color: totalTx > 0 ? _getSuccessRateColor(session.pointCount / totalTx) : null,
        ),
        _StatTile(
          icon: Icons.timer,
          label: 'Duration',
          value: session.durationText,
        ),
        _StatTile(
          icon: Icons.straighten,
          label: 'Max Distance',
          value: formatDistance(session.maxDistance),
        ),
        _StatTile(
          icon: Icons.signal_cellular_alt,
          label: 'Avg RSSI',
          value: session.avgRssi != null ? '${session.avgRssi!.toStringAsFixed(1)} dBm' : '-',
          color: session.avgRssi != null ? getRssiColor(session.avgRssi!) : null,
        ),
        _StatTile(
          icon: Icons.arrow_downward,
          label: 'Min RSSI',
          value: session.minRssi != null ? '${session.minRssi!.toStringAsFixed(1)} dBm' : '-',
          color: session.minRssi != null ? getRssiColor(session.minRssi!) : null,
        ),
        _StatTile(
          icon: Icons.arrow_upward,
          label: 'Max RSSI',
          value: session.maxRssi != null ? '${session.maxRssi!.toStringAsFixed(1)} dBm' : '-',
          color: session.maxRssi != null ? getRssiColor(session.maxRssi!) : null,
        ),
        _StatTile(
          icon: Icons.show_chart,
          label: 'Avg SNR',
          value: session.avgSnr != null ? '${session.avgSnr!.toStringAsFixed(1)} dB' : '-',
        ),
        _StatTile(
          icon: Icons.settings_input_antenna,
          label: 'SF Range',
          value: session.sfRangeText,
        ),
        _StatTile(
          icon: Icons.swap_vert,
          label: 'ADR Changes',
          value: '${session.sfChangeCount}',
          color: session.sfChangeCount > 0 ? Colors.orange : null,
        ),
      ],
    );
  }

  Color _getSuccessRateColor(double rate) {
    if (rate >= 0.9) return Colors.green;
    if (rate >= 0.7) return Colors.orange;
    return Colors.red;
  }

  Widget _buildDetailsCard(Session session) {
    final dateFormat = DateFormat('MMM d, yyyy HH:mm:ss');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _DetailRow('Start Time', dateFormat.format(session.startTime)),
            if (session.endTime != null)
              _DetailRow('End Time', dateFormat.format(session.endTime!)),
            if (session.deviceEui != null) _DetailRow('Device EUI', session.deviceEui!),
            if (session.notes != null && session.notes!.isNotEmpty)
              _DetailRow('Notes', session.notes!),
          ],
        ),
      ),
    );
  }

  void _renameSession(Session session) async {
    final controller = TextEditingController(text: session.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Session'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Session Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && mounted) {
      await context.read<SessionService>().renameSession(session.id, newName);
      setState(() {
        _session = session.copyWith(name: newName);
      });
    }
  }

  void _showExportOptions() {
    bool exportFailed = _showFailed;
    bool exportGatewayLines = _showGatewayLines;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Export Session', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),

                // Export options
                Text('Include in export:', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: exportFailed,
                  onChanged: (v) => setModalState(() => exportFailed = v ?? true),
                  title: Text('Failed transmissions (${_failedTx.length})'),
                  subtitle: const Text('Gray markers for lost packets'),
                  secondary: const Icon(Icons.error_outline, color: Colors.grey),
                  dense: true,
                ),
                CheckboxListTile(
                  value: exportGatewayLines,
                  onChanged: (v) => setModalState(() => exportGatewayLines = v ?? false),
                  title: const Text('Gateway connection lines'),
                  subtitle: const Text('Lines from points to gateways'),
                  secondary: const Icon(Icons.cell_tower, color: Colors.purple),
                  dense: true,
                ),

                const Divider(),
                const SizedBox(height: 8),

                ListTile(
                  leading: const Icon(Icons.code),
                  title: const Text('GeoJSON'),
                  subtitle: const Text('For QGIS, web maps, and GIS software'),
                  onTap: () {
                    Navigator.pop(context);
                    _exportGeoJson(
                      includeFailedTx: exportFailed,
                      includeGatewayLines: exportGatewayLines,
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.public),
                  title: const Text('KML'),
                  subtitle: const Text('For Google Earth and Maps'),
                  onTap: () {
                    Navigator.pop(context);
                    _exportKml();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _exportGeoJson({
    bool includeFailedTx = true,
    bool includeGatewayLines = false,
  }) async {
    try {
      final sessionService = context.read<SessionService>();
      final geoJson = await sessionService.exportToGeoJson(
        widget.sessionId,
        includeFailedTx: includeFailedTx,
        includeGatewayLines: includeGatewayLines,
      );
      final filename = '${_session!.name.replaceAll(' ', '_')}.geojson';
      final filePath = await sessionService.saveExportFile(geoJson, filename);

      if (mounted) {
        await Share.shareXFiles(
          [XFile(filePath)],
          subject: 'LiLoRa Session: ${_session!.name}',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _exportKml() async {
    try {
      final sessionService = context.read<SessionService>();
      final kml = await sessionService.exportToKml(widget.sessionId);
      final filename = '${_session!.name.replaceAll(' ', '_')}.kml';
      final filePath = await sessionService.saveExportFile(kml, filename);

      if (mounted) {
        await Share.shareXFiles(
          [XFile(filePath)],
          subject: 'LiLoRa Session: ${_session!.name}',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  void _deleteSession(Session session) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Session?'),
        content: Text(
          'Are you sure you want to delete "${session.name}"? '
          'This will also delete all ${session.pointCount} range points.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      await context.read<SessionService>().deleteSession(session.id);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session deleted')),
        );
      }
    }
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

  void _showGatewayDetails(Map<String, dynamic> gateway) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final receptionCount = gateway['receptionCount'] as int? ?? 0;
        final avgRssi = gateway['avgRssi'] as double?;
        final avgSnr = gateway['avgSnr'] as double?;
        final minRssi = gateway['minRssi'] as double?;
        final maxRssi = gateway['maxRssi'] as double?;

        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.cell_tower, color: Colors.purple, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Gateway', style: theme.textTheme.titleLarge),
                        Text(
                          gateway['id'] as String? ?? 'Unknown',
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _infoRow('Receptions', '$receptionCount'),
              _infoRow('Avg RSSI', avgRssi != null ? '${avgRssi.toStringAsFixed(1)} dBm' : '-'),
              _infoRow('Avg SNR', avgSnr != null ? '${avgSnr.toStringAsFixed(1)} dB' : '-'),
              _infoRow('RSSI Range', minRssi != null && maxRssi != null
                  ? '${minRssi.toStringAsFixed(0)} to ${maxRssi.toStringAsFixed(0)} dBm'
                  : '-'),
              const Divider(),
              _infoRow('Latitude', (gateway['lat'] as double?)?.toStringAsFixed(6) ?? '-'),
              _infoRow('Longitude', (gateway['lon'] as double?)?.toStringAsFixed(6) ?? '-'),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
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
              _infoRow('Frame', '#${failed.frameCount}'),
              const Divider(),
              _infoRow('Latitude', failed.latitude.toStringAsFixed(6)),
              _infoRow('Longitude', failed.longitude.toStringAsFixed(6)),
              _infoRow('Sent at', failed.sentTime.toLocal().toString().split('.')[0]),
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
                  _infoRow('RSSI', formatRssi(point.rssi)),
                  _infoRow('SNR', formatSnr(point.snr)),
                  _infoRow('Distance', formatDistance(point.distance)),
                  _infoRow('Spreading Factor', formatSpreadingFactor(point.spreadingFactor)),
                  _infoRow('Frequency', formatFrequency(point.frequency)),
                  const Divider(),
                  _infoRow('Latitude', point.latitude.toStringAsFixed(6)),
                  _infoRow('Longitude', point.longitude.toStringAsFixed(6)),
                  _infoRow('Altitude', '${point.altitude} m'),
                  _infoRow('Satellites', '${point.satellites}'),
                  _infoRow('HDOP', point.hdop.toStringAsFixed(1)),
                  const Divider(),
                  _infoRow('Frame', '#${point.frameCount}'),
                  _infoRow('Device', point.deviceEui),
                  _infoRow('Time', point.timestamp.toLocal().toString().split('.')[0]),
                  // Multi-gateway info
                  if (point.gatewayCount != null && point.gatewayCount! > 0) ...[
                    const Divider(),
                    Row(
                      children: [
                        const Icon(Icons.cell_tower, size: 18, color: Colors.purple),
                        const SizedBox(width: 8),
                        Text(
                          'Gateways (${point.gatewayCount})',
                          style: theme.textTheme.titleSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (point.gateways != null)
                      ...point.gateways!.map((gw) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              gw.gatewayId,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                _gatewayMetric('RSSI', '${gw.rssi.toStringAsFixed(0)} dBm', getRssiColor(gw.rssi)),
                                const SizedBox(width: 16),
                                _gatewayMetric('SNR', '${gw.snr.toStringAsFixed(1)} dB', null),
                                if (gw.distance != null) ...[
                                  const SizedBox(width: 16),
                                  _gatewayMetric('Dist', formatDistance(gw.distance), null),
                                ],
                              ],
                            ),
                          ],
                        ),
                      )),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _gatewayMetric(String label, String value, Color? color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
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

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 100,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color ?? theme.colorScheme.primary),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}
