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
  core/receiver_connection.cpp
  core/discovery.cpp
  core/discovery.h
)

find_package(Threads REQUIRED)
target_link_libraries(phonecam-core PUBLIC Threads::Threads)

target_include_directories(phonecam-core PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/core
)

if(WIN32)
  target_compile_definitions(phonecam-core PUBLIC NOMINMAX)
  target_link_libraries(phonecam-core PUBLIC ws2_32 iphlpapi dnsapi)
endif()

if(PHONECAM_TARGET STREQUAL "windows" OR (WIN32 AND NOT PHONECAM_TARGET STREQUAL "macos"))
  add_subdirectory(windows)
elseif(PHONECAM_TARGET STREQUAL "macos")
  add_subdirectory(macos)
endif()

if(BUILD_TESTING)
  add_executable(pipeline-tests tests/pipeline_tests.cpp)
  target_link_libraries(pipeline-tests PRIVATE phonecam-core)
  add_test(NAME pipeline-memory-tests COMMAND pipeline-tests)
  add_test(NAME pipeline-network-tests COMMAND pipeline-tests --network)
  set_tests_properties(pipeline-network-tests PROPERTIES TIMEOUT 30)
  add_executable(conformance-tests
    tests/conformance_tests.cpp
  )
  target_link_libraries(conformance-tests PRIVATE
    phonecam-core
  )
  add_test(NAME conformance-tests COMMAND conformance-tests "${CMAKE_CURRENT_SOURCE_DIR}/../docs/protocol-vectors")

  if(NOT WIN32)
  add_executable(phonecam-soak-sender
    tests/phonecam_soak_sender.cpp
  )
  target_link_libraries(phonecam-soak-sender PRIVATE
    phonecam-core
  )

  endif()

  # The hardware soak is opt-in; conformance must not silently depend on devices.
  if(MSVC)
    target_compile_options(conformance-tests PRIVATE /UNDEBUG)
  else()
    target_compile_options(conformance-tests PRIVATE -UNDEBUG)
  endif()
endif()
