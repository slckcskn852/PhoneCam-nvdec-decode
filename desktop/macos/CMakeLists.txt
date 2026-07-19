cmake_minimum_required(VERSION 3.24)
project(PhoneCamMacos LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# macOS receiver Cocoa app
add_executable(phonecam-receiver
  src/main.mm
)

target_link_libraries(phonecam-receiver PRIVATE
  phonecam-core
  "-framework Cocoa"
  "-framework VideoToolbox"
  "-framework CoreMedia"
  "-framework CoreVideo"
  "-framework AVFoundation"
  "-framework QuartzCore"
)

# CoreMediaIO Camera Extension skeleton target
add_executable(phonecam-camera-extension
  src/cmio_extension.mm
)

target_link_libraries(phonecam-camera-extension PRIVATE
  phonecam-core
  "-framework Foundation"
  "-framework CoreMedia"
  "-framework CoreMediaIO"
)
