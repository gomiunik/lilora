#ifndef _LILORA_PAYLOAD_ENCODER_H
#define _LILORA_PAYLOAD_ENCODER_H

/*
 * LiLoRa Payload Encoder Module
 *
 * Encodes GPS data into compact 13-byte binary format for LoRaWAN transmission.
 * Uses big-endian byte order for cross-platform compatibility.
 *
 * Payload Format (13 bytes):
 * Bytes 0-3:  Latitude (int32, scaled by 1e7)
 * Bytes 4-7:  Longitude (int32, scaled by 1e7)
 * Byte 8:     Fix quality (0-6)
 * Bytes 9-10: Altitude (int16, meters)
 * Byte 11:    HDOP (scaled by 10, max 255 = 25.5)
 * Byte 12:    Satellite count (max 255)
 */

#include <Arduino.h>
#include "nmea_parser.h"

// Payload size in bytes
#define GPS_PAYLOAD_SIZE 13

// =============================================================================
// Encoder Functions
// =============================================================================

/**
 * Encode GPS data into binary payload (big-endian)
 *
 * @param gps Pointer to GPS data structure
 * @param payload Output buffer (must be at least GPS_PAYLOAD_SIZE bytes)
 */
void encodeGpsPayload(const GPSData* gps, uint8_t* payload) {
    // Scale coordinates to integers (1e7 gives ~1cm precision)
    int32_t lat = (int32_t)(gps->latitude * 1e7);
    int32_t lon = (int32_t)(gps->longitude * 1e7);

    // Latitude (bytes 0-3, big-endian)
    payload[0] = (lat >> 24) & 0xFF;
    payload[1] = (lat >> 16) & 0xFF;
    payload[2] = (lat >> 8) & 0xFF;
    payload[3] = lat & 0xFF;

    // Longitude (bytes 4-7, big-endian)
    payload[4] = (lon >> 24) & 0xFF;
    payload[5] = (lon >> 16) & 0xFF;
    payload[6] = (lon >> 8) & 0xFF;
    payload[7] = lon & 0xFF;

    // Fix quality (byte 8)
    payload[8] = gps->fixQuality;

    // Altitude (bytes 9-10, big-endian, signed int16)
    int16_t alt = gps->altitude;
    payload[9] = (alt >> 8) & 0xFF;
    payload[10] = alt & 0xFF;

    // HDOP scaled by 10 (byte 11), capped at 255
    uint8_t hdop = (gps->hdop > 25.5f) ? 255 : (uint8_t)(gps->hdop * 10);
    payload[11] = hdop;

    // Satellite count (byte 12)
    payload[12] = gps->satellites;
}

/**
 * Encode "no GPS" marker payload (all zeros except fix=0)
 * Use when no valid GPS data is available
 *
 * @param payload Output buffer (must be at least GPS_PAYLOAD_SIZE bytes)
 */
void encodeNoGpsPayload(uint8_t* payload) {
    memset(payload, 0, GPS_PAYLOAD_SIZE);
    // Fix quality 0 already indicates invalid
}

/**
 * Print payload as hex string for debugging
 *
 * @param payload Payload buffer
 * @param size Size of payload
 */
void printPayloadHex(const uint8_t* payload, size_t size) {
    Serial.print(F("[Payload] Hex: "));
    for (size_t i = 0; i < size; i++) {
        if (payload[i] < 0x10) Serial.print('0');
        Serial.print(payload[i], HEX);
    }
    Serial.println();
}

/**
 * Decode payload back to GPS data (for verification/debugging)
 *
 * @param payload Input payload buffer
 * @param gps Output GPS data structure
 */
void decodeGpsPayload(const uint8_t* payload, GPSData* gps) {
    // Latitude (big-endian signed int32)
    int32_t lat = ((int32_t)payload[0] << 24) |
                  ((int32_t)payload[1] << 16) |
                  ((int32_t)payload[2] << 8) |
                  (int32_t)payload[3];
    gps->latitude = lat / 1e7;

    // Longitude (big-endian signed int32)
    int32_t lon = ((int32_t)payload[4] << 24) |
                  ((int32_t)payload[5] << 16) |
                  ((int32_t)payload[6] << 8) |
                  (int32_t)payload[7];
    gps->longitude = lon / 1e7;

    // Fix quality
    gps->fixQuality = payload[8];

    // Altitude (big-endian signed int16)
    int16_t alt = ((int16_t)payload[9] << 8) | (int16_t)payload[10];
    gps->altitude = alt;

    // HDOP
    gps->hdop = payload[11] / 10.0f;

    // Satellites
    gps->satellites = payload[12];

    // Set validity based on fix quality
    gps->valid = (gps->fixQuality >= 1);
}

/**
 * Prepare uplink payload using current GPS data
 * Returns true if valid GPS data was encoded, false if "no GPS" marker was used
 *
 * @param payload Output buffer (must be at least GPS_PAYLOAD_SIZE bytes)
 * @return true if valid GPS data, false if placeholder
 */
bool prepareGpsUplinkPayload(uint8_t* payload) {
    if (isGpsDataFresh()) {
        encodeGpsPayload(&gpsData, payload);

        Serial.print(F("[Payload] Encoding GPS: "));
        Serial.print(gpsData.latitude, 6);
        Serial.print(F(", "));
        Serial.print(gpsData.longitude, 6);
        Serial.print(F(" alt="));
        Serial.print(gpsData.altitude);
        Serial.print(F("m fix="));
        Serial.print(gpsData.fixQuality);
        Serial.print(F(" sats="));
        Serial.println(gpsData.satellites);

        printPayloadHex(payload, GPS_PAYLOAD_SIZE);
        return true;
    } else {
        encodeNoGpsPayload(payload);
        Serial.println(F("[Payload] No valid GPS - encoding zeros"));
        printPayloadHex(payload, GPS_PAYLOAD_SIZE);
        return false;
    }
}

// =============================================================================
// Self-Test Function (for debugging)
// =============================================================================

/**
 * Run encoder self-test with known values
 * Prints results to Serial
 */
void testPayloadEncoder() {
    Serial.println(F("[Payload] Running self-test..."));

    // Test data: Munich, Germany
    GPSData testGps;
    testGps.latitude = 48.137154;
    testGps.longitude = 11.576124;
    testGps.fixQuality = 1;
    testGps.altitude = 520;
    testGps.hdop = 1.2;
    testGps.satellites = 8;
    testGps.valid = true;

    // Encode
    uint8_t payload[GPS_PAYLOAD_SIZE];
    encodeGpsPayload(&testGps, payload);

    Serial.print(F("[Payload] Test input: lat="));
    Serial.print(testGps.latitude, 6);
    Serial.print(F(" lon="));
    Serial.println(testGps.longitude, 6);

    printPayloadHex(payload, GPS_PAYLOAD_SIZE);

    // Decode back
    GPSData decoded;
    decodeGpsPayload(payload, &decoded);

    Serial.print(F("[Payload] Decoded: lat="));
    Serial.print(decoded.latitude, 6);
    Serial.print(F(" lon="));
    Serial.print(decoded.longitude, 6);
    Serial.print(F(" alt="));
    Serial.print(decoded.altitude);
    Serial.print(F(" fix="));
    Serial.print(decoded.fixQuality);
    Serial.print(F(" hdop="));
    Serial.print(decoded.hdop, 1);
    Serial.print(F(" sats="));
    Serial.println(decoded.satellites);

    // Verify
    bool pass = true;
    if (abs(decoded.latitude - testGps.latitude) > 0.000001) pass = false;
    if (abs(decoded.longitude - testGps.longitude) > 0.000001) pass = false;
    if (decoded.altitude != testGps.altitude) pass = false;
    if (decoded.fixQuality != testGps.fixQuality) pass = false;
    if (decoded.satellites != testGps.satellites) pass = false;

    Serial.print(F("[Payload] Self-test: "));
    Serial.println(pass ? "PASSED" : "FAILED");
}

#endif // _LILORA_PAYLOAD_ENCODER_H
