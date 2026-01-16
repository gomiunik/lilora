#ifndef _LILORA_CONFIG_H
#define _LILORA_CONFIG_H

#include <LilyGoLib.h>
#include <LV_Helper.h>

// =============================================================================
// LiLoRa Firmware Configuration
// =============================================================================

// -----------------------------------------------------------------------------
// Display Settings
// -----------------------------------------------------------------------------

// Dark mode: true = white text on black background, false = black text on white
const bool DARK_MODE = true;

// Colors for dark mode
const uint32_t COLOR_BG_DARK = 0x000000;       // Black background
const uint32_t COLOR_TEXT_DARK = 0xFFFFFF;     // White text
const uint32_t COLOR_ACCENT_DARK = 0x00FF00;   // Green accent

// Colors for light mode
const uint32_t COLOR_BG_LIGHT = 0xFFFFFF;      // White background
const uint32_t COLOR_TEXT_LIGHT = 0x000000;    // Black text
const uint32_t COLOR_ACCENT_LIGHT = 0x0066CC;  // Blue accent

// Battery indicator settings
const bool SHOW_BATTERY_INDICATOR = true;      // Show battery percentage on screen
const uint32_t BATTERY_UPDATE_INTERVAL_MS = 30000;  // Update battery every 30 seconds

// Screen refresh optimization (reduces power consumption)
// Set to 1 for real-time countdown, higher values save battery
const uint32_t DISPLAY_REFRESH_INTERVAL_SECONDS = 10;  // Refresh countdown every N seconds

// -----------------------------------------------------------------------------
// Bluetooth / GPS Settings (Phase 2)
// -----------------------------------------------------------------------------

// Enable/disable BLE GPS receiver
const bool ENABLE_BLE_GPS = true;

// BLE connection timeout - restart advertising if no connection after this time
const uint32_t BLE_CONNECT_TIMEOUT_MS = 300000;  // 5 minutes

// Show BLE/GPS status on display
const bool SHOW_BLE_STATUS = true;

// -----------------------------------------------------------------------------
// LoRaWAN Settings
// -----------------------------------------------------------------------------

// Regional choices: EU868, US915, AU915, AS923, AS923_2, AS923_3, AS923_4, IN865, KR920, CN500
const LoRaWANBand_t LORAWAN_REGION = EU868;
const uint8_t LORAWAN_SUB_BAND = 0;  // For US915, change this to 2, otherwise leave on 0

// Uplink interval in seconds (60 seconds for testing, increase for production)
const uint32_t UPLINK_INTERVAL_SECONDS = 60UL;

// Join retry settings
const uint8_t MAX_JOIN_ATTEMPTS = 3;
const uint32_t JOIN_RETRY_BASE_DELAY_MS = 10000;  // 10 seconds base delay
const uint32_t JOIN_RETRY_MAX_DELAY_MS = 60000;   // 60 seconds max delay

// Frame port for uplink data
const uint8_t UPLINK_FPORT = 1;

// -----------------------------------------------------------------------------
// Load LoRaWAN Credentials
// -----------------------------------------------------------------------------
// Credentials are stored in a separate file to keep them out of version control
// Copy lorawan_credentials.h.template to lorawan_credentials.h and fill in your keys

#include "lorawan_credentials.h"

// =============================================================================
// Hardware Objects (provided by LilyGoLib)
// =============================================================================

// Create the LoRaWAN node using the radio from LilyGoLib
LoRaWANNode node(&radio, &LORAWAN_REGION, LORAWAN_SUB_BAND);

// =============================================================================
// State Machine
// =============================================================================

enum LoRaWanState {
    LORAWAN_IDLE,       // Initial state
    LORAWAN_JOINING,    // Attempting to join network
    LORAWAN_JOINED,     // Successfully joined, configuring
    LORAWAN_UPLINK,     // Sending uplinks
    LORAWAN_DOWNLINK,   // Processing downlink (handled within uplink)
    LORAWAN_ERROR       // Error state
};

// =============================================================================
// Helper Functions
// =============================================================================

// Result code to text - error codes from RadioLib
String stateDecode(const int16_t result) {
    switch (result) {
        case RADIOLIB_ERR_NONE:
            return "ERR_NONE";
        case RADIOLIB_ERR_CHIP_NOT_FOUND:
            return "ERR_CHIP_NOT_FOUND";
        case RADIOLIB_ERR_PACKET_TOO_LONG:
            return "ERR_PACKET_TOO_LONG";
        case RADIOLIB_ERR_RX_TIMEOUT:
            return "ERR_RX_TIMEOUT";
        case RADIOLIB_ERR_MIC_MISMATCH:
            return "ERR_MIC_MISMATCH";
        case RADIOLIB_ERR_INVALID_BANDWIDTH:
            return "ERR_INVALID_BANDWIDTH";
        case RADIOLIB_ERR_INVALID_SPREADING_FACTOR:
            return "ERR_INVALID_SPREADING_FACTOR";
        case RADIOLIB_ERR_INVALID_CODING_RATE:
            return "ERR_INVALID_CODING_RATE";
        case RADIOLIB_ERR_INVALID_FREQUENCY:
            return "ERR_INVALID_FREQUENCY";
        case RADIOLIB_ERR_INVALID_OUTPUT_POWER:
            return "ERR_INVALID_OUTPUT_POWER";
        case RADIOLIB_ERR_NETWORK_NOT_JOINED:
            return "RADIOLIB_ERR_NETWORK_NOT_JOINED";
        case RADIOLIB_ERR_DOWNLINK_MALFORMED:
            return "RADIOLIB_ERR_DOWNLINK_MALFORMED";
        case RADIOLIB_ERR_INVALID_REVISION:
            return "RADIOLIB_ERR_INVALID_REVISION";
        case RADIOLIB_ERR_INVALID_PORT:
            return "RADIOLIB_ERR_INVALID_PORT";
        case RADIOLIB_ERR_NO_RX_WINDOW:
            return "RADIOLIB_ERR_NO_RX_WINDOW";
        case RADIOLIB_ERR_INVALID_CID:
            return "RADIOLIB_ERR_INVALID_CID";
        case RADIOLIB_ERR_UPLINK_UNAVAILABLE:
            return "RADIOLIB_ERR_UPLINK_UNAVAILABLE";
        case RADIOLIB_ERR_COMMAND_QUEUE_FULL:
            return "RADIOLIB_ERR_COMMAND_QUEUE_FULL";
        case RADIOLIB_ERR_COMMAND_QUEUE_ITEM_NOT_FOUND:
            return "RADIOLIB_ERR_COMMAND_QUEUE_ITEM_NOT_FOUND";
        case RADIOLIB_ERR_JOIN_NONCE_INVALID:
            return "RADIOLIB_ERR_JOIN_NONCE_INVALID";
        case RADIOLIB_ERR_DWELL_TIME_EXCEEDED:
            return "RADIOLIB_ERR_DWELL_TIME_EXCEEDED";
        case RADIOLIB_ERR_CHECKSUM_MISMATCH:
            return "RADIOLIB_ERR_CHECKSUM_MISMATCH";
        case RADIOLIB_ERR_NO_JOIN_ACCEPT:
            return "RADIOLIB_ERR_NO_JOIN_ACCEPT";
        case RADIOLIB_LORAWAN_SESSION_RESTORED:
            return "RADIOLIB_LORAWAN_SESSION_RESTORED";
        case RADIOLIB_LORAWAN_NEW_SESSION:
            return "RADIOLIB_LORAWAN_NEW_SESSION";
        case RADIOLIB_ERR_NONCES_DISCARDED:
            return "RADIOLIB_ERR_NONCES_DISCARDED";
        case RADIOLIB_ERR_SESSION_DISCARDED:
            return "RADIOLIB_ERR_SESSION_DISCARDED";
    }
    return "See https://jgromes.github.io/RadioLib/group__status__codes.html";
}

// Debug helper function
void debug(bool failed, const __FlashStringHelper* message, int state, bool halt) {
    if (failed) {
        Serial.print(message);
        Serial.print(" - ");
        Serial.print(stateDecode(state));
        Serial.print(" (");
        Serial.print(state);
        Serial.println(")");
        while (halt) { delay(1); }
    }
}

// Helper function to display a byte array as hex
void arrayDump(uint8_t *buffer, uint16_t len) {
    for (uint16_t c = 0; c < len; c++) {
        if (buffer[c] < 0x10) { Serial.print('0'); }
        Serial.print(buffer[c], HEX);
    }
    Serial.println();
}

// Convert state enum to string for display
const char* stateToString(LoRaWanState state) {
    switch (state) {
        case LORAWAN_IDLE:     return "IDLE";
        case LORAWAN_JOINING:  return "JOINING";
        case LORAWAN_JOINED:   return "JOINED";
        case LORAWAN_UPLINK:   return "UPLINK";
        case LORAWAN_DOWNLINK: return "DOWNLINK";
        case LORAWAN_ERROR:    return "ERROR";
        default:               return "UNKNOWN";
    }
}

#endif // _LILORA_CONFIG_H
