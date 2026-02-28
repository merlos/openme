cmake_minimum_required(VERSION 3.14)
project(openmelib VERSION 1.0.0 LANGUAGES C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

# ─── Options ──────────────────────────────────────────────────────────────────
option(OPENME_FETCH_MONOCYPHER  "Download Monocypher via FetchContent"     ON)
option(OPENME_BUILD_EXAMPLES    "Build desktop example programs"           ON)
option(OPENME_BUILD_TESTS       "Build unit tests"                         OFF)

# ─── Monocypher dependency ─────────────────────────────────────────────────────
if (OPENME_FETCH_MONOCYPHER)
    include(FetchContent)
    FetchContent_Declare(
        monocypher
        URL      https://monocypher.org/download/monocypher-4.0.2.tar.gz
        URL_HASH SHA256=38d07179738c0c90677dba3ceb7a7b8496bcfea758ba1a53e803fed30ae0879c
    )
    FetchContent_MakeAvailable(monocypher)
    set(MONOCYPHER_INCLUDE_DIR "${monocypher_SOURCE_DIR}/src")
    set(MONOCYPHER_SOURCES     "${monocypher_SOURCE_DIR}/src/monocypher.c")
else()
    # Expect monocypher.h / .c in vendor/monocypher/ or already in include path
    set(MONOCYPHER_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/vendor/monocypher")
    set(MONOCYPHER_SOURCES     "${CMAKE_CURRENT_SOURCE_DIR}/vendor/monocypher/monocypher.c")
    if (NOT EXISTS "${MONOCYPHER_INCLUDE_DIR}/monocypher.h")
        message(FATAL_ERROR
            "monocypher.h not found in ${MONOCYPHER_INCLUDE_DIR}.\n"
            "Run vendor/monocypher/get_monocypher.sh or set OPENME_FETCH_MONOCYPHER=ON.")
    endif()
endif()

# ─── Library target ────────────────────────────────────────────────────────────
add_library(openmelib
    src/openmelib.c
    src/openme_sha256.c
    ${MONOCYPHER_SOURCES}
)

target_include_directories(openmelib
    PUBLIC  include
    PRIVATE src ${MONOCYPHER_INCLUDE_DIR}
)

# Suppress "missing default RNG" warning on known-safe platforms
if (CMAKE_SYSTEM_NAME MATCHES "Linux|Darwin|Windows")
    target_compile_definitions(openmelib PRIVATE)
endif()

# Silence monocypher's potential -Wunused-function on some compilers
if (CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
    set_source_files_properties(${MONOCYPHER_SOURCES}
        PROPERTIES COMPILE_FLAGS "-Wno-unused-function")
endif()

# ─── Install ──────────────────────────────────────────────────────────────────
include(GNUInstallDirs)
install(TARGETS openmelib
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
)
install(FILES include/openmelib.h DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})

# ─── Examples ──────────────────────────────────────────────────────────────────
if (OPENME_BUILD_EXAMPLES)
    add_subdirectory(examples/desktop)
endif()

# ─── Tests ─────────────────────────────────────────────────────────────────────
if (OPENME_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()
