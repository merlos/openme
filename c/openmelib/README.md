# openmelib — C client library for the openme knock protocol

Pure C99 implementation of the [openme](https://openme.merlos.org/) SPA
(Single Packet Authentication) knock protocol.  Designed for maximum
portability: from Linux/macOS/Windows desktops down to ESP32 and Arduino boards.

## Platform support

| Platform | Compiler | RNG | Time | UDP send |
|----------|----------|-----|------|----------|
| Linux | GCC / Clang | `getrandom()` | `clock_gettime` | POSIX sockets |
| macOS | Clang / GCC | `arc4random_buf` | `clock_gettime` | POSIX sockets |
| Windows | MSVC / MinGW | `BCryptGenRandom` | `GetSystemTimeAsFileTime` | Winsock2 |
| ESP32 (Arduino) | xtensa-gcc | `esp_fill_random` | NTP via `configTime` | `WiFiUDP` |
| ESP32 (IDF) | xtensa-gcc | `esp_fill_random` | SNTP | lwIP sockets |
| Arduino MKR/Nano | arm-none-eabi | hardware TRNG | NTPClient | `WiFiUDP` |
| Bare-metal MCU | any C99 | **user hook** | **user hook** | user-provided |

The packet-construction core (`openme_build_packet`) makes **zero** OS calls —
it is portable to any platform where you can provide 32 random bytes and a
Unix nanosecond timestamp.

## Crypto stack

| Step | Algorithm | Implementation |
|------|-----------|----------------|
| ECDH | X25519 (Curve25519) | Monocypher 4 |
| KDF | HKDF-SHA-256 (RFC 5869) | bundled SHA-256 |
| AEAD | ChaCha20-Poly1305 | Monocypher 4 |
| Signature | Ed25519 | Monocypher 4 |

## Wire format

```
 0       1      33      45                   101                   165
 ┌───────┬──────┬───────┬─────────────────────┬─────────────────────┐
 │version│ephem │ nonce │     ciphertext      │    ed25519_sig      │
 │ 1 B   │32 B  │12 B   │      56 B           │      64 B           │
 └───────┴──────┴───────┴─────────────────────┴─────────────────────┘
 ◄─────────────── signed portion (101 B) ──────────────────────────►
```

Full protocol specification: <https://openme.merlos.org/docs/protocol/>

---

## Prerequisites — Monocypher

openmelib uses **Monocypher 4** for the asymmetric and symmetric crypto
primitives.  You must provide `monocypher.h` and `monocypher.c` before
building.

### Quick fetch

```sh
cd c/openmelib/vendor/monocypher
./get_monocypher.sh        # downloads 4.0.2 from monocypher.org
```

---

## Building — Desktop (CMake)

```sh
cd c/openmelib
mkdir build && cd build

# Monocypher will be downloaded automatically via FetchContent:
cmake .. -DOPENME_FETCH_MONOCYPHER=ON -DOPENME_BUILD_EXAMPLES=ON
cmake --build .

# Run the example:
./openme_knock_example my.server.com 54154 "<server_pubkey_b64>" "<client_seed_b64>"
```

### Manual / vendored Monocypher

```sh
cmake .. -DOPENME_FETCH_MONOCYPHER=OFF   # uses vendor/monocypher/
```

---

## Building — ESP32 with ESP-IDF

1. Run `get_monocypher.sh` to populate `vendor/monocypher/`.
2. Copy (or symlink) the `c/openmelib/` directory into your IDF project's
   `components/` folder.
3. In your component's `CMakeLists.txt` use `CMakeLists_idf.txt` as a guide
   (rename it to `CMakeLists.txt`).
4. Build normally: `idf.py build`.

See `examples/esp32_idf/` for a complete standalone project.

---

## Building — Arduino

1. Run `get_monocypher.sh` so that `src/monocypher.h` and `src/monocypher.c`
   are populated.
2. In the Arduino IDE: **Sketch → Include Library → Add .ZIP Library …**
   and select the `c/openmelib/` directory (zipped).
3. Open `examples/arduino/openme_knock/openme_knock.ino`, fill in your
   credentials, and upload.

> **Time on Arduino:** The server rejects packets outside its replay window
> (default ±60 s).  Use NTP or an RTC to set the clock before knocking.
> On ESP32 (Arduino) use `configTime(0, 0, "pool.ntp.org")`.
> On other boards call `openme_set_base_time_ns()` with a Unix-nanosecond
> epoch obtained from NTPClient.

---

## API summary

```c
#include "openmelib.h"

/* High-level: build + send in one call (POSIX / Windows / lwIP) */
int openme_send_knock(
    const char *host, uint16_t port,
    const uint8_t server_pubkey[32],
    const uint8_t client_seed[32],
    const uint8_t target_ip[16]);  /* NULL → use source IP */

/* Mid-level: build packet, send yourself (Arduino WiFiUDP etc.) */
int openme_knock_packet(
    uint8_t out[OPENME_PACKET_SIZE],
    const uint8_t server_pubkey[32],
    const uint8_t client_seed[32],
    const uint8_t target_ip[16]);

/* Low-level: fully deterministic, supply all entropy (bare-metal) */
int openme_build_packet(
    uint8_t out[OPENME_PACKET_SIZE],
    const uint8_t server_pubkey[32],
    const uint8_t client_seed[32],
    int64_t timestamp_ns,
    const uint8_t ephem_secret[32],
    const uint8_t aead_nonce[12],
    const uint8_t random_nonce[16],
    const uint8_t target_ip[16]);

/* Key decoding helper */
int openme_b64_decode(uint8_t *out, size_t out_len, const char *b64);

/* Arduino-only: set the base timestamp for openme_now_ns() */
void openme_set_base_time_ns(int64_t unix_ns);
```

Return values: `OPENME_OK` (0) on success, negative on error.

---

## Bare-metal / custom platform

When none of the detected platforms match, you must supply two functions:

```c
// Provide cryptographically secure random bytes.
void openme_random_bytes(uint8_t *buf, size_t len) { /* ... */ }

// Return current Unix time as nanoseconds (int64).
int64_t openme_now_ns(void) { /* ... */ }
```

Compile with `-DOPENME_CUSTOM_RNG -DOPENME_CUSTOM_TIME` to suppress the
built-in (stub/warning) implementations.

---

## File layout

```
c/openmelib/
├── include/
│   └── openmelib.h          Public API
├── src/
│   ├── openmelib.c          Implementation
│   ├── openmelib.h          Arduino re-export shim
│   ├── openme_sha256.h      Internal SHA-256 / HMAC / HKDF
│   └── openme_sha256.c
├── vendor/monocypher/
│   ├── get_monocypher.sh    Fetches monocypher.h + .c
│   ├── monocypher.h         Populated by get_monocypher.sh
│   └── monocypher.c
├── examples/
│   ├── desktop/             CMake + C example (Linux/macOS/Windows)
│   ├── arduino/openme_knock/   Arduino sketch (ESP32/MKR/RP2040)
│   └── esp32_idf/           Full ESP-IDF project
├── CMakeLists.txt           CMake library build
├── CMakeLists_idf.txt       ESP-IDF component registration
├── idf_component.yml        IDF Component Manager manifest
└── library.properties       Arduino Library Manager metadata
```

---

## License

openmelib is released under the same license as the openme project.  
Monocypher is released under the [2-Clause BSD License](https://monocypher.org/licence).
