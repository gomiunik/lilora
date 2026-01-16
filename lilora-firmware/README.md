# LiLoRa Firmware - Phase 2

LoRaWAN range tracking firmware for LilyGo T-Watch S3 with SX1262 radio and Bluetooth GPS integration.

## Features

### LoRaWAN (Phase 1)
- **OTAA Join**: Connects to ChirpStack or TTN network servers
- **Session Persistence**: Sessions survive power cycles (stored in NVS)
- **Automatic Retry**: Exponential backoff on join failure (max 3 attempts)
- **Duty Cycle Compliance**: Respects regional fair use policies
- **Display Status**: Real-time status and metrics on watch screen
- **Downlink Support**: Receives and logs downlink messages

### Bluetooth GPS (Phase 2)
- **BLE UART Server**: Nordic UART Service for mobile app communication
- **NMEA Parser**: Parses GGA and RMC sentences with checksum validation
- **GPS Payload**: 13-byte binary encoding for efficient LoRaWAN transmission
- **Real-time Display**: Shows BLE connection and GPS fix status
- **Auto-Discovery**: Device advertises as "LiLoRa-XXXX" for easy pairing

## Hardware Requirements

- LilyGo T-Watch S3 with SX1262 LoRa (868MHz or 915MHz variant)
- USB-C cable for programming
- Mobile phone with LiLoRa GPS app (Android or iOS)

## Software Requirements

- Arduino IDE 2.x
- LilyGoLib library (install via Library Manager or from GitHub)
- RadioLib library (included with LilyGoLib)

## Installation

### 1. Install Arduino IDE

Download from https://www.arduino.cc/en/software

### 2. Install ESP32 Board Support

1. Open Arduino IDE
2. Go to **File > Preferences**
3. Add to "Additional Board Manager URLs":
   ```
   https://espressif.github.io/arduino-esp32/package_esp32_index.json
   ```
4. Go to **Tools > Board > Boards Manager**
5. Search "esp32" and install **esp32 by Espressif Systems**

### 3. Install LilyGoLib

1. Go to **Sketch > Include Library > Manage Libraries**
2. Search "LilyGoLib" and install it
3. Or download from: https://github.com/Xinyuan-LilyGO/LilyGoLib

### 4. Configure Credentials

1. Copy `lorawan_credentials.h.template` to `lorawan_credentials.h`
2. Edit `lorawan_credentials.h` with your keys from ChirpStack/TTN:
   - `LORAWAN_JOIN_EUI` - JoinEUI/AppEUI (8 bytes as hex)
   - `LORAWAN_DEV_EUI` - Device EUI (8 bytes as hex)
   - `LORAWAN_APP_KEY` - Application Key (16 bytes)
   - `LORAWAN_NWK_KEY` - Network Key (16 bytes, same as AppKey for LoRaWAN 1.0.x)

### 5. Configure Region (if not EU868)

Edit `config.h` and change:
```cpp
const LoRaWANBand_t LORAWAN_REGION = EU868;  // Change to US915, AU915, etc.
```

### 6. Select Board and Upload

1. Connect T-Watch S3 via USB-C
2. **Tools > Board > esp32**: Select "LilyGo T-Watch S3"
3. **Tools > Port**: Select the COM port
4. Configure **Tools** settings:
   - **USB CDC On Boot**: Enabled
   - **CPU frequency**: 240MHz(WiFi)
   - **Core Debug Level**: None
   - **USB DFU On Boot**: Disabled
   - **Erase All Flash before Sketch Upload**: Disabled
   - **Events run on**: Core 1
   - **JTAG Adapter**: Disabled
   - **Arduino Runs On**: Core 1
   - **USB Firmware MSC On Boot**: Disabled
   - **Partition Scheme**: 16M Flash (3MB APP/9.9MB FATFS)
   - **Board revision**: Radio-SX1262
   - **Upload mode**: UART0/Hardware CDC
   - **Upload Speed**: 921600
   - **USB Mode**: CDC and JTAG
5. Click **Upload**

More details about configuration and deployment (plus how to put watch into download mode) can be found in the LilyGo T-Watch S3 documentation: https://github.com/Xinyuan-LilyGO/LilyGoLib/blob/master/docs/lilygo-t-watch-s3.md

## Network Server Setup

### ChirpStack

1. Create Application and Device Profile
2. **Important**: Set LoRaWAN MAC version to **1.1.0**
3. Enable "Resets DevNonces" in device settings (for development)
4. Copy DevEUI, AppEUI, AppKey to `lorawan_credentials.h`
5. Add HTTP Integration pointing to your backend (Phase 3)

### The Things Network (TTN)

1. Create Application and register End Device
2. Select LoRaWAN version 1.1.0
3. Copy DevEUI, JoinEUI (AppEUI), AppKey to credentials file

## GPS Payload Format

The firmware encodes GPS data into a compact 13-byte binary payload:

| Bytes | Type | Description |
|-------|------|-------------|
| 0-3 | int32 | Latitude (scaled by 1e7) |
| 4-7 | int32 | Longitude (scaled by 1e7) |
| 8 | uint8 | Fix quality (0=invalid, 1=GPS, 2=DGPS) |
| 9-10 | int16 | Altitude (meters) |
| 11 | uint8 | HDOP (scaled by 10) |
| 12 | uint8 | Satellite count |

### Example Decoder (Python)

```python
import struct

def decode_lilora_payload(hex_payload: str) -> dict:
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

# Example usage
payload = "1CB77CF806F6B81C01020C0908"
print(decode_lilora_payload(payload))
```

### ChirpStack Codec (JavaScript)

```javascript
function decodeUplink(input) {
  var data = input.bytes;

  var lat = (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];
  if (lat > 0x7FFFFFFF) lat -= 0x100000000;

  var lon = (data[4] << 24) | (data[5] << 16) | (data[6] << 8) | data[7];
  if (lon > 0x7FFFFFFF) lon -= 0x100000000;

  var alt = (data[9] << 8) | data[10];
  if (alt > 0x7FFF) alt -= 0x10000;

  return {
    data: {
      latitude: lat / 1e7,
      longitude: lon / 1e7,
      fix_quality: data[8],
      altitude: alt,
      hdop: data[11] / 10.0,
      satellites: data[12]
    }
  };
}
```

## Serial Monitor Output

Open Serial Monitor at **115200 baud** to see:

```
========================================
   LiLoRa Firmware v2.0 - Phase 2
   LoRaWAN Range Tracking System
   + Bluetooth GPS Integration
========================================

[Setup] Dark mode: ENABLED
[Setup] Initializing T-Watch hardware...
[Setup] Initializing display...
[Setup] Initializing Bluetooth GPS receiver...
[BLE] Initializing Bluetooth...
[BLE] Device name: LiLoRa-A1B2
[BLE] Advertising started
[Setup] Initializing LoRaWAN...
[Setup] Region: EU868, DevEUI: 70B3D57ED00700C3
[Session] Checking for saved session...
[Session] Session restored and activated successfully!

[BLE] Device connected
[BLE] RX (82 bytes): $GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,47.0,M,,*47
[NMEA] Parsed: Lat=48.117300, Lon=11.516667, Alt=545m, Fix=1, Sats=8

[Uplink] Preparing uplink...
[Payload] Encoding GPS: 48.117300, 11.516667 alt=545m fix=1 sats=8
[Payload] Hex: 1CB77CF806F6B81C01022109008
[Uplink] Transmitted successfully
[Uplink] Next uplink in 60 seconds
```

## Display Information

The watch display shows:

```
+---------------------------+
|       LiLoRa v2.0         |
+---------------------------+
|  Uplinks: 5  Downlinks: 1 |
|  RSSI: -85 dBm  SNR: 7.5  |
|       Next TX: 45 s       |
| BLE: Connected | GPS: Fix |
|                           |
|      [ SEND NOW ]         |
+---------------------------+
```

## Configuration Options

Edit `config.h` to customize:

| Setting | Default | Description |
|---------|---------|-------------|
| `LORAWAN_REGION` | EU868 | LoRaWAN frequency band |
| `UPLINK_INTERVAL_SECONDS` | 60 | Seconds between uplinks |
| `MAX_JOIN_ATTEMPTS` | 3 | Max OTAA join retries |
| `ENABLE_BLE_GPS` | true | Enable Bluetooth GPS receiver |
| `SHOW_BLE_STATUS` | true | Show BLE/GPS status on display |
| `DARK_MODE` | true | Dark theme for display |

## File Structure

```
lilora-firmware/
├── lilora-firmware.ino       # Main sketch
├── config.h                  # Configuration and helpers
├── bluetooth.h               # BLE UART server (Phase 2)
├── nmea_parser.h             # NMEA sentence parser (Phase 2)
├── payload_encoder.h         # GPS binary encoder (Phase 2)
├── lorawan_credentials.h     # Your OTAA keys (gitignored)
├── lorawan_credentials.h.template  # Template for keys
├── .gitignore
└── README.md
```

## Troubleshooting

### Join fails immediately
- Verify DevEUI, AppEUI, AppKey match network server exactly
- Ensure "Resets DevNonces" is enabled on network server
- Check gateway is online and in range

### Session not restored after power cycle
- NVS storage may be corrupted - erase flash and re-upload
- Ensure `store.begin("lilora")` completes without error

### Upload fails
- Try holding BOOT button during upload
- Try different USB cable (some are charge-only)
- Select correct COM port

### No serial output
- Set baud rate to 115200
- Enable "USB CDC On Boot" in Tools menu

### BLE device not appearing
- Ensure ENABLE_BLE_GPS is true in config.h
- Check Serial Monitor for "[BLE] Advertising started"
- Try restarting the watch

### GPS data not received
- Verify mobile app is connected and forwarding
- Check Serial Monitor for "[BLE] RX" messages
- Ensure NMEA sentences have valid checksum

### GPS payload shows zeros
- GPS data may be stale (>10 seconds old)
- Check mobile app has GPS fix
- Verify NMEA parser is working via Serial output

## Testing with nRF Connect

You can test BLE functionality without the mobile app:

1. Install nRF Connect on your phone
2. Scan for "LiLoRa-XXXX" device
3. Connect and find Nordic UART Service
4. Write test NMEA to RX characteristic:
   ```
   $GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,47.0,M,,*47
   ```
5. Check Serial Monitor for parsed output

## Next Steps (Phase 3)

- FastAPI backend service with WebSocket support
- Webhook integration for ChirpStack/TTN
- Real-time data visualization in mobile app

## License

MIT License - See project root for details
