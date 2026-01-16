# LiLoRa Project Plan - Detailed Implementation Guide

## Executive Summary

**Project**: LiLoRa - LoRaWAN Range Tracking System
**Goal**: Create a complete solution for mapping LoRaWAN coverage using wearable hardware and mobile visualization
**Timeline**: 5 development phases (detailed below)
**Architecture**: Multi-repo (firmware, mobile, backend) with ChirpStack/TTN integration

## Phase 1: Firmware Foundation (lilora-firmware)

**Objective**: Establish stable LoRaWAN communication with network server

**Status**: 🟢 **COMPLETE - TESTED**
- All firmware code written, compiles, and uploads successfully
- Hardware upload issues resolved
- LoRaWAN join and uplink working
- **Remaining**: LoRaWAN GPS payload verification on network server

### Tasks

#### 1.1 Project Setup
- [x] Create `lilora-firmware` directory
- [x] Initialize PlatformIO project: `pio init --board lilygo-t-watch-s3`
- [x] Configure `platformio.ini` with dependencies:
  - ~~LilyGoLib~~ (removed due to version conflicts with ESP32 core)
  - RadioLib v6.6.0+
  - ESP32 Arduino framework
- [x] Set monitor speed to 115200 baud
- [x] Add `.gitignore` for PlatformIO artifacts

#### 1.2 Hardware Initialization
- [x] Create `src/hardware.cpp` and `src/hardware.h`
- [x] Initialize T-Watch S3 peripherals:
  - SPI for SX1262 radio (SCK, MISO, MOSI pins) - **Config 2 pins work**: SCLK=18, MISO=19, MOSI=23
  - GPIO for radio control (NSS=5, DIO1=26, BUSY=32, RST=14)
  - Display for status messages (deferred to Phase 2)
  - Touch for user input (deferred to Phase 2)
- [x] Test hardware init with LED blink or display message (serial output confirms init)

#### 1.3 LoRaWAN Configuration
- [x] Create `src/lorawan_config.h` (add to `.gitignore`)
- [x] Create `src/lorawan_config.cpp` (definitions - also in `.gitignore`)
- [x] Define OTAA credentials structure:
  ```cpp
  #define LORAWAN_REGION EU868  // 868MHz for this device
  extern uint8_t devEUI[8];   // MSB format
  extern uint8_t appEUI[8];   // MSB format
  extern uint8_t appKey[16];  // MSB format
  ```
- [x] Create `src/lorawan_config.h.template` and `.cpp.template` for version control
- [x] Document key format (MSB vs LSB) in comments
- [x] Configure actual credentials for T-Watch S3 868MHz device

#### 1.4 LoRaWAN Join Implementation
- [x] Create `src/lorawan.cpp` and `src/lorawan.h`
- [x] Implement state machine:
  - `LORAWAN_IDLE`, `LORAWAN_JOINING`, `LORAWAN_JOINED`, `LORAWAN_UPLINK`, `LORAWAN_DOWNLINK`, `LORAWAN_ERROR`
- [x] Initialize RadioLib `LoRaWANNode` object with SX1262 pins
- [x] Implement `joinNetwork()` function:
  - Set regional parameters (EU868, data rate, power)
  - Attempt OTAA join with timeout (30 seconds)
  - Fixed RadioLib 6.6.0 API: `beginOTAA()` + `activateOTAA()`
- [x] Add retry logic (max 3 attempts with exponential backoff)
- [x] Display join status on serial monitor (screen deferred to Phase 2)
- [x] Fixed API compatibility issues (uint64_t conversion for DevEUI/AppEUI)

#### 1.5 Session Persistence
- [x] Create `src/storage.cpp` and `src/storage.h`
- [x] Implement NVS (Non-Volatile Storage) functions:
  - `saveSession()` - Store DevNonces, session keys, FCntUp
  - `loadSession()` - Restore session on boot
  - `clearSession()` - Force rejoin (useful for debugging)
- [x] Implement session restore logic in `setup()`:
  - Check if valid session exists in NVS
  - If yes, call `node.restore()` (placeholder - RadioLib version-dependent)
  - If no, proceed with OTAA join
- [ ] Test session persistence: Upload firmware → join → power cycle → verify no rejoin (**BLOCKED: Upload issues**)

#### 1.6 Uplink Transmission
- [x] Implement `sendUplink()` function in `src/lorawan.cpp`:
  - Generate dummy 3-byte payload (random sensor values: temp, humidity, battery)
  - Set frame port (port 1 for sensor data)
  - Call `node.sendReceive()` with confirmed/unconfirmed flag (RadioLib 6.6.0 API)
  - Handle acknowledgments and downlink reception in same call
- [x] Implement transmission interval (60 seconds for testing, configurable)
- [x] Add duty cycle compliance check (RadioLib handles this automatically)
- [x] Log uplink status: Payload hex, RSSI, SNR

#### 1.7 Downlink Reception
- [x] Implement downlink handling in main loop:
  - Automatic reception in RX windows via `sendReceive()` (RadioLib 6.6.0)
  - Parse received payload and frame port
  - Log downlink data to serial monitor (hex payload, port, length)
- [ ] (Optional) Implement command handling:
  - Port 1: Configuration update (TX power, SF) - **Deferred to Phase 2**
  - Port 2: LED pattern or display message - **Deferred to Phase 2**
- [ ] Test downlink from network server console (**BLOCKED: Needs successful join first**)

#### 1.8 Testing and Validation
- [ ] **Join Test**: Verify successful OTAA join within 30 seconds (**PENDING: Upload and ChirpStack config**)
- [ ] **Session Restore Test**: Power cycle device 5 times, confirm only 1 join (**PENDING**)
- [ ] **Uplink Test**: Send 10 uplinks, verify all appear on network server (**PENDING**)
- [ ] **Downlink Test**: Queue downlink from server, verify reception on device (**PENDING**)
- [ ] **Duty Cycle Test**: Send rapid uplinks, verify RadioLib enforces fair use policy (**PENDING**)
- [ ] **Range Test**: Walk 100m from gateway, confirm uplinks still succeed (**PENDING**)

### Deliverables
- ✅ Working LoRaWAN firmware with OTAA join (code complete)
- ✅ Session persistence in NVS (code complete)
- ✅ Uplink transmission with dummy payload (code complete)
- ✅ Downlink reception and logging (code complete)
- ✅ Serial monitor debug output (code complete)
- ✅ Build succeeds, upload succeeds
- ⏸️ **Testing blocked by**: Upload issues and ChirpStack configuration (needs LoRaWAN 1.0.4)

### Success Criteria
- [ ] Device joins network within 30 seconds (**PENDING: Awaiting upload fix**)
- [ ] Session survives power cycle (no rejoin) (**PENDING**)
- [ ] Uplink success rate >95% within 100m of gateway (**PENDING**)
- [ ] Firmware runs for 1 hour without crash (**PENDING**)

### Implementation Notes & Lessons Learned

#### Hardware Configuration (T-Watch S3 868MHz)
- **Device Model**: T-Watch-2020 (printed on back), T-Watch-S3 868MHz with SX1262 LoRa
- **Correct Pin Configuration** (Configuration 2):
  - RADIO_SCLK_PIN = 18
  - RADIO_MISO_PIN = 19
  - RADIO_MOSI_PIN = 23
  - RADIO_CS_PIN = 5
  - RADIO_RST_PIN = 14
  - RADIO_DIO1_PIN = 26
  - RADIO_BUSY_PIN = 32
- **Note**: Pin configurations vary by T-Watch variant - see `hardware.h` for alternatives

#### RadioLib 6.6.0 API Compatibility
- **Issue**: API differs from older examples in LilyGoLib
- **Solutions Implemented**:
  - Convert DevEUI/AppEUI byte arrays to `uint64_t` using `bytesToUint64()` helper
  - Use `node.beginOTAA(appEUI_u64, devEUI_u64, appKey, appKey)` for LoRaWAN 1.0.x
  - Call `node.activateOTAA()` to perform join (returns `RADIOLIB_LORAWAN_NEW_SESSION` on success)
  - Use `node.sendReceive(payload, length, port, downlinkBuf, &downlinkSize, confirmed)` for uplink+downlink
  - Downlinks are automatically received in RX windows (no separate `receiveDownlink()` call needed)

#### Dependency Management
- **LilyGoLib Removed**: Requires ESP32 Arduino Core 3.3.0+, but PlatformIO provides 3.0.17
- **Solution**: Created custom `hardware.h/cpp` with direct SPI and pin initialization
- **Only Dependency**: RadioLib 6.6.0 (no other libraries needed for Phase 1)

#### LoRaWAN Configuration Requirements
- **ChirpStack Settings**:
  - LoRaWAN MAC version: **1.0.4** (NOT 1.1.x - firmware expects single AppKey)
  - Regional Parameters: **RP002-1.0.4**
  - Device Profile: Class A, OTAA
  - **Development Only**: Enable "Resets DevNonces" and "Resets frame counters"
- **Credentials**: Must be MSB (Most Significant Byte first) format
- **Keys Split**: Moved from header definitions to separate `.cpp` file to fix linker errors

#### Upload Troubleshooting
- **ESP32-S3 Bootloader**: Requires manual entry on some boards
- **Methods Tried**:
  1. Hold BOOT (side crown) during "Connecting..." message
  2. Power cycle while holding BOOT
  3. Different USB cables/ports (USB 2.0 preferred)
- **RESET Button**: May not exist on all T-Watch-2020/S3 variants - use power cycle instead

#### Documentation Created
- `README.md` - Setup and build instructions
- `CHANGELOG.md` - API fixes and version history
- `TROUBLESHOOTING.md` - Comprehensive problem-solving guide
- `build.bat` / `upload.bat` - Windows helper scripts
- Template files for credentials (`lorawan_config.h.template`, `.cpp.template`)

---

## Phase 2: Bluetooth GPS Integration

**Objective**: Stream GPS coordinates from mobile phone to T-Watch via BLE

**Status**: 🟢 **CODE COMPLETE - INTEGRATION TESTING PENDING**
- All firmware BLE/NMEA/encoder code written
- All mobile app code written and compiles successfully
- **Next Steps**: Hardware integration testing with T-Watch and mobile device

### Tasks

#### 2.1 Firmware - BLE Server Setup
- [x] Create `bluetooth.h` (Arduino IDE style - header only)
- [x] Define BLE Service and Characteristic UUIDs:
  ```cpp
  #define NUS_SERVICE_UUID "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
  #define NUS_CHAR_RX_UUID "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
  #define NUS_CHAR_TX_UUID "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
  ```
  (Using Nordic UART Service UUIDs for compatibility)
- [x] Implement BLE server initialization:
  - Create BLE device with name "LiLoRa-XXXX" (XXXX = last 4 digits of MAC)
  - Create service and characteristic with WRITE property
  - Add characteristic callbacks for NMEA data reception
- [x] Implement `onWrite()` callback:
  - Receive NMEA sentence string from mobile app
  - Append to circular buffer (handle multi-packet sentences)
  - Trigger parsing when newline detected

#### 2.2 Firmware - NMEA Parser
- [x] Create `nmea_parser.h` (Arduino IDE style - header only)
- [x] Implement NMEA sentence parser:
  - Support GGA (position fix) and RMC (recommended minimum) sentences
  - Extract: latitude, longitude, fix quality, altitude, HDOP, satellite count
  - Validate checksum before parsing
- [x] Create GPS data structure:
  ```cpp
  struct GPSData {
      double latitude;
      double longitude;
      uint8_t fixQuality;  // 0=no fix, 1=GPS, 2=DGPS
      int16_t altitude;
      float hdop;
      uint8_t satellites;
      uint32_t timestamp;  // millis() when received
      bool valid;
  };
  ```
- [x] Handle edge cases: missing fields, invalid checksums, old data (>10 seconds)

#### 2.3 Firmware - Payload Encoding
- [x] Create `payload_encoder.h` (Arduino IDE style - header only)
- [x] Implement binary encoder for GPS data:
  ```cpp
  // 13-byte payload format:
  // Byte 0-3:  Latitude (int32, scaled by 1e7)
  // Byte 4-7:  Longitude (int32, scaled by 1e7)
  // Byte 8:    Fix quality
  // Byte 9-10: Altitude (int16, meters)
  // Byte 11:   HDOP (scaled by 10)
  // Byte 12:   Satellite count
  ```
- [x] Use big-endian byte order for cross-platform compatibility
- [x] Replace dummy payload in `doSendUplink()` with encoded GPS data

#### 2.4 Mobile App - Project Setup
- [x] Create `lilora_mobile` directory
- [x] Initialize Flutter project: `flutter create lilora_mobile`
- [x] Add dependencies to `pubspec.yaml`:
  - `flutter_blue_plus: ^1.32.0` (BLE)
  - `geolocator: ^13.0.0` (GPS)
  - `permission_handler: ^11.3.0` (permissions)
  - `provider: ^6.1.0` (state management)
- [x] Configure Android permissions in `android/app/src/main/AndroidManifest.xml`:
  - `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`
  - `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` (Android 12+)
- [x] Configure iOS permissions in `ios/Runner/Info.plist`:
  - `NSLocationWhenInUseUsageDescription`
  - `NSBluetoothAlwaysUsageDescription`

#### 2.5 Mobile App - Permission Handling
- [x] Create `lib/services/permission_service.dart`
- [x] Implement permission request flow:
  - Location permission (when in use)
  - Bluetooth permission (Android 12+)
  - Handle denied, permanently denied, and granted states
- [x] Show user-friendly UI with permission status indicators
- [x] Add settings deeplink for permanently denied permissions

#### 2.6 Mobile App - GPS Service
- [x] Create `lib/services/gps_service.dart`
- [x] Implement GPS stream:
  - Use `geolocator.getPositionStream()` with 1-meter distance filter
  - Set accuracy to `LocationAccuracy.high`
  - Handle location service disabled state
- [x] Create NMEA formatter (`lib/utils/nmea_formatter.dart`):
  - Generate GGA sentence from `Position` object
  - Calculate checksum (XOR of all bytes between $ and *)
  - Format: `$GPGGA,hhmmss.ss,lat,N/S,lon,E/W,fix,sats,hdop,alt,M,...*checksum`
- [ ] Test NMEA generation: Print to console and validate with online parser (**PENDING: Device testing**)

#### 2.7 Mobile App - Bluetooth Service
- [x] Create `lib/services/bluetooth_service.dart`
- [x] Implement BLE scanner:
  - Scan for devices with name starting with "LiLoRa"
  - Display list of found devices in UI
  - Handle scan timeout (15 seconds)
- [x] Implement connection manager:
  - Connect to selected device
  - Discover services and characteristics
  - Find Nordic UART Service characteristic
  - Monitor connection state (connected, disconnected)
- [x] Implement NMEA sender:
  - Write NMEA sentences to characteristic
  - Auto-forwarding every 1 second when enabled

#### 2.8 Mobile App - UI Implementation
- [x] Create `lib/screens/home_screen.dart`
- [x] Implement home screen layout:
  - Permission status indicators (GPS, Bluetooth)
  - BLE scan button and device list
  - Connection status indicator
  - GPS forwarding toggle switch
  - Current GPS coordinates display
  - NMEA sentence preview (last sent)
- [x] Add connection state management (Provider)
- [x] Implement error handling and user feedback (SnackBars)

#### 2.9 Integration Testing
- [ ] **BLE Connection Test**: Scan for T-Watch, verify device appears in list (**PENDING: Hardware**)
- [ ] **NMEA Transmission Test**: Connect and send sentences, view firmware serial output (**PENDING**)
- [ ] **GPS Parsing Test**: Mock GPS coordinates, verify firmware decodes correctly (**PENDING**)
- [ ] **LoRaWAN Uplink Test**: Check ChirpStack/TTN for GPS data in hex payload (**PENDING**)
- [ ] **End-to-End Test**: Walk outdoors, verify GPS updates on network server (**PENDING**)

### Deliverables
- ✅ Firmware with BLE NMEA server (`bluetooth.h`)
- ✅ NMEA parser (`nmea_parser.h`) and GPS data encoder (`payload_encoder.h`)
- ✅ Flutter app with BLE scanner and GPS forwarding
- ✅ NMEA generator from device location (`nmea_formatter.dart`)
- ✅ Documentation updated (README files for both firmware and mobile app)

### Success Criteria
- Mobile app connects to T-Watch within 10 seconds
- GPS coordinates update every 1 second
- Firmware receives and parses NMEA correctly (>99% success rate)
- LoRaWAN uplink contains valid GPS data (visible on network server)

---

## Phase 3: Backend Service (lilora-backend)

**Objective**: Receive LoRaWAN uplinks via webhook and broadcast to clients

**Status**: 🟢 **CODE COMPLETE - TESTING PENDING**
- All backend code written and tests pass (19/19)
- FastAPI with ChirpStack/TTN webhook endpoints
- WebSocket broadcasting for real-time data
- **Next Steps**: Deploy to cloud, configure network server webhooks

### Tasks

#### 3.1 Project Setup
- [x] Create `lilora-backend` directory
- [x] Initialize Python project (using uv):
  ```bash
  mkdir lilora-backend && cd lilora-backend
  python -m venv venv
  source venv/bin/activate  # Windows: venv\Scripts\activate
  ```
- [x] Create `pyproject.toml` and `requirements.txt`:
  ```
  fastapi>=0.115.0
  uvicorn[standard]>=0.27.0
  pydantic>=2.5.0
  pydantic-settings>=2.0.0
  python-dotenv>=1.0.0
  ```
- [x] Create `.env.example` for configuration (API keys)
- [x] Create `.gitignore` (exclude `.venv/`, `.env`, `__pycache__/`)

#### 3.2 FastAPI Application Structure
- [x] Create `main.py` with FastAPI app initialization
- [x] Add CORS middleware for web client access
- [x] Create directory structure:
  ```
  lilora-backend/
  ├── main.py
  ├── models/
  │   ├── __init__.py
  │   ├── uplink.py        # ChirpStack/TTN schemas
  │   └── range_point.py   # Decoded data model
  ├── services/
  │   ├── __init__.py
  │   ├── decoder.py       # Payload decoder
  │   └── websocket_manager.py
  └── routers/
      ├── __init__.py
      ├── webhook.py       # Webhook endpoints
      └── websocket.py     # WebSocket endpoint
  ```

#### 3.3 Data Models
- [x] Create `models/uplink.py` with Pydantic models:
  - `ChirpStackUplink` - Schema for ChirpStack webhook JSON
  - `TTNUplink` - Schema for TTN v3 webhook JSON
  - Extract common fields: DevEUI, FCnt, payload (hex), metadata (RSSI, SNR, frequency, data rate)
- [x] Create `models/range_point.py`:
  ```python
  class RangePoint(BaseModel):
      timestamp: datetime
      device_eui: str
      frame_count: int
      latitude: float
      longitude: float
      altitude: int
      fix_quality: int
      hdop: float
      satellites: int
      rssi: float
      snr: float
      spreading_factor: int
      frequency: float
      gateway_lat: Optional[float]
      gateway_lon: Optional[float]
      distance: Optional[float]  # meters from gateway
  ```

#### 3.4 Payload Decoder
- [x] Create `services/decoder.py`
- [x] Implement `decode_payload(hex_string: str) -> GPSData`:
  ```python
  def decode_payload(hex_payload: str) -> dict:
      data = bytes.fromhex(hex_payload)
      lat, lon, fix, alt, hdop, sats = struct.unpack('>iiBhBB', data)
      return {
          "latitude": lat / 1e7,
          "longitude": lon / 1e7,
          "fix_quality": fix,
          "altitude": alt,
          "hdop": hdop / 10.0,
          "satellites": sats
      }
  ```
- [x] Add error handling for malformed payloads
- [x] Add unit tests for decoder (pytest)

#### 3.5 WebSocket Manager
- [x] Create `services/websocket_manager.py`
- [x] Implement connection manager:
  ```python
  class WebSocketManager:
      def __init__(self):
          self.active_connections: List[WebSocket] = []

      async def connect(self, websocket: WebSocket):
          await websocket.accept()
          self.active_connections.append(websocket)

      def disconnect(self, websocket: WebSocket):
          self.active_connections.remove(websocket)

      async def broadcast(self, message: dict):
          for connection in self.active_connections:
              await connection.send_json(message)
  ```
- [x] Handle disconnections gracefully (remove from list)
- [x] Add ping/pong mechanism for keepalive

#### 3.6 Webhook Endpoints
- [x] Create `routers/webhook.py`
- [x] Implement ChirpStack webhook handler:
  ```python
  @router.post("/webhook/chirpstack")
  async def chirpstack_webhook(uplink: ChirpStackUplink):
      # Extract metadata
      # Decode payload
      # Create RangePoint
      # Broadcast to WebSocket clients
      return {"status": "ok"}
  ```
- [x] Implement TTN webhook handler (similar structure)
- [x] Add authentication (API key in header - optional)
- [x] Log all received uplinks (timestamp, DevEUI, RSSI)

#### 3.7 WebSocket Endpoint
- [x] Create `routers/websocket.py`
- [x] Implement WebSocket route:
  ```python
  @router.websocket("/ws")
  async def websocket_endpoint(websocket: WebSocket):
      await manager.connect(websocket)
      try:
          while True:
              # Keep connection alive
              data = await websocket.receive_text()
              # Echo or handle client messages if needed
      except WebSocketDisconnect:
          manager.disconnect(websocket)
  ```
- [ ] Test with WebSocket client (browser console or `websocat` tool) (**PENDING: Deployment**)

#### 3.8 Distance Calculation
- [x] Implement Haversine formula in `services/decoder.py`:
  ```python
  def calculate_distance(lat1, lon1, lat2, lon2) -> float:
      # Returns distance in meters
      R = 6371000  # Earth radius in meters
      # Haversine formula implementation
      return distance
  ```
- [x] Extract gateway location from uplink metadata
- [x] Add distance field to `RangePoint` before broadcasting

#### 3.9 Testing and Deployment
- [x] Write unit tests for decoder (`tests/test_decoder.py`)
- [x] Write integration tests for webhook endpoints (`tests/test_webhook.py`)
- [x] Create `Dockerfile`:
  ```dockerfile
  # Option 1: Using uv (faster builds)
  FROM python:3.11-slim
  WORKDIR /app
  RUN pip install uv
  COPY pyproject.toml .
  RUN uv sync --frozen
  COPY . .
  CMD ["uv", "run", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]

  # Option 2: Using pip (traditional)
  FROM python:3.11-slim
  WORKDIR /app
  COPY requirements.txt .
  RUN pip install --no-cache-dir -r requirements.txt
  COPY . .
  CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
  ```
- [x] Test locally: `uv run uvicorn main:app --reload --host 0.0.0.0 --port 8000`
- [ ] Deploy to cloud (Railway, Fly.io, or VPS) (**PENDING**)
- [ ] Configure webhook in ChirpStack/TTN to deployed URL (**PENDING**)

### Deliverables
- ✅ FastAPI backend with webhook and WebSocket endpoints
- ✅ Payload decoder (binary to GPS coordinates)
- ✅ WebSocket broadcast manager
- ✅ Docker container for deployment

### Success Criteria
- Webhook receives uplinks from network server within 1 second
- Payload decoding success rate >99%
- WebSocket broadcasts to all connected clients (<100ms latency)
- Backend handles 10+ concurrent WebSocket connections
- Service runs for 24 hours without crash

---

## Phase 4: Mobile Visualization (lilora-mobile)

**Objective**: Display real-time coverage map with signal quality metrics

### Tasks

#### 4.1 Map Integration
- [ ] Add map dependency to `pubspec.yaml`:
  - Option A: `flutter_map: ^6.0.0` (open-source, no API key)
  - Option B: `google_maps_flutter: ^2.5.0` (requires Google Maps API key)
- [ ] Create `lib/screens/map_screen.dart`
- [ ] Initialize map widget with user's current location as center
- [ ] Add zoom controls and follow-user toggle
- [ ] Implement map layers: base map, markers, polyline path

#### 4.2 WebSocket Client
- [ ] Add `web_socket_channel: ^2.4.0` to dependencies
- [ ] Create `lib/services/websocket_service.dart`
- [ ] Implement WebSocket connection:
  ```dart
  class WebSocketService {
    WebSocketChannel? _channel;
    final _controller = StreamController<RangePoint>.broadcast();

    void connect(String url) {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _channel!.stream.listen((message) {
        final rangePoint = RangePoint.fromJson(jsonDecode(message));
        _controller.add(rangePoint);
      });
    }
  }
  ```
- [ ] Add reconnection logic (exponential backoff)
- [ ] Handle connection errors and timeouts

#### 4.3 Range Point Visualization
- [ ] Create `lib/models/range_point.dart` matching backend schema
- [ ] Implement color gradient for signal quality:
  - Green: RSSI > -100 dBm (excellent)
  - Yellow: RSSI -100 to -110 dBm (good)
  - Orange: RSSI -110 to -120 dBm (fair)
  - Red: RSSI < -120 dBm (poor)
- [ ] Add markers to map for each received range point:
  - Circular marker with color based on RSSI
  - Size based on SNR (larger = better)
  - Tap to show details popup (RSSI, SNR, SF, timestamp)
- [ ] Draw polyline connecting sequential points (path visualization)

#### 4.4 Live Metrics Dashboard
- [ ] Create `lib/widgets/metrics_overlay.dart`
- [ ] Display live metrics on top of map:
  - Current RSSI/SNR (large, prominent display)
  - Spreading factor and frequency
  - Distance from gateway
  - Packet loss rate (missed uplinks)
  - Max distance achieved in session
  - Total points recorded
- [ ] Update metrics in real-time as new data arrives
- [ ] Add animation for metric changes (number counter)

#### 4.5 Session Management
- [ ] Add local database dependency:
  - Option A: `hive: ^2.2.3` (NoSQL, fast)
  - Option B: `sqflite: ^2.3.0` (SQL, more structured)
- [ ] Create `lib/database/session_db.dart`
- [ ] Implement session model:
  ```dart
  class Session {
    String id;
    DateTime startTime;
    DateTime? endTime;
    List<RangePoint> points;
    double maxDistance;
    int totalPoints;
    double avgRssi;
  }
  ```
- [ ] Add start/stop session buttons on map screen
- [ ] Save range points to database as they arrive
- [ ] Calculate session statistics (max distance, avg RSSI, coverage area)

#### 4.6 Session List Screen
- [ ] Create `lib/screens/session_list_screen.dart`
- [ ] Display list of past sessions:
  - Start time and duration
  - Total points and max distance
  - Average RSSI/SNR
  - Thumbnail map preview (optional)
- [ ] Add search/filter by date
- [ ] Implement session deletion (with confirmation)
- [ ] Tap session to view details on map screen

#### 4.7 Export Functionality
- [ ] Implement GeoJSON exporter:
  ```dart
  String exportToGeoJSON(Session session) {
    return jsonEncode({
      "type": "FeatureCollection",
      "features": session.points.map((p) => {
        "type": "Feature",
        "geometry": {"type": "Point", "coordinates": [p.longitude, p.latitude]},
        "properties": {"rssi": p.rssi, "snr": p.snr, "timestamp": p.timestamp}
      }).toList()
    });
  }
  ```
- [ ] Implement KML exporter (for Google Earth)
- [ ] Add export button on session details screen
- [ ] Use `share_plus` package to share exported file
- [ ] Test import in QGIS and Google Earth

#### 4.8 UI Polish
- [ ] Add app icon and splash screen
- [ ] Implement dark mode support
- [ ] Add loading indicators and error messages
- [ ] Implement navigation drawer or bottom nav bar
- [ ] Add settings screen:
  - Backend WebSocket URL configuration
  - Map style selection
  - Units (meters/feet, dBm)
  - Auto-connect preferences
- [ ] Add tutorial/onboarding flow for first-time users

#### 4.9 Integration Testing
- [ ] **Map Display Test**: Verify map loads and centers on user location
- [ ] **WebSocket Test**: Connect to backend, verify range points appear
- [ ] **Marker Test**: Walk outdoors, verify markers added in real-time
- [ ] **Session Test**: Start session, record 50 points, stop and save
- [ ] **Export Test**: Export session as GeoJSON, open in QGIS

### Deliverables
- ✅ Flutter app with real-time map visualization
- ✅ WebSocket client for backend connection
- ✅ Session recording and management
- ✅ GeoJSON/KML export functionality

### Success Criteria
- Map updates in real-time (<1 second latency)
- App handles 1000+ range points per session without lag
- Sessions persist across app restarts
- Export files open correctly in QGIS and Google Earth
- App runs for 2+ hours without crash

---

## Phase 5: Enhancements (Optional)

**Objective**: Add advanced features for power users and production deployment

### Tasks

#### 5.1 Adaptive Data Rate (ADR) Monitoring
- [ ] Track spreading factor changes over time
- [ ] Display SF history chart on map (line graph)
- [ ] Add notification when ADR adjusts (network optimization)
- [ ] Log ADR events to session for later analysis

#### 5.2 Multi-Gateway Support
- [ ] Parse multiple gateway metadata from uplink
- [ ] Display multiple gateway locations on map
- [ ] Show signal quality from each gateway (heatmap)
- [ ] Calculate best server selection accuracy

#### 5.3 Offline Mode
- [ ] Queue LoRaWAN uplinks when network unavailable
- [ ] Store uplinks in firmware NVS (limited capacity)
- [ ] Sync queued uplinks when network restored
- [ ] Display offline indicator on T-Watch screen

#### 5.4 Firmware OTA Updates
- [ ] Implement OTA update via BLE from mobile app
- [ ] Add firmware version display in app
- [ ] Create update package builder script
- [ ] Test OTA with sample firmware update

#### 5.5 Advanced Analytics
- [ ] Generate coverage heatmap from historical data
- [ ] Implement path loss prediction model
- [ ] Export Fresnel zone visualization
- [ ] Calculate Packet Delivery Ratio (PDR) per area

#### 5.6 Community Features
- [ ] Add user authentication (Firebase or Auth0)
- [ ] Implement session sharing (upload to cloud)
- [ ] Create community coverage map (aggregate data)
- [ ] Add leaderboard (max distance, most sessions)

#### 5.7 Production Hardening
- [ ] Add backend rate limiting and authentication
- [ ] Implement database for historical data storage (PostgreSQL)
- [ ] Set up monitoring and alerting (Prometheus, Grafana)
- [ ] Create CI/CD pipeline (GitHub Actions)
- [ ] Write comprehensive documentation and API reference

### Deliverables
- ✅ Advanced features based on user feedback
- ✅ Production-ready deployment configuration
- ✅ Community contribution tools

### Success Criteria
- Features are opt-in and don't impact basic functionality
- Production backend handles 100+ devices simultaneously
- Community map aggregates data from 10+ contributors

---

## Timeline Estimate

**Note**: These are estimates only. Actual timeline depends on developer experience and time commitment.

- **Phase 1**: 1-2 weeks (firmware foundation)
- **Phase 2**: 2-3 weeks (BLE integration, mobile app basics)
- **Phase 3**: 1-2 weeks (backend service)
- **Phase 4**: 2-3 weeks (mobile visualization)
- **Phase 5**: 3-4 weeks (enhancements, as needed)

**Total**: 9-14 weeks for full implementation

---

## Risk Management

### Technical Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| BLE connection instability | High | Implement auto-reconnect, heartbeat, connection monitoring |
| LoRaWAN join failures | High | Add retry logic, clear error messages, session debugging |
| GPS accuracy issues indoors | Medium | Warn user when HDOP > 5, require outdoor testing |
| Backend webhook delays | Medium | Add timeout handling, message queue (Redis) |
| Mobile app battery drain | Medium | Optimize GPS update rate, BLE low-power mode |

### Non-Technical Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Hardware unavailability | High | Order T-Watch S3 early, consider alternative dev boards |
| Network server access | Medium | Set up local ChirpStack instance as backup |
| Time constraints | Medium | Prioritize phases 1-3, defer phase 5 enhancements |

---

## Success Metrics

### Functional Metrics
- [ ] LoRaWAN uplink success rate >95% within gateway range
- [ ] GPS coordinate accuracy <10 meters (HDOP <2)
- [ ] End-to-end latency <2 seconds (GPS → map display)
- [ ] App crashes <1% of sessions

### Performance Metrics
- [ ] Firmware battery life >8 hours continuous operation
- [ ] Backend handles 100+ concurrent WebSocket connections
- [ ] Mobile app frame rate >30 FPS with 500+ markers on map

### User Experience Metrics
- [ ] Setup time <10 minutes (join network, connect BLE, view map)
- [ ] UI responsiveness: all actions complete <1 second
- [ ] Export time <5 seconds for 1000-point session

---

## References

- **LilyGo T-Watch S3**: https://lilygo.cc/products/t-watch-s3
- **RadioLib Documentation**: https://jgromes.github.io/RadioLib/
- **ChirpStack Docs**: https://www.chirpstack.io/docs/
- **TTN Docs**: https://www.thethingsnetwork.org/docs/
- **Flutter Blue Plus**: https://pub.dev/packages/flutter_blue_plus
- **FastAPI**: https://fastapi.tiangolo.com/

---

**Document Version**: 2.1
**Last Updated**: January 2026
**Status**: Phase 3 Code Complete - Deployment Pending

### Current Progress Summary

| Phase | Status | Code | Testing |
|-------|--------|------|---------|
| Phase 1: Firmware Foundation | 🟡 Code Complete | ✅ Done | ⏸️ Blocked (upload issues) |
| Phase 2: Bluetooth GPS | 🟢 Code Complete | ✅ Done | ⏸️ Pending hardware |
| Phase 3: Backend Service | 🟢 Code Complete | ✅ Done | ✅ 19/19 tests pass |
| Phase 4: Mobile Visualization | ⬜ Not Started | - | - |
| Phase 5: Enhancements | ⬜ Not Started | - | - |
