# LiLoRa Firmware - Phase 1

LoRaWAN range tracking firmware for LilyGo T-Watch S3 with SX1262 radio.

## Features

- **OTAA Join**: Connects to ChirpStack or TTN network servers
- **Session Persistence**: Sessions survive power cycles (stored in NVS)
- **Automatic Retry**: Exponential backoff on join failure (max 3 attempts)
- **Duty Cycle Compliance**: Respects regional fair use policies
- **Display Status**: Real-time status and metrics on watch screen
- **Downlink Support**: Receives and logs downlink messages

## Hardware Requirements

- LilyGo T-Watch S3 with SX1262 LoRa (868MHz or 915MHz variant)
- USB-C cable for programming

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
4. **Tools > **
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
3. Enable "Resets DevNonces" in device settings (for development) (Disable frame-counter validation)
4. Copy DevEUI, AppEUI, AppKey to `lorawan_credentials.h`

### The Things Network (TTN)

1. Create Application and register End Device
2. Select LoRaWAN version 1.1.0
3. Copy DevEUI, JoinEUI (AppEUI), AppKey to credentials file

## Serial Monitor Output

Open Serial Monitor at **115200 baud** to see:

```
========================================
   LiLoRa Firmware v1.0 - Phase 1
   LoRaWAN Range Tracking System
========================================

[Setup] Initializing T-Watch hardware...
[Setup] Initializing display...
[Setup] Initializing LoRaWAN...
[Setup] Region: EU868, DevEUI: 70B3D57ED00700C3
[Session] Checking for saved session...
[Session] No saved nonces found - fresh start
[Setup] Starting fresh join

[Join] Attempt 1 of 3
[Join] SUCCESS! New session established

[Config] Configuring LoRaWAN node...
[Config] DevAddr: 26011234
[Config] ADR enabled
[Config] Configuration complete

[Uplink] Preparing uplink...
[Uplink] Payload: 1F03E8
[Uplink] Frame counter: 1
[Uplink] Transmitted successfully
[Uplink] Next uplink in 60 seconds
```

## Configuration Options

Edit `config.h` to customize:

| Setting | Default | Description |
|---------|---------|-------------|
| `LORAWAN_REGION` | EU868 | LoRaWAN frequency band |
| `UPLINK_INTERVAL_SECONDS` | 60 | Seconds between uplinks |
| `MAX_JOIN_ATTEMPTS` | 3 | Max OTAA join retries |
| `JOIN_RETRY_BASE_DELAY_MS` | 10000 | Initial retry delay |
| `UPLINK_FPORT` | 1 | Frame port for data |

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

## File Structure

```
lilora-firmware/
├── lilora-firmware.ino       # Main sketch
├── config.h                  # Configuration and helpers
├── lorawan_credentials.h     # Your OTAA keys (gitignored)
├── lorawan_credentials.h.template  # Template for keys
├── .gitignore
└── README.md
```

## Next Steps (Phase 2)

- Add Bluetooth LE server for GPS data from mobile app
- Implement NMEA parser for GPS coordinates
- Encode GPS data in uplink payload
- Display GPS fix status on watch screen

## License

MIT License - See project root for details
