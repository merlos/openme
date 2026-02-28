# GitHub Copilot Instructions — openme

This file teaches GitHub Copilot (and any AI coding assistant) how the openme
project is structured and what conventions to follow.

**Keep this file up to date.**  
Whenever you add a new platform, rename a module, change a protocol constant,
add a documentation section, or change a testing convention, update the
relevant section(s) here.

---

## Table of Contents

1. [What openme does](#1-what-openme-does)
2. [Repository layout](#2-repository-layout)
3. [Protocol — the 165-byte knock packet](#3-protocol--the-165-byte-knock-packet)
4. [Naming conventions](#4-naming-conventions)
5. [Documentation standards](#5-documentation-standards)
6. [Security & input validation](#6-security--input-validation)
7. [Unit testing](#7-unit-testing)
8. [Code style & DRY principles](#8-code-style--dry-principles)
9. [GitHub Actions CI](#9-github-actions-ci)
10. [Adding a new platform](#10-adding-a-new-platform)

---

## 1. What openme does

openme is a **Single Packet Authentication (SPA)** system.

```
Client                              Server  (every port looks CLOSED to scanners)
  │                                     │
  │──── 165-byte encrypted UDP ────────>│  verify Ed25519 signature
  │                                     │  decrypt ChaCha20-Poly1305 payload
  │                                     │  open firewall rule for client IP (30 s)
  │<══════════ SSH / HTTPS / etc. ══════│
```

The server never responds to unauthorized connections.  
The knock packet looks like random noise — there is no banner, no handshake,
nothing to probe.

Reference documentation: <https://openme.merlos.org/docs/>

---

## 2. Repository layout

```
openme/
├── .github/
│   ├── copilot-instructions.md   ← this file
│   └── workflows/
│       ├── cli.yml               Go test + cross-compile
│       ├── docs.yml              Quarto site build + OpenMeKit DocC reference
│       ├── openmelib.yml         C library multi-platform CI
│       ├── apple-openmekit.yml   Swift SPM tests (macOS 14 + 15)
│       ├── apple-apps.yml        Xcode build + unit tests (iOS, macOS, watchOS)
│       ├── android.yml           Gradle JVM unit tests + AAR build
│       └── windows.yml           .NET xUnit tests + WPF build
│
├── cli/                          Go server daemon & cross-platform CLI
│   ├── cmd/openme/               main() entry point
│   ├── internal/
│   │   ├── client/               outbound knock logic
│   │   ├── config/               YAML config parsing & validation
│   │   ├── crypto/               packet construction (Go canonical implementation)
│   │   ├── firewall/             nft + iptables backends
│   │   ├── qr/                   QR code generation / import
│   │   └── server/               UDP listener, replay window, rule manager
│   └── pkg/protocol/             shared protocol constants (port, version, sizes)
│
├── apple/
│   ├── OpenMeKit/                Swift package — shared SPA library
│   │   ├── Sources/OpenMeKit/
│   │   │   ├── KnockService.swift          packet build + NWConnection send
│   │   │   ├── KnockManager.swift          profile lifecycle
│   │   │   ├── ClientConfig.swift          Codable profile model
│   │   │   └── ProfileStore.swift          persistence
│   │   └── Tests/OpenMeKitTests/
│   │       ├── KnockServiceTests.swift     packet-size, versoin, key validation
│   │       └── ProfileParserTests.swift    YAML round-trip, error paths
│   ├── openme-ios/               iOS SwiftUI app
│   ├── openme-macos/             macOS SwiftUI app (menu-bar)
│   ├── openme-watch/             watchOS companion app
│   └── openme-widget/            WidgetKit home-screen widget
│
├── android/
│   └── openmekit/src/main/kotlin/org/merlos/openmekit/
│       ├── KnockService.kt       packet build + DatagramSocket send
│       ├── KnockManager.kt
│       ├── Profile.kt
│       └── ProfileStore.kt
│
├── windows/
│   ├── OpenMeKit/                .NET 8 library (C#)
│   │   ├── KnockService.cs       packet build + UdpClient send
│   │   ├── KnockManager.cs
│   │   ├── Profile.cs
│   │   └── ProfileStore.cs
│   ├── openme-windows/           WPF system-tray application
│   └── OpenMeKit.Tests/          xUnit tests
│
├── c/
│   └── openmelib/                Pure C99 SPA library (ESP32, Arduino, desktop)
│       ├── include/openmelib.h   Public API
│       ├── src/
│       │   ├── openmelib.c       Platform-adaptive implementation
│       │   ├── openme_sha256.h/c Bundled SHA-256 / HMAC / HKDF
│       │   └── monocypher.h      (populated by get_monocypher.sh)
│       ├── vendor/monocypher/    Monocypher 4 sources
│       ├── examples/
│       │   ├── desktop/          POSIX / Windows CLI example
│       │   ├── arduino/          Arduino (.ino) sketch
│       │   └── esp32_idf/        ESP-IDF FreeRTOS project
│       ├── CMakeLists.txt        Desktop / cross-compile build
│       ├── CMakeLists_idf.txt    ESP-IDF component registration
│       ├── idf_component.yml     IDF Component Manager manifest
│       └── library.properties   Arduino Library Manager metadata
│
└── docs/                         Quarto documentation site
    ├── _quarto.yml
    ├── index.qmd
    ├── protocol/                 Wire format, cryptography, handshake, replay
    ├── configuration/            Server config, client config, firewall, NAT
    ├── getting-started/          Step-by-step setup guides
    ├── security/                 Threat model, key management
    ├── api/                      Go pkgsite auto-generated reference
    ├── android-sdk/              Kotlin/Android KDoc reference
    └── faq/
```

The `docs/` site is the single source of truth for the **protocol specification**.
Platform implementations follow the spec; they do not define it.

---

## 3. Protocol — the 165-byte knock packet

Every platform **must** produce identical bytes for the same inputs.  
Canonical spec: [docs/protocol/packet-format.qmd](../docs/protocol/packet-format.qmd)

### Outer packet layout

```
Offset  Size  Field
     0     1  version          Protocol version — currently 0x01
     1    32  ephemeral_pubkey Client's ephemeral Curve25519 public key (per knock)
    33    12  nonce            ChaCha20-Poly1305 nonce (random, per knock)
    45    56  ciphertext       Encrypted 40-byte plaintext + 16-byte Poly1305 tag
   101    64  ed25519_sig      Ed25519 signature over bytes 0–100 (signed portion)
```

Total: **165 bytes**.  Packets of any other size must be silently discarded.

### Inner plaintext (40 bytes, after AEAD decryption)

```
Offset  Size  Field
     0     8  timestamp_ns   Unix nanoseconds, big-endian int64
     8    16  random_nonce   128-bit CSPRNG — uniqueness / replay protection
    24    16  target_ip      IPv6 (or IPv4-mapped). All-zeros = use source IP of knock
```

### Crypto stack

| Step | Algorithm | Key / Output |
|------|-----------|--------------|
| ECDH | X25519 (Curve25519) | ephemeral_priv + server_static_pub → 32-byte shared secret |
| KDF  | HKDF-SHA-256 (RFC 5869) | ikm=shared_secret, salt=∅, info=`"openme-v1-chacha20poly1305"` → 32-byte key |
| AEAD | ChaCha20-Poly1305 (RFC 8439) | encrypt plaintext, aad=∅ → ciphertext \|\| tag |
| Sign | Ed25519 (RFC 8032) | sign bytes 0–100 with client Ed25519 private key |

Protocol constants (never change without a version bump):

```
PROTOCOL_VERSION  = 1         (uint8)
PACKET_SIZE       = 165       (bytes)
SIGNED_SIZE       = 101       (bytes)
PLAINTEXT_SIZE    = 40        (bytes)
HKDF_INFO         = "openme-v1-chacha20poly1305"  (UTF-8, no NUL)
DEFAULT_UDP_PORT  = 54154
DEFAULT_TIMEOUT   = 30s
REPLAY_WINDOW     = 60s
```

---

## 4. Naming conventions

Use the table below when creating symbols that correspond across platforms.  
Follow each language's idiomatic style — the *concept name* is shared, not the
literal identifier.

| Concept | Go | Swift | Kotlin | C# | C |
|---------|----|----|----|----|---|
| Packet builder | `buildPacket(...)` | `KnockService.buildPacket(...)` | `KnockService.buildPacket(...)` | `KnockService.BuildPacket(...)` | `openme_build_packet(...)` |
| Send knock | `knock(...)` | `KnockService.knock(...)` | `KnockService.knock(...)` | `KnockService.Knock(...)` | `openme_send_knock(...)` |
| Packet size constant | `PacketSize` / `packetSize` | `KnockService.packetSize` | `KnockService.PACKET_SIZE` | `KnockService.PacketSize` | `OPENME_PACKET_SIZE` |
| Signed size constant | `SignedSize` | `KnockService.signedPortionSize` | `KnockService.SIGNED_PORTION_SIZE` | `KnockService.SignedPortionSize` | `OPENME_SIGNED_SIZE` |
| Protocol version | `ProtocolVersion` | `KnockService.protocolVersion` | `KnockService.PROTOCOL_VERSION` | `KnockService.ProtocolVersion` | `OPENME_VERSION` |
| Profile / connection config | `Profile` | `ClientConfig` | `Profile` | `Profile` | `openme_profile_t` (if added) |
| Invalid server key error | `ErrInvalidServerKey` | `.invalidServerKey` | `KnockError.InvalidServerKey` | `KnockException` (subtype) | `OPENME_ERR_NULL` / `OPENME_ERR_PARAM` |

Rules:
- **Go**: package-level funcs/types in `snake_case` packages; exported names in `PascalCase`.
- **Swift**: `camelCase` methods on enums/structs; `lowerCamelCase` properties.
- **Kotlin**: `UPPER_SNAKE_CASE` constants; `camelCase` methods; `object KnockService`.
- **C#**: `PascalCase` everything public; `static class KnockService`.
- **C**: prefix all public symbols with `openme_`; `OPENME_` for macros/constants.

---

## 5. Documentation standards

Documentation is the contract between the implementation and callers.  
Write it before (or alongside) code, not as an afterthought.

### Minimum required for every public symbol

1. **Intent** — one sentence: what does this do and why does it exist?
2. **Parameters** — type, valid range/constraints, semantics.
3. **Return value / output** — what is returned on success and on every failure.
4. **Example** — at least one realistic call site, inline in the doc comment.
5. **Cross-reference** — link to the relevant Quarto page where the behaviour is specified.

### Language-native format

Use the doc-comment format native to each language so IDE tooling, generated
reference docs, and in-editor hover work correctly.

**Go** — `godoc` block comments:
```go
// BuildPacket constructs a 165-byte SPA knock packet.
//
// Steps: X25519 ECDH → HKDF-SHA256 → ChaCha20-Poly1305 → Ed25519 sign.
//
// Parameters:
//   - serverPubKey: 32-byte Curve25519 public key of the server.
//   - clientPrivKey: 32-byte Ed25519 seed of this client.
//   - targetIP: IPv6 target (16 bytes); nil → use source IP.
//   - timestamp: Unix nanoseconds; pass 0 to use time.Now().
//
// Returns: 165-byte slice ready to transmit over UDP, or a non-nil error.
//
// See https://openme.merlos.org/docs/protocol/packet-format.html
func BuildPacket(serverPubKey, clientPrivKey []byte, targetIP net.IP, timestamp int64) ([]byte, error) {
```

**Swift** — DocC `///` triple-slash:
```swift
/// Constructs a 165-byte SPA knock packet.
///
/// - Parameters:
///   - serverPubKey: Server's static Curve25519 public key (32 bytes).
///   - signingKey: Client's Ed25519 private key.
///   - targetIP: 16-byte IPv6 destination, or `nil` to use source IP.
///   - timestamp: Nanosecond Unix timestamp; defaults to `Date()`.
/// - Returns: A 165-byte `Data` value ready to transmit over UDP.
/// - Throws: `KnockServiceError` if key agreement, HKDF, AEAD, or signing fails.
///
/// [Packet Format](https://openme.merlos.org/docs/protocol/packet-format.html)
public static func buildPacket(...) throws -> Data {
```

**Kotlin** — KDoc `/** */`:
```kotlin
/**
 * Constructs a 165-byte SPA knock packet.
 *
 * Steps: X25519 ECDH → HKDF-SHA256 → ChaCha20-Poly1305 → Ed25519 sign.
 *
 * @param serverPubKey 32-byte X25519 server public key.
 * @param signingKey Ed25519 private key (seed, 32 bytes).
 * @return 165-byte [ByteArray] ready to send over UDP.
 * @throws KnockError if any crypto step fails.
 *
 * @see [Packet Format](https://openme.merlos.org/docs/protocol/packet-format.html)
 */
fun buildPacket(serverPubKey: X25519PublicKeyParameters, signingKey: Ed25519PrivateKeyParameters): ByteArray {
```

**C#** — XML doc `/// <summary>`:
```csharp
/// <summary>
/// Constructs a 165-byte SPA knock packet.
/// </summary>
/// <param name="serverPubKey">32-byte Curve25519 server public key.</param>
/// <param name="clientSeed">32-byte Ed25519 seed of this client.</param>
/// <param name="targetIp">16-byte IPv6 target; pass <see langword="null"/> to use source IP.</param>
/// <returns>A 165-byte array ready to transmit over UDP.</returns>
/// <exception cref="KnockException">Thrown if any crypto step fails.</exception>
/// <remarks>
/// See <see href="https://openme.merlos.org/docs/protocol/packet-format.html">Packet Format</see>.
/// </remarks>
public static byte[] BuildPacket(byte[] serverPubKey, byte[] clientSeed, byte[]? targetIp = null) {
```

**C** — Doxygen `/** */`:
```c
/**
 * @brief Constructs a 165-byte SPA knock packet (fully deterministic).
 *
 * All entropy and the timestamp are supplied by the caller — this function
 * makes no OS calls and is safe on bare-metal targets.
 *
 * @param out           Output buffer, exactly OPENME_PACKET_SIZE (165) bytes.
 * @param server_pubkey 32-byte X25519 server public key.
 * @param client_seed   32-byte Ed25519 seed of this client.
 * @param timestamp_ns  Unix nanoseconds (int64, big-endian in packet).
 * @param ephem_secret  32-byte ephemeral X25519 secret (CSPRNG per knock).
 * @param aead_nonce    12-byte ChaCha20-Poly1305 nonce (CSPRNG per knock).
 * @param random_nonce  16-byte payload nonce (CSPRNG per knock).
 * @param target_ip     16-byte IPv6 target, or NULL → all-zeros (use source IP).
 * @return OPENME_OK (0) on success, negative error code on failure.
 *
 * @see https://openme.merlos.org/docs/protocol/packet-format.html
 */
int openme_build_packet(...);
```

### Quarto cross-references

Link doc comments to the relevant `docs/` page using the **published URL**
(`https://openme.merlos.org/docs/<section>/<page>.html`), **not** a relative
file path.  This ensures links work in IDE hover text, generated API references,
and the published site.

Canonical link targets:

| Topic | URL |
|-------|-----|
| Packet format | `https://openme.merlos.org/docs/protocol/packet-format.html` |
| Cryptography | `https://openme.merlos.org/docs/protocol/cryptography.html` |
| Handshake | `https://openme.merlos.org/docs/protocol/handshake.html` |
| Replay protection | `https://openme.merlos.org/docs/protocol/replay-protection.html` |
| Server config | `https://openme.merlos.org/docs/configuration/server.html` |
| Client config | `https://openme.merlos.org/docs/configuration/client.html` |
| Security model | `https://openme.merlos.org/docs/security/` |

---

## 6. Security & input validation

openme handles **cryptographic key material** and **untrusted network input**.
Apply the following rules everywhere:

### Key material

- Never log, print, or include key bytes in error messages.
- Zeroize (wipe) key material from memory as soon as it is no longer needed.
  - Go: `crypto/internal/subtle.WithDFSanDisabled` is not available; use
    `for i := range slice { slice[i] = 0 }` immediately after use.
  - Swift: `Data` zeroing via `withUnsafeMutableBytes`; prefer `SymmetricKey`
    from CryptoKit which zeroes on deallocation.
  - Kotlin/C#: overwrite `ByteArray` elements immediately after use.
  - C: `crypto_wipe()` from Monocypher; never rely on compiler/OS to clear.
- Config files containing private keys must be created with mode `0600`
  (owner read/write only); warn and refuse to start if permissions are wider.
- Never accept a private key from an environment variable or command-line
  argument in production paths; always read from a file.

### Packet / wire input validation (server side)

Validate every field before using it:

| Field | Check |
|-------|-------|
| Packet length | Must be exactly 165 bytes; discard anything else silently. |
| Protocol version | Must be `0x01`; discard newer/older silently (no error reply). |
| Ed25519 signature | Verify over bytes 0–100 before attempting decryption. |
| AEAD authentication tag | ChaCha20-Poly1305 decryption authenticates automatically; treat decryption failure as a silent discard. |
| Timestamp | `abs(recv_time - timestamp_ns) <= replay_window`; default ±60 s. |
| Random nonce | Must not appear in the replay cache within the window. |
| Target IP | If non-zero, must be a valid unicast address; reject multicast/broadcast/loopback. |

**Never send an error response to an unauthenticated knock** — doing so reveals
the server is running openme.

### Key decoding (client-side, from base64)

- Validate decoded length before use: server Curve25519 key = exactly 32 bytes;
  client Ed25519 key = 32 bytes (seed) or 64 bytes (seed + public key; take
  first 32 bytes as seed).
- Return a typed error immediately; provide a clear message that does not echo
  the raw key bytes.

### Input validation pattern for all platforms

```
decode → length check → type coercion → use → wipe
```

Every path that inputs key material from an untrusted source (file, QR,
clipboard, network) must go through this sequence.

---

## 7. Unit testing

Target **≥ 80 % line coverage** for library code (`KnockService`, packet
builders, config parsers).  Target **100 %** for the crypto pipeline itself.

### What must always be tested

1. **Known-answer test (KAT)** — given fixed keys, fixed entropy, and a fixed
   timestamp, `buildPacket` must produce the exact expected 165-byte output.
   Use a test vector generated from the Go reference implementation.
2. **Valid knock round-trip** — build packet with Go server implementation and
   verify with client implementation (or vice versa).
3. **Packet size assertion** — output is always exactly 165 bytes.
4. **Invalid key detection** — reject short keys, empty strings, non-base64
   input, key of wrong type (e.g., passing an Ed25519 key where Curve25519
   is expected).
5. **Config parsing** — valid YAML, missing required field, wrong type, extra
   field, empty file.
6. **Replay window** — timestamps outside `±replay_window` are rejected.

### Platform testing conventions

**Go** — standard `testing` package; table-driven tests; race detector enabled
in CI (`go test -race`):
```go
func TestBuildPacket_KnownAnswer(t *testing.T) {
    got, err := buildPacket(fixture.ServerPub, fixture.ClientSeed, nil, fixture.Timestamp)
    require.NoError(t, err)
    assert.Equal(t, fixture.ExpectedPacket, got)
}
```

**Swift** — XCTest (`XCTestCase`); one test class per source file:
```swift
func testBuildPacket_knownAnswer() throws {
    let packet = try KnockService.buildPacket(
        serverPubKey: Fixtures.serverPubKey,
        signingKey: Fixtures.clientSigningKey,
        targetIP: nil,
        timestamp: Fixtures.timestamp
    )
    XCTAssertEqual(packet, Fixtures.expectedPacket)
}
```

**Kotlin** — JUnit 5 + kotlin.test; one test class per source file:
```kotlin
@Test
fun buildPacket_knownAnswer() {
    val packet = KnockService.buildPacket(Fixtures.serverPubKey, Fixtures.clientSigningKey)
    assertContentEquals(Fixtures.expectedPacket, packet)
}
```

**C#** — xUnit; one test class per source file:
```csharp
[Fact]
public void BuildPacket_KnownAnswer()
{
    var packet = KnockService.BuildPacket(Fixtures.ServerPubKey, Fixtures.ClientSeed);
    Assert.Equal(Fixtures.ExpectedPacket, packet);
}
```

**C** — Unity Test Framework or a minimal `assert()`-based harness that works
on ESP32 and desktop; results must be parseable by CMake's CTest:
```c
void test_build_packet_known_answer(void) {
    uint8_t got[OPENME_PACKET_SIZE];
    openme_build_packet(got, SERVER_PUB, CLIENT_SEED,
                        TIMESTAMP_NS, EPHEM_SECRET,
                        AEAD_NONCE, RANDOM_NONCE, NULL);
    TEST_ASSERT_EQUAL_UINT8_ARRAY(expected_packet, got, OPENME_PACKET_SIZE);
}
```

### Shared test fixtures

Keep test vectors in `cli/internal/crypto/testdata/` (Go canonical source).
Every other platform should import or copy the same vectors.

---

## 8. Code style & DRY principles

### Protocol constants — single source of truth

Constants (`PACKET_SIZE`, `SIGNED_SIZE`, `VERSION`, `HKDF_INFO`,
`DEFAULT_UDP_PORT`, …) are defined **once per language** in a dedicated
constants file, never inline in business logic:

| Platform | Constants location |
|----------|--------------------|
| Go | `cli/pkg/protocol/constants.go` |
| Swift | `apple/OpenMeKit/Sources/OpenMeKit/KnockService.swift` (`static let`) |
| Kotlin | `android/openmekit/…/KnockService.kt` (`const val`) |
| C# | `windows/OpenMeKit/KnockService.cs` (`const`) |
| C | `c/openmelib/include/openmelib.h` (`#define`) |

### DRY rules

- Do not copy-paste key decoding or base64 logic across files in the same
  platform — factor into a shared helper.
- Do not inline HKDF info string — always reference the constant.
- Error messages for the same logical failure should be consistent within a
  platform (wording may vary across platforms).

### General style

- Prefer immutable/value types for key material.
- Short-circuit validate inputs at the top of every public function; do not
  let invalid inputs reach crypto code.
- Keep packet construction (`buildPacket`) free of I/O.  I/O (DNS, sockets,
  logging) belongs in a separate function (`knock` / `sendKnock`).
- Avoid global/static mutable state in library code.

---

## 9. GitHub Actions CI

### Existing workflows

| File | Trigger | What it does |
|------|---------|--------------|
| `.github/workflows/cli.yml` | push/PR to `cli/**` | Go vet, `go test -race` on Linux/macOS/Windows, cross-compile for 5 targets |
| `.github/workflows/docs.yml` | push/PR to `docs/**`, `apple/OpenMeKit/**` | `quarto render` + DocC reference, deploy to GitHub Pages |
| `.github/workflows/openmelib.yml` | push/PR to `c/openmelib/**` | CMake matrix (6 jobs), ARM cross-compile, bare-metal arm-none-eabi, Arduino CLI (5 boards), ESP-IDF (4 targets), cppcheck |
| `.github/workflows/apple-openmekit.yml` | push/PR to `apple/OpenMeKit/**` | `swift test` on macOS 14 + 15; SPM package cache |
| `.github/workflows/apple-apps.yml` | push/PR to `apple/**` | `xcodebuild test` for openme-ios (iPhone Simulator) and openme-macos; `xcodebuild build` for openme-watch |
| `.github/workflows/android.yml` | push/PR to `android/**` | Gradle JVM unit tests for openmekit; assemble release AAR |
| `.github/workflows/windows.yml` | push/PR to `windows/**` | xUnit tests for OpenMeKit (.NET 8) on Linux + Windows; `dotnet build` for WPF GUI on Windows |

### Rules for new workflows

- Place in `.github/workflows/<platform>.yml`.
- Use `paths:` filters so only relevant changes trigger the job.
- Pin action versions to a SHA or a major tag (`@v4`), not `@main`.
- Every build job must produce a passing green build before merging to `main`.
- Upload build artefacts (`actions/upload-artifact`) for binary distributions.
- Separate `test` and `build`/`cross-compile` jobs; use `needs:` so
  cross-compilation only runs after tests pass.
- Coverage reports should be uploaded as artefacts and, optionally, sent to
  Codecov.

### Adding CI for a new platform

1. Create `.github/workflows/<platform>.yml`.
2. Set `paths:` to `<platform-dir>/**` and `.github/workflows/<platform>.yml`.
3. Compile the library/app on at least two OS runners if applicable.
4. Run the test suite and fail the workflow on test failure.
5. Add the workflow badge to the platform README.

---

## 10. Adding a new platform

Follow these steps when implementing openme on a new platform or language:

1. **Protocol** — implement `buildPacket` using the spec in
   `docs/protocol/packet-format.qmd`.  Output must be byte-for-byte identical
   to the Go reference for the same inputs.
2. **Test vector** — add a known-answer test using the shared fixture from
   `cli/internal/crypto/testdata/`.
3. **Naming** — follow the naming table in §4, adapting to language conventions.
4. **Documentation** — every public symbol must meet the standard in §5 with
   a link to the relevant Quarto page.
5. **Security** — apply all rules in §6: key wiping, input validation, no
   error responses.
6. **CI** — add a workflow following §9.
7. **README** — add a `<platform>/README.md` with build instructions, and
   update the root `README.md` Platform Status table.
8. **This file** — update §2 (layout), §4 (naming), §9 (CI table), and any
   other sections affected by the new platform.
