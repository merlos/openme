/**
 * main.c — ESP32 ESP-IDF example for openmelib.
 *
 * Connects to Wi-Fi, syncs time via SNTP, then sends an openme SPA knock
 * every 60 seconds.
 *
 * Build:
 *   idf.py set-target esp32   # or esp32s3, esp32c3, etc.
 *   idf.py build flash monitor
 *
 * Configuration:
 *   idf.py menuconfig → Example Configuration
 *   (or edit sdkconfig.defaults / main/Kconfig.projbuild)
 */

#include <string.h>
#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_log.h"
#include "nvs_flash.h"
#include "esp_netif.h"
#include "esp_sntp.h"

#include "openmelib.h"

static const char *TAG = "openme";

/* ─── User configuration ─────────────────────────────────────────────────────
 * Override these via menuconfig (Kconfig) or hardcode for quick testing.   */

#ifndef CONFIG_OPENME_WIFI_SSID
#  define CONFIG_OPENME_WIFI_SSID     "YourWiFiSSID"
#endif
#ifndef CONFIG_OPENME_WIFI_PASS
#  define CONFIG_OPENME_WIFI_PASS     "YourWiFiPassword"
#endif
#ifndef CONFIG_OPENME_SERVER_HOST
#  define CONFIG_OPENME_SERVER_HOST   "your.server.example.com"
#endif
#ifndef CONFIG_OPENME_SERVER_PORT
#  define CONFIG_OPENME_SERVER_PORT   54154
#endif

/* Base64-encoded keys — replace with real values or load from NVS */
static const char SERVER_PUBKEY_B64[] = "REPLACE_WITH_32_BYTE_BASE64_SERVER_PUBLIC_KEY=";
static const char CLIENT_SEED_B64[]   = "REPLACE_WITH_32_BYTE_BASE64_CLIENT_SEED=";

/* ─── Internal state ─────────────────────────────────────────────────────── */

static uint8_t       g_server_pubkey[32];
static uint8_t       g_client_seed[32];
static EventGroupHandle_t s_wifi_event_group;
#define WIFI_CONNECTED_BIT BIT0

/* ─── Wi-Fi event handler ────────────────────────────────────────────────── */

static void wifi_event_handler(void *arg, esp_event_base_t base,
                                int32_t id, void *data)
{
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
        esp_wifi_connect();
    } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        ESP_LOGW(TAG, "Wi-Fi disconnected; retrying…");
        esp_wifi_connect();
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t *e = (ip_event_got_ip_t *)data;
        ESP_LOGI(TAG, "IP: " IPSTR, IP2STR(&e->ip_info.ip));
        xEventGroupSetBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
    }
}

static void wifi_init(void) {
    s_wifi_event_group = xEventGroupCreate();
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    esp_event_handler_instance_t h1, h2;
    ESP_ERROR_CHECK(esp_event_handler_instance_register(
        WIFI_EVENT, ESP_EVENT_ANY_ID,  wifi_event_handler, NULL, &h1));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(
        IP_EVENT,   IP_EVENT_STA_GOT_IP, wifi_event_handler, NULL, &h2));

    wifi_config_t wcfg = {
        .sta = {
            .ssid     = CONFIG_OPENME_WIFI_SSID,
            .password = CONFIG_OPENME_WIFI_PASS,
            .threshold.authmode = WIFI_AUTH_WPA2_PSK,
        },
    };
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wcfg));
    ESP_ERROR_CHECK(esp_wifi_start());

    xEventGroupWaitBits(s_wifi_event_group, WIFI_CONNECTED_BIT,
                        pdFALSE, pdTRUE, portMAX_DELAY);
}

/* ─── SNTP ───────────────────────────────────────────────────────────────── */

static void sntp_sync(void) {
    esp_sntp_setoperatingmode(SNTP_OPMODE_POLL);
    esp_sntp_setservername(0, "pool.ntp.org");
    esp_sntp_init();

    time_t now = 0;
    struct tm tm_info = {0};
    int retries = 0;
    while (tm_info.tm_year < (2020 - 1900) && retries++ < 20) {
        ESP_LOGI(TAG, "Waiting for SNTP…");
        vTaskDelay(pdMS_TO_TICKS(2000));
        time(&now);
        localtime_r(&now, &tm_info);
    }
    char buf[64];
    strftime(buf, sizeof(buf), "%c", &tm_info);
    ESP_LOGI(TAG, "Time synced: %s", buf);
}

/* ─── Knock task ─────────────────────────────────────────────────────────── */

static void knock_task(void *arg) {
    (void)arg;
    ESP_LOGI(TAG, "Knock task started");

    while (1) {
        uint8_t packet[OPENME_PACKET_SIZE];
        int rc = openme_knock_packet(packet, g_server_pubkey, g_client_seed, NULL);
        if (rc != OPENME_OK) {
            ESP_LOGE(TAG, "openme_knock_packet failed: %d", rc);
            vTaskDelay(pdMS_TO_TICKS(5000));
            continue;
        }

        /* Send via POSIX UDP socket (lwIP under the hood on ESP-IDF) */
        rc = openme_send_knock(
            CONFIG_OPENME_SERVER_HOST,
            CONFIG_OPENME_SERVER_PORT,
            g_server_pubkey,
            g_client_seed,
            NULL   /* NULL → use knock source IP */
        );
        if (rc == OPENME_OK) {
            ESP_LOGI(TAG, "Knock sent to %s:%d",
                     CONFIG_OPENME_SERVER_HOST, CONFIG_OPENME_SERVER_PORT);
        } else {
            ESP_LOGE(TAG, "Send failed: %d", rc);
        }

        /* Knock again after 30 s (before the server-side timeout expires) */
        vTaskDelay(pdMS_TO_TICKS(30000));
    }
}

/* ─── app_main ───────────────────────────────────────────────────────────── */

void app_main(void) {
    /* Decode keys */
    int ns = openme_b64_decode(g_server_pubkey, 32, SERVER_PUBKEY_B64);
    int nc = openme_b64_decode(g_client_seed,   32, CLIENT_SEED_B64);
    if (ns != 32 || nc != 32) {
        ESP_LOGE(TAG, "Key decode failed: server=%d client=%d", ns, nc);
        return;
    }

    ESP_ERROR_CHECK(nvs_flash_init());
    wifi_init();
    sntp_sync();

    xTaskCreate(knock_task, "knock_task", 4096, NULL, 5, NULL);
}
