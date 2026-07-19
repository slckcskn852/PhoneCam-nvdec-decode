cmake_minimum_required(VERSION 3.24)
project(PhoneCamDesktop LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(CTest)

# Check target
if(NOT PHONECAM_TARGET)
  if(APPLE)
    set(PHONECAM_TARGET "macos" CACHE STRING "Target platform")
  else()
    set(PHONECAM_TARGET "windows" CACHE STRING "Target platform")
  endif()
endif()

message(STATUS "PhoneCam Target Platform: ${PHONECAM_TARGET}")

# Shared Core Library
add_library(phonecam-core STATIC
  core/rtp_hevc.cpp
  core/rtp_hevc.h
  core/control_parser.cpp
  core/control_parser.h
  core/playout_buffer.cpp
  core/playout_buffer.h
  core/phonecam_client.cpp
  core/phonecam_client.h
  core/discovery.cpp
  core/discovery.h
)

target_include_directories(phonecam-core PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/core
)

if(WIN32)
  target_link_libraries(phonecam-core PUBLIC ws2_32)
endif()

if(PHONECAM_TARGET STREQUAL "windows" OR (WIN32 AND NOT PHONECAM_TARGET STREQUAL "macos"))
  add_subdirectory(windows)
elseif(PHONECAM_TARGET STREQUAL "macos" OR APPLE)
  add_subdirectory(macos)
endif()

if(BUILD_TESTING)
  add_executable(conformance-tests
    tests/conformance_tests.cpp
  )
  target_link_libraries(conformance-tests PRIVATE
    phonecam-core
  )
  add_test(NAME conformance-tests COMMAND conformance-tests "${CMAKE_CURRENT_SOURCE_DIR}/../docs/protocol-vectors")

  add_executable(phonecam-soak-sender
    tests/phonecam_soak_sender.cpp
  )
  target_link_libraries(phonecam-soak-sender PRIVATE
    phonecam-core
  )

  add_test(NAME soak-test COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/../scripts/soak_4k60.sh" --duration 10)
endif()
