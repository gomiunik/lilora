#ifndef _LILORA_NMEA_PARSER_H
#define _LILORA_NMEA_PARSER_H

/*
 * LiLoRa NMEA Parser Module
 *
 * Parses NMEA 0183 sentences (GGA and RMC) to extract GPS coordinates.
 * Validates checksum before parsing to ensure data integrity.
 */

#include <Arduino.h>

// =============================================================================
// GPS Data Structure
// =============================================================================

struct GPSData {
    double latitude;       // Decimal degrees (-90 to +90)
    double longitude;      // Decimal degrees (-180 to +180)
    uint8_t fixQuality;    // 0=invalid, 1=GPS, 2=DGPS, 6=estimated
    int16_t altitude;      // Meters above sea level
    float hdop;            // Horizontal dilution of precision (1.0 = ideal)
    uint8_t satellites;    // Number of satellites in use
    uint32_t timestamp;    // millis() when data was received
    bool valid;            // True if data is fresh and has valid fix

    GPSData() : latitude(0), longitude(0), fixQuality(0), altitude(0),
                hdop(99.9), satellites(0), timestamp(0), valid(false) {}
};

// GPS data timeout in milliseconds (data older than this is invalid)
#define GPS_DATA_TIMEOUT_MS 10000

// Global GPS data - updated by parser
static GPSData gpsData;

// =============================================================================
// Helper Functions
// =============================================================================

/**
 * Calculate NMEA checksum (XOR of all characters between $ and *)
 */
uint8_t calculateNmeaChecksum(const char* sentence) {
    uint8_t checksum = 0;
    const char* p = sentence;

    // Skip leading $
    if (*p == '$') p++;

    // XOR all characters until * or end
    while (*p != '\0' && *p != '*') {
        checksum ^= (uint8_t)*p;
        p++;
    }

    return checksum;
}

/**
 * Validate NMEA sentence checksum
 * Format: $....*XX where XX is hex checksum
 */
bool validateNmeaChecksum(const char* sentence) {
    // Find the asterisk
    const char* asterisk = strchr(sentence, '*');
    if (asterisk == nullptr || strlen(asterisk) < 3) {
        return false;  // No checksum found
    }

    // Parse the checksum from sentence
    char checksumStr[3] = {asterisk[1], asterisk[2], '\0'};
    uint8_t providedChecksum = (uint8_t)strtol(checksumStr, nullptr, 16);

    // Calculate expected checksum
    uint8_t calculatedChecksum = calculateNmeaChecksum(sentence);

    return providedChecksum == calculatedChecksum;
}

/**
 * Convert NMEA coordinate format to decimal degrees
 * NMEA format: DDMM.MMMM (latitude) or DDDMM.MMMM (longitude)
 * Returns decimal degrees
 */
double nmeaToDecimal(const char* coord, char hemisphere) {
    if (coord == nullptr || strlen(coord) == 0) {
        return 0.0;
    }

    double raw = atof(coord);
    int degrees = (int)(raw / 100);
    double minutes = raw - (degrees * 100);
    double decimal = degrees + (minutes / 60.0);

    // Apply hemisphere (S or W = negative)
    if (hemisphere == 'S' || hemisphere == 'W') {
        decimal = -decimal;
    }

    return decimal;
}

/**
 * Get next field from NMEA sentence (fields separated by comma)
 * Modifies the pointer to point past the current field
 * Returns pointer to current field (null-terminated)
 */
char* getNextField(char** sentence) {
    if (*sentence == nullptr || **sentence == '\0') {
        return nullptr;
    }

    char* field = *sentence;

    // Find next comma or end of string
    char* comma = strchr(*sentence, ',');
    if (comma != nullptr) {
        *comma = '\0';  // Null-terminate current field
        *sentence = comma + 1;  // Move past comma
    } else {
        // No more commas, point to end
        *sentence = *sentence + strlen(*sentence);
    }

    return field;
}

// =============================================================================
// GGA Parser
// =============================================================================

/**
 * Parse GPGGA sentence
 * Format: $GPGGA,hhmmss.ss,llll.ll,a,yyyyy.yy,a,x,xx,x.x,x.x,M,x.x,M,x.x,xxxx*hh
 *
 * Fields:
 * 0: Sentence type ($GPGGA)
 * 1: Time (hhmmss.ss)
 * 2: Latitude (llll.ll)
 * 3: N/S indicator
 * 4: Longitude (yyyyy.yy)
 * 5: E/W indicator
 * 6: Fix quality (0=invalid, 1=GPS, 2=DGPS, etc.)
 * 7: Number of satellites
 * 8: HDOP
 * 9: Altitude above MSL
 * 10: Altitude units (M)
 * 11: Geoid separation
 * 12: Geoid units (M)
 * 13: Age of differential correction
 * 14: Reference station ID
 */
bool parseGGA(const char* sentence, GPSData* data) {
    // Make a copy since we'll modify it
    char buf[256];
    strncpy(buf, sentence, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';

    // Remove checksum part for easier parsing
    char* asterisk = strchr(buf, '*');
    if (asterisk != nullptr) {
        *asterisk = '\0';
    }

    char* ptr = buf;
    char* field;
    int fieldNum = 0;

    // Skip $ if present
    if (*ptr == '$') ptr++;

    char latStr[20] = "";
    char latDir = 'N';
    char lonStr[20] = "";
    char lonDir = 'E';

    while ((field = getNextField(&ptr)) != nullptr) {
        switch (fieldNum) {
            case 0:  // Sentence type
                if (strncmp(field, "GPGGA", 5) != 0 && strncmp(field, "GNGGA", 5) != 0) {
                    return false;  // Not a GGA sentence
                }
                break;

            case 1:  // Time - ignored for now
                break;

            case 2:  // Latitude
                strncpy(latStr, field, sizeof(latStr) - 1);
                break;

            case 3:  // N/S
                if (strlen(field) > 0) latDir = field[0];
                break;

            case 4:  // Longitude
                strncpy(lonStr, field, sizeof(lonStr) - 1);
                break;

            case 5:  // E/W
                if (strlen(field) > 0) lonDir = field[0];
                break;

            case 6:  // Fix quality
                data->fixQuality = atoi(field);
                break;

            case 7:  // Satellites
                data->satellites = atoi(field);
                break;

            case 8:  // HDOP
                data->hdop = atof(field);
                break;

            case 9:  // Altitude
                data->altitude = (int16_t)atof(field);
                break;

            // Fields 10-14 are ignored
        }
        fieldNum++;
    }

    // Convert coordinates to decimal degrees
    if (strlen(latStr) > 0 && strlen(lonStr) > 0) {
        data->latitude = nmeaToDecimal(latStr, latDir);
        data->longitude = nmeaToDecimal(lonStr, lonDir);
    }

    // Mark as valid if we have a fix
    data->valid = (data->fixQuality >= 1);
    data->timestamp = millis();

    return true;
}

// =============================================================================
// RMC Parser (optional - provides similar data to GGA)
// =============================================================================

/**
 * Parse GPRMC sentence
 * Format: $GPRMC,hhmmss.ss,A,llll.ll,a,yyyyy.yy,a,x.x,x.x,ddmmyy,x.x,a*hh
 *
 * Fields:
 * 0: Sentence type ($GPRMC)
 * 1: Time
 * 2: Status (A=valid, V=invalid)
 * 3: Latitude
 * 4: N/S
 * 5: Longitude
 * 6: E/W
 * 7: Speed (knots)
 * 8: Course
 * 9: Date
 * 10: Magnetic variation
 * 11: E/W
 */
bool parseRMC(const char* sentence, GPSData* data) {
    char buf[256];
    strncpy(buf, sentence, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';

    char* asterisk = strchr(buf, '*');
    if (asterisk != nullptr) {
        *asterisk = '\0';
    }

    char* ptr = buf;
    char* field;
    int fieldNum = 0;

    if (*ptr == '$') ptr++;

    char latStr[20] = "";
    char latDir = 'N';
    char lonStr[20] = "";
    char lonDir = 'E';
    char status = 'V';

    while ((field = getNextField(&ptr)) != nullptr) {
        switch (fieldNum) {
            case 0:  // Sentence type
                if (strncmp(field, "GPRMC", 5) != 0 && strncmp(field, "GNRMC", 5) != 0) {
                    return false;
                }
                break;

            case 2:  // Status (A=valid)
                if (strlen(field) > 0) status = field[0];
                break;

            case 3:  // Latitude
                strncpy(latStr, field, sizeof(latStr) - 1);
                break;

            case 4:  // N/S
                if (strlen(field) > 0) latDir = field[0];
                break;

            case 5:  // Longitude
                strncpy(lonStr, field, sizeof(lonStr) - 1);
                break;

            case 6:  // E/W
                if (strlen(field) > 0) lonDir = field[0];
                break;
        }
        fieldNum++;
    }

    if (strlen(latStr) > 0 && strlen(lonStr) > 0) {
        data->latitude = nmeaToDecimal(latStr, latDir);
        data->longitude = nmeaToDecimal(lonStr, lonDir);
    }

    // RMC doesn't have fix quality, use status
    data->valid = (status == 'A');
    if (data->valid && data->fixQuality == 0) {
        data->fixQuality = 1;  // Assume GPS fix if valid
    }
    data->timestamp = millis();

    return true;
}

// =============================================================================
// Main Parser Interface
// =============================================================================

/**
 * Parse an NMEA sentence and update GPS data
 * Supports: GPGGA, GNGGA, GPRMC, GNRMC
 * Returns true if parsing successful
 */
bool parseNMEA(const char* sentence, GPSData* data) {
    if (sentence == nullptr || strlen(sentence) < 10) {
        return false;
    }

    // Validate checksum first
    if (!validateNmeaChecksum(sentence)) {
        Serial.print(F("[NMEA] Checksum failed: "));
        Serial.println(sentence);
        return false;
    }

    // Determine sentence type and parse
    if (strstr(sentence, "GGA") != nullptr) {
        return parseGGA(sentence, data);
    } else if (strstr(sentence, "RMC") != nullptr) {
        return parseRMC(sentence, data);
    }

    // Unsupported sentence type - not an error, just ignore
    return false;
}

/**
 * Process a received NMEA sentence string
 * Updates global gpsData if successful
 * Returns true if GPS data was updated
 */
bool processNmeaSentence(const String& sentence) {
    if (sentence.length() == 0) {
        return false;
    }

    // Trim whitespace
    String trimmed = sentence;
    trimmed.trim();

    if (trimmed.length() == 0) {
        return false;
    }

    // Parse and update global GPS data
    if (parseNMEA(trimmed.c_str(), &gpsData)) {
        Serial.print(F("[NMEA] Parsed: Lat="));
        Serial.print(gpsData.latitude, 6);
        Serial.print(F(", Lon="));
        Serial.print(gpsData.longitude, 6);
        Serial.print(F(", Alt="));
        Serial.print(gpsData.altitude);
        Serial.print(F("m, Fix="));
        Serial.print(gpsData.fixQuality);
        Serial.print(F(", Sats="));
        Serial.println(gpsData.satellites);
        return true;
    }

    return false;
}

/**
 * Check if GPS data is fresh (within timeout period)
 */
bool isGpsDataFresh() {
    return gpsData.valid && (millis() - gpsData.timestamp < GPS_DATA_TIMEOUT_MS);
}

/**
 * Get GPS data validity status string for display
 */
String getGpsStatusString() {
    if (!gpsData.valid) {
        return "No Fix";
    }
    if (!isGpsDataFresh()) {
        return "Stale";
    }

    char buf[32];
    snprintf(buf, sizeof(buf), "Fix (%d sats)", gpsData.satellites);
    return String(buf);
}

#endif // _LILORA_NMEA_PARSER_H
