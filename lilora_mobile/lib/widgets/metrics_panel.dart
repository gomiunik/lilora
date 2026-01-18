import 'package:flutter/material.dart';
import '../models/range_point.dart';
import '../utils/geo_utils.dart';

/// Panel displaying live metrics for the current range point.
/// Shows RSSI, SNR, distance, spreading factor, and other stats.
class MetricsPanel extends StatelessWidget {
  final RangePoint? currentPoint;
  final int totalPoints;
  final double? maxDistance;
  final bool isRecording;
  final VoidCallback? onRecordTap;

  const MetricsPanel({
    super.key,
    this.currentPoint,
    this.totalPoints = 0,
    this.maxDistance,
    this.isRecording = false,
    this.onRecordTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final point = currentPoint;

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Main metrics row
            Row(
              children: [
                // RSSI
                Expanded(
                  child: _MetricTile(
                    label: 'RSSI',
                    value: point != null ? formatRssi(point.rssi) : '-',
                    color: point != null ? getRssiColor(point.rssi) : null,
                    icon: point != null ? getSignalIcon(point.rssi) : Icons.signal_cellular_off,
                  ),
                ),
                const SizedBox(width: 8),
                // SNR
                Expanded(
                  child: _MetricTile(
                    label: 'SNR',
                    value: point != null ? formatSnr(point.snr) : '-',
                    icon: Icons.show_chart,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Secondary metrics row
            Row(
              children: [
                // Distance
                Expanded(
                  child: _MetricTile(
                    label: 'Distance',
                    value: formatDistance(point?.distance),
                    icon: Icons.straighten,
                  ),
                ),
                const SizedBox(width: 8),
                // Spreading Factor
                Expanded(
                  child: _MetricTile(
                    label: 'SF',
                    value: point != null ? 'SF${point.spreadingFactor}' : '-',
                    icon: Icons.waves,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            // Session stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Total points
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.pin_drop, size: 16),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '$totalPoints points',
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Max distance
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.trending_up, size: 16),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Max: ${formatDistance(maxDistance)}',
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Record button
                FilledButton.tonalIcon(
                  onPressed: onRecordTap,
                  icon: Icon(isRecording ? Icons.stop : Icons.fiber_manual_record),
                  label: Text(isRecording ? 'Stop' : 'Record'),
                  style: FilledButton.styleFrom(
                    backgroundColor: isRecording ? Colors.red.withValues(alpha: 0.2) : null,
                    foregroundColor: isRecording ? Colors.red : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Individual metric tile with icon, label, and value.
class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact version of the metrics panel for overlay display.
class CompactMetricsPanel extends StatelessWidget {
  final RangePoint? currentPoint;

  const CompactMetricsPanel({super.key, this.currentPoint});

  @override
  Widget build(BuildContext context) {
    final point = currentPoint;
    if (point == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              getSignalIcon(point.rssi),
              color: getRssiColor(point.rssi),
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              formatRssi(point.rssi),
              style: TextStyle(
                color: getRssiColor(point.rssi),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 16),
            const Icon(Icons.straighten, size: 16),
            const SizedBox(width: 4),
            Text(formatDistance(point.distance)),
          ],
        ),
      ),
    );
  }
}
