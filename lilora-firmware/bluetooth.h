#ifndef _LILORA_BLUETOOTH_H
#define _LILORA_BLUETOOTH_H

/*
 * LiLoRa Bluetooth Module - BLE UART Server
 *
 * Implements Nordic UART Service (NUS) to receive NMEA sentences from mobile app.
 * Uses standard UUIDs for compatibility with nRF Connect and other BLE tools.
 * Also handles command protocol for remote uplink triggering.
 */

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <esp_mac.h>  // For esp_read_mac and ESP_MAC_BT

// Nordic UART Service UUIDs (industry standard)
#define NUS_SERVICE_UUID        "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define NUS_CHAR_RX_UUID        "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"  // Write (phone -> watch)
#define NUS_CHAR_TX_UUID        "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"  // Notify (watch -> phone)

// BLE Configuration
#define BLE_DEVICE_NAME_PREFIX  "LiLoRa"
#define BLE_NMEA_BUFFER_SIZE    512  // Circular buffer for NMEA sentences

// External flag for phone-triggered uplink (defined in main .ino)
extern volatile bool phoneUplinkRequested;

// =============================================================================
// Circular Buffer for NMEA Reception
// =============================================================================

class NmeaBuffer {
private:
    char buffer[BLE_NMEA_BUFFER_SIZE];
    volatile size_t writeIndex;
    volatile size_t readIndex;

public:
    NmeaBuffer() : writeIndex(0), readIndex(0) {
        memset(buffer, 0, sizeof(buffer));
    }

    void write(const char* data, size_t len) {
        for (size_t i = 0; i < len; i++) {
            buffer[writeIndex] = data[i];
            writeIndex = (writeIndex + 1) % BLE_NMEA_BUFFER_SIZE;
            // If buffer overflows, advance read pointer
            if (writeIndex == readIndex) {
                readIndex = (readIndex + 1) % BLE_NMEA_BUFFER_SIZE;
            }
        }
    }

    // Read a complete line (ending with \n) into dest
    // Returns number of bytes read, or 0 if no complete line available
    size_t readLine(char* dest, size_t maxLen) {
        size_t start = readIndex;
        size_t count = 0;
        bool foundNewline = false;

        // Search for newline
        size_t idx = start;
        while (idx != writeIndex && count < maxLen - 1) {
            if (buffer[idx] == '\n') {
                foundNewline = true;
                count++;
                break;
            }
            count++;
            idx = (idx + 1) % BLE_NMEA_BUFFER_SIZE;
        }

        if (!foundNewline) {
            return 0;  // No complete line yet
        }

        // Copy line to destination
        for (size_t i = 0; i < count; i++) {
            dest[i] = buffer[readIndex];
            readIndex = (readIndex + 1) % BLE_NMEA_BUFFER_SIZE;
        }
        dest[count] = '\0';

        return count;
    }

    bool hasData() const {
        return writeIndex != readIndex;
    }

    void clear() {
        writeIndex = 0;
        readIndex = 0;
    }
};

// =============================================================================
// Global BLE State
// =============================================================================

static BLEServer* pServer = nullptr;
static BLECharacteristic* pTxCharacteristic = nullptr;
static BLECharacteristic* pRxCharacteristic = nullptr;
static bool bleDeviceConnected = false;
static bool bleOldDeviceConnected = false;
static NmeaBuffer nmeaBuffer;
static String bleDeviceName;

// =============================================================================
// BLE Callbacks
// =============================================================================

class BleServerCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
        bleDeviceConnected = true;
        Serial.println(F("[BLE] Device connected"));
    }

    void onDisconnect(BLEServer* pServer) {
        bleDeviceConnected = false;
        Serial.println(F("[BLE] Device disconnected"));
    }
};

class BleRxCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* pCharacteristic) {
        String rxValue = pCharacteristic->getValue();
        if (rxValue.length() > 0) {
            // Check for command prefix (CMD,<command>)
            if (rxValue.startsWith("CMD,")) {
                handleBleCommand(rxValue.substring(4));
                return;
            }

            // Add received data to NMEA buffer
            nmeaBuffer.write(rxValue.c_str(), rxValue.length());

            // Debug: Print first 50 chars
            Serial.print(F("[BLE] RX ("));
            Serial.print(rxValue.length());
            Serial.print(F(" bytes): "));
            if (rxValue.length() > 50) {
                Serial.print(rxValue.substring(0, 50));
                Serial.println(F("..."));
            } else {
                // Remove trailing newlines for clean output
                String clean = rxValue;
                clean.trim();
                Serial.println(clean);
            }
        }
    }

    void handleBleCommand(String cmd) {
        cmd.trim();
        Serial.print(F("[BLE] Command received: "));
        Serial.println(cmd);

        if (cmd == "TX" || cmd == "SEND") {
            // Phone requested an uplink transmission
            phoneUplinkRequested = true;
            Serial.println(F("[BLE] Phone requested uplink"));
        } else {
            Serial.print(F("[BLE] Unknown command: "));
            Serial.println(cmd);
        }
    }
};

// =============================================================================
// BLE Functions
// =============================================================================

/**
 * Generate device name with MAC suffix: "LiLoRa-XXXX"
 */
String getBleDeviceName() {
    uint8_t mac[6];
    // Use WiFi MAC as base (more portable across ESP-IDF versions)
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    char nameBuf[20];
    snprintf(nameBuf, sizeof(nameBuf), "%s-%02X%02X",
             BLE_DEVICE_NAME_PREFIX, mac[4], mac[5]);
    return String(nameBuf);
}

/**
 * Initialize BLE server with Nordic UART Service
 */
void initBluetooth() {
    Serial.println(F("[BLE] Initializing Bluetooth..."));

    // Generate device name
    bleDeviceName = getBleDeviceName();
    Serial.print(F("[BLE] Device name: "));
    Serial.println(bleDeviceName);

    // Initialize BLE
    BLEDevice::init(bleDeviceName.c_str());

    // Create BLE Server
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new BleServerCallbacks());

    // Create Nordic UART Service
    BLEService* pService = pServer->createService(NUS_SERVICE_UUID);

    // Create TX Characteristic (Notify - watch -> phone)
    pTxCharacteristic = pService->createCharacteristic(
        NUS_CHAR_TX_UUID,
        BLECharacteristic::PROPERTY_NOTIFY
    );
    pTxCharacteristic->addDescriptor(new BLE2902());

    // Create RX Characteristic (Write - phone -> watch)
    pRxCharacteristic = pService->createCharacteristic(
        NUS_CHAR_RX_UUID,
        BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
    );
    pRxCharacteristic->setCallbacks(new BleRxCallbacks());

    // Start the service
    pService->start();

    // Start advertising
    BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(NUS_SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06);  // Functions that help with iPhone connections
    pAdvertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();

    Serial.println(F("[BLE] Advertising started"));
}

/**
 * Check if BLE device is connected
 */
bool isBleConnected() {
    return bleDeviceConnected;
}

/**
 * Get the BLE device name
 */
String getBleDeviceNameCached() {
    return bleDeviceName;
}

/**
 * Send data to connected device (optional - for status feedback)
 */
void bleSend(const char* data) {
    if (bleDeviceConnected && pTxCharacteristic != nullptr) {
        pTxCharacteristic->setValue((uint8_t*)data, strlen(data));
        pTxCharacteristic->notify();
    }
}

/**
 * Handle BLE connection state changes and restart advertising if needed
 * Call this in loop() to handle reconnections
 */
void updateBluetooth() {
    // Handle disconnect -> start advertising again
    if (!bleDeviceConnected && bleOldDeviceConnected) {
        delay(500);  // Give BLE stack time to settle
        BLEDevice::startAdvertising();
        Serial.println(F("[BLE] Restarting advertising"));
        bleOldDeviceConnected = bleDeviceConnected;
    }

    // Handle new connection
    if (bleDeviceConnected && !bleOldDeviceConnected) {
        bleOldDeviceConnected = bleDeviceConnected;
    }
}

/**
 * Check if there's a complete NMEA sentence available
 */
bool hasNmeaSentence() {
    return nmeaBuffer.hasData();
}

/**
 * Read a complete NMEA sentence from buffer
 * Returns empty string if no complete sentence available
 */
String readNmeaSentence() {
    char line[256];
    size_t len = nmeaBuffer.readLine(line, sizeof(line));
    if (len > 0) {
        return String(line);
    }
    return String();
}

/**
 * Clear the NMEA buffer
 */
void clearNmeaBuffer() {
    nmeaBuffer.clear();
}

#endif // _LILORA_BLUETOOTH_H
