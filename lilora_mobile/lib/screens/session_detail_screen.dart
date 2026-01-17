import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/range_point.dart';
import '../models/session.dart';
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
  bool _isLoading = true;
  final MapController _mapController = MapController();

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

    setState(() {
      _session = session;
      _points = points;
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

                // Path line
                if (_points.length > 1)
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

                // Point markers
                MarkerLayer(
                  markers: _points
                      .where((p) => p.hasValidGps)
                      .map((point) => Marker(
                            point: LatLng(point.latitude, point.longitude),
                            width: 16,
                            height: 16,
                            child: Container(
                              decoration: BoxDecoration(
                                color: getRssiColor(point.rssi).withValues(alpha: 0.8),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1),
                              ),
                            ),
                          ))
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
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _StatTile(
          icon: Icons.pin_drop,
          label: 'Points',
          value: '${session.pointCount}',
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
      ],
    );
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
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Export Session', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.code),
                title: const Text('GeoJSON'),
                subtitle: const Text('For QGIS, web maps, and GIS software'),
                onTap: () {
                  Navigator.pop(context);
                  _exportGeoJson();
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
    );
  }

  Future<void> _exportGeoJson() async {
    try {
      final sessionService = context.read<SessionService>();
      final geoJson = await sessionService.exportToGeoJson(widget.sessionId);
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
