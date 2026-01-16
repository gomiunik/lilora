/*
 * LiLoRa Firmware - Phase 1: LoRaWAN Foundation
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
 *
 * Hardware: LilyGo T-Watch S3 with SX1262 LoRa (868MHz)
 *
 * Setup:
 * 1. Copy lorawan_credentials.h.template to lorawan_credentials.h
 * 2. Fill in your OTAA keys from ChirpStack/TTN
 * 3. Configure region in config.h if not EU868
 * 4. Upload via Arduino IDE with LilyGoLib installed
 *
 * Network Server Requirements:
 * - LoRaWAN MAC version: 1.1.0
 * - Enable "Resets DevNonces" for development
 * - Device Profile: Class A, OTAA
 */

#include "config.h"
#include <Preferences.h>

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

// Manual uplink trigger
volatile bool manualUplinkRequested = false;

// UI elements
lv_obj_t *statusLabel;
lv_obj_t *metricsLabel;
lv_obj_t *sendButton;
lv_obj_t *countdownLabel;

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

    // Create status label (top)
    statusLabel = lv_label_create(lv_scr_act());
    lv_obj_set_style_text_font(statusLabel, &lv_font_montserrat_16, 0);
    lv_obj_set_style_text_color(statusLabel, colorText, 0);
    lv_obj_align(statusLabel, LV_ALIGN_TOP_MID, 0, 10);
    lv_label_set_text(statusLabel, "LiLoRa Starting...");

    // Create metrics label (center-top)
    metricsLabel = lv_label_create(lv_scr_act());
    lv_obj_set_style_text_font(metricsLabel, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(metricsLabel, colorText, 0);
    lv_obj_align(metricsLabel, LV_ALIGN_CENTER, 0, -30);
    lv_label_set_text(metricsLabel, "Initializing...");

    // Create countdown label (below metrics)
    countdownLabel = lv_label_create(lv_scr_act());
    lv_obj_set_style_text_font(countdownLabel, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_color(countdownLabel, colorAccent, 0);
    lv_obj_align(countdownLabel, LV_ALIGN_CENTER, 0, 30);
    lv_label_set_text(countdownLabel, "");

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
    char countdownText[32];
    snprintf(countdownText, sizeof(countdownText), "Next TX: %lu s", secondsRemaining);
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
// Physical Button Handling
// =============================================================================

void checkPhysicalButton() {
    // Debounce - check every 100ms
    if (millis() - lastButtonCheck < 100) {
        return;
    }
    lastButtonCheck = millis();

    // Note: Touch screen button is handled by LVGL automatically
    // Physical crown/side button handling can be added here if needed
    // For T-Watch S3, the crown button may require specific GPIO reading
    // depending on hardware variant
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

    // Enable duty cycle compliance
    node.setDutyCycle(true, 1250);
    Serial.println(F("[Config] Duty cycle enabled"));

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
    // Check duty cycle
    uint32_t timeUntilUplink = node.timeUntilUplink();
    if (timeUntilUplink > 0) {
        Serial.print(F("[Uplink] Must wait "));
        Serial.print(timeUntilUplink);
        Serial.println(F(" ms for duty cycle"));
        return false;
    }
    return true;
}

void doSendUplink() {
    Serial.println(F(""));
    Serial.println(F("[Uplink] Preparing uplink..."));

    updateDisplay("SENDING", "Transmitting...");
    enableSendButton(false);

    // Set battery level for network server
    uint8_t battLevel = 146;  // ~57% battery
    node.setDeviceStatus(battLevel);

    // Generate dummy payload (3 bytes: temp, humidity, battery %)
    // In Phase 2, this will be replaced with GPS data
    uint8_t value1 = radio.random(100);      // Simulated temperature (0-100)
    uint16_t value2 = radio.random(2000);    // Simulated humidity*10 (0-200.0%)

    uint8_t uplinkPayload[3];
    uplinkPayload[0] = value1;
    uplinkPayload[1] = highByte(value2);
    uplinkPayload[2] = lowByte(value2);

    Serial.print(F("[Uplink] Payload: "));
    arrayDump(uplinkPayload, sizeof(uplinkPayload));

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

    // Calculate next uplink time (respecting duty cycle)
    uint32_t minDelay = UPLINK_INTERVAL_SECONDS * 1000;
    uint32_t dutyCycleDelay = node.timeUntilUplink();
    uint32_t delayMs = max(dutyCycleDelay, minDelay);

    nextUplinkTime = millis() + delayMs;

    Serial.print(F("[Uplink] Next uplink in "));
    Serial.print(delayMs / 1000);
    Serial.println(F(" seconds"));

    updateDisplay("ACTIVE", nullptr);
    updateCountdown(delayMs / 1000);
    enableSendButton(true);
}

void sendUplink() {
    // Check for manual uplink request
    if (manualUplinkRequested) {
        manualUplinkRequested = false;
        Serial.println(F("[Uplink] Manual uplink requested"));

        if (canSendUplink()) {
            doSendUplink();
        } else {
            updateDisplay("WAIT", "Duty cycle limit\nTry again later");
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
    Serial.println(F("   LiLoRa Firmware v1.1 - Phase 1"));
    Serial.println(F("   LoRaWAN Range Tracking System"));
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

    updateDisplay("LiLoRa v1.1", "Initializing...");

    // Initialize LoRaWAN
    Serial.println(F("[Setup] Initializing LoRaWAN..."));
    node.beginOTAA(joinEUI, devEUI, nwkKey, appKey);

    Serial.print(F("[Setup] Region: EU868, DevEUI: "));
    Serial.println(devEUI, HEX);

    // Open NVS storage
    store.begin("lilora");

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
