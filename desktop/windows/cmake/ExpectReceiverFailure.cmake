if(NOT DEFINED RECEIVER)
  message(FATAL_ERROR "RECEIVER is required")
endif()

execute_process(
  COMMAND "${RECEIVER}" --rtsp rtsp://127.0.0.1:65534/no-stream --frames 1 --no-preview --no-softcam
  RESULT_VARIABLE receiver_result
  OUTPUT_VARIABLE receiver_stdout
  ERROR_VARIABLE receiver_stderr
)

set(receiver_output "${receiver_stdout}\n${receiver_stderr}")

if(receiver_result EQUAL 0)
  message(FATAL_ERROR "Receiver unexpectedly succeeded against an unavailable RTSP endpoint.\n${receiver_output}")
endif()

if(NOT receiver_output MATCHES "Failed to open RTSP stream")
  message(FATAL_ERROR "Receiver failure output did not include the expected RTSP diagnostic.\n${receiver_output}")
endif()

message(STATUS "Receiver failed as expected against an unavailable RTSP endpoint.")
