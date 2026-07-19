cmake_minimum_required(VERSION 3.24)

project(PhoneCamWindowsReceiver LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

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
  target_link_libraries(phonecam-receiver PRIVATE user32 gdi32 ws2_32)
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
