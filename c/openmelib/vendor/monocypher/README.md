# How to obtain Monocypher

openmelib uses [Monocypher](https://monocypher.org/) (version 4.x) for all
asymmetric and symmetric cryptography (X25519, ChaCha20-Poly1305, Ed25519).

Place `monocypher.h` and `monocypher.c` directly in this `vendor/monocypher/`
directory.  The two files can be obtained in one of three ways:

## Option A — Download the release archive (recommended)

```sh
MONO_VER=4.0.2
curl -sSL https://monocypher.org/download/monocypher-${MONO_VER}.tar.gz \
  | tar -xz --strip-components=1 -C . \
       monocypher-${MONO_VER}/src/monocypher.h \
       monocypher-${MONO_VER}/src/monocypher.c
```

Or use the provided helper script from the repo root:

```sh
c/openmelib/vendor/monocypher/get_monocypher.sh
```

## Option B — CMake FetchContent (handled automatically)

When building with CMake, set `-DOPENME_FETCH_MONOCYPHER=ON` (the default).
CMake will download and configure Monocypher automatically — no manual step needed.

## Option C — System / project package

If your project already provides Monocypher via a package manager or a parent
CMake project, set `-DOPENME_FETCH_MONOCYPHER=OFF` and ensure `monocypher.h`
is in your include path.

## ESP-IDF

Add the `openmelib` component to your `idf_component.yml` (see `../idf_component.yml`).
The component manifest declares Monocypher as a dependency which IDF Component
Manager downloads automatically.

## Arduino

Run the helper script once before opening the sketch:

```sh
c/openmelib/vendor/monocypher/get_monocypher.sh
```

Then include the whole `openmelib/` directory as an Arduino library
(Sketch → Include Library → Add .ZIP Library … or copy to `~/Arduino/libraries/`).
