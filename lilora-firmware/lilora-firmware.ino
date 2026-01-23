/*
 * LiLoRa Firmware - Phase 2: Bluetooth GPS Integration
 *
 * LoRaWAN range tracking firmware for LilyGo T-Watch S3
 *
 * Features:
 * - OTAA join to ChirpStack/TTN network server
 * - Session persistence in NVS (survives power cycles)
 * - Configurable uplink interval with duty cycle compliance
 * - Downlink reception and logging
 * - Display status on watch screen
 * - Dark mode support (configurable)
 * - Manual uplink via on-screen button or physical button
 * - BLE GPS receiver (receives NMEA sentences from mobile app)
 * - GPS payload encoding for LoRaWAN uplinks
 *
 * Hardware: LilyGo T-Watch S3 with SX1262 LoRa (868MHz)
 *
 * Setup:
 * 1. Copy lorawan_credentials.h.template to lorawan_credentials.h
 * 2. Fill in your OTAA keys from ChirpStack/TTN
 * 3. Configure region in config.h if not EU868
 * 4. Upload via Arduino IDE with LilyGoLib installed
 * 5. Install LiLoRa mobile app and pair via Bluetooth
 *
 * Network Server Requirements:
 * - LoRaWAN MAC version: 1.1.0
 * - Enable "Resets DevNonces" for development
 * - Device Profile: Class A, OTAA
 */

#include "config.h"
#include <Preferences.h>

// Phase 2: BLE GPS modules
#include "bluetooth.h"
#include "nmea_parser.h"
#include "payload_encoder.h"

// =============================================================================
// Global Variables
// =============================================================================

// State machine
LoRaWanState currentState = LORAWAN_IDLE;
uint8_t joinAttempts = 0;

// Session storage
Preferences store;
uint8_t sessionBuffer[RADIOLIB_LORAWAN_SESSION_BUF_SIZE];

// Timing
uint32_t nextUplinkTime = 0;
uint32_t lastButtonCheck = 0;

// Manual uplink trigger (from watch button)
volatile bool manualUplinkRequested = false;

// Phone uplink trigger (from BLE command)
volatile bool phoneUplinkRequested = false;
uint32_t lastPhoneUplinkTime = 0;
const uint32_t PHONE_UPLINK_MIN_INTERVAL_MS = 5000;  // 5 second debounce

// Sleep mode trigger (set by power button callback)
volatile bool sleepRequested = false;

// UI elements
lv_obj_t *statusLabel;
lv_obj_t *metricsLabel;
lv_obj_t *sendButton;
lv_obj_t *countdownLabel;
lv_obj_t *bleGpsLabel;  // Phase 2: BLE/GPS status
lv_obj_t *batteryLabel; // Battery percentage indicator

// Statistics
uint32_t uplinkCount = 0;
uint32_t downlinkCount = 0;
int16_t lastRSSI = 0;
float lastSNR = 0;

// Colors based on mode
lv_color_t colorBg;
lv_color_t colorText;
lv_color_t colorAccent;

// =============================================================================
// Display Functions
// =============================================================================

void applyTheme() {
    if (DARK_MODE) {
        colorBg = lv_color_hex(COLOR_BG_DARK);
        colorText = lv_color_hex(COLOR_TEXT_DARK);
        colorAccent = lv_color_hex(COLOR_ACCENT_DARK);
    } else {
        colorBg = lv_color_hex(COLOR_BG_LIGHT);
        colorText = lv_color_hex(COLOR_TEXT_LIGHT);
        colorAccent = lv_color_hex(COLOR_ACCENT_LIGHT);
    }

    // Apply background color to screen
    lv_obj_set_style_bg_color(lv_scr_act(), colorBg, 0);
}

// Button event callback
static void sendButtonCallback(lv_event_t *e) {
    lv_event_code_t code = lv_event_get_code(e);
    if (code == LV_EVENT_CLICKED) {
        Serial.println(F("[Button] Send button pressed!"));
        manualUplinkRequested = true;
    }
}

void initDisplay() {
    // Apply theme colors
    applyTheme();

    // Create battery label (top-right corner)
    if (SHOW_BATTERY_INDICATOR) {
        batteryLabel = lv_label_create(lv_scr_act());
        lv_obj_set_style_text_font(batteryLabel, &lv_font_montserrat_12, 0);
        lv_obj_set_style_text_color(batteryLabel, colorAccent, 0);
        lv_obj_align(batteryLabel, LV_ALIGN_TOP_RIGHT, -10, 6);
        lv_label_set_text(batteryLabel, "---%");
    }

    // Create status label (top)
    statusLabel = lv_label_create(lv_scr_act());
    lv_obj_set_style_text_font(statusLabel, &lv_font_montserrat_16, 0);
    lv_obj_set_style_text_color(statusLabel, colorText, 0);
    lv_obj_align(statusLabel, LV_ALIGN_TOP_MID, 0, 5);
    lv_label_set_text(statusLabel, "LiLoRa Starting...");

    // Create metrics label (center-top)
    metricsLabel = lv_label_create(lv_scr_act());
    lv_obj_set_style_text_font(metricsLabel, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(metricsLabel, colorText, 0);
    lv_obj_align(metricsLabel, LV_ALIGN_CENTER, 0, -45);
    lv_label_set_text(metricsLabel, "Initializing...");

    // Create countdown label (below metrics)
    countdownLabel = lv_label_create(lv_scr_act());
    lv_obj_set_style_text_font(countdownLabel, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_color(countdownLabel, colorAccent, 0);
    lv_obj_align(countdownLabel, LV_ALIGN_CENTER, 0, 0);
    lv_label_set_text(countdownLabel, "");

    // Create BLE/GPS status label (Phase 2)
    if (SHOW_BLE_STATUS) {
        bleGpsLabel = lv_label_create(lv_scr_act());
        lv_obj_set_style_text_font(bleGpsLabel, &lv_font_montserrat_12, 0);
        lv_obj_set_style_text_color(bleGpsLabel, colorText, 0);
        lv_obj_align(bleGpsLabel, LV_ALIGN_CENTER, 0, 25);
        lv_label_set_text(bleGpsLabel, "BLE: -- | GPS: --");
    }

    // Create send button (bottom)
    sendButton = lv_btn_create(lv_scr_act());
    lv_obj_set_size(sendButton, 140, 50);
    lv_obj_align(sendButton, LV_ALIGN_BOTTOM_MID, 0, -20);
    lv_obj_add_event_cb(sendButton, sendButtonCallback, LV_EVENT_CLICKED, NULL);

    // Style the button
    lv_obj_set_style_bg_color(sendButton, colorAccent, 0);
    lv_obj_set_style_bg_color(sendButton, lv_color_darken(colorAccent, 50), LV_STATE_PRESSED);

    // Button label
    lv_obj_t *btnLabel = lv_label_create(sendButton);
    lv_label_set_text(btnLabel, "SEND NOW");
    lv_obj_set_style_text_color(btnLabel, DARK_MODE ? lv_color_hex(0x000000) : lv_color_hex(0xFFFFFF), 0);
    lv_obj_center(btnLabel);

    // Initially disable button until joined
    lv_obj_add_state(sendButton, LV_STATE_DISABLED);
    lv_obj_set_style_bg_opa(sendButton, LV_OPA_50, LV_STATE_DISABLED);
}

void enableSendButton(bool enable) {
    if (enable) {
        lv_obj_clear_state(sendButton, LV_STATE_DISABLED);
    } else {
        lv_obj_add_state(sendButton, LV_STATE_DISABLED);
    }
}

void updateDisplay(const char* status, const char* metrics) {
    lv_label_set_text(statusLabel, status);
    if (metrics != nullptr) {
        lv_label_set_text(metricsLabel, metrics);
    }
    lv_timer_handler();
}

void updateCountdown(uint32_t secondsRemaining) {
    // Only update display at configured interval to save power
    static uint32_t lastDisplayedSeconds = 0xFFFFFFFF;

    // Calculate which "bucket" we're in based on refresh interval
    uint32_t displayBucket = secondsRemaining / DISPLAY_REFRESH_INTERVAL_SECONDS;
    uint32_t displaySeconds = displayBucket * DISPLAY_REFRESH_INTERVAL_SECONDS;

    // Also update when crossing into single digits for better UX
    if (secondsRemaining < DISPLAY_REFRESH_INTERVAL_SECONDS) {
        displaySeconds = secondsRemaining;
    }

    // Skip update if same displayed value (saves power by avoiding LCD writes)
    if (displaySeconds == lastDisplayedSeconds) return;
    lastDisplayedSeconds = displaySeconds;

    char countdownText[32];
    snprintf(countdownText, sizeof(countdownText), "Next TX: %lu s", displaySeconds);
    lv_label_set_text(countdownLabel, countdownText);
}

void updateDisplayMetrics() {
    char metricsText[128];
    snprintf(metricsText, sizeof(metricsText),
        "Uplinks: %lu  Downlinks: %lu\n"
        "RSSI: %d dBm  SNR: %.1f dB",
        uplinkCount, downlinkCount, lastRSSI, lastSNR);
    lv_label_set_text(metricsLabel, metricsText);
}

// Update BLE/GPS status on display (Phase 2)
void updateBleGpsStatus() {
    if (!SHOW_BLE_STATUS || bleGpsLabel == nullptr) return;

    char statusText[64];
    const char* bleStatus = isBleConnected() ? "Connected" : "Waiting";
    String gpsStatus = getGpsStatusString();

    snprintf(statusText, sizeof(statusText), "BLE: %s | GPS: %s",
             bleStatus, gpsStatus.c_str());
    lv_label_set_text(bleGpsLabel, statusText);
}

// Update battery indicator
void updateBatteryIndicator() {
    if (!SHOW_BATTERY_INDICATOR || batteryLabel == nullptr) return;

    static uint32_t lastBatteryUpdate = 0;
    if (millis() - lastBatteryUpdate < BATTERY_UPDATE_INTERVAL_MS) return;
    lastBatteryUpdate = millis();

    char batteryText[16];
    int batteryPercent = instance.pmu.getBatteryPercent();
    bool isCharging = instance.pmu.isCharging();
    bool isUsbConnected = instance.pmu.isVbusIn();

    if (batteryPercent < 0) {
        // Battery not connected or error reading
        snprintf(batteryText, sizeof(batteryText), "---%%");
    } else if (isCharging) {
        snprintf(batteryText, sizeof(batteryText), "%d%%+", batteryPercent);
    } else if (isUsbConnected) {
        snprintf(batteryText, sizeof(batteryText), "%d%%*", batteryPercent);
    } else {
        snprintf(batteryText, sizeof(batteryText), "%d%%", batteryPercent);
    }

    lv_label_set_text(batteryLabel, batteryText);

    // Log battery status periodically
    Serial.print(F("[Battery] "));
    Serial.print(batteryPercent);
    Serial.print(F("% | Voltage: "));
    Serial.print(instance.pmu.getBattVoltage());
    Serial.print(F("mV | Charging: "));
    Serial.println(isCharging ? "Yes" : "No");
}

// Process incoming BLE NMEA data (Phase 2)
void processBleData() {
    if (!ENABLE_BLE_GPS) return;

    // Handle BLE connection state changes
    updateBluetooth();

    // Process any complete NMEA sentences in the buffer
    String sentence;
    int sentencesProcessed = 0;
    const int maxSentencesPerLoop = 5;  // Limit to avoid blocking

    while (sentencesProcessed < maxSentencesPerLoop) {
        sentence = readNmeaSentence();
        if (sentence.length() == 0) break;

        processNmeaSentence(sentence);
        sentencesProcessed++;
    }

    // Update display periodically
    static uint32_t lastStatusUpdate = 0;
    if (millis() - lastStatusUpdate > 1000) {
        updateBleGpsStatus();
        lastStatusUpdate = millis();
    }
}

// =============================================================================
// Session Persistence Functions (Fixed - saves to NVS)
// =============================================================================

bool saveSession() {
    Serial.println(F("[Session] Saving session to NVS..."));

    // Save nonces
    uint8_t noncesBuffer[RADIOLIB_LORAWAN_NONCES_BUF_SIZE];
    uint8_t *persist = node.getBufferNonces();
    memcpy(noncesBuffer, persist, RADIOLIB_LORAWAN_NONCES_BUF_SIZE);
    store.putBytes("nonces", noncesBuffer, RADIOLIB_LORAWAN_NONCES_BUF_SIZE);

    // Save session to NVS (not RTC memory - survives power cycle!)
    persist = node.getBufferSession();
    memcpy(sessionBuffer, persist, RADIOLIB_LORAWAN_SESSION_BUF_SIZE);
    store.putBytes("session", sessionBuffer, RADIOLIB_LORAWAN_SESSION_BUF_SIZE);

    Serial.println(F("[Session] Session saved successfully"));
    return true;
}

bool restoreSession() {
    Serial.println(F("[Session] Checking for saved session..."));

    // Check if both nonces and session exist
    if (!store.isKey("nonces") || !store.isKey("session")) {
        Serial.println(F("[Session] No saved session found - fresh start"));
        return false;
    }

    Serial.println(F("[Session] Found saved session, attempting restore..."));

    // Restore nonces from NVS
    uint8_t noncesBuffer[RADIOLIB_LORAWAN_NONCES_BUF_SIZE];
    store.getBytes("nonces", noncesBuffer, RADIOLIB_LORAWAN_NONCES_BUF_SIZE);
    int state = node.setBufferNonces(noncesBuffer);
    if (state != RADIOLIB_ERR_NONE) {
        Serial.print(F("[Session] Failed to restore nonces: "));
        Serial.println(stateDecode(state));
        return false;
    }
    Serial.println(F("[Session] Nonces restored"));

    // Restore session from NVS
    store.getBytes("session", sessionBuffer, RADIOLIB_LORAWAN_SESSION_BUF_SIZE);
    state = node.setBufferSession(sessionBuffer);
    if (state != RADIOLIB_ERR_NONE) {
        Serial.print(F("[Session] Failed to restore session buffer: "));
        Serial.println(stateDecode(state));
        return false;
    }
    Serial.println(F("[Session] Session buffer restored"));

    // Activate the restored session
    state = node.activateOTAA();
    if (state == RADIOLIB_LORAWAN_SESSION_RESTORED) {
        Serial.println(F("[Session] Session restored and activated successfully!"));
        Serial.print(F("[Session] DevAddr: "));
        Serial.println((unsigned long)node.getDevAddr(), HEX);
        return true;
    }

    Serial.print(F("[Session] Session activation failed: "));
    Serial.println(stateDecode(state));
    return false;
}

void clearSession() {
    Serial.println(F("[Session] Clearing saved session..."));
    store.remove("nonces");
    store.remove("session");
    memset(sessionBuffer, 0, sizeof(sessionBuffer));
    Serial.println(F("[Session] Session cleared"));
}

// =============================================================================
// Light Sleep Functions
// =============================================================================

void enterLightSleep() {
    Serial.println(F("[Sleep] Entering light sleep..."));

    // Save current state to restore after wake
    LoRaWanState previousState = currentState;
    currentState = LORAWAN_SLEEPING;

    // Show sleep message on display
    updateDisplay("SLEEPING", "Press button to wake");
    lv_timer_handler();
    delay(500);  // Give time to see the message

    // Dim display smoothly
    instance.decrementBrightness(0);
    delay(100);

    // Stop BLE advertising before sleep
    if (ENABLE_BLE_GPS) {
        Serial.println(F("[Sleep] Stopping BLE advertising..."));
        BLEDevice::stopAdvertising();
    }

    // Enter light sleep - this blocks until wake-up
    // LilyGoLib handles: radio sleep, display sleep, PMU wake config
    Serial.println(F("[Sleep] Calling lightSleep()..."));
    instance.lightSleep(WAKEUP_SRC_POWER_KEY);

    // === CODE CONTINUES HERE AFTER WAKE-UP ===
    Serial.println(F("[Sleep] Woke up from light sleep!"));

    // Restore display brightness with smooth animation
    instance.incrementalBrightness(DEVICE_MAX_BRIGHTNESS_LEVEL);

    // Restart BLE advertising
    if (ENABLE_BLE_GPS) {
        Serial.println(F("[Sleep] Restarting BLE advertising..."));
        BLEDevice::startAdvertising();
    }

    // Mark GPS data as stale (may be outdated after sleep)
    gpsData.valid = false;

    // Restore previous state
    currentState = previousState;

    // Update display
    updateDisplay("ACTIVE", "Woke from sleep");
    updateDisplayMetrics();
    if (SHOW_BLE_STATUS) {
        updateBleGpsStatus();
    }
    updateBatteryIndicator();

    Serial.println(F("[Sleep] Sleep/wake cycle complete"));
}

// =============================================================================
// Physical Button Handling
// =============================================================================

void checkPhysicalButton() {
    // Process PMU events (power button is managed by AXP2101 PMU)
    instance.loop();

    // Check if sleep was requested via power button
    if (sleepRequested && ENABLE_LIGHT_SLEEP) {
        sleepRequested = false;

        // Only allow sleep when in normal operation states
        if (currentState == LORAWAN_UPLINK || currentState == LORAWAN_JOINED) {
            enterLightSleep();
        } else {
            Serial.println(F("[Sleep] Cannot enter sleep in current state"));
        }
    }
}

// =============================================================================
// LoRaWAN Join Functions
// =============================================================================

bool attemptJoin() {
    joinAttempts++;

    char statusText[64];
    snprintf(statusText, sizeof(statusText), "Joining... (%d/%d)", joinAttempts, MAX_JOIN_ATTEMPTS);
    updateDisplay(statusText, "Sending join request");

    Serial.println(F(""));
    Serial.print(F("[Join] Attempt "));
    Serial.print(joinAttempts);
    Serial.print(F(" of "));
    Serial.println(MAX_JOIN_ATTEMPTS);

    int state = node.activateOTAA();

    // Always save nonces after join attempt (successful or not)
    Serial.println(F("[Join] Saving nonces after join attempt"));
    uint8_t noncesBuffer[RADIOLIB_LORAWAN_NONCES_BUF_SIZE];
    uint8_t *persist = node.getBufferNonces();
    memcpy(noncesBuffer, persist, RADIOLIB_LORAWAN_NONCES_BUF_SIZE);
    store.putBytes("nonces", noncesBuffer, RADIOLIB_LORAWAN_NONCES_BUF_SIZE);

    if (state == RADIOLIB_LORAWAN_NEW_SESSION) {
        Serial.println(F("[Join] SUCCESS! New session established"));
        // Save full session on successful join
        saveSession();
        return true;
    }

    Serial.print(F("[Join] Failed: "));
    Serial.println(stateDecode(state));

    return false;
}

uint32_t calculateBackoffDelay() {
    // Exponential backoff: base_delay * 2^(attempt-1), capped at max_delay
    uint32_t delay = JOIN_RETRY_BASE_DELAY_MS * (1 << (joinAttempts - 1));
    if (delay > JOIN_RETRY_MAX_DELAY_MS) {
        delay = JOIN_RETRY_MAX_DELAY_MS;
    }
    return delay;
}

void handleJoining() {
    if (attemptJoin()) {
        currentState = LORAWAN_JOINED;
        updateDisplay("JOINED", "Configuring...");
        return;
    }

    if (joinAttempts >= MAX_JOIN_ATTEMPTS) {
        Serial.println(F("[Join] Max attempts reached - entering error state"));
        currentState = LORAWAN_ERROR;
        updateDisplay("JOIN FAILED", "Max attempts exceeded\nPower cycle to retry");
        return;
    }

    // Calculate backoff delay
    uint32_t backoffMs = calculateBackoffDelay();

    char statusText[64];
    snprintf(statusText, sizeof(statusText), "Join failed\nRetry in %lu s", backoffMs / 1000);
    updateDisplay("JOINING", statusText);

    Serial.print(F("[Join] Waiting "));
    Serial.print(backoffMs / 1000);
    Serial.println(F(" seconds before retry..."));

    // Wait with periodic display updates
    uint32_t endTime = millis() + backoffMs;
    while (millis() < endTime) {
        uint32_t remaining = (endTime - millis()) / 1000;
        snprintf(statusText, sizeof(statusText), "Retry in %lu s\nAttempt %d/%d",
                 remaining, joinAttempts + 1, MAX_JOIN_ATTEMPTS);
        updateDisplay("JOINING", statusText);
        lv_timer_handler();
        delay(1000);
    }
}

// =============================================================================
// LoRaWAN Configuration
// =============================================================================

void configureNode() {
    Serial.println(F(""));
    Serial.println(F("[Config] Configuring LoRaWAN node..."));

    // Print the DevAddr
    Serial.print(F("[Config] DevAddr: "));
    Serial.println((unsigned long)node.getDevAddr(), HEX);

    // Enable ADR (Adaptive Data Rate)
    node.setADR(true);
    Serial.println(F("[Config] ADR enabled"));

    // Set initial datarate (will be adjusted by ADR)
    node.setDatarate(5);
    Serial.println(F("[Config] Initial DR: 5"));

    // Disable firmware-side duty cycle tracking
    // The network server (ChirpStack/TTN) already enforces duty cycle limits
    // Firmware-side tracking causes issues after session restore because
    // RadioLib doesn't restore the duty cycle timer state from NVS
    node.setDutyCycle(false);
    Serial.println(F("[Config] Duty cycle tracking disabled (enforced by network server)"));

    // Enable dwell time limits (400ms for some regions)
    node.setDwellTime(true, 400);
    Serial.println(F("[Config] Dwell time enabled"));

    Serial.println(F("[Config] Configuration complete"));
    Serial.println(F(""));
}

// =============================================================================
// Uplink/Downlink Functions
// =============================================================================

bool canSendUplink() {
    // With firmware duty cycle disabled, always allow uplinks
    // Network server will enforce actual duty cycle limits
    // and reject/throttle if needed
    return true;
}

void doSendUplink() {
    Serial.println(F(""));
    Serial.println(F("[Uplink] Preparing uplink..."));

    updateDisplay("SENDING", "Transmitting...");
    enableSendButton(false);

    // Set battery level for network server (actual reading from PMU)
    // LoRaWAN battery level: 0=external power, 1-254=battery level, 255=unable to measure
    int batteryPercent = instance.pmu.getBatteryPercent();
    uint8_t battLevel;
    if (batteryPercent < 0) {
        battLevel = 255;  // Unable to measure
    } else if (instance.pmu.isVbusIn() && !instance.pmu.isCharging()) {
        battLevel = 0;    // External power (USB connected, not charging = full)
    } else {
        // Map 0-100% to 1-254 (LoRaWAN spec)
        battLevel = (uint8_t)(1 + (batteryPercent * 253 / 100));
    }
    node.setDeviceStatus(battLevel);

    // Generate GPS payload (Phase 2)
    // 13-byte binary format with lat, lon, alt, fix, hdop, sats
    uint8_t uplinkPayload[GPS_PAYLOAD_SIZE];
    bool hasValidGps = prepareGpsUplinkPayload(uplinkPayload);

    // Prepare for downlink
    uint8_t downlinkPayload[64];
    size_t downlinkSize = 0;

    LoRaWANEvent_t uplinkDetails;
    LoRaWANEvent_t downlinkDetails;

    uint32_t fCntUp = node.getFCntUp();
    Serial.print(F("[Uplink] Frame counter: "));
    Serial.println(fCntUp);

    // Request LinkCheck and DeviceTime on first uplink
    bool confirmed = false;
    if (fCntUp == 1) {
        Serial.println(F("[Uplink] Requesting LinkCheck and DeviceTime"));
        node.sendMacCommandReq(RADIOLIB_LORAWAN_MAC_LINK_CHECK);
        node.sendMacCommandReq(RADIOLIB_LORAWAN_MAC_DEVICE_TIME);
        confirmed = true;
    }

    // Send uplink and wait for downlink
    int16_t state = node.sendReceive(
        uplinkPayload, sizeof(uplinkPayload),
        UPLINK_FPORT,
        downlinkPayload, &downlinkSize,
        confirmed,
        &uplinkDetails, &downlinkDetails
    );

    if (state < RADIOLIB_ERR_NONE) {
        Serial.print(F("[Uplink] Error: "));
        Serial.println(stateDecode(state));
        updateDisplay("UPLINK ERROR", stateDecode(state).c_str());
        enableSendButton(true);

        // Still schedule next uplink
        nextUplinkTime = millis() + (UPLINK_INTERVAL_SECONDS * 1000);
        return;
    }

    uplinkCount++;
    Serial.println(F("[Uplink] Transmitted successfully"));

    // Notify phone via BLE about the transmission (for tracking failed deliveries)
    if (ENABLE_BLE_GPS && isBleConnected()) {
        char txNotify[128];
        // Format: TX,<frameCount>,<lat>,<lon>,<hasGps>
        // Example: TX,42,46.056900,14.505800,1
        snprintf(txNotify, sizeof(txNotify), "TX,%lu,%.6f,%.6f,%d\n",
                 fCntUp,
                 hasValidGps ? gpsData.latitude : 0.0,
                 hasValidGps ? gpsData.longitude : 0.0,
                 hasValidGps ? 1 : 0);
        bleSend(txNotify);
        Serial.print(F("[BLE] Sent TX notification: "));
        Serial.print(txNotify);
    }

    // Save session after successful uplink
    saveSession();

    // Handle downlink if received
    if (state > 0) {
        handleDownlink(downlinkPayload, downlinkSize, &downlinkDetails);
    } else {
        Serial.println(F("[Uplink] No downlink received"));
    }

    // Update metrics display
    lastRSSI = radio.getRSSI();
    lastSNR = radio.getSNR();
    updateDisplayMetrics();

    // Calculate next uplink time based on configured interval
    uint32_t delayMs = UPLINK_INTERVAL_SECONDS * 1000;

    nextUplinkTime = millis() + delayMs;

    Serial.print(F("[Uplink] Next uplink in "));
    Serial.print(delayMs / 1000);
    Serial.println(F(" seconds"));

    updateDisplay("ACTIVE", nullptr);
    updateCountdown(delayMs / 1000);
    enableSendButton(true);
}

void sendUplink() {
    // Check for manual uplink request (from watch button)
    if (manualUplinkRequested) {
        manualUplinkRequested = false;
        Serial.println(F("[Uplink] Manual uplink requested (watch button)"));

        if (canSendUplink()) {
            doSendUplink();
        } else {
            updateDisplay("WAIT", "Duty cycle limit\nTry again later");
            delay(2000);
            updateDisplay("ACTIVE", nullptr);
        }
        return;
    }

    // Check for phone uplink request (from BLE command)
    if (phoneUplinkRequested) {
        phoneUplinkRequested = false;

        // Debounce: Check if enough time has passed since last phone-triggered uplink
        uint32_t now = millis();
        if (now - lastPhoneUplinkTime < PHONE_UPLINK_MIN_INTERVAL_MS) {
            Serial.println(F("[Uplink] Phone request ignored - debounce"));
            // Notify phone about rate limit
            if (ENABLE_BLE_GPS && isBleConnected()) {
                bleSend("ERR,RATE_LIMIT\n");
            }
            return;
        }

        Serial.println(F("[Uplink] Phone uplink requested (BLE command)"));
        lastPhoneUplinkTime = now;

        if (canSendUplink()) {
            doSendUplink();
        } else {
            updateDisplay("WAIT", "Duty cycle limit\nTry again later");
            // Notify phone about duty cycle limit
            if (ENABLE_BLE_GPS && isBleConnected()) {
                bleSend("ERR,DUTY_CYCLE\n");
            }
            delay(2000);
            updateDisplay("ACTIVE", nullptr);
        }
        return;
    }

    // Check if it's time for automatic uplink
    if (millis() < nextUplinkTime) {
        // Update countdown display
        uint32_t remaining = (nextUplinkTime - millis()) / 1000;
        updateCountdown(remaining);
        return;
    }

    doSendUplink();
}

void handleDownlink(uint8_t* payload, size_t size, LoRaWANEvent_t* details) {
    downlinkCount++;

    Serial.println(F(""));
    Serial.println(F("[Downlink] Received downlink!"));

    // Log downlink metadata
    Serial.print(F("[Downlink] RSSI: "));
    Serial.print(radio.getRSSI());
    Serial.println(F(" dBm"));

    Serial.print(F("[Downlink] SNR: "));
    Serial.print(radio.getSNR());
    Serial.println(F(" dB"));

    Serial.print(F("[Downlink] Frequency: "));
    Serial.print(details->freq, 3);
    Serial.println(F(" MHz"));

    Serial.print(F("[Downlink] Datarate: "));
    Serial.println(details->datarate);

    Serial.print(F("[Downlink] Frame count: "));
    Serial.println(details->fCnt);

    Serial.print(F("[Downlink] Port: "));
    Serial.println(details->fPort);

    if (size > 0) {
        Serial.print(F("[Downlink] Payload ("));
        Serial.print(size);
        Serial.print(F(" bytes): "));
        arrayDump(payload, size);

        // TODO Phase 2: Handle downlink commands
        // Port 1: Configuration update
        // Port 2: Display message
    } else {
        Serial.println(F("[Downlink] MAC commands only (no payload)"));
    }

    // Check for LinkCheck response
    uint8_t margin = 0;
    uint8_t gwCnt = 0;
    if (node.getMacLinkCheckAns(&margin, &gwCnt) == RADIOLIB_ERR_NONE) {
        Serial.print(F("[Downlink] LinkCheck margin: "));
        Serial.println(margin);
        Serial.print(F("[Downlink] LinkCheck gateway count: "));
        Serial.println(gwCnt);
    }

    // Check for DeviceTime response
    uint32_t networkTime = 0;
    uint16_t milliseconds = 0;
    if (node.getMacDeviceTimeAns(&networkTime, &milliseconds, true) == RADIOLIB_ERR_NONE) {
        Serial.print(F("[Downlink] Network time (Unix): "));
        Serial.println(networkTime);
    }

    Serial.println(F(""));
}

// =============================================================================
// Setup
// =============================================================================

void setup() {
    Serial.begin(115200);
    delay(1000);

    Serial.println(F(""));
    Serial.println(F("========================================"));
    Serial.println(F("   LiLoRa Firmware v2.0 - Phase 2"));
    Serial.println(F("   LoRaWAN Range Tracking System"));
    Serial.println(F("   + Bluetooth GPS Integration"));
    Serial.println(F("========================================"));
    Serial.println(F(""));
    Serial.print(F("[Setup] Dark mode: "));
    Serial.println(DARK_MODE ? "ENABLED" : "DISABLED");

    // Initialize T-Watch hardware (LilyGoLib handles all pin config)
    Serial.println(F("[Setup] Initializing T-Watch hardware..."));
    instance.begin();

    // Initialize LVGL display
    Serial.println(F("[Setup] Initializing display..."));
    beginLvglHelper(instance);
    initDisplay();

    // Set brightness to maximum
    instance.setBrightness(DEVICE_MAX_BRIGHTNESS_LEVEL);

    updateDisplay("LiLoRa v2.0", "Initializing...");

    // Initialize Bluetooth (Phase 2)
    if (ENABLE_BLE_GPS) {
        Serial.println(F("[Setup] Initializing Bluetooth GPS receiver..."));
        initBluetooth();
        Serial.print(F("[Setup] BLE device name: "));
        Serial.println(getBleDeviceNameCached());
    }

    // Initialize LoRaWAN
    Serial.println(F("[Setup] Initializing LoRaWAN..."));
    node.beginOTAA(joinEUI, devEUI, nwkKey, appKey);

    Serial.print(F("[Setup] Region: EU868, DevEUI: "));
    Serial.println(devEUI, HEX);

    // Open NVS storage
    store.begin("lilora");

    // Register power button event handler for sleep/wake
    if (ENABLE_LIGHT_SLEEP) {
        Serial.println(F("[Setup] Registering power button handler for sleep..."));
        instance.onEvent([](DeviceEvent_t event, void *params, void *user_data) {
            if (event == POWER_EVENT) {
                PMUEventType_t pmuEvent = instance.getPMUEventType(params);
                if (pmuEvent == PMU_EVENT_KEY_CLICKED) {
                    Serial.println(F("[Button] Power button clicked - sleep requested"));
                    sleepRequested = true;
                }
            }
        }, POWER_EVENT, NULL);
    }

    // Try to restore previous session
    if (restoreSession()) {
        Serial.println(F("[Setup] Session restored - skipping join"));
        currentState = LORAWAN_JOINED;
        updateDisplay("SESSION RESTORED", "Configuring...");
    } else {
        Serial.println(F("[Setup] Starting fresh join"));
        currentState = LORAWAN_JOINING;
        updateDisplay("LiLoRa v1.1", "Starting join...");
    }

    Serial.println(F("[Setup] Initialization complete"));
    Serial.println(F(""));
}

// =============================================================================
// Main Loop
// =============================================================================

void loop() {
    // Process BLE GPS data (Phase 2)
    processBleData();

    // Handle phone uplink request when not in UPLINK state (error case)
    if (phoneUplinkRequested && currentState != LORAWAN_UPLINK) {
        phoneUplinkRequested = false;
        Serial.println(F("[Uplink] Phone request rejected - not joined"));
        if (ENABLE_BLE_GPS && isBleConnected()) {
            bleSend("ERR,NOT_JOINED\n");
        }
    }

    // Update battery indicator
    updateBatteryIndicator();

    switch (currentState) {
        case LORAWAN_IDLE:
            // Should not reach here after setup
            currentState = LORAWAN_JOINING;
            break;

        case LORAWAN_JOINING:
            handleJoining();
            break;

        case LORAWAN_JOINED:
            configureNode();
            currentState = LORAWAN_UPLINK;
            updateDisplay("ACTIVE", "Ready to transmit");
            updateDisplayMetrics();
            enableSendButton(true);
            break;

        case LORAWAN_UPLINK:
            sendUplink();
            break;

        case LORAWAN_DOWNLINK:
            // Downlink is handled within sendUplink()
            currentState = LORAWAN_UPLINK;
            break;

        case LORAWAN_SLEEPING:
            // Should not reach here - enterLightSleep() blocks until wake
            // If we somehow get here, restore to UPLINK state
            currentState = LORAWAN_UPLINK;
            break;

        case LORAWAN_ERROR:
            // Stay in error state - requires power cycle
            lv_timer_handler();
            delay(10000);
            break;
    }

    // Check physical button
    checkPhysicalButton();

    // Keep LVGL running
    lv_timer_handler();
    delay(5);
}
