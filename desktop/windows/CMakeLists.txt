cmake_minimum_required(VERSION 3.24)

project(PhoneCamWindowsReceiver LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Also support the documented standalone configuration used by CI.
if(NOT TARGET phonecam-core)
  include(CTest)
  find_package(Threads REQUIRED)
  add_library(phonecam-core STATIC
    ../core/rtp_hevc.cpp ../core/control_parser.cpp ../core/playout_buffer.cpp
    ../core/phonecam_client.cpp ../core/discovery.cpp ../core/receiver_connection.cpp)
  target_include_directories(phonecam-core PUBLIC ../core)
  target_link_libraries(phonecam-core PUBLIC Threads::Threads)
  if(WIN32)
    target_compile_definitions(phonecam-core PUBLIC NOMINMAX)
    target_link_libraries(phonecam-core PUBLIC ws2_32 iphlpapi dnsapi)
  endif()
  if(BUILD_TESTING)
  add_executable(pipeline-tests ../tests/pipeline_tests.cpp)
  target_link_libraries(pipeline-tests PRIVATE phonecam-core)
  add_test(NAME pipeline-memory-tests COMMAND pipeline-tests)
  add_test(NAME pipeline-network-tests COMMAND pipeline-tests --network)
  set_tests_properties(pipeline-network-tests PROPERTIES TIMEOUT 30)
    add_executable(conformance-tests ../tests/conformance_tests.cpp)
    target_link_libraries(conformance-tests PRIVATE phonecam-core)
    if(MSVC)
      target_compile_options(conformance-tests PRIVATE /UNDEBUG)
    else()
      target_compile_options(conformance-tests PRIVATE -UNDEBUG)
    endif()
    add_test(NAME conformance-tests COMMAND conformance-tests "${CMAKE_CURRENT_SOURCE_DIR}/../../docs/protocol-vectors")
  endif()
endif()

set(FFMPEG_ROOT "" CACHE PATH "Path to an LGPL FFmpeg build containing include/ and lib/")
set(SOFTCAM_ROOT "" CACHE PATH "Path to a built tshino/softcam checkout or dist folder")
option(PHONECAM_WITH_SOFTCAM "Enable PhoneCam Virtual Camera output through Softcam" ON)
option(PHONECAM_REQUIRE_SOFTCAM "Fail configuration if Softcam cannot be found" OFF)

find_path(FFMPEG_INCLUDE_DIR libavformat/avformat.h
  PATHS
    "${FFMPEG_ROOT}/include"
    "$ENV{FFMPEG_ROOT}/include"
)
find_library(FFMPEG_AVFORMAT avformat PATHS "${FFMPEG_ROOT}/lib" "$ENV{FFMPEG_ROOT}/lib")
find_library(FFMPEG_AVCODEC avcodec PATHS "${FFMPEG_ROOT}/lib" "$ENV{FFMPEG_ROOT}/lib")
find_library(FFMPEG_AVUTIL avutil PATHS "${FFMPEG_ROOT}/lib" "$ENV{FFMPEG_ROOT}/lib")
find_library(FFMPEG_SWSCALE swscale PATHS "${FFMPEG_ROOT}/lib" "$ENV{FFMPEG_ROOT}/lib")

if(NOT FFMPEG_INCLUDE_DIR OR NOT FFMPEG_AVFORMAT OR NOT FFMPEG_AVCODEC OR NOT FFMPEG_AVUTIL OR NOT FFMPEG_SWSCALE)
  message(FATAL_ERROR "FFmpeg not found. Set -DFFMPEG_ROOT=C:/path/to/lgpl-ffmpeg")
endif()

add_executable(phonecam-receiver
  src/main.cpp
)

target_include_directories(phonecam-receiver PRIVATE "${FFMPEG_INCLUDE_DIR}")
target_link_libraries(phonecam-receiver PRIVATE
  phonecam-core
  "${FFMPEG_AVFORMAT}"
  "${FFMPEG_AVCODEC}"
  "${FFMPEG_AVUTIL}"
  "${FFMPEG_SWSCALE}"
)

if(WIN32)
  add_custom_command(TARGET phonecam-receiver POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/scripts/Install-PhoneCamFirewallRules.ps1" "$<TARGET_FILE_DIR:phonecam-receiver>")
  target_link_libraries(phonecam-receiver PRIVATE user32 gdi32 ws2_32 shell32)
endif()

if(PHONECAM_WITH_SOFTCAM)
  find_path(SOFTCAM_INCLUDE_DIR softcam/softcam.h
    PATHS
      "${SOFTCAM_ROOT}/dist/include"
      "${SOFTCAM_ROOT}/src"
      "$ENV{SOFTCAM_ROOT}/dist/include"
      "$ENV{SOFTCAM_ROOT}/src"
  )
  find_library(SOFTCAM_LIBRARY softcam
    PATHS
      "${SOFTCAM_ROOT}/dist/lib/x64"
      "${SOFTCAM_ROOT}/dist/lib"
      "$ENV{SOFTCAM_ROOT}/dist/lib/x64"
      "$ENV{SOFTCAM_ROOT}/dist/lib"
  )

  if(SOFTCAM_INCLUDE_DIR AND SOFTCAM_LIBRARY)
    target_compile_definitions(phonecam-receiver PRIVATE PHONECAM_WITH_SOFTCAM=1)
    target_include_directories(phonecam-receiver PRIVATE "${SOFTCAM_INCLUDE_DIR}")
    target_link_libraries(phonecam-receiver PRIVATE "${SOFTCAM_LIBRARY}")
    if(WIN32 AND BUILD_TESTING)
      add_executable(softcam-lifecycle-tests ../tests/softcam_lifecycle_tests.cpp)
      target_include_directories(softcam-lifecycle-tests PRIVATE "${SOFTCAM_INCLUDE_DIR}")
      target_link_libraries(softcam-lifecycle-tests PRIVATE "${SOFTCAM_LIBRARY}" psapi)
      add_test(NAME softcam-lifecycle-tests COMMAND softcam-lifecycle-tests)
      set_tests_properties(softcam-lifecycle-tests PROPERTIES TIMEOUT 60)
    endif()
    if(WIN32)
      find_file(SOFTCAM_DLL softcam.dll PATHS "${SOFTCAM_ROOT}/dist/bin/x64" "$ENV{SOFTCAM_ROOT}/dist/bin/x64" NO_DEFAULT_PATH)
      if(SOFTCAM_DLL)
        add_custom_command(TARGET phonecam-receiver POST_BUILD
          COMMAND ${CMAKE_COMMAND} -E copy_if_different "${SOFTCAM_DLL}" "$<TARGET_FILE_DIR:phonecam-receiver>")
      endif()
    endif()
  else()
    if(PHONECAM_REQUIRE_SOFTCAM)
      message(FATAL_ERROR "Softcam not found, but PHONECAM_REQUIRE_SOFTCAM=ON. Set -DSOFTCAM_ROOT=... to a built PhoneCam-branded Softcam checkout.")
    endif()
    message(WARNING "Softcam not found. Building preview-only receiver. Set -DSOFTCAM_ROOT=... to enable virtual camera output.")
    target_compile_definitions(phonecam-receiver PRIVATE PHONECAM_WITH_SOFTCAM=0)
  endif()
else()
  target_compile_definitions(phonecam-receiver PRIVATE PHONECAM_WITH_SOFTCAM=0)
endif()

if(BUILD_TESTING)
  add_test(NAME receiver-self-test COMMAND phonecam-receiver --self-test --frames 3 --fps 240 --no-preview --no-softcam)
  add_test(NAME receiver-invalid-fps COMMAND phonecam-receiver --self-test --fps nan --no-preview --no-softcam)
  set_tests_properties(receiver-invalid-fps PROPERTIES WILL_FAIL TRUE)
endif()
