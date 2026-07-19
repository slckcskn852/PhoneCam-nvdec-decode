#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "uri"
require "digest"

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/validate_mvp_evidence.rb --android-matrix PATH [--android-only | --windows-runtime PATH --windows-manual PATH]"
  parser.on("--android-matrix PATH", "Path to Android Wi-Fi profile matrix JSON evidence") do |value|
    options[:android_matrix] = value
  end
  parser.on("--android-only", "Validate only the physical Android matrix evidence") do
    options[:android_only] = true
  end
  parser.on("--windows-runtime PATH", "Path to Windows runtime-evidence.json") do |value|
    options[:windows_runtime] = value
  end
  parser.on("--windows-manual PATH", "Path to completed manual-app-evidence-template.json") do |value|
    options[:windows_manual] = value
  end
end.parse!

def load_json(path, label, issues)
  if path.nil? || path.strip.empty?
    issues << "#{label} path is required"
    return {}
  end

  unless File.file?(path)
    issues << "#{label} file not found: #{path}"
    return {}
  end

  JSON.parse(File.read(path))
rescue JSON::ParserError => error
  issues << "#{label} is not valid JSON: #{error.message}"
  {}
end

def require_value(issues, condition, message)
  issues << message unless condition
end

def non_empty_string?(value)
  value.is_a?(String) && !value.strip.empty?
end

def six_digit_pairing_code?(value)
  value.is_a?(String) && value.match?(/\A\d{6}\z/)
end

def number?(value)
  value.is_a?(Numeric)
end

def positive_integer?(value)
  value.is_a?(Integer) && value.positive?
end

def rotation_taps?(value)
  value.is_a?(Integer) && value.between?(0, 3)
end

def rotation_degrees?(value)
  value.is_a?(Integer) && [0, 90, 180, 270].include?(value)
end

def rotation_direction?(value)
  %w[left right].include?(value)
end

def approximately_equal?(actual, expected, tolerance = 0.01)
  number?(actual) && (actual.to_f - expected).abs <= tolerance
end

def android_profile_expected_bitrate_mbps(profile_name)
  {
    "Efficient" => 1.2,
    "Balanced" => 1.8,
    "Motion" => 2.8
  }[profile_name]
end

def android_profile_max_incoming_mbps(profile_name)
  {
    "Efficient" => 2.0,
    "Balanced" => 3.0,
    "Motion" => 4.5
  }[profile_name]
end

RTSP_URL_FIELD_NAMES = %w[effectiveRtspUrl selectedRtspUrl openedRtspUrl rtspUrl].freeze

def rtsp_url_for_runtime(windows_runtime)
  RTSP_URL_FIELD_NAMES.map { |name| windows_runtime[name] }.find { |value| non_empty_string?(value) }
end

def rtsp_host(url)
  parsed = URI.parse(url)
  return nil unless parsed.scheme == "rtsp"

  parsed.host
rescue URI::InvalidURIError
  nil
end

def canonical_rtsp_endpoint(url)
  parsed = URI.parse(url)
  return nil unless parsed.scheme == "rtsp" && non_empty_string?(parsed.host)

  path = parsed.path
  path = "/" if path.nil? || path.empty?
  "#{parsed.host.downcase}:#{parsed.port || 554}#{path}"
rescue URI::InvalidURIError
  nil
end

def rtsp_url_field_values(evidence)
  return [] unless evidence.is_a?(Hash)

  RTSP_URL_FIELD_NAMES.each_with_object([]) do |name, fields|
    value = evidence[name]
    fields << [name, value] if non_empty_string?(value)
  end
end

def require_consistent_rtsp_url_fields(issues, label, evidence)
  endpoints = {}
  rtsp_url_field_values(evidence).each do |field_name, url|
    endpoint = canonical_rtsp_endpoint(url)
    host = rtsp_host(url)
    require_value(issues, non_empty_string?(host), "#{label} #{field_name} must use the rtsp:// scheme with a host")
    if non_empty_string?(host)
      require_value(
        issues,
        !local_or_emulator_rtsp_host?(host),
        "#{label} #{field_name} must be a real Android LAN address"
      )
    end
    endpoints[field_name] = endpoint if endpoint
  end

  unique_endpoints = endpoints.values.compact.uniq
  require_value(
    issues,
    unique_endpoints.size <= 1,
    "#{label} recorded RTSP URL fields must all refer to the same endpoint"
  )
  unique_endpoints.first
end

def local_or_emulator_rtsp_host?(host)
  normalized = host.to_s.downcase.delete_prefix("[").delete_suffix("]")
  return true if normalized.empty?
  return true if %w[localhost phone-ip 0.0.0.0 ::1].include?(normalized)
  return true if normalized.start_with?("127.")
  return true if normalized.start_with?("10.0.2.")

  false
end

def require_matching_physical_rtsp_url(issues, label, url, expected_endpoint, expected_label)
  require_value(issues, non_empty_string?(url), "#{label} RTSP URL must be recorded")
  return nil unless non_empty_string?(url)

  endpoint = canonical_rtsp_endpoint(url)
  host = rtsp_host(url)
  require_value(issues, non_empty_string?(host), "#{label} RTSP URL must use the rtsp:// scheme with a host")
  if non_empty_string?(host)
    require_value(
      issues,
      !local_or_emulator_rtsp_host?(host),
      "#{label} RTSP URL must be a real physical-phone LAN address"
    )
  end
  if endpoint && expected_endpoint
    require_value(issues, endpoint == expected_endpoint, "#{label} RTSP URL must match #{expected_label}")
  end

  endpoint
end

def absolute_evidence_path?(path)
  path.start_with?("/") || path.start_with?("\\\\") || path.match?(/\A[A-Za-z]:[\\\/]/)
end

def evidence_path(value, base_dir)
  return nil unless non_empty_string?(value)

  stripped = value.strip
  absolute_evidence_path?(stripped) ? stripped : File.join(base_dir, stripped)
end

def evidence_file_exists?(value, base_dir)
  path = evidence_path(value, base_dir)
  path && File.file?(path)
end

def evidence_file_nonempty?(value, base_dir)
  path = evidence_path(value, base_dir)
  path && File.file?(path) && File.size(path).positive?
end

def evidence_image_file?(value, base_dir)
  path = evidence_path(value, base_dir)
  return false unless path && File.file?(path) && File.size(path).positive?

  header = File.binread(path, 12)
  header.start_with?("\x89PNG\r\n\x1A\n".b) ||
    header.start_with?("\xFF\xD8\xFF".b) ||
    header.start_with?("BM".b)
end

def evidence_decoded_frame_file?(value, base_dir)
  path = evidence_path(value, base_dir)
  return false unless path && File.file?(path) && File.size(path).positive?

  header = File.binread(path, 12)
  evidence_image_file?(value, base_dir) ||
    header.start_with?("P6".b) ||
    header.start_with?("P3".b)
end

def require_nonempty_evidence_file(issues, label, value, base_dir)
  require_value(issues, non_empty_string?(value), "#{label} path must be recorded")
  return unless non_empty_string?(value)

  path = evidence_path(value, base_dir)
  unless path && File.file?(path)
    issues << "#{label} file must exist"
    return
  end

  issues << "#{label} file must be non-empty" unless File.size(path).positive?
end

def require_evidence_image_file(issues, label, value, base_dir)
  require_value(issues, non_empty_string?(value), "#{label} path must be recorded")
  return unless non_empty_string?(value)

  path = evidence_path(value, base_dir)
  unless path && File.file?(path)
    issues << "#{label} file must exist"
    return
  end

  unless File.size(path).positive?
    issues << "#{label} file must be non-empty"
    return
  end

  issues << "#{label} file must be a PNG, JPEG, or BMP image" unless evidence_image_file?(value, base_dir)
end

def require_decoded_frame_file(issues, label, value, base_dir)
  require_value(issues, non_empty_string?(value), "#{label} path must be recorded")
  return unless non_empty_string?(value)

  path = evidence_path(value, base_dir)
  unless path && File.file?(path)
    issues << "#{label} file must exist"
    return
  end

  unless File.size(path).positive?
    issues << "#{label} file must be non-empty"
    return
  end

  issues << "#{label} file must be a PPM, PNG, JPEG, or BMP image" unless evidence_decoded_frame_file?(value, base_dir)
end

def require_evidence_text_includes(issues, label, value, base_dir, expected_text)
  require_nonempty_evidence_file(issues, label, value, base_dir)
  return unless non_empty_string?(value)

  text = evidence_file_text(value, base_dir)
  return unless text

  issues << "#{label} must contain #{expected_text.inspect}" unless text.include?(expected_text)
end

def evidence_file_text(value, base_dir)
  path = evidence_path(value, base_dir)
  return nil unless path && File.file?(path)

  File.read(path)
end

def normalized_evidence_path(value, base_dir)
  path = evidence_path(value, base_dir)
  return nil unless path

  File.expand_path(path).tr("\\", "/")
end

def evidence_file_sha256(value, base_dir)
  path = evidence_path(value, base_dir)
  return nil unless path && File.file?(path)

  Digest::SHA256.file(path).hexdigest
end

def require_matching_runtime_artifact(issues, label, manual_value, runtime_value, manual_base_dir, runtime_base_dir)
  require_nonempty_evidence_file(issues, "Windows manual runtimeArtifacts.#{label}", manual_value, manual_base_dir)
  return unless non_empty_string?(manual_value) && non_empty_string?(runtime_value)

  manual_path = normalized_evidence_path(manual_value, manual_base_dir)
  runtime_path = normalized_evidence_path(runtime_value, runtime_base_dir)
  require_value(
    issues,
    manual_path == runtime_path,
    "Windows manual runtimeArtifacts.#{label} must match runtime evidence"
  )
end

def max_ffmpeg_frame_count(log_text)
  return nil unless log_text

  frames = log_text.scan(/frame=\s*([0-9]+)/).flatten.map(&:to_i)
  frames.max
end

def screenshot_reference(section)
  return "" unless section.is_a?(Hash)

  non_empty_string?(section["screenshotPath"]) ? section["screenshotPath"] : section["screenshotOrNote"]
end

def load_profile_evidence(path, profile_name, issues, base_dir)
  if !non_empty_string?(path)
    issues << "Android #{profile_name} evidenceJson must be present"
    return [{}, nil]
  end

  resolved_path = evidence_path(path, base_dir)
  unless resolved_path && File.file?(resolved_path)
    issues << "Android #{profile_name} evidenceJson file not found: #{path}"
    return [{}, nil]
  end

  [JSON.parse(File.read(resolved_path)), resolved_path]
rescue JSON::ParserError => error
  issues << "Android #{profile_name} evidenceJson is not valid JSON: #{error.message}"
  [{}, nil]
end

def android_profile_rtsp_endpoints(profile_evidence)
  direct = profile_evidence["directDecode"].is_a?(Hash) ? profile_evidence["directDecode"] : {}
  discovery = profile_evidence["pairCodeDiscoveryDecode"].is_a?(Hash) ? profile_evidence["pairCodeDiscoveryDecode"] : {}
  [
    profile_evidence["rtspUrl"],
    direct["openedRtspUrl"],
    discovery["selectedRtspUrl"],
    discovery["openedRtspUrl"]
  ].map { |url| non_empty_string?(url) ? canonical_rtsp_endpoint(url) : nil }.compact.uniq
end

def validate_android_network_evidence(issues, profile_name, profile_evidence, rtsp_url)
  network = profile_evidence["network"].is_a?(Hash) ? profile_evidence["network"] : {}
  require_value(issues, network["wifiEvidenceCaptured"] == true, "Android #{profile_name} Wi-Fi network evidence must be captured")

  network_rtsp_host = network["rtspHost"]
  require_value(issues, non_empty_string?(network_rtsp_host), "Android #{profile_name} network rtspHost must be recorded")
  if non_empty_string?(network_rtsp_host)
    require_value(
      issues,
      !local_or_emulator_rtsp_host?(network_rtsp_host),
      "Android #{profile_name} network rtspHost must be a real physical-phone LAN address"
    )
  end

  profile_host = rtsp_host(rtsp_url) if non_empty_string?(rtsp_url)
  if non_empty_string?(profile_host) && non_empty_string?(network_rtsp_host)
    require_value(
      issues,
      network_rtsp_host.downcase == profile_host.downcase,
      "Android #{profile_name} network rtspHost must match the profile RTSP URL host"
    )
  end

  summaries = [
    network["wifiStatusSummary"],
    network["wifiDumpsysSummary"],
    network["ipRouteSummary"]
  ]
  require_value(
    issues,
    summaries.any? { |summary| non_empty_string?(summary) },
    "Android #{profile_name} Wi-Fi network evidence must include a status, dumpsys, or route summary"
  )
end

def validate_android_decode_metrics(issues, profile_name, label, evidence, max_incoming_mbps)
  avg_fps = evidence["avgFps"]
  incoming_mbps = evidence["incomingMbps"]
  decode_errors = evidence["decodeErrors"]

  require_value(issues, number?(avg_fps) && avg_fps.to_f.positive?, "Android #{profile_name} #{label} avgFps must be positive")
  require_value(issues, number?(incoming_mbps) && incoming_mbps.to_f.positive?, "Android #{profile_name} #{label} incomingMbps must be positive")
  if number?(incoming_mbps) && number?(max_incoming_mbps)
    require_value(
      issues,
      incoming_mbps.to_f <= max_incoming_mbps,
      "Android #{profile_name} #{label} incoming Mbps must stay within the profile bandwidth ceiling"
    )
  end
  require_value(issues, decode_errors == 0, "Android #{profile_name} #{label} decode errors must be zero")
end

def validate_android_profile_evidence(issues, profile_name, profile_evidence, profile_evidence_path)
  require_value(issues, profile_evidence["status"] == "passed", "Android #{profile_name} structured evidence status must be passed")
  require_value(issues, profile_evidence["finalMvpEvidence"] == true, "Android #{profile_name} evidence must be final MVP physical Wi-Fi evidence")
  require_value(issues, profile_evidence["profile"] == profile_name, "Android #{profile_name} structured evidence profile must match")
  profile_json_dir = profile_evidence_path ? File.dirname(File.expand_path(profile_evidence_path)) : Dir.pwd
  profile_evidence_dir = non_empty_string?(profile_evidence["evidenceDir"]) ? evidence_path(profile_evidence["evidenceDir"], profile_json_dir) : profile_json_dir
  profile_evidence_dir ||= profile_json_dir

  serial = profile_evidence["androidSerial"]
  require_value(issues, non_empty_string?(serial), "Android #{profile_name} structured evidence must include androidSerial")
  if non_empty_string?(serial)
    require_value(issues, !serial.start_with?("emulator-"), "Android #{profile_name} evidence must come from a physical Android target")
  end

  frames_requested = profile_evidence["framesRequested"]
  require_value(issues, frames_requested.is_a?(Integer) && frames_requested.positive?, "Android #{profile_name} framesRequested must be positive")

  pairing_code = profile_evidence["pairingCode"]
  require_value(issues, six_digit_pairing_code?(pairing_code), "Android #{profile_name} pairingCode must be six digits")
  require_value(issues, profile_evidence["previewLive"] == true, "Android #{profile_name} sender preview must report live")

  stream_rotate_taps = profile_evidence["streamRotateTaps"]
  stream_rotation_degrees = profile_evidence["streamRotationDegrees"]
  stream_rotation_direction = profile_evidence["streamRotationDirection"]
  stream_rotation_request_mode = profile_evidence["streamRotationRequestMode"]
  stream_requested_rotation_degrees = profile_evidence["streamRequestedOutputRotationDegrees"]
  require_value(issues, rotation_taps?(stream_rotate_taps), "Android #{profile_name} streamRotateTaps must be recorded as 0..3")
  require_value(issues, rotation_degrees?(stream_rotation_degrees), "Android #{profile_name} stream output rotation degrees must be recorded as 0/90/180/270")
  require_value(issues, rotation_direction?(stream_rotation_direction), "Android #{profile_name} stream rotationDirection must be left or right")
  require_value(
    issues,
    %w[tap-count absolute-degrees].include?(stream_rotation_request_mode),
    "Android #{profile_name} stream rotation request mode must be tap-count or absolute-degrees"
  )
  if stream_rotation_request_mode == "absolute-degrees"
    require_value(issues, rotation_degrees?(stream_requested_rotation_degrees), "Android #{profile_name} requested stream output rotation degrees must be 0/90/180/270")
    if rotation_degrees?(stream_requested_rotation_degrees) && rotation_degrees?(stream_rotation_degrees)
      require_value(issues, stream_rotation_degrees == stream_requested_rotation_degrees, "Android #{profile_name} stream output rotation degrees must match the requested target")
    end
  end
  stream_orientation = profile_evidence["streamOrientation"].is_a?(Hash) ? profile_evidence["streamOrientation"] : {}
  require_value(issues, stream_orientation["orientationStatus"] == "passed", "Android #{profile_name} stream orientation status must be passed")
  require_value(issues, stream_orientation["orientationEvidenceCaptured"] == true, "Android #{profile_name} stream orientation evidence must be captured")
  require_value(
    issues,
    stream_orientation["orientationEvidenceVersion"].is_a?(Integer) && stream_orientation["orientationEvidenceVersion"] >= 4,
    "Android #{profile_name} stream orientation evidence must be version 4 or newer"
  )
  require_value(
    issues,
    stream_orientation["rotationControlMode"] == "per-camera-output",
    "Android #{profile_name} stream orientation rotationControlMode must be per-camera-output"
  )
  require_value(
    issues,
    stream_orientation["orientationLockMode"] == "fixed-landscape",
    "Android #{profile_name} stream orientation orientationLockMode must be fixed-landscape"
  )
  require_value(
    issues,
    %w[tap-count absolute-degrees].include?(stream_orientation["rotationRequestMode"]),
    "Android #{profile_name} stream orientation rotationRequestMode must be tap-count or absolute-degrees"
  )
  if %w[tap-count absolute-degrees].include?(stream_rotation_request_mode) &&
     %w[tap-count absolute-degrees].include?(stream_orientation["rotationRequestMode"])
    require_value(
      issues,
      stream_orientation["rotationRequestMode"] == stream_rotation_request_mode,
      "Android #{profile_name} stream orientation rotationRequestMode must match top-level streamRotationRequestMode"
    )
  end
  require_value(
    issues,
    rotation_direction?(stream_orientation["rotationDirection"]),
    "Android #{profile_name} stream orientation rotationDirection must be left or right"
  )
  require_value(
    issues,
    rotation_taps?(stream_orientation["rotateTaps"]),
    "Android #{profile_name} stream orientation rotateTaps must be recorded as 0..3"
  )
  require_value(
    issues,
    rotation_degrees?(stream_orientation["outputRotationDegrees"]),
    "Android #{profile_name} stream orientation output rotation degrees must be recorded as 0/90/180/270"
  )
  if rotation_direction?(stream_rotation_direction) && rotation_direction?(stream_orientation["rotationDirection"])
    require_value(issues, stream_orientation["rotationDirection"] == stream_rotation_direction, "Android #{profile_name} stream orientation rotationDirection must match top-level streamRotationDirection")
  end
  if rotation_taps?(stream_rotate_taps) && rotation_taps?(stream_orientation["rotateTaps"])
    require_value(issues, stream_orientation["rotateTaps"] == stream_rotate_taps, "Android #{profile_name} stream orientation rotateTaps must match top-level streamRotateTaps")
  end
  if rotation_degrees?(stream_rotation_degrees) && rotation_degrees?(stream_orientation["outputRotationDegrees"])
    require_value(issues, stream_orientation["outputRotationDegrees"] == stream_rotation_degrees, "Android #{profile_name} stream orientation output rotation degrees must match top-level streamRotationDegrees")
  end
  if stream_orientation["rotationRequestMode"] == "absolute-degrees"
    require_value(issues, rotation_degrees?(stream_orientation["requestedOutputRotationDegrees"]), "Android #{profile_name} stream orientation requested output rotation degrees must be 0/90/180/270")
    if rotation_degrees?(stream_requested_rotation_degrees) && rotation_degrees?(stream_orientation["requestedOutputRotationDegrees"])
      require_value(
        issues,
        stream_orientation["requestedOutputRotationDegrees"] == stream_requested_rotation_degrees,
        "Android #{profile_name} stream orientation requested output rotation degrees must match top-level requested stream output rotation degrees"
      )
    end
    if rotation_degrees?(stream_orientation["requestedOutputRotationDegrees"]) && rotation_degrees?(stream_orientation["outputRotationDegrees"])
      require_value(
        issues,
        stream_orientation["outputRotationDegrees"] == stream_orientation["requestedOutputRotationDegrees"],
        "Android #{profile_name} stream orientation output rotation degrees must match the requested target"
      )
    end
  end
  require_value(issues, non_empty_string?(stream_orientation["orientationNotes"]), "Android #{profile_name} stream orientation notes must be recorded")
  require_value(issues, non_empty_string?(stream_orientation["devicePosture"]), "Android #{profile_name} stream orientation device posture must be recorded")
  require_value(issues, non_empty_string?(stream_orientation["cameraDiagnostics"]), "Android #{profile_name} stream orientation cameraDiagnostics must be recorded")
  stream_orientation_artifacts = stream_orientation["orientationArtifacts"].is_a?(Hash) ? stream_orientation["orientationArtifacts"] : {}
  {
    "input" => "stream orientation input dump",
    "window" => "stream orientation window dump",
    "display" => "stream orientation display dump",
    "accelerometerRotation" => "stream orientation accelerometer_rotation setting",
    "userRotation" => "stream orientation user_rotation setting"
  }.each do |key, label|
    require_nonempty_evidence_file(
      issues,
      "Android #{profile_name} #{label}",
      stream_orientation_artifacts[key],
      profile_evidence_dir
    )
  end

  rtsp_url = profile_evidence["rtspUrl"]
  profile_rtsp_endpoint = nil
  require_value(issues, non_empty_string?(rtsp_url), "Android #{profile_name} RTSP URL must be recorded")
  if non_empty_string?(rtsp_url)
    profile_rtsp_endpoint = canonical_rtsp_endpoint(rtsp_url)
    host = rtsp_host(rtsp_url)
    require_value(issues, non_empty_string?(host), "Android #{profile_name} RTSP URL must use the rtsp:// scheme with a host")
    if non_empty_string?(host)
      require_value(
        issues,
        !local_or_emulator_rtsp_host?(host),
        "Android #{profile_name} RTSP URL must be a real physical-phone LAN address"
      )
    end
  end
  validate_android_network_evidence(issues, profile_name, profile_evidence, rtsp_url)

  expected_resolution = profile_evidence["expectedResolution"]
  require_value(issues, non_empty_string?(expected_resolution), "Android #{profile_name} expectedResolution must be recorded")
  expected_bitrate_mbps = android_profile_expected_bitrate_mbps(profile_name)
  max_incoming_mbps = android_profile_max_incoming_mbps(profile_name)
  require_value(
    issues,
    approximately_equal?(profile_evidence["expectedBitrateMbps"], expected_bitrate_mbps),
    "Android #{profile_name} expectedBitrateMbps must match profile"
  )
  require_value(
    issues,
    approximately_equal?(profile_evidence["maxAllowedIncomingMbps"], max_incoming_mbps),
    "Android #{profile_name} maxAllowedIncomingMbps must match profile"
  )

  direct = profile_evidence["directDecode"].is_a?(Hash) ? profile_evidence["directDecode"] : {}
  require_value(issues, direct["status"] == "passed", "Android #{profile_name} direct LAN decode must be passed")
  require_value(issues, direct["exitStatus"] == 0, "Android #{profile_name} direct LAN decode exit status must be 0")
  if frames_requested.is_a?(Integer)
    require_value(issues, direct["frames"] == frames_requested, "Android #{profile_name} direct LAN decode frame count must match request")
  end
  if non_empty_string?(expected_resolution)
    require_value(issues, direct["resolution"] == expected_resolution, "Android #{profile_name} direct LAN decode resolution must match profile")
  end
  validate_android_decode_metrics(issues, profile_name, "direct LAN decode", direct, max_incoming_mbps)
  require_decoded_frame_file(
    issues,
    "Android #{profile_name} direct LAN decoded frame snapshot",
    direct["snapshot"],
    profile_evidence_dir
  )
  require_matching_physical_rtsp_url(
    issues,
    "Android #{profile_name} direct LAN decode",
    direct["openedRtspUrl"],
    profile_rtsp_endpoint,
    "the profile RTSP URL"
  )

  discovery = profile_evidence["pairCodeDiscoveryDecode"].is_a?(Hash) ? profile_evidence["pairCodeDiscoveryDecode"] : {}
  require_value(issues, discovery["status"] == "passed", "Android #{profile_name} pair-code discovery decode must be passed")
  require_value(issues, discovery["exitStatus"] == 0, "Android #{profile_name} pair-code discovery decode exit status must be 0")
  require_value(issues, discovery["pairingCode"] == pairing_code, "Android #{profile_name} pair-code discovery pairingCode must match the UI pairing code")
  if frames_requested.is_a?(Integer)
    require_value(issues, discovery["frames"] == frames_requested, "Android #{profile_name} pair-code discovery frame count must match request")
  end
  if non_empty_string?(expected_resolution)
    require_value(issues, discovery["resolution"] == expected_resolution, "Android #{profile_name} pair-code discovery resolution must match profile")
  end
  validate_android_decode_metrics(issues, profile_name, "pair-code discovery", discovery, max_incoming_mbps)
  require_decoded_frame_file(
    issues,
    "Android #{profile_name} pair-code discovery decoded frame snapshot",
    discovery["snapshot"],
    profile_evidence_dir
  )
  discovery_rtsp_url = discovery["selectedRtspUrl"] || discovery["openedRtspUrl"]
  require_matching_physical_rtsp_url(
    issues,
    "Android #{profile_name} pair-code discovery",
    discovery_rtsp_url,
    profile_rtsp_endpoint,
    "the profile RTSP URL"
  )

  logcat = profile_evidence["logcat"].is_a?(Hash) ? profile_evidence["logcat"] : {}
  require_value(issues, logcat["crashFree"] == true, "Android #{profile_name} logcat must be crash-free")
  require_value(issues, logcat["streamConfigFailureFree"] == true, "Android #{profile_name} logcat must be stream-config-failure-free")

  artifacts = profile_evidence["artifacts"].is_a?(Hash) ? profile_evidence["artifacts"] : {}
  {
    "summary" => "summary",
    "initialUi" => "initial UI dump",
    "profileUi" => "profile UI dump",
    "streamRotationUi" => "stream rotation UI dump",
    "logcatAfterStart" => "post-start logcat"
  }.each do |key, label|
    require_nonempty_evidence_file(
      issues,
      "Android #{profile_name} #{label}",
      artifacts[key],
      profile_evidence_dir
    )
  end
  require_evidence_text_includes(
    issues,
    "Android #{profile_name} compact streaming UI dump",
    artifacts["streamingCompactUi"],
    profile_evidence_dir,
    "PREVIEW LIVE"
  )
  require_evidence_text_includes(
    issues,
    "Android #{profile_name} streaming UI dump",
    artifacts["streamingUi"],
    profile_evidence_dir,
    "Preview: live"
  )
  {
    "initialScreenshot" => "initial screenshot",
    "profileScreenshot" => "profile screenshot",
    "streamingCompactScreenshot" => "compact streaming screenshot",
    "streamingScreenshot" => "streaming screenshot",
    "streamRotationScreenshot" => "stream rotation screenshot"
  }.each do |key, label|
    require_evidence_image_file(
      issues,
      "Android #{profile_name} #{label}",
      artifacts[key],
      profile_evidence_dir
    )
  end

  front = profile_evidence["frontCamera"].is_a?(Hash) ? profile_evidence["frontCamera"] : {}
  return false unless front["verified"] == true

  require_value(issues, front["switchStatus"] == "passed", "Android #{profile_name} front-camera switch must be passed")
  require_value(issues, front["decodeStatus"] == "passed", "Android #{profile_name} front-camera decode must be passed")
  require_value(issues, front["orientationStatus"] == "passed", "Android #{profile_name} front-camera orientation status must be passed")
  require_value(issues, front["orientationEvidenceCaptured"] == true, "Android #{profile_name} front-camera orientation evidence must be captured")
  require_value(issues, front["orientationEvidenceVersion"].is_a?(Integer) && front["orientationEvidenceVersion"] >= 4,
                "Android #{profile_name} front-camera orientation evidence must be version 4 or newer")
  require_value(issues, front["rotationControlMode"] == "per-camera-output",
                "Android #{profile_name} front-camera orientation rotationControlMode must be per-camera-output")
  require_value(issues, front["orientationLockMode"] == "fixed-landscape",
                "Android #{profile_name} front-camera orientation orientationLockMode must be fixed-landscape")
  require_value(issues, %w[tap-count absolute-degrees].include?(front["rotationRequestMode"]),
                "Android #{profile_name} front-camera rotationRequestMode must be tap-count or absolute-degrees")
  require_value(issues, rotation_direction?(front["rotationDirection"]),
                "Android #{profile_name} front-camera rotationDirection must be left or right")
  require_value(issues, rotation_taps?(front["rotateTaps"]),
                "Android #{profile_name} front-camera rotateTaps must be recorded as 0..3")
  require_value(issues, rotation_degrees?(front["outputRotationDegrees"]),
                "Android #{profile_name} front-camera output rotation degrees must be recorded as 0/90/180/270")
  if front["rotationRequestMode"] == "absolute-degrees"
    require_value(issues, rotation_degrees?(front["requestedOutputRotationDegrees"]),
                  "Android #{profile_name} front-camera requested output rotation degrees must be 0/90/180/270")
    if rotation_degrees?(front["requestedOutputRotationDegrees"]) && rotation_degrees?(front["outputRotationDegrees"])
      require_value(issues, front["outputRotationDegrees"] == front["requestedOutputRotationDegrees"],
                    "Android #{profile_name} front-camera output rotation degrees must match the requested target")
    end
  end
  require_value(issues, non_empty_string?(front["orientationNotes"]), "Android #{profile_name} front-camera orientation notes must be recorded")
  require_value(issues, non_empty_string?(front["devicePosture"]), "Android #{profile_name} front-camera device posture must be recorded")
  require_value(issues, non_empty_string?(front["cameraDiagnostics"]), "Android #{profile_name} front-camera cameraDiagnostics must be recorded")
  if frames_requested.is_a?(Integer)
    require_value(issues, front["frames"] == frames_requested, "Android #{profile_name} front-camera decode frame count must match request")
  end
  if non_empty_string?(expected_resolution)
    require_value(issues, front["resolution"] == expected_resolution, "Android #{profile_name} front-camera decode resolution must match profile")
  end
  validate_android_decode_metrics(issues, profile_name, "front-camera decode", front, max_incoming_mbps)
  front_endpoint = require_matching_physical_rtsp_url(
    issues,
    "Android #{profile_name} front-camera decode",
    front["openedRtspUrl"],
    profile_rtsp_endpoint,
    "the profile RTSP URL"
  )
  orientation_artifacts = front["orientationArtifacts"].is_a?(Hash) ? front["orientationArtifacts"] : {}
  {
    "input" => "input dump",
    "window" => "window dump",
    "display" => "display dump",
    "accelerometerRotation" => "accelerometer_rotation setting",
    "userRotation" => "user_rotation setting"
  }.each do |key, label|
    require_nonempty_evidence_file(
      issues,
      "Android #{profile_name} front-camera orientation #{label}",
      orientation_artifacts[key],
      profile_evidence_dir
    )
  end
  front_artifacts = front["artifacts"].is_a?(Hash) ? front["artifacts"] : {}
  {
    "switchUi" => "front-camera switch UI dump",
    "finalSwitchUi" => "front-camera final switch UI dump",
    "rotationUi" => "front-camera rotation UI dump",
    "receiverStdout" => "front-camera receiver stdout",
    "logcatAfterSwitch" => "front-camera switch logcat",
    "logcatAfterFrontReceiver" => "front-camera receiver logcat"
  }.each do |key, label|
    require_nonempty_evidence_file(
      issues,
      "Android #{profile_name} #{label}",
      front_artifacts[key],
      profile_evidence_dir
    )
  end
  require_decoded_frame_file(
    issues,
    "Android #{profile_name} front-camera decoded frame snapshot",
    front_artifacts["receiverSnapshot"],
    profile_evidence_dir
  )
  {
    "switchScreenshot" => "front-camera switch screenshot",
    "finalSwitchScreenshot" => "front-camera final switch screenshot",
    "rotationScreenshot" => "front-camera rotation screenshot"
  }.each do |key, label|
    require_evidence_image_file(
      issues,
      "Android #{profile_name} #{label}",
      front_artifacts[key],
      profile_evidence_dir
    )
  end

  front["switchStatus"] == "passed" &&
    profile_evidence["previewLive"] == true &&
    front["decodeStatus"] == "passed" &&
    front["orientationStatus"] == "passed" &&
    front["orientationEvidenceCaptured"] == true &&
    front["orientationEvidenceVersion"].is_a?(Integer) &&
    front["orientationEvidenceVersion"] >= 4 &&
    front["rotationControlMode"] == "per-camera-output" &&
    front["orientationLockMode"] == "fixed-landscape" &&
    rotation_direction?(front["rotationDirection"]) &&
    rotation_taps?(front["rotateTaps"]) &&
    rotation_degrees?(front["outputRotationDegrees"]) &&
    non_empty_string?(front["devicePosture"]) &&
    non_empty_string?(front["cameraDiagnostics"]) &&
    (!frames_requested.is_a?(Integer) || front["frames"] == frames_requested) &&
    (!non_empty_string?(expected_resolution) || front["resolution"] == expected_resolution) &&
    front_endpoint &&
    (!profile_rtsp_endpoint || front_endpoint == profile_rtsp_endpoint)
end

def validate_windows_runtime_logs(issues, windows_runtime, base_dir, capture_required, runtime_rtsp_url, manual_evidence_path)
  logs = windows_runtime["logs"].is_a?(Hash) ? windows_runtime["logs"] : {}
  require_value(issues, !logs.empty?, "Windows runtime logs must be recorded")
  return if logs.empty?

  require_nonempty_evidence_file(issues, "Windows runtime summary log", logs["summary"], base_dir)
  require_nonempty_evidence_file(issues, "Windows runtime receiver stdout log", logs["receiverStdout"], base_dir)
  require_nonempty_evidence_file(issues, "Windows runtime DirectShow device log", logs["directShowDevices"], base_dir)
  if capture_required
    require_nonempty_evidence_file(issues, "Windows runtime capture log", logs["capture"], base_dir)
    require_nonempty_evidence_file(issues, "Windows runtime DirectShow snapshot log", logs["directShowSnapshot"], base_dir)
  end
  if windows_runtime["receiverKeptRunning"] == true
    require_nonempty_evidence_file(issues, "Windows runtime manual app checklist", logs["manualAppChecklist"], base_dir)
    require_nonempty_evidence_file(issues, "Windows runtime manual evidence template", logs["manualEvidenceTemplate"], base_dir)
    if non_empty_string?(manual_evidence_path) && non_empty_string?(logs["manualEvidenceTemplate"])
      expected_manual_path = File.expand_path(manual_evidence_path).tr("\\", "/")
      actual_manual_path = normalized_evidence_path(logs["manualEvidenceTemplate"], base_dir)
      require_value(
        issues,
        actual_manual_path == expected_manual_path,
        "Windows runtime manualEvidenceTemplate path must match --windows-manual"
      )
    end
  end

  summary_text = evidence_file_text(logs["summary"], base_dir)
  if summary_text
    require_value(issues, summary_text.include?("PhoneCam Windows runtime verification passed"), "Windows runtime summary log must record a passed verification")
  end

  receiver_stdout = evidence_file_text(logs["receiverStdout"], base_dir)
  if receiver_stdout && non_empty_string?(runtime_rtsp_url)
    require_value(issues, receiver_stdout.include?(runtime_rtsp_url), "Windows runtime receiver stdout log must contain the selected Android RTSP URL")
  end

  camera_name = windows_runtime["cameraName"]
  directshow_text = evidence_file_text(logs["directShowDevices"], base_dir)
  if directshow_text && non_empty_string?(camera_name)
    require_value(issues, directshow_text.include?(camera_name), "Windows runtime DirectShow device log must contain cameraName")
  end

  return unless capture_required

  capture_text = evidence_file_text(logs["capture"], base_dir)
  requested_frames = windows_runtime["capture"].is_a?(Hash) ? windows_runtime["capture"]["requestedFrames"] : nil
  camera_name = windows_runtime["cameraName"]
  if capture_text && non_empty_string?(camera_name)
    require_value(issues, capture_text.include?(camera_name), "Windows runtime capture log must contain cameraName")
  end
  snapshot_text = evidence_file_text(logs["directShowSnapshot"], base_dir)
  if snapshot_text && non_empty_string?(camera_name)
    require_value(issues, snapshot_text.include?(camera_name), "Windows runtime DirectShow snapshot log must contain cameraName")
  end
  capture_log_frames = max_ffmpeg_frame_count(capture_text)
  if requested_frames.is_a?(Integer) && requested_frames.positive?
    require_value(
      issues,
      capture_log_frames.is_a?(Integer) && capture_log_frames >= requested_frames,
      "Windows runtime capture log must show at least requestedFrames"
    )
  end
end

issues = []

android_matrix = load_json(options[:android_matrix], "Android matrix evidence", issues)
windows_runtime = options[:android_only] ? {} : load_json(options[:windows_runtime], "Windows runtime evidence", issues)
windows_manual = options[:android_only] ? {} : load_json(options[:windows_manual], "Windows manual app evidence", issues)
runtime_rtsp_url = nil
runtime_rtsp_endpoint = nil
android_rtsp_endpoints = []
android_pairing_codes = []
windows_manual_base_dir = options[:windows_manual] ? File.dirname(File.expand_path(options[:windows_manual])) : Dir.pwd
windows_runtime_base_dir = options[:windows_runtime] ? File.dirname(File.expand_path(options[:windows_runtime])) : Dir.pwd
android_matrix_base_dir = options[:android_matrix] ? File.dirname(File.expand_path(options[:android_matrix])) : Dir.pwd
windows_manual_path = options[:windows_manual] ? File.expand_path(options[:windows_manual]) : nil
runtime_receiver_process_id = nil

unless android_matrix.empty?
  require_value(issues, android_matrix["status"] == "passed", "Android matrix status must be passed")
  require_value(issues, android_matrix["finalMvpEvidence"] == true, "Android matrix evidence must be final MVP physical Wi-Fi matrix evidence")
  require_value(issues, android_matrix["allowUnverifiedOrientation"] == false, "Android matrix allowUnverifiedOrientation must be false for final MVP evidence")
  require_value(issues, android_matrix["matrixExitStatus"] == 0, "Android matrix exit status must be 0")
  require_value(issues, android_matrix["verifyFrontCamera"] == true, "Android matrix must verify front camera")

  profiles = android_matrix["profiles"]
  required_profiles = %w[Efficient Balanced Motion]
  require_value(issues, profiles.is_a?(Array), "Android matrix profiles must be an array")
  if profiles.is_a?(Array)
    by_name = profiles.each_with_object({}) { |profile, memo| memo[profile["profile"]] = profile }
    missing = required_profiles - by_name.keys
    require_value(issues, missing.empty?, "Android matrix missing profiles: #{missing.join(", ")}")
    front_camera_verified = false
    required_profiles.each do |profile_name|
      profile = by_name[profile_name]
      next unless profile

      require_value(issues, profile["status"] == "passed", "Android #{profile_name} profile must be passed")
      require_value(issues, profile["exitStatus"] == 0, "Android #{profile_name} exit status must be 0")
      require_value(issues, non_empty_string?(profile["evidenceDir"]), "Android #{profile_name} evidenceDir must be present")
      profile_evidence, profile_evidence_path = load_profile_evidence(profile["evidenceJson"], profile_name, issues, android_matrix_base_dir)
      unless profile_evidence.empty?
        android_rtsp_endpoints.concat(android_profile_rtsp_endpoints(profile_evidence))
        android_pairing_codes << profile_evidence["pairingCode"] if six_digit_pairing_code?(profile_evidence["pairingCode"])
        front_camera_verified = validate_android_profile_evidence(issues, profile_name, profile_evidence, profile_evidence_path) || front_camera_verified
      end
    end
    android_rtsp_endpoints.uniq!
    android_pairing_codes.uniq!
    require_value(issues, android_pairing_codes.size == 1, "Android matrix profiles must use one stable six-digit pairing code")
    require_value(issues, front_camera_verified, "Android matrix must include a passed front-camera switch and decode evidence")
  end
end

unless windows_runtime.empty?
  require_value(issues, windows_runtime["status"] == "passed", "Windows runtime status must be passed")
  require_value(issues, windows_runtime["mode"] == "windows-runtime-verification", "Windows runtime mode must be windows-runtime-verification")
  require_value(issues, windows_runtime["directShowCameraFound"] == true, "Windows runtime must find the DirectShow camera")
  require_value(issues, windows_runtime["receiverKeptRunning"] == true, "Windows runtime must keep receiver running for manual app checks")
  runtime_receiver_process_id = windows_runtime["receiverProcessId"]
  require_value(
    issues,
    positive_integer?(runtime_receiver_process_id),
    "Windows runtime receiverProcessId must be a positive integer"
  )

  source_mode = windows_runtime["sourceMode"]
  require_value(
    issues,
    ["auto-discovered Android RTSP", "manual RTSP"].include?(source_mode),
    "Windows runtime sourceMode must be a real Android RTSP mode"
  )
  require_value(issues, source_mode != "generated self-test", "Windows runtime generated self-test cannot satisfy final MVP evidence")

  runtime_recorded_endpoint = require_consistent_rtsp_url_fields(issues, "Windows runtime", windows_runtime)
  if ["auto-discovered Android RTSP", "manual RTSP"].include?(source_mode)
    require_value(
      issues,
      non_empty_string?(windows_runtime["openedRtspUrl"]),
      "Windows runtime openedRtspUrl must be recorded from receiver stdout"
    )
  end
  if source_mode == "auto-discovered Android RTSP"
    require_value(
      issues,
      non_empty_string?(windows_runtime["selectedRtspUrl"]),
      "Windows runtime auto-discovery selectedRtspUrl must be recorded from receiver stdout"
    )
  end
  runtime_rtsp_url = rtsp_url_for_runtime(windows_runtime)
  require_value(issues, non_empty_string?(runtime_rtsp_url), "Windows runtime must record the selected/opened Android RTSP URL")
  if non_empty_string?(runtime_rtsp_url)
    runtime_rtsp_endpoint = canonical_rtsp_endpoint(runtime_rtsp_url)
    runtime_rtsp_endpoint ||= runtime_recorded_endpoint
    host = rtsp_host(runtime_rtsp_url)
    require_value(issues, non_empty_string?(host), "Windows runtime RTSP URL must use the rtsp:// scheme with a host")
    if non_empty_string?(host)
      require_value(
        issues,
        !local_or_emulator_rtsp_host?(host),
        "Windows runtime RTSP URL must be a real Android LAN address, not localhost/emulator/placeholder"
      )
    end
  end

  capture = windows_runtime["capture"].is_a?(Hash) ? windows_runtime["capture"] : {}
  require_value(issues, capture["skipped"] == false, "Windows runtime DirectShow capture must not be skipped")
  require_value(issues, capture["frames"].is_a?(Integer) && capture["frames"].positive?, "Windows runtime must capture at least one DirectShow frame")
  requested_frames = capture["requestedFrames"]
  require_value(
    issues,
    requested_frames.is_a?(Integer) && requested_frames.positive?,
    "Windows runtime DirectShow capture requestedFrames must be positive"
  )
  if capture["frames"].is_a?(Integer) && requested_frames.is_a?(Integer) && requested_frames.positive?
    require_value(
      issues,
      capture["frames"] >= requested_frames,
      "Windows runtime DirectShow capture frame count must meet requestedFrames"
    )
  end
  require_evidence_image_file(
    issues,
    "Windows runtime DirectShow captured frame snapshot",
    capture["snapshot"],
    windows_runtime_base_dir
  )
  validate_windows_runtime_logs(
    issues,
    windows_runtime,
    windows_runtime_base_dir,
    capture["skipped"] == false,
    runtime_rtsp_url,
    windows_manual_path
  )

  if source_mode == "auto-discovered Android RTSP"
    pair_code = windows_runtime["pairCode"]
    require_value(issues, six_digit_pairing_code?(pair_code), "Windows runtime auto-discovery pairCode must be six digits")
    if six_digit_pairing_code?(pair_code) && android_pairing_codes.size == 1
      require_value(issues, pair_code == android_pairing_codes.first, "Windows runtime pairCode must match the physical Android matrix pairing code")
    end
  end

  require_value(issues, non_empty_string?(windows_runtime["cameraName"]), "Windows runtime cameraName must be present")
end

if !android_matrix.empty? && !windows_runtime.empty?
  require_value(issues, !android_rtsp_endpoints.empty?, "Android matrix must provide RTSP URLs for Windows runtime cross-checking")
  if runtime_rtsp_endpoint && !android_rtsp_endpoints.empty?
    require_value(
      issues,
      android_rtsp_endpoints.include?(runtime_rtsp_endpoint),
      "Windows runtime RTSP URL must match a physical Android matrix RTSP URL"
    )
  end
end

unless windows_manual.empty?
  require_value(issues, windows_manual["status"] == "passed", "Windows manual app evidence status must be passed")
  require_value(issues, windows_manual["receiverKeptRunning"] == true, "Windows manual app evidence must be tied to a kept-running receiver")
  manual_receiver_process_id = windows_manual["receiverProcessId"]
  require_value(
    issues,
    positive_integer?(manual_receiver_process_id),
    "Windows manual app evidence receiverProcessId must be a positive integer"
  )
  if positive_integer?(manual_receiver_process_id) && positive_integer?(runtime_receiver_process_id)
    require_value(
      issues,
      manual_receiver_process_id == runtime_receiver_process_id,
      "Windows manual app evidence receiverProcessId must match runtime evidence"
    )
  end
  require_value(issues, non_empty_string?(windows_manual["cameraName"]), "Windows manual app evidence cameraName must be present")
  if non_empty_string?(windows_manual["cameraName"]) && non_empty_string?(windows_runtime["cameraName"])
    require_value(issues, windows_manual["cameraName"] == windows_runtime["cameraName"], "Windows manual app evidence cameraName must match runtime evidence")
  end

  runtime_artifacts = windows_manual["runtimeArtifacts"].is_a?(Hash) ? windows_manual["runtimeArtifacts"] : {}
  require_value(issues, !runtime_artifacts.empty?, "Windows manual app evidence runtimeArtifacts must be present")
  require_value(
    issues,
    windows_manual["directShowFrameMatchesExpectedAndroidStream"] == true,
    "Windows manual app evidence directShowFrameMatchesExpectedAndroidStream must be true"
  )
  require_value(
    issues,
    non_empty_string?(windows_manual["directShowFrameReviewNote"]),
    "Windows manual app evidence directShowFrameReviewNote must be recorded"
  )
  unless windows_runtime.empty?
    runtime_capture = windows_runtime["capture"].is_a?(Hash) ? windows_runtime["capture"] : {}
    runtime_logs = windows_runtime["logs"].is_a?(Hash) ? windows_runtime["logs"] : {}
    require_matching_runtime_artifact(
      issues,
      "directShowFrameSnapshot",
      runtime_artifacts["directShowFrameSnapshot"],
      runtime_capture["snapshot"],
      windows_manual_base_dir,
      windows_runtime_base_dir
    )
    require_matching_runtime_artifact(
      issues,
      "directShowSnapshotLog",
      runtime_artifacts["directShowSnapshotLog"],
      runtime_logs["directShowSnapshot"],
      windows_manual_base_dir,
      windows_runtime_base_dir
    )
    require_matching_runtime_artifact(
      issues,
      "directShowCaptureLog",
      runtime_artifacts["directShowCaptureLog"],
      runtime_logs["capture"],
      windows_manual_base_dir,
      windows_runtime_base_dir
    )
  end

  manual_source_mode = windows_manual["sourceMode"]
  require_value(
    issues,
    ["auto-discovered Android RTSP", "manual RTSP"].include?(manual_source_mode),
    "Windows manual app evidence sourceMode must be a real Android RTSP mode"
  )
  if non_empty_string?(manual_source_mode) && non_empty_string?(windows_runtime["sourceMode"])
    require_value(
      issues,
      manual_source_mode == windows_runtime["sourceMode"],
      "Windows manual app evidence sourceMode must match runtime evidence"
    )
  end

  require_consistent_rtsp_url_fields(issues, "Windows manual app evidence", windows_manual)
  manual_rtsp_url = rtsp_url_for_runtime(windows_manual)
  require_value(issues, non_empty_string?(manual_rtsp_url), "Windows manual app evidence must record the selected/opened Android RTSP URL")
  if non_empty_string?(manual_rtsp_url)
    host = rtsp_host(manual_rtsp_url)
    require_value(issues, non_empty_string?(host), "Windows manual app evidence RTSP URL must use the rtsp:// scheme with a host")
    if non_empty_string?(host)
      require_value(
        issues,
        !local_or_emulator_rtsp_host?(host),
        "Windows manual app evidence RTSP URL must be a real Android LAN address"
      )
    end
    if non_empty_string?(runtime_rtsp_url)
      require_value(issues, manual_rtsp_url == runtime_rtsp_url, "Windows manual app evidence RTSP URL must match runtime evidence")
    end
  end

  obs = windows_manual["obs"].is_a?(Hash) ? windows_manual["obs"] : {}
  require_value(issues, non_empty_string?(obs["version"]), "OBS version must be recorded")
  require_value(issues, obs["cameraListed"] == true, "OBS must list the PhoneCam camera")
  require_value(issues, obs["liveFramesRendered"] == true, "OBS must render live frames")
  obs_screenshot = screenshot_reference(obs)
  require_value(issues, non_empty_string?(obs_screenshot), "OBS screenshotPath must be recorded")
  require_value(issues, evidence_file_exists?(obs_screenshot, windows_manual_base_dir), "OBS screenshotPath file must exist")
  require_value(issues, evidence_file_nonempty?(obs_screenshot, windows_manual_base_dir), "OBS screenshotPath file must be non-empty")
  require_value(issues, evidence_image_file?(obs_screenshot, windows_manual_base_dir), "OBS screenshotPath file must be a PNG, JPEG, or BMP image")
  obs_screenshot_path = normalized_evidence_path(obs_screenshot, windows_manual_base_dir) if non_empty_string?(obs_screenshot)

  browser = windows_manual["browserOrCameraApp"].is_a?(Hash) ? windows_manual["browserOrCameraApp"] : {}
  require_value(issues, non_empty_string?(browser["app"]), "Browser/camera app name must be recorded")
  require_value(issues, non_empty_string?(browser["version"]), "Browser/camera app version must be recorded")
  require_value(issues, browser["cameraListed"] == true, "Browser/camera app must list the PhoneCam camera")
  require_value(issues, browser["liveFramesRendered"] == true, "Browser/camera app must render live frames")
  browser_screenshot = screenshot_reference(browser)
  require_value(issues, non_empty_string?(browser_screenshot), "Browser/camera app screenshotPath must be recorded")
  require_value(issues, evidence_file_exists?(browser_screenshot, windows_manual_base_dir), "Browser/camera app screenshotPath file must exist")
  require_value(issues, evidence_file_nonempty?(browser_screenshot, windows_manual_base_dir), "Browser/camera app screenshotPath file must be non-empty")
  require_value(issues, evidence_image_file?(browser_screenshot, windows_manual_base_dir), "Browser/camera app screenshotPath file must be a PNG, JPEG, or BMP image")
  browser_screenshot_path = normalized_evidence_path(browser_screenshot, windows_manual_base_dir) if non_empty_string?(browser_screenshot)

  directshow_snapshot_path = normalized_evidence_path(
    runtime_artifacts["directShowFrameSnapshot"],
    windows_manual_base_dir
  ) if non_empty_string?(runtime_artifacts["directShowFrameSnapshot"])
  if obs_screenshot_path && browser_screenshot_path
    require_value(
      issues,
      obs_screenshot_path != browser_screenshot_path,
      "OBS and browser/camera app screenshots must be distinct files"
    )
    obs_screenshot_hash = evidence_file_sha256(obs_screenshot, windows_manual_base_dir)
    browser_screenshot_hash = evidence_file_sha256(browser_screenshot, windows_manual_base_dir)
    if obs_screenshot_hash && browser_screenshot_hash
      require_value(
        issues,
        obs_screenshot_hash != browser_screenshot_hash,
        "OBS and browser/camera app screenshots must have different image content"
      )
    end
  end
  if directshow_snapshot_path
    require_value(
      issues,
      obs_screenshot_path != directshow_snapshot_path,
      "OBS screenshotPath must be a separate app screenshot, not the DirectShow frame snapshot"
    )
    require_value(
      issues,
      browser_screenshot_path != directshow_snapshot_path,
      "Browser/camera app screenshotPath must be a separate app screenshot, not the DirectShow frame snapshot"
    )
    directshow_snapshot_hash = evidence_file_sha256(
      runtime_artifacts["directShowFrameSnapshot"],
      windows_manual_base_dir
    )
    if directshow_snapshot_hash
      obs_screenshot_hash ||= evidence_file_sha256(obs_screenshot, windows_manual_base_dir)
      browser_screenshot_hash ||= evidence_file_sha256(browser_screenshot, windows_manual_base_dir)
      require_value(
        issues,
        obs_screenshot_hash != directshow_snapshot_hash,
        "OBS screenshotPath must not duplicate the DirectShow frame snapshot content"
      ) if obs_screenshot_hash
      require_value(
        issues,
        browser_screenshot_hash != directshow_snapshot_hash,
        "Browser/camera app screenshotPath must not duplicate the DirectShow frame snapshot content"
      ) if browser_screenshot_hash
    end
  end
end

if issues.any?
  warn(options[:android_only] ? "Android matrix evidence validation failed:" : "MVP evidence validation failed:")
  issues.each { |issue| warn " - #{issue}" }
  exit 2
end

puts(options[:android_only] ? "Android matrix evidence validation passed" : "MVP evidence validation passed")
