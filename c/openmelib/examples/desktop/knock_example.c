/**
 * knock_example.c — Desktop example for openmelib.
 *
 * Build:
 *   mkdir build && cd build
 *   cmake .. -DOPENME_BUILD_EXAMPLES=ON
 *   cmake --build .
 *   ./openme_knock_example <server_host> <server_port> <server_pubkey_b64> <client_seed_b64>
 *
 * Example:
 *   ./openme_knock_example my.server.example.com 54154 \
 *       "Szh...base64...key==" \
 *       "abc...base64...seed=="
 */

#include "openmelib.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

static void usage(const char *prog) {
    fprintf(stderr,
        "Usage: %s <host> <port> <server_pubkey_base64> <client_seed_base64>\n"
        "\n"
        "  host               Hostname or IP of the openme server\n"
        "  port               UDP port (default: 54154)\n"
        "  server_pubkey_b64  Base64-encoded 32-byte Curve25519 public key\n"
        "  client_seed_b64    Base64-encoded 32-byte Ed25519 seed\n",
        prog);
}

int main(int argc, char *argv[]) {
    if (argc < 5) { usage(argv[0]); return 1; }

    const char   *host     = argv[1];
    unsigned long port_ul  = strtoul(argv[2], NULL, 10);
    const char   *srv_b64  = argv[3];
    const char   *cli_b64  = argv[4];

    if (port_ul == 0 || port_ul > 65535) {
        fprintf(stderr, "Error: invalid port number.\n");
        return 1;
    }
    uint16_t port = (uint16_t)port_ul;

    /* Decode server public key */
    uint8_t server_pubkey[32];
    int n = openme_b64_decode(server_pubkey, sizeof(server_pubkey), srv_b64);
    if (n != 32) {
        fprintf(stderr, "Error: server public key must decode to exactly 32 bytes (got %d).\n", n);
        return 1;
    }

    /* Decode client Ed25519 seed (32 bytes, or 64-byte seed+pub — use first 32) */
    uint8_t client_buf[64];
    int m = openme_b64_decode(client_buf, sizeof(client_buf), cli_b64);
    if (m != 32 && m != 64) {
        fprintf(stderr, "Error: client key must decode to 32 or 64 bytes (got %d).\n", m);
        return 1;
    }
    uint8_t *client_seed = client_buf; /* first 32 bytes = seed */

    /* Send knock */
    printf("Sending knock to %s:%u …\n", host, (unsigned)port);
    int rc = openme_send_knock(host, port, server_pubkey, client_seed, NULL);

    if (rc == OPENME_OK) {
        printf("Knock sent successfully.\n");
        printf("The server will open your firewall for ~30 seconds.\n");
        return 0;
    } else {
        fprintf(stderr, "Error: openme_send_knock returned %d.\n", rc);
        return 1;
    }
}
