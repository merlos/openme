cmake_minimum_required(VERSION 3.16)

# Resolve openmelib component path (relative to this file, go up 3 levels)
set(EXTRA_COMPONENT_DIRS "${CMAKE_CURRENT_SOURCE_DIR}/../../..")

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(openme_knock_esp32)
