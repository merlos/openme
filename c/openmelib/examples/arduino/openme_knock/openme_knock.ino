/**
 * openme_knock.ino — Arduino example for openmelib.
 *
 * Sends an openme SPA knock packet over UDP to open a firewall rule on the
 * openme server.  Tested on:
 *   - ESP32 (Arduino framework)
 *   - Arduino MKR WiFi 1010
 *   - Arduino Nano RP2040 Connect
 *
 * Setup:
 *  1. Install the openmelib library (Sketch → Include Library → Add .ZIP Library).
 *     Make sure vendor/monocypher/monocypher.h and .c are present
 *     (run vendor/monocypher/get_monocypher.sh first).
 *  2. Fill in the credentials below.
 *  3. Flash the board.
 *
 * openmelib docs: https://openme.merlos.org/
 */

// ─── Configuration — replace with your real values ───────────────────────────

const char *WIFI_SSID     = "YourWiFiSSID";
const char *WIFI_PASSWORD = "YourWiFiPassword";

// Server address and PORT
const char    *SERVER_HOST = "your.server.example.com";
const uint16_t SERVER_PORT = 54154;

// 32-byte Curve25519 public key of the openme server (base64-encoded).
// From `openme init` output on the server, or from the server config file.
const char *SERVER_PUBKEY_B64 = "REPLACE_WITH_32_BYTE_BASE64_SERVER_PUBLIC_KEY=";

// 32-byte Ed25519 seed of this client (base64-encoded).
// Generate with `openme keygen` on the CLI, then copy the private_key value.
// If you have a 64-byte key, use only the first 32 bytes (the seed portion).
const char *CLIENT_SEED_B64 = "REPLACE_WITH_32_BYTE_BASE64_CLIENT_SEED=";

// ─── NTP time configuration ───────────────────────────────────────────────────
// The server rejects knocks with timestamps outside its replay window (±60 s).
// On ESP32 use configTime() to sync NTP before the first knock.
// On other boards, set OPENME_UNIX_BASE_NS manually (see README) or use an RTC.

// ─── Includes ─────────────────────────────────────────────────────────────────

#if defined(ESP32) || defined(ARDUINO_ARCH_ESP32)
#  include <WiFi.h>
#  include <WiFiUdp.h>
#  include <time.h>          /* configTime / getLocalTime */
#elif defined(ARDUINO_SAMD_MKRWIFI1010) || defined(ARDUINO_NANO_RP2040_CONNECT)
#  include <WiFiNINA.h>
#  include <WiFiUdp.h>
#  include <NTPClient.h>     /* Install "NTPClient" from Library Manager */
#else
#  include <Ethernet.h>
#  include <EthernetUdp.h>
#  warning "Using Ethernet fallback — adjust for your shield."
#endif

#include <openmelib.h>       /* or #include "openmelib.h" */

// ─── Globals ──────────────────────────────────────────────────────────────────
static uint8_t g_server_pubkey[32];
static uint8_t g_client_seed[32];
static bool    g_keys_valid = false;

#if defined(ESP32) || defined(ARDUINO_ARCH_ESP32)
static WiFiUDP udp;
#elif defined(ARDUINO_SAMD_MKRWIFI1010) || defined(ARDUINO_NANO_RP2040_CONNECT)
static WiFiUDP udp;
static WiFiUDP ntpUDP;
static NTPClient timeClient(ntpUDP, "pool.ntp.org");
#endif

// ─── setup() ──────────────────────────────────────────────────────────────────
void setup() {
    Serial.begin(115200);
    while (!Serial) delay(10);

    Serial.println("[openme] Decoding keys …");
    int ns = openme_b64_decode(g_server_pubkey, 32, SERVER_PUBKEY_B64);
    int nc = openme_b64_decode(g_client_seed,   32, CLIENT_SEED_B64);
    if (ns != 32 || nc != 32) {
        Serial.println("[openme] ERROR: key decode failed — check CONFIG values.");
        return;
    }
    g_keys_valid = true;

    Serial.print("[openme] Connecting to WiFi …");
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 30) {
        delay(500); Serial.print("."); attempts++;
    }
    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("\n[openme] ERROR: WiFi connection failed.");
        return;
    }
    Serial.print("\n[openme] IP: "); Serial.println(WiFi.localIP());

#if defined(ESP32) || defined(ARDUINO_ARCH_ESP32)
    // Sync time via NTP (required for valid timestamps)
    configTime(0, 0, "pool.ntp.org", "time.nist.gov");
    Serial.print("[openme] Syncing time");
    struct tm tm_info;
    attempts = 0;
    while (!getLocalTime(&tm_info) && attempts < 20) {
        delay(500); Serial.print("."); attempts++;
    }
    Serial.println();
    if (attempts >= 20) {
        Serial.println("[openme] WARNING: NTP sync failed — knock may be rejected.");
    }
#elif defined(ARDUINO_SAMD_MKRWIFI1010) || defined(ARDUINO_NANO_RP2040_CONNECT)
    timeClient.begin();
    timeClient.update();
    // Provide NTP epoch (seconds) as base time for openme_now_ns()
    openme_set_base_time_ns((int64_t)timeClient.getEpochTime() * 1000000000LL
                            - (int64_t)millis() * 1000000LL);
#endif

    udp.begin(0); // bind to any local port for sending
    Serial.println("[openme] Ready. Will knock once in loop().");
}

// ─── loop() ───────────────────────────────────────────────────────────────────
void loop() {
    static bool knocked = false;
    if (!knocked && g_keys_valid) {
        knocked = true;
        sendKnock();
    }
    delay(5000);
}

// ─── sendKnock() ──────────────────────────────────────────────────────────────
void sendKnock() {
    Serial.printf("[openme] Sending knock to %s:%u …\n", SERVER_HOST, SERVER_PORT);

    // Build the 165-byte packet
    uint8_t packet[OPENME_PACKET_SIZE];
    int rc = openme_knock_packet(packet, g_server_pubkey, g_client_seed, NULL);
    if (rc != OPENME_OK) {
        Serial.printf("[openme] ERROR: openme_knock_packet returned %d\n", rc);
        return;
    }

    // Send via WiFiUDP
    if (!udp.beginPacket(SERVER_HOST, SERVER_PORT)) {
        Serial.println("[openme] ERROR: beginPacket failed (DNS / network issue).");
        return;
    }
    udp.write(packet, OPENME_PACKET_SIZE);
    if (udp.endPacket()) {
        Serial.println("[openme] Knock sent! Firewall should open within ~1 s.");
    } else {
        Serial.println("[openme] ERROR: endPacket failed.");
    }
}
