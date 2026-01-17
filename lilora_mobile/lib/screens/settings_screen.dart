import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';

/// Settings screen for configuring backend connection and app preferences.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _urlController;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    final wsService = context.read<WebSocketService>();
    _urlController = TextEditingController(text: wsService.serverUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // Backend Configuration Section
          _SectionHeader(title: 'Backend Configuration'),
          Consumer<WebSocketService>(
            builder: (context, wsService, _) {
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Connection status
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: wsService.isConnected
                                  ? Colors.green
                                  : wsService.isConnecting
                                      ? Colors.orange
                                      : Colors.red,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            wsService.isConnected
                                ? 'Connected'
                                : wsService.isConnecting
                                    ? 'Connecting...'
                                    : 'Disconnected',
                            style: theme.textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        wsService.statusMessage,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // WebSocket URL input
                      TextField(
                        controller: _urlController,
                        decoration: InputDecoration(
                          labelText: 'WebSocket URL',
                          hintText: 'ws://192.168.1.100:8000/ws',
                          border: const OutlineInputBorder(),
                          suffixIcon: _isEditing
                              ? IconButton(
                                  icon: const Icon(Icons.check),
                                  onPressed: _saveUrl,
                                )
                              : null,
                        ),
                        onChanged: (_) {
                          setState(() => _isEditing = true);
                        },
                        onSubmitted: (_) => _saveUrl(),
                      ),
                      const SizedBox(height: 16),

                      // Connection buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: wsService.isConnected
                                  ? () => wsService.disconnect()
                                  : null,
                              icon: const Icon(Icons.link_off),
                              label: const Text('Disconnect'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: wsService.isConnected || wsService.isConnecting
                                  ? null
                                  : () => wsService.connect(),
                              icon: const Icon(Icons.link),
                              label: const Text('Connect'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // About Section
          _SectionHeader(title: 'About'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.cell_tower,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LiLoRa GPS',
                            style: theme.textTheme.titleLarge,
                          ),
                          Text(
                            'Version 1.0.0',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'LoRaWAN Range Tracking System',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Track and visualize LoRaWAN signal coverage using a '
                    'LilyGo T-Watch S3 wearable device. Stream GPS coordinates '
                    'via Bluetooth LE and view real-time range data on the map.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Help Section
          _SectionHeader(title: 'Help'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.bluetooth),
                  title: const Text('Connect Tab'),
                  subtitle: const Text('Connect to T-Watch and stream GPS'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.map),
                  title: const Text('Map Tab'),
                  subtitle: const Text('View real-time range visualization'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Sessions Tab'),
                  subtitle: const Text('View and export recorded sessions'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _saveUrl() {
    final wsService = context.read<WebSocketService>();
    final newUrl = _urlController.text.trim();

    if (newUrl.isNotEmpty) {
      wsService.setServerUrl(newUrl);

      setState(() => _isEditing = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL saved. Tap Connect to use new URL.')),
      );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
