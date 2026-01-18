import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/range_point.dart';

/// WebSocket service for connecting to the LiLoRa backend.
/// Receives real-time range point data and broadcasts to listeners.
class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _keepaliveTimer;
  Timer? _reconnectTimer;

  // Connection state
  bool _isConnected = false;
  bool _isConnecting = false;
  String _statusMessage = 'Disconnected';
  int _reconnectAttempts = 0;
  int _activeConnections = 0;

  // Reconnection settings
  static const int _maxReconnectAttempts = 5;
  static const Duration _initialReconnectDelay = Duration(seconds: 2);
  static const Duration _keepaliveInterval = Duration(seconds: 30);

  // SharedPreferences key for URL persistence
  static const String _urlKey = 'websocket_server_url';

  // Data streams
  final _rangePointController = StreamController<RangePoint>.broadcast();
  RangePoint? _lastRangePoint;

  // Configuration
  String _serverUrl = 'ws://localhost:8000/ws';

  // Getters
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String get statusMessage => _statusMessage;
  int get activeConnections => _activeConnections;
  RangePoint? get lastRangePoint => _lastRangePoint;
  String get serverUrl => _serverUrl;

  /// Stream of incoming range points
  Stream<RangePoint> get rangePointStream => _rangePointController.stream;

  /// Load saved URL from SharedPreferences
  Future<void> loadSavedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString(_urlKey);
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _serverUrl = savedUrl;
      notifyListeners();
    }
  }

  /// Set the server URL (call before connect) and persist to storage
  Future<void> setServerUrl(String url) async {
    _serverUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, url);
    notifyListeners();
  }

  /// Connect to the WebSocket server
  Future<void> connect({String? url}) async {
    if (_isConnected || _isConnecting) return;

    final targetUrl = url ?? _serverUrl;
    _isConnecting = true;
    _statusMessage = 'Connecting to $targetUrl...';
    notifyListeners();

    try {
      _channel = WebSocketChannel.connect(Uri.parse(targetUrl));

      // Wait for connection to be ready
      await _channel!.ready;

      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _statusMessage = 'Connected';
      notifyListeners();

      // Start listening for messages
      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
        cancelOnError: false,
      );

      // Start keepalive timer
      _startKeepalive();
    } catch (e) {
      _isConnecting = false;
      _isConnected = false;
      _statusMessage = 'Connection failed: ${e.toString()}';
      notifyListeners();
      _scheduleReconnect();
    }
  }

  /// Disconnect from the WebSocket server
  Future<void> disconnect() async {
    _cancelTimers();
    _reconnectAttempts = _maxReconnectAttempts; // Prevent auto-reconnect

    await _subscription?.cancel();
    _subscription = null;

    await _channel?.sink.close();
    _channel = null;

    _isConnected = false;
    _isConnecting = false;
    _statusMessage = 'Disconnected';
    notifyListeners();
  }

  void _handleMessage(dynamic rawMessage) {
    try {
      final message = rawMessage.toString();

      // Try to parse as JSON
      final json = jsonDecode(message) as Map<String, dynamic>;

      // Check message type
      if (json.containsKey('type')) {
        final type = json['type'] as String;
        switch (type) {
          case 'connected':
            // Welcome message from server
            _activeConnections = json['active_connections'] as int? ?? 0;
            _statusMessage = 'Connected ($_activeConnections clients)';
            notifyListeners();
            break;
          case 'pong':
            // Keepalive response - connection is healthy
            break;
          default:
            // Unknown message type
            debugPrint('WebSocket: Unknown message type: $type');
        }
      } else if (json.containsKey('device_eui')) {
        // This is a RangePoint broadcast
        final point = RangePoint.fromJson(json);
        _lastRangePoint = point;
        _rangePointController.add(point);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('WebSocket: Failed to parse message: $e');
    }
  }

  void _handleError(dynamic error) {
    debugPrint('WebSocket error: $error');
    _statusMessage = 'Error: ${error.toString()}';
    _isConnected = false;
    notifyListeners();
    _scheduleReconnect();
  }

  void _handleDone() {
    debugPrint('WebSocket connection closed');
    _isConnected = false;
    _statusMessage = 'Disconnected';
    notifyListeners();

    // Only reconnect if we didn't manually disconnect
    if (_reconnectAttempts < _maxReconnectAttempts) {
      _scheduleReconnect();
    }
  }

  void _startKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Timer.periodic(_keepaliveInterval, (_) {
      if (_isConnected && _channel != null) {
        _channel!.sink.add('ping');
      }
    });
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _statusMessage = 'Reconnection failed after $_maxReconnectAttempts attempts';
      notifyListeners();
      return;
    }

    _cancelTimers();
    _reconnectAttempts++;

    // Exponential backoff
    final delay = _initialReconnectDelay * (1 << (_reconnectAttempts - 1));
    _statusMessage = 'Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts/$_maxReconnectAttempts)';
    notifyListeners();

    _reconnectTimer = Timer(delay, () {
      connect();
    });
  }

  void _cancelTimers() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  /// Reset reconnection attempts (call when user manually retries)
  void resetReconnection() {
    _reconnectAttempts = 0;
    _cancelTimers();
    connect();
  }

  @override
  void dispose() {
    _cancelTimers();
    _subscription?.cancel();
    _channel?.sink.close();
    _rangePointController.close();
    super.dispose();
  }
}
