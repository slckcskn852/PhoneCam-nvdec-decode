#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"

ROOT = File.expand_path("..", __dir__)

def read(relative_path)
  File.read(File.join(ROOT, relative_path))
end

def assert(condition, message)
  return if condition

  abort(message)
end

def write_json(path, data)
  File.write(path, JSON.pretty_generate(data))
end

FIXTURE_PNG = "\x89PNG\r\n\x1A\nfixture image evidence".b
FIXTURE_BROWSER_PNG = "\x89PNG\r\n\x1A\nfixture browser image evidence".b
FIXTURE_DIRECTSHOW_BMP = "BMfixture directshow frame".b
FIXTURE_PPM = "P6\n1 1\n255\nabc".b

def write_fixture_artifact(path, text)
  if File.extname(path).casecmp(".png").zero?
    File.binwrite(path, FIXTURE_PNG)
  elsif File.extname(path).casecmp(".ppm").zero?
    File.binwrite(path, FIXTURE_PPM)
  else
    File.write(path, text)
  end
end

def flattened_manifest_strings(value)
  case value
  when Hash
    value.values.flat_map { |child| flattened_manifest_strings(child) }
  when Array
    value.flat_map { |child| flattened_manifest_strings(child) }
  when String
    [value]
  else
    []
  end
end

workflow_text = read(".github/workflows/build.yml")
workflow = YAML.load_file(File.join(ROOT, ".github/workflows/build.yml"))
assert(workflow.is_a?(Hash) && workflow["jobs"].is_a?(Hash), "workflow yaml did not parse to a jobs hash")
assert(workflow_text.include?("scripts\\Collect-PhoneCamWindowsEvidence.ps1"),
       "Windows workflow package check must require the evidence collector")
assert(workflow_text.include?("scripts/mac_receiver_dev_smoke.sh") &&
       workflow_text.include?("scripts/mac_receiver_fixture_smoke.sh") &&
       workflow_text.include?("scripts/package_mac_receiver_app.sh") &&
       workflow_text.include?("scripts/local_verification.sh"),
       "workflow shell syntax check must include Mac receiver helper scripts")
assert(workflow_text.include?("ROTATION_PLAN_SELF_TEST=1 scripts/android_wifi_receiver_smoke.sh"),
       "workflow static contracts must run the Android rotation planning self-test")
mac_job = workflow.fetch("jobs").fetch("mac-receiver", nil)
assert(mac_job && mac_job["runs-on"] == "macos-latest", "workflow must include a macOS receiver build job")
assert(workflow_text.include?("brew install ffmpeg") &&
       workflow_text.include?("PHONECAM_WITH_SOFTCAM=OFF") &&
       workflow_text.include?("ctest --test-dir build/macos-receiver") &&
       workflow_text.include?("dist/PhoneCam-Mac/PhoneCam Receiver.app"),
       "macOS receiver job must install FFmpeg, build preview-only, run CTest, and package the dev app")

manifest = JSON.parse(read("desktop/windows/vcpkg.json"))
ffmpeg = manifest.fetch("dependencies").find do |dep|
  dep.is_a?(Hash) && dep["name"] == "ffmpeg"
end
assert(ffmpeg, "desktop/windows/vcpkg.json is missing an ffmpeg dependency object")
assert(ffmpeg["default-features"] == false, "ffmpeg default-features must stay false for LGPL-clean packaging")

features = Array(ffmpeg["features"])
required_features = %w[avcodec avformat swscale]
missing_features = required_features - features
assert(missing_features.empty?, "ffmpeg missing required features: #{missing_features.join(", ")}")

forbidden_features = %w[gpl nonfree all-gpl all-nonfree x264 x265 fdk-aac]
bad_features = features & forbidden_features
assert(bad_features.empty?, "ffmpeg uses forbidden GPL/nonfree features: #{bad_features.join(", ")}")

package_script = read("desktop/windows/scripts/Package-PhoneCamWindows.ps1")
windows_readme = read("desktop/windows/README.md")
prepare_softcam_script = read("desktop/windows/scripts/Prepare-PhoneCamSoftcam.ps1")
receiver_cmake = read("desktop/windows/CMakeLists.txt")
receiver_source = read("desktop/windows/src/main.cpp")
third_party_notices = read("docs/third-party-notices.md")
assert(package_script.include?("$packageReadmeTemplate = @'") &&
       package_script.include?("__RUNTIME_FFMPEG_NOTE__") &&
       package_script.include?("__RUNTIME_FFMPEG_PATH__") &&
       package_script.include?('$packageReadmeTemplate.Replace("__RUNTIME_FFMPEG_NOTE__", $runtimeFfmpegNote).Replace("__RUNTIME_FFMPEG_PATH__", $runtimeFfmpegPath)'),
       "Windows package README generation must use a literal template so Markdown and PowerShell backticks are preserved")
assert(receiver_source.include?("--snapshot") && receiver_source.include?("Snapshot written:"),
       "receiver must support decoded frame snapshots for physical evidence")
assert(receiver_source.include?("__APPLE__") && receiver_source.include?("NSWindow") &&
       receiver_source.include?("macOS preview sink active"),
       "receiver must keep a real macOS preview sink for Mac dev validation")
assert(receiver_cmake.include?("enable_language(OBJCXX)") && receiver_cmake.include?("-framework Cocoa"),
       "receiver CMake must compile and link the macOS preview sink on Apple hosts")
assert(package_script.include?('-Filter "*.dll"'), "Windows packager must copy all runtime DLLs from the FFmpeg/vcpkg bin directory")
assert(package_script.include?('@("avcodec", "avformat", "avutil", "swscale")'),
       "Windows packager must require core FFmpeg runtime DLLs")
assert(package_script.include?("Test-PhoneCamWindowsRuntime.ps1"), "Windows package must include runtime verification script")
assert(package_script.include?("Collect-PhoneCamWindowsEvidence.ps1"), "Windows package must include evidence collector script")
assert(package_script.include?("- scripts\\Collect-PhoneCamWindowsEvidence.ps1"),
       "Windows package README must list the evidence collector script")
assert(package_script.include?("- scripts\\Test-PhoneCamReceiverFixture.ps1"),
       "Windows package README must list the RTSP receiver fixture helper")
assert(package_script.include?("- scripts\\Prepare-PhoneCamSoftcam.ps1"),
       "Windows package README must list the Softcam preparation helper")
assert(package_script.include?("Install-PhoneCamFirewallRules.ps1"), "Windows package must include firewall helper")
assert(package_script.include?("validate_mvp_evidence.rb"), "Windows package must include final MVP evidence validator")
assert(package_script.include?("bundle_mvp_evidence.rb"), "Windows package must include portable MVP evidence bundler")
assert(package_script.include?("Ruby available as `ruby` on PATH") &&
       package_script.include?("-Ruby C:\\path\\to\\ruby.exe") &&
       package_script.include?("Android matrix preflight, final MVP validator, and portable evidence bundler"),
       "Windows package README must document the Ruby prerequisite for final evidence collection")
assert(package_script.include?("-AutoDiscover") && package_script.include?("-RtspUrl"),
       "Windows package README must document Android RTSP-to-DirectShow verification")
assert(package_script.include?("-KeepReceiverRunning"),
       "Windows package README must document keeping the receiver running for OBS/browser checks")
assert(package_script.include?("-UnregisterOnly"),
       "Windows package README must document Softcam cleanup after OBS/browser checks")
assert(package_script.include?("runtime-evidence.json"),
       "Windows package README must document the structured runtime evidence artifact")
assert(package_script.include?("-PreflightOnly") && package_script.include?("windows-preflight-evidence.json"),
       "Windows package README must document runtime preflight evidence")
assert(package_script.include?("no-capture collector preflight") &&
       package_script.include?("without changing firewall state") &&
       package_script.include?("registering/capturing DirectShow") &&
       package_script.include?("bundling final evidence"),
       "Windows package README must document collector preflight-only mode")
assert(package_script.include?("manual-app-evidence-template.json"),
       "Windows package README must document the manual app evidence template")
assert(package_script.include?("docs\\testing.md"),
       "Windows package must include the repo testing runbook")
assert(package_script.include?("- docs\\SOFTCAM_BRANDING.md"),
       "Windows package README must list the Softcam branding guide")
assert(package_script.include?("docs\\verification-report.md"),
       "Windows package must include the current verification report")
assert(package_script.include?("Get-SoftcamBrandingReport") &&
       package_script.include?("PHONECAM-SOFTCAM-BUILD.txt") &&
       package_script.include?("SOFTCAM-BUILD.txt") &&
       package_script.include?("PhoneCam Virtual Camera") &&
       package_script.include?("{1BF2F2F1-5C41-4C0B-B53B-B606627B60F3}") &&
       package_script.include?("Softcam branding verification failed"),
       "Windows package must verify and include PhoneCam-branded Softcam build metadata")
assert(prepare_softcam_script.include?("PHONECAM-SOFTCAM-BUILD.txt") &&
       prepare_softcam_script.include?("Resolved commit") &&
       prepare_softcam_script.include?("Filter name: PhoneCam Virtual Camera") &&
       prepare_softcam_script.include?("CLSID: {1BF2F2F1-5C41-4C0B-B53B-B606627B60F3}") &&
       prepare_softcam_script.include?("Built softcam_installer.exe was not found"),
       "Softcam preparation script must write branded build metadata and require the installer")
assert(package_script.include?("-ValidateManualEvidence"),
       "Windows package README must document manual app evidence validation")
assert(package_script.include?("-RuntimeEvidence"),
       "Windows package README must document runtime/manual evidence cross-checking")
assert(package_script.include?("DirectShow capture logs naming the camera"),
       "Windows package README must document capture-log camera-name evidence")
assert(package_script.include?("DirectShow frame snapshot"),
       "Windows package README must document the saved DirectShow frame snapshot")
assert(package_script.include?("runtimeArtifacts.directShowFrameSnapshot") &&
       package_script.include?("runtimeArtifacts.directShowSnapshotLog") &&
       package_script.include?("runtimeArtifacts.directShowCaptureLog") &&
       package_script.include?("directShowFrameMatchesExpectedAndroidStream") &&
       package_script.include?("directShowFrameReviewNote"),
       "Windows package README must document runtime artifact paths and DirectShow snapshot review in the generated manual template")
assert(package_script.include?("separate app screenshots") &&
       package_script.include?("different image content") &&
       package_script.include?("PNG, JPEG, or BMP") &&
       package_script.include?("must not reuse the DirectShow frame snapshot path or content"),
       "Windows package README must document distinct real OBS/browser screenshot image artifacts and content")
assert(package_script.include?("sender camera diagnostics") &&
       package_script.include?("device posture") &&
       package_script.include?("output-rotation degrees") &&
       package_script.include?("recorded Rotate Left/Rotate Right direction") &&
       package_script.include?("rotation request mode") &&
       package_script.include?("requested absolute output-rotation target when used") &&
       package_script.include?("target/output consistency") &&
       package_script.include?("orientationEvidenceVersion >= 4") &&
       package_script.include?("rotationControlMode per-camera-output") &&
       package_script.include?("orientationLockMode fixed-landscape"),
       "Windows package README must document the Android orientation diagnostics, explicit rotation direction, target consistency, and per-camera rotation evidence required before Windows evidence")
assert(windows_readme.include?("recorded `Rotate Left`/`Rotate Right` direction") &&
       windows_readme.include?("rotation request mode") &&
       windows_readme.include?("target/output consistency for absolute rotation targets") &&
       windows_readme.include?("requested absolute output-rotation target consistency") &&
       windows_readme.include?("resulting 0/90/180/270 output-rotation degrees"),
       "Windows README must document explicit Android rotation direction and target/output consistency for final evidence")
assert(package_script.include?("checks it against the stable six-digit pairing code recorded in the Android matrix") &&
       package_script.include?("before Windows preflight or DirectShow registration starts") &&
       package_script.include?("A mistyped code fails early"),
       "Windows package README must document the collector's Android-matrix pair-code preflight")
assert(package_script.include?("bundle-manifest.json"),
       "Windows package README must document portable evidence bundling")
assert(package_script.include?("PhoneCam-Android-Matrix-Handoff") &&
       package_script.include?("--android-only") &&
       package_script.include?("validates only the Android matrix") &&
       package_script.include?("does not replace Windows DirectShow, OBS, or browser evidence"),
       "Windows package README must document the Android-only portable handoff bundle")
assert(!package_script.include?("UnityCapture") && !package_script.include?("pyvirtualcam"),
       "Windows MVP package must not include legacy UnityCapture or pyvirtualcam prototype dependencies")
assert(third_party_notices.include?("Unity Capture") &&
       third_party_notices.include?("UnityCaptureFilter") &&
       third_party_notices.include?("MIT") &&
       third_party_notices.include?("zlib") &&
       third_party_notices.include?("reference material only"),
       "third-party notices must document the checked-in UnityCapture reference tree and its non-production status")
assert(third_party_notices.include?("pyvirtualcam") &&
       third_party_notices.include?("GPLv2") &&
       third_party_notices.include?("Do not package pyvirtualcam"),
       "third-party notices must document pyvirtualcam's GPLv2 legacy-only status")

collector_script = read("desktop/windows/scripts/Collect-PhoneCamWindowsEvidence.ps1")
%w[PreflightOnly KeepReceiverRunning FinalizeOnly validate_mvp_evidence.rb bundle_mvp_evidence.rb Install-PhoneCamFirewallRules.ps1 PairCode RtspUrl RuntimeEvidence ManualEvidence PhoneCam-MVP-Evidence Resolve-PowerShellExecutable Resolve-ExternalCommand Invoke-External Get-AndroidMatrixPairingCode Get-AndroidMatrixRtspEndpoints Get-CanonicalRtspEndpoint Resolve-EvidencePath Normalize-PairCode directShowFrameMatchesExpectedAndroidStream directShowFrameReviewNote].each do |expected|
  assert(collector_script.include?(expected), "Windows evidence collector must support #{expected}")
end
assert(collector_script.include?("$Label command not found") &&
       collector_script.include?("pass -$Label with the full executable path") &&
       collector_script.include?('Command $rubyExe'),
       "Windows evidence collector must resolve Ruby up front and use the resolved executable")
assert(collector_script.include?("-PairCode must contain exactly six digits."),
       "Windows evidence collector must reject malformed pair codes before runtime work")
assert(collector_script.include?("RtspUrl $RtspUrl does not match any Android matrix RTSP URL") &&
       collector_script.index("RtspUrl $RtspUrl does not match any Android matrix RTSP URL") &&
       collector_script.index("RtspUrl $RtspUrl does not match any Android matrix RTSP URL") < collector_script.index("Windows runtime preflight"),
       "Windows evidence collector must reject manual RTSP URLs that are not in the Android matrix before Windows preflight/runtime work")
assert(collector_script.include?("-SkipPreflight is not supported by the final evidence collector"),
       "Windows evidence collector must reject skipped preflight in final evidence runs")
assert(collector_script.include?("[switch]$PreflightOnly") &&
       collector_script.include?("-PreflightOnly cannot be combined with -FinalizeOnly") &&
       collector_script.include?("PhoneCam Windows evidence preflight passed.") &&
       collector_script.include?("No DirectShow capture, OBS/browser enumeration, firewall changes, or final MVP bundle were attempted.") &&
       collector_script.index("PhoneCam Windows evidence preflight passed.") &&
       collector_script.index("Windows runtime preflight") &&
       collector_script.index("Windows Android-to-DirectShow runtime evidence") &&
       collector_script.index("Windows runtime preflight") < collector_script.index("PhoneCam Windows evidence preflight passed.") &&
       collector_script.index("PhoneCam Windows evidence preflight passed.") < collector_script.index("Windows Android-to-DirectShow runtime evidence"),
       "Windows evidence collector must support a no-capture preflight-only mode before DirectShow runtime work")
assert(collector_script.include?("--android-only") &&
       collector_script.index("Android matrix evidence preflight") &&
       collector_script.index("Android matrix evidence preflight") < collector_script.index("Windows runtime preflight"),
       "Windows evidence collector must preflight Android matrix evidence before Windows runtime work")
assert(collector_script.include?("PairCode $PairCode does not match Android matrix pairing code") &&
       collector_script.index("Get-AndroidMatrixPairingCode") &&
       collector_script.index("PairCode $PairCode does not match Android matrix pairing code") &&
       collector_script.index("PairCode $PairCode does not match Android matrix pairing code") < collector_script.index("Windows runtime preflight"),
       "Windows evidence collector must reject mismatched pair codes before Windows preflight/runtime work")
assert(collector_script.include?('"-File", $runtimeScript'),
       "Windows evidence collector must run the runtime verifier in a child PowerShell process")

runtime_script = read("desktop/windows/scripts/Test-PhoneCamWindowsRuntime.ps1")
%w[RtspUrl AutoDiscover PairCode DiscoverSeconds Source\ mode KeepReceiverRunning UnregisterOnly PreflightOnly windows-runtime-preflight windows-preflight-evidence.json doesNotProve ValidateManualEvidence RuntimeEvidence runtime-evidence.json manual-app-evidence-template.json manual-app-enumeration-checklist keepReceiverAfterSuccess screenshotPath receiverProcessId Normalize-PairCode directShowFrameMatchesExpectedAndroidStream directShowFrameReviewNote Test-RequiredPositiveInteger Test-RequiredEvidencePath Test-EvidenceImageFile PNG,\ JPEG,\ or\ BMP\ image receiverProcessId\ must\ match\ runtime\ evidence manualEvidenceTemplate\ must\ match\ runtime\ evidence Get-EvidencePropertyValue Test-MatchingRuntimeArtifact runtimeArtifacts.$ManualName\ must\ match\ runtime\ evidence Get-MaxFfmpegFrameCount Get-CanonicalRtspEndpoint Assert-ReceiverRtspEvidence Receiver\ stdout\ did\ not\ record\ openedRtspUrl Receiver\ stdout\ did\ not\ record\ selectedRtspUrl RTSP\ evidence\ fields\ point\ to\ different\ endpoints captureText.Contains($CameraName) capturedFrameCount\ -lt\ $CaptureFrames directshow-frame.bmp ffmpeg-directshow-snapshot.log directShowSnapshot runtimeArtifacts directShowFrameSnapshot directShowSnapshotLog directShowCaptureLog expected\ Android\ stream].each do |expected|
  assert(runtime_script.include?(expected), "Windows runtime verifier must support #{expected}")
end
assert(runtime_script.include?("-PairCode must contain exactly six digits."),
       "Windows runtime verifier must reject malformed pair codes before receiver startup")
assert(runtime_script.include?("Elevated PowerShell is required for -UnregisterOnly."),
       "Windows runtime verifier must fail clearly when Softcam cleanup is not elevated")
assert(runtime_script.include?("-KeepReceiverRunning cannot be combined with -SkipCapture"),
       "Windows runtime verifier must not allow OBS/browser evidence without DirectShow capture")
assert(runtime_script.include?('"-f", "image2"') &&
       runtime_script.include?('"-update", "1"') &&
       runtime_script.include?('"-t", $CaptureSeconds.ToString()'),
       "Windows DirectShow snapshot capture must be bounded and write a single image artifact")
assert(runtime_script.include?("Test-EvidenceImageFile -Issues $snapshotIssues") &&
       runtime_script.include?("DirectShow frame snapshot was not a PNG, JPEG, or BMP image"),
       "Windows runtime verifier must reject non-image DirectShow frame snapshots")
assert(runtime_script.include?("screenshots must be distinct files") &&
       runtime_script.include?("must be a separate app screenshot, not the DirectShow frame snapshot"),
       "Windows manual evidence validator must reject reused screenshot artifacts")
assert(runtime_script.include?("Get-EvidenceFileHash") &&
       runtime_script.include?("screenshots must have different image content") &&
       runtime_script.include?("must not duplicate the DirectShow frame snapshot content"),
       "Windows manual evidence validator must reject copied screenshot content")

android_matrix_script = read("scripts/android_wifi_profile_matrix_smoke.sh")
assert(android_matrix_script.include?("matrix-evidence.json"),
       "Android Wi-Fi profile matrix must write structured JSON evidence")
assert(android_matrix_script.include?("wifi-evidence.json"),
       "Android Wi-Fi profile matrix must link per-profile structured JSON evidence")
assert(android_matrix_script.include?('REQUIRE_DISCOVERY="${REQUIRE_DISCOVERY:-1}"'),
       "Android Wi-Fi profile matrix must require pair-code discovery by default")
assert(android_matrix_script.include?('"pairingCode"') &&
       android_matrix_script.include?('"rtspUrl"') &&
       android_matrix_script.include?('"previewLive"'),
       "Android Wi-Fi profile matrix must summarize pairing code, RTSP URL, and live-preview evidence")
assert(android_matrix_script.include?('STREAM_ROTATE_TAPS="$STREAM_ROTATE_TAPS"') &&
       android_matrix_script.include?('FRONT_CAMERA_ROTATE_TAPS="$FRONT_CAMERA_ROTATE_TAPS"') &&
       android_matrix_script.include?('STREAM_OUTPUT_ROTATION_DEGREES="$STREAM_OUTPUT_ROTATION_DEGREES"') &&
       android_matrix_script.include?('FRONT_CAMERA_OUTPUT_ROTATION_DEGREES="$FRONT_CAMERA_OUTPUT_ROTATION_DEGREES"') &&
       android_matrix_script.include?('ALLOW_UNVERIFIED_ORIENTATION="$ALLOW_UNVERIFIED_ORIENTATION"') &&
       android_matrix_script.include?('STREAM_ORIENTATION_STATUS="$STREAM_ORIENTATION_STATUS"') &&
       android_matrix_script.include?('FRONT_CAMERA_ORIENTATION_STATUS="$FRONT_CAMERA_ORIENTATION_STATUS"'),
       "Android Wi-Fi profile matrix must forward rotation/orientation inputs into per-profile runs")
assert(android_matrix_script.include?('ALLOW_UNVERIFIED_ORIENTATION="${ALLOW_UNVERIFIED_ORIENTATION:-0}"') &&
       android_matrix_script.include?('"allowUnverifiedOrientation"') &&
       android_matrix_script.include?('"finalMvpEvidence"') &&
       android_matrix_script.include?("Physical orientation acceptance inputs are required before running the final Android Wi-Fi matrix") &&
       android_matrix_script.include?("For exploratory collection only, set ALLOW_UNVERIFIED_ORIENTATION=1 CONTINUE_ON_FAILURE=1"),
       "Android Wi-Fi profile matrix must fail early without final orientation acceptance inputs unless explicitly exploratory")
android_wifi_script = read("scripts/android_wifi_receiver_smoke.sh")
android_device_script = read("scripts/android_device_smoke.sh")
android_layout = read("android/app/src/main/res/layout/activity_rtsp.xml")
android_activity = read("android/app/src/main/java/com/phonecam/RtspMainActivity.kt")
assert(android_layout.include?("rotateCounterClockwiseBtn") &&
       android_layout.include?("Rotate Left") &&
       android_layout.include?("Rotate Right") &&
       android_activity.include?("rotateStreamCorrection(-90)") &&
       android_activity.include?("rotateStreamCorrection(90)"),
       "Android sender UI must expose explicit left/right output-rotation controls for foldable orientation correction")
assert(android_device_script.include?("rotateStreamBtn") &&
       android_device_script.include?("Rotate changes output rotation"),
       "Android device smoke must exercise the Rotate control")
assert(android_device_script.include?("Preview: live") &&
       android_device_script.include?("SurfaceView preview reported live") &&
       android_device_script.include?("Android device smoke failed: SurfaceView preview did not report live") &&
       android_device_script.include?('exit "$smoke_status"'),
       "Android device smoke must verify and fail on missing SurfaceView preview status")
assert(android_device_script.include?("diagnosticsToggleBtn") &&
       android_device_script.include?("ui-after-start-compact.xml"),
       "Android device smoke must reveal full diagnostics after capturing the compact preview UI")
assert(android_wifi_script.include?("FRONT_CAMERA_ORIENTATION_STATUS"),
       "Android Wi-Fi smoke must require explicit front-camera orientation status")
assert(android_wifi_script.include?("FRONT_CAMERA_ORIENTATION_NOTES"),
       "Android Wi-Fi smoke must require explicit front-camera orientation notes")
assert(android_wifi_script.include?("FRONT_CAMERA_DEVICE_POSTURE"),
       "Android Wi-Fi smoke must record the physical device posture")
assert(android_wifi_script.include?("ORIENTATION_EVIDENCE_VERSION=4") &&
       android_wifi_script.include?('"rotationControlMode"') &&
       android_wifi_script.include?('"orientationLockMode"') &&
       android_wifi_script.include?("per-camera-output") &&
       android_wifi_script.include?("fixed-landscape"),
       "Android Wi-Fi smoke must version orientation evidence and mark per-camera Rotate/landscape-lock evidence")
assert(android_wifi_script.include?("STREAM_ROTATE_TAPS") &&
       android_wifi_script.include?("FRONT_CAMERA_ROTATE_TAPS") &&
       android_wifi_script.include?("STREAM_OUTPUT_ROTATION_DEGREES") &&
       android_wifi_script.include?("FRONT_CAMERA_OUTPUT_ROTATION_DEGREES") &&
       android_wifi_script.include?("rotation_plan_to_target") &&
       android_wifi_script.include?("tap_rotate_left_control") &&
       android_wifi_script.include?('"rotationDirection"') &&
       android_wifi_script.include?("outputRotationDegrees"),
       "Android Wi-Fi smoke must record requested Rotate control taps or absolute targets and output rotation")
assert(android_wifi_script.include?("STREAM_ORIENTATION_STATUS") &&
       android_wifi_script.include?("STREAM_ORIENTATION_NOTES") &&
       android_wifi_script.include?("STREAM_DEVICE_POSTURE") &&
       android_wifi_script.include?("streamOrientation"),
       "Android Wi-Fi smoke must require explicit stream/back-camera orientation evidence")
assert(android_wifi_script.include?("ORIENTATION_CALIBRATION") &&
       android_wifi_script.include?("CALIBRATION_FRAMES") &&
       android_wifi_script.include?("orientation-calibration.json") &&
       android_wifi_script.include?("finalMvpEvidence") &&
       android_wifi_script.include?('json_bool "$final_mvp_evidence"') &&
       android_wifi_script.include?('ALLOW_UNVERIFIED_ORIENTATION" == "1"') &&
       android_wifi_script.include?("receiver-calibration") &&
       android_wifi_script.include?("doesNotProve"),
       "Android Wi-Fi smoke must support exploratory back/front rotation calibration evidence and mark exploratory evidence non-final")
assert(android_wifi_script.include?("camera_diagnostics_from_ui") &&
       android_wifi_script.include?('"cameraDiagnostics"') &&
       android_wifi_script.include?("diagnosticsToggleBtn") &&
       android_wifi_script.include?("ui-after-start-compact.xml"),
       "Android Wi-Fi smoke must reveal and capture camera/display diagnostics from the sender UI")
assert(android_wifi_script.include?('ALLOW_UNVERIFIED_ORIENTATION="${ALLOW_UNVERIFIED_ORIENTATION:-0}"') &&
       android_wifi_script.include?("Physical orientation acceptance inputs are required before running the final Android Wi-Fi smoke") &&
       android_wifi_script.include?("For exploratory collection only, set ALLOW_UNVERIFIED_ORIENTATION=1 CONTINUE_ON_FAILURE=1"),
       "Android Wi-Fi smoke must fail early without final orientation acceptance inputs unless explicitly exploratory")
assert(android_wifi_script.include?('"previewLive"') &&
       android_wifi_script.include?("SurfaceView preview reported live") &&
       android_wifi_script.include?("SurfaceView preview did not report live") &&
       android_wifi_script.include?('"$direct_passed" == "1" && "$preview_live" == "1"'),
       "Android Wi-Fi smoke must record and require SurfaceView live-preview status")
assert(android_wifi_script.include?("android-orientation-window.txt"),
       "Android Wi-Fi smoke must capture orientation artifacts")
assert(android_wifi_script.include?("android-orientation-accelerometer-rotation.txt") &&
       android_wifi_script.include?("android-orientation-user-rotation.txt"),
       "Android Wi-Fi smoke must use the front-camera orientation artifact prefix consistently")
assert(android_wifi_script.include?("--snapshot") && android_wifi_script.include?("receiver-front-frame.ppm"),
       "Android Wi-Fi smoke must capture decoded receiver frame snapshots")
fixture_script = read("scripts/smoke_receiver_fixture.sh")
assert(fixture_script.include?("--snapshot") && fixture_script.include?("receiver-frame.ppm"),
       "RTSP fixture must verify decoded receiver frame snapshots")
assert(fixture_script.include?("rtspTransports: [tcp]") && fixture_script.include?("-rtsp_transport tcp"),
       "RTSP fixture must force TCP transport to avoid sandbox-hostile UDP RTP/RTCP listeners")
mac_receiver_script = read("scripts/mac_receiver_dev_smoke.sh")
assert(mac_receiver_script.include?("mac-receiver-evidence.json"),
       "Mac receiver dev smoke must write structured JSON evidence")
assert(mac_receiver_script.include?("macDevOnly") && mac_receiver_script.include?("doesNotProve"),
       "Mac receiver dev smoke evidence must state that it is not Windows DirectShow evidence")
assert(mac_receiver_script.include?("--auto-discover") && mac_receiver_script.include?("--rtsp"),
       "Mac receiver dev smoke must support direct RTSP and auto-discovery")
assert(mac_receiver_script.include?("--snapshot") && mac_receiver_script.include?("receiver-frame.ppm"),
       "Mac receiver dev smoke must capture a decoded frame snapshot")
assert(mac_receiver_script.include?("PREVIEW") && mac_receiver_script.include?("previewRequested"),
       "Mac receiver dev smoke must optionally exercise the macOS preview sink")
mac_receiver_fixture_script = read("scripts/mac_receiver_fixture_smoke.sh")
assert(mac_receiver_fixture_script.include?("mac_receiver_dev_smoke.sh") &&
       mac_receiver_fixture_script.include?("mac-receiver-evidence.json"),
       "Mac receiver fixture must exercise the Mac dev smoke helper and validate structured evidence")
assert(mac_receiver_fixture_script.include?("rtspTransports: [tcp]") && mac_receiver_fixture_script.include?("-rtsp_transport tcp"),
       "Mac receiver fixture must force TCP transport to avoid sandbox-hostile UDP RTP/RTCP listeners")
mac_receiver_app_script = read("scripts/package_mac_receiver_app.sh")
assert(mac_receiver_app_script.include?("PhoneCam Receiver.app") &&
       mac_receiver_app_script.include?("CFBundleIdentifier") &&
       mac_receiver_app_script.include?("com.phonecam.receiver.dev") &&
       mac_receiver_app_script.include?("does not prove Windows DirectShow/OBS enumeration"),
       "Mac receiver app packager must create a clearly dev-only app bundle")
local_verification_script = read("scripts/local_verification.sh")
assert(local_verification_script.include?("RUN_RTSP_FIXTURE") &&
       local_verification_script.include?("FORCE_ANDROID_TESTS=1") &&
       local_verification_script.include?("Android rotation plan self-test") &&
       local_verification_script.include?("ROTATION_PLAN_SELF_TEST=1") &&
       local_verification_script.include?("RUN_POWERSHELL_SYNTAX") &&
       local_verification_script.include?("PowerShell syntax check") &&
       local_verification_script.include?("Parser]::ParseFile") &&
       local_verification_script.include?("scripts/build_android_debug.sh") &&
       local_verification_script.include?("ctest --test-dir") &&
       local_verification_script.include?("scripts/package_mac_receiver_app.sh") &&
       local_verification_script.include?("does not run adb") &&
       local_verification_script.include?("Remaining external evidence"),
       "Local verification helper must run safe Mac-side checks with fresh Android JVM tests and state external blockers")
android_build_script = read("scripts/build_android_debug.sh")
assert(android_build_script.include?("FORCE_ANDROID_TESTS") &&
       android_build_script.include?("--rerun-tasks") &&
       android_build_script.include?("TEST-*.xml") &&
       android_build_script.include?("timestamp="),
       "Android build helper must support fresh JVM test reruns and print test XML summaries")
windows_fixture_script = read("desktop/windows/scripts/Test-PhoneCamReceiverFixture.ps1")
assert(windows_fixture_script.include?("--snapshot") && windows_fixture_script.include?("receiver-frame.ppm"),
       "Windows RTSP fixture must verify decoded receiver frame snapshots")
assert(windows_fixture_script.include?("rtspTransports: [tcp]") && windows_fixture_script.include?('"-rtsp_transport", "tcp"'),
       "Windows RTSP fixture must force TCP transport to avoid UDP RTP/RTCP listener requirements")

bundler_script = read("scripts/bundle_mvp_evidence.rb")
assert(bundler_script.include?("validate_mvp_evidence.rb") && bundler_script.include?("refusing to bundle incomplete MVP evidence"),
       "MVP evidence bundler must validate source and bundled evidence by default")
assert(bundler_script.include?("--skip-validation"),
       "MVP evidence bundler must make diagnostic validation skipping explicit")
assert(bundler_script.include?("--android-only") &&
       bundler_script.include?("Android matrix evidence bundle") &&
       bundler_script.include?('"androidOnly"') &&
       bundler_script.include?("Collect-PhoneCamWindowsEvidence.ps1"),
       "MVP evidence bundler must support Android-only portable handoff bundles")
assert(bundler_script.include?('"tools"') &&
       bundler_script.include?('"validator"') &&
       bundler_script.include?('"sourceInputs"') &&
       bundler_script.include?('"sha256"') &&
       bundler_script.include?("relative_manifest_path"),
       "MVP evidence bundler must write a portable manifest with source fingerprints, a bundled validator, and relative paths")

mvp_evidence_script = read("scripts/validate_mvp_evidence.rb")
assert(mvp_evidence_script.include?("--android-only") &&
       mvp_evidence_script.include?("Android matrix evidence validation passed") &&
       mvp_evidence_script.include?("Android matrix evidence validation failed") &&
       mvp_evidence_script.include?("final MVP physical Wi-Fi matrix evidence") &&
       mvp_evidence_script.include?("allowUnverifiedOrientation must be false"),
       "MVP evidence validator must support Android-only preflight mode")
assert(mvp_evidence_script.include?("require_matching_runtime_artifact") &&
       mvp_evidence_script.include?("Windows manual runtimeArtifacts"),
       "MVP evidence validator must cross-check manual runtimeArtifacts against runtime evidence")
%w[android-matrix windows-runtime windows-manual directDecode finalMvpEvidence streamOrientation frontCamera streamingCompactScreenshot streamingScreenshot streamRotationUi streamRotateTaps streamRotationDegrees switchScreenshot decoded\ frame\ snapshot directShowCameraFound receiverKeptRunning receiverProcessId receiverProcessId\ must\ match\ runtime\ evidence directShowFrameMatchesExpectedAndroidStream directShowFrameReviewNote manualAppChecklist manualEvidenceTemplate manualEvidenceTemplate\ path\ must\ match cameraName generated\ self-test selectedRtspUrl openedRtspUrl\ must\ be\ recorded 10.0.2. physical\ Android\ matrix\ RTSP\ URL pairingCode previewLive sender\ preview pairCode wifiEvidenceCaptured rtspHost requestedFrames receiverStdout directShowDevices directShowSnapshot DirectShow\ captured\ frame\ snapshot DirectShow\ snapshot\ log PNG,\ JPEG,\ or\ BMP\ image expectedBitrateMbps incomingMbps decodeErrors orientationStatus orientationEvidenceCaptured orientationEvidenceVersion rotationControlMode orientationLockMode outputRotationDegrees devicePosture orientationNotes cameraDiagnostics stream\ orientation front-camera\ orientation selected\ Android\ RTSP\ URL recorded\ RTSP\ URL\ fields\ must\ all\ refer\ to\ the\ same\ endpoint sourceMode\ must\ match\ runtime\ evidence capture\ log\ must\ show capture\ log\ must\ contain].each do |expected|
  assert(mvp_evidence_script.include?(expected), "MVP evidence validator must check #{expected}")
end
assert(mvp_evidence_script.include?("rotationDirection must be left or right") &&
       mvp_evidence_script.include?("output rotation degrees must be recorded as 0/90/180/270") &&
       mvp_evidence_script.include?("rotation request mode must be tap-count or absolute-degrees") &&
       mvp_evidence_script.include?("rotationRequestMode must match top-level streamRotationRequestMode") &&
       mvp_evidence_script.include?("output rotation degrees must match the requested target"),
       "MVP evidence validator must require explicit left/right rotation direction, normalized rotation degrees, and target/output consistency")
assert(mvp_evidence_script.include?("Digest::SHA256") &&
       mvp_evidence_script.include?("screenshots must have different image content") &&
       mvp_evidence_script.include?("must not duplicate the DirectShow frame snapshot content"),
       "MVP evidence validator must reject copied OBS/browser or DirectShow screenshot content")
assert(mvp_evidence_script.include?("require_decoded_frame_file") &&
       mvp_evidence_script.include?("PPM, PNG, JPEG, or BMP image"),
       "MVP evidence validator must reject non-image Android receiver frame snapshots")

Dir.mktmpdir("phonecam-mvp-evidence") do |dir|
  profile_resolutions = {
    "Efficient" => "960x540",
    "Balanced" => "1280x720",
    "Motion" => "1280x720"
  }
  profile_bitrates = {
    "Efficient" => 1.2,
    "Balanced" => 1.8,
    "Motion" => 2.8
  }
  profile_max_incoming_mbps = {
    "Efficient" => 2.0,
    "Balanced" => 3.0,
    "Motion" => 4.5
  }
  profile_observed_incoming_mbps = {
    "Efficient" => 1.4,
    "Balanced" => 2.1,
    "Motion" => 3.2
  }
  android_matrix = {
    "status" => "passed",
    "finalMvpEvidence" => true,
    "allowUnverifiedOrientation" => false,
    "matrixExitStatus" => 0,
    "verifyFrontCamera" => true,
    "profiles" => %w[Efficient Balanced Motion].map do |profile|
      evidence_dir = File.join(dir, profile.downcase)
      evidence_json = File.join(evidence_dir, "wifi-evidence.json")
      {
        "profile" => profile,
        "status" => "passed",
        "exitStatus" => 0,
        "evidenceDir" => evidence_dir,
        "evidenceJson" => evidence_json
      }
    end
  }
  android_matrix["profiles"].each do |profile_row|
    profile = profile_row.fetch("profile")
    evidence_dir = profile_row.fetch("evidenceDir")
    FileUtils.mkdir_p(evidence_dir)
    profile_artifacts = {
      "summary" => File.join(evidence_dir, "summary.txt"),
      "initialUi" => File.join(evidence_dir, "ui.xml"),
      "initialScreenshot" => File.join(evidence_dir, "screenshot.png"),
      "profileUi" => File.join(evidence_dir, "ui-profile-#{profile.downcase}.xml"),
      "profileScreenshot" => File.join(evidence_dir, "screenshot-profile-#{profile.downcase}.png"),
      "streamingCompactUi" => File.join(evidence_dir, "ui-after-start-compact.xml"),
      "streamingCompactScreenshot" => File.join(evidence_dir, "screenshot-after-start-compact.png"),
      "streamingUi" => File.join(evidence_dir, "ui-after-start.xml"),
      "streamingScreenshot" => File.join(evidence_dir, "screenshot-after-start.png"),
      "streamRotationUi" => File.join(evidence_dir, "ui-after-start.xml"),
      "streamRotationScreenshot" => File.join(evidence_dir, "screenshot-after-start.png"),
      "logcatAfterStart" => File.join(evidence_dir, "logcat-after-start.txt")
    }
    profile_artifacts.each do |key, path|
      text = case key
             when "streamingCompactUi"
               'fixture compact sender UI text="PREVIEW LIVE" text="Preview: live | Camera: Back | Output rotation: 0 deg"'
             when "streamingUi", "streamRotationUi"
               'fixture diagnostics UI text="Preview: live" text="Camera diagnostics: id 0, sensor 90 deg, display 90 deg, root 0 deg, window 2208x1768"'
             else
               "fixture #{File.basename(path)}"
             end
      write_fixture_artifact(path, text)
    end
    stream_orientation_artifacts = {
      "input" => File.join(evidence_dir, "android-stream-orientation-input.txt"),
      "window" => File.join(evidence_dir, "android-stream-orientation-window.txt"),
      "display" => File.join(evidence_dir, "android-stream-orientation-display.txt"),
      "accelerometerRotation" => File.join(evidence_dir, "android-stream-orientation-accelerometer-rotation.txt"),
      "userRotation" => File.join(evidence_dir, "android-stream-orientation-user-rotation.txt")
    }
    stream_orientation_artifacts.each_value { |path| File.write(path, "fixture stream orientation evidence") }
    direct_snapshot_path = File.join(evidence_dir, "receiver-direct-frame.ppm")
    discovery_snapshot_path = File.join(evidence_dir, "receiver-discovery-frame.ppm")
    File.binwrite(direct_snapshot_path, FIXTURE_PPM)
    File.binwrite(discovery_snapshot_path, FIXTURE_PPM)
    orientation_artifacts = {}
    front_artifacts = {}
    if profile == "Motion"
      orientation_artifacts = {
        "input" => File.join(evidence_dir, "android-orientation-input.txt"),
        "window" => File.join(evidence_dir, "android-orientation-window.txt"),
        "display" => File.join(evidence_dir, "android-orientation-display.txt"),
        "accelerometerRotation" => File.join(evidence_dir, "android-orientation-accelerometer-rotation.txt"),
        "userRotation" => File.join(evidence_dir, "android-orientation-user-rotation.txt")
      }
      orientation_artifacts.each_value { |path| File.write(path, "fixture orientation evidence") }
      front_artifacts = {
        "switchUi" => File.join(evidence_dir, "ui-after-switch.xml"),
        "switchScreenshot" => File.join(evidence_dir, "screenshot-after-switch.png"),
        "finalSwitchUi" => File.join(evidence_dir, "ui-after-switch-final.xml"),
        "finalSwitchScreenshot" => File.join(evidence_dir, "screenshot-after-switch-final.png"),
        "rotationUi" => File.join(evidence_dir, "ui-front-rotate-1.xml"),
        "rotationScreenshot" => File.join(evidence_dir, "screenshot-front-rotate-1.png"),
        "receiverStdout" => File.join(evidence_dir, "receiver-front-direct.stdout.log"),
        "receiverStderr" => File.join(evidence_dir, "receiver-front-direct.stderr.log"),
        "receiverSnapshot" => File.join(evidence_dir, "receiver-front-frame.ppm"),
        "logcatAfterSwitch" => File.join(evidence_dir, "logcat-after-switch.txt"),
        "logcatAfterFrontReceiver" => File.join(evidence_dir, "logcat-after-front-receiver.txt")
      }
      front_artifacts.each_value { |path| write_fixture_artifact(path, "fixture front-camera artifact") }
    end
    write_json(
      profile_row.fetch("evidenceJson"),
      {
        "status" => "passed",
        "finalMvpEvidence" => true,
        "androidSerial" => "R58N0000000",
        "profile" => profile,
        "expectedResolution" => profile_resolutions.fetch(profile),
        "expectedBitrateMbps" => profile_bitrates.fetch(profile),
        "maxAllowedIncomingMbps" => profile_max_incoming_mbps.fetch(profile),
        "framesRequested" => 60,
        "rtspUrl" => "rtsp://192.168.1.50:8554/",
        "pairingCode" => "123456",
        "previewLive" => true,
        "streamRotationRequestMode" => "tap-count",
        "streamRotationDirection" => "right",
        "streamRotateTaps" => 0,
        "streamRotationDegrees" => 0,
        "streamRequestedOutputRotationDegrees" => nil,
        "streamOrientation" => {
          "orientationEvidenceVersion" => 4,
          "rotationControlMode" => "per-camera-output",
          "orientationLockMode" => "fixed-landscape",
          "orientationStatus" => "passed",
          "orientationEvidenceCaptured" => true,
          "rotationRequestMode" => "tap-count",
          "requestedOutputRotationDegrees" => nil,
          "rotationDirection" => "right",
          "rotateTaps" => 0,
          "outputRotationDegrees" => 0,
          "orientationNotes" => "back camera receiver output is landscape-correct",
          "devicePosture" => "test phone physically landscape on tabletop",
          "cameraDiagnostics" => "id 0, sensor 90 deg, display 90 deg, root 0 deg, window 2208x1768",
          "orientationSummary" => "mCurrentRotation=ROTATION_90",
          "displaySummary" => "rotation 1",
          "inputSummary" => "SurfaceOrientation: 1",
          "accelerometerRotation" => "1",
          "userRotation" => "1",
          "orientationArtifacts" => stream_orientation_artifacts
        },
        "network" => {
          "wifiEvidenceCaptured" => true,
          "rtspHost" => "192.168.1.50",
          "wifiStatusSummary" => "Wi-Fi is enabled",
          "wifiDumpsysSummary" => "wlan0 connected to test-network",
          "ipRouteSummary" => "default via 192.168.1.1 dev wlan0"
        },
        "directDecode" => {
          "status" => "passed",
          "exitStatus" => 0,
          "pairingCode" => "123456",
          "frames" => 60,
          "resolution" => profile_resolutions.fetch(profile),
          "avgFps" => 29.8,
          "incomingMbps" => profile_observed_incoming_mbps.fetch(profile),
          "decodeErrors" => 0,
          "openedRtspUrl" => "rtsp://192.168.1.50:8554/",
          "snapshot" => direct_snapshot_path
        },
        "requireDiscovery" => false,
        "pairCodeDiscoveryDecode" => {
          "status" => "passed",
          "exitStatus" => 0,
          "pairingCode" => "123456",
          "frames" => 60,
          "resolution" => profile_resolutions.fetch(profile),
          "avgFps" => 29.7,
          "incomingMbps" => profile_observed_incoming_mbps.fetch(profile),
          "decodeErrors" => 0,
          "selectedRtspUrl" => "rtsp://192.168.1.50:8554/",
          "openedRtspUrl" => "rtsp://192.168.1.50:8554/",
          "snapshot" => discovery_snapshot_path
        },
        "frontCamera" => {
          "verified" => profile == "Motion",
          "switchStatus" => profile == "Motion" ? "passed" : "failed",
          "decodeStatus" => profile == "Motion" ? "passed" : "failed",
          "frames" => profile == "Motion" ? 60 : 0,
          "resolution" => profile == "Motion" ? profile_resolutions.fetch(profile) : "",
          "avgFps" => profile == "Motion" ? 29.6 : nil,
          "incomingMbps" => profile == "Motion" ? profile_observed_incoming_mbps.fetch(profile) : nil,
          "decodeErrors" => profile == "Motion" ? 0 : nil,
          "openedRtspUrl" => profile == "Motion" ? "rtsp://192.168.1.50:8554/" : "",
          "orientationEvidenceVersion" => profile == "Motion" ? 4 : nil,
          "rotationControlMode" => profile == "Motion" ? "per-camera-output" : nil,
          "orientationLockMode" => profile == "Motion" ? "fixed-landscape" : nil,
          "orientationStatus" => profile == "Motion" ? "passed" : "not-verified",
          "orientationEvidenceCaptured" => profile == "Motion",
          "rotationRequestMode" => profile == "Motion" ? "tap-count" : nil,
          "requestedOutputRotationDegrees" => nil,
          "rotationDirection" => profile == "Motion" ? "right" : nil,
          "rotateTaps" => profile == "Motion" ? 1 : 0,
          "outputRotationDegrees" => profile == "Motion" ? 90 : nil,
          "orientationNotes" => profile == "Motion" ? "front camera receiver output is landscape-correct after phone rotation" : "",
          "devicePosture" => profile == "Motion" ? "test phone physically landscape on tabletop" : "",
          "cameraDiagnostics" => profile == "Motion" ? "id 1, sensor 270 deg, display 90 deg, root 0 deg, window 2208x1768" : "",
          "orientationSummary" => profile == "Motion" ? "mCurrentRotation=ROTATION_90" : "",
          "displaySummary" => profile == "Motion" ? "rotation 1" : "",
          "inputSummary" => profile == "Motion" ? "SurfaceOrientation: 1" : "",
          "accelerometerRotation" => profile == "Motion" ? "1" : "",
          "userRotation" => profile == "Motion" ? "1" : "",
          "orientationArtifacts" => orientation_artifacts,
          "artifacts" => front_artifacts
        },
        "logcat" => {
          "crashFree" => true,
          "streamConfigFailureFree" => true
        },
        "artifacts" => profile_artifacts
      }
    )
  end
  obs_screenshot_path = File.join(dir, "obs-phonecam.png")
  browser_screenshot_path = File.join(dir, "browser-phonecam.png")
  runtime_summary_path = File.join(dir, "runtime-summary.txt")
  receiver_stdout_path = File.join(dir, "receiver.stdout.log")
  directshow_devices_path = File.join(dir, "ffmpeg-dshow-devices.log")
  capture_log_path = File.join(dir, "ffmpeg-capture.log")
  directshow_snapshot_path = File.join(dir, "directshow-frame.bmp")
  directshow_snapshot_log_path = File.join(dir, "ffmpeg-directshow-snapshot.log")
  manual_app_checklist_path = File.join(dir, "manual-app-enumeration-checklist.txt")
  manual_path = File.join(dir, "manual-app-evidence-template.json")
  File.binwrite(obs_screenshot_path, FIXTURE_PNG)
  File.binwrite(browser_screenshot_path, FIXTURE_BROWSER_PNG)
  File.write(runtime_summary_path, "PhoneCam Windows runtime verification passed.")
  File.write(receiver_stdout_path, "Opening rtsp://192.168.1.50:8554/ with RTSP-over-TCP")
  File.write(directshow_devices_path, "DirectShow video device: PhoneCam Virtual Camera")
  File.write(capture_log_path, "Input #0, dshow, from 'video=PhoneCam Virtual Camera':\nframe=1\nframe=30")
  File.binwrite(directshow_snapshot_path, FIXTURE_DIRECTSHOW_BMP)
  File.write(directshow_snapshot_log_path, "Input #0, dshow, from 'video=PhoneCam Virtual Camera':\nframe=1")
  File.write(manual_app_checklist_path, "fixture manual checklist")
  windows_runtime = {
    "status" => "passed",
    "mode" => "windows-runtime-verification",
    "directShowCameraFound" => true,
    "receiverKeptRunning" => true,
    "receiverProcessId" => 4242,
    "sourceMode" => "auto-discovered Android RTSP",
    "selectedRtspUrl" => "rtsp://192.168.1.50:8554/",
    "openedRtspUrl" => "rtsp://192.168.1.50:8554/",
    "pairCode" => "123456",
    "capture" => {
      "skipped" => false,
      "frames" => 30,
      "requestedFrames" => 30,
      "snapshot" => directshow_snapshot_path
    },
    "logs" => {
      "summary" => runtime_summary_path,
      "receiverStdout" => receiver_stdout_path,
      "directShowDevices" => directshow_devices_path,
      "capture" => capture_log_path,
      "directShowSnapshot" => directshow_snapshot_log_path,
      "manualAppChecklist" => manual_app_checklist_path,
      "manualEvidenceTemplate" => manual_path
    },
    "cameraName" => "PhoneCam Virtual Camera"
  }
  windows_manual = {
    "status" => "passed",
    "cameraName" => "PhoneCam Virtual Camera",
    "sourceMode" => "auto-discovered Android RTSP",
    "effectiveRtspUrl" => "rtsp://192.168.1.50:8554/",
    "receiverKeptRunning" => true,
    "receiverProcessId" => 4242,
    "directShowFrameMatchesExpectedAndroidStream" => true,
    "directShowFrameReviewNote" => "DirectShow frame snapshot shows the expected Android camera stream.",
    "runtimeArtifacts" => {
      "directShowFrameSnapshot" => directshow_snapshot_path,
      "directShowSnapshotLog" => directshow_snapshot_log_path,
      "directShowCaptureLog" => capture_log_path
    },
    "obs" => {
      "version" => "30.0.0",
      "cameraListed" => true,
      "liveFramesRendered" => true,
      "screenshotPath" => obs_screenshot_path
    },
    "browserOrCameraApp" => {
      "app" => "Browser camera test",
      "version" => "1.0",
      "cameraListed" => true,
      "liveFramesRendered" => true,
      "screenshotPath" => browser_screenshot_path
    }
  }

  android_path = File.join(dir, "matrix-evidence.json")
  runtime_path = File.join(dir, "runtime-evidence.json")
  generated_runtime_path = File.join(dir, "generated-runtime-evidence.json")
  localhost_runtime_path = File.join(dir, "localhost-runtime-evidence.json")
  emulator_runtime_path = File.join(dir, "emulator-runtime-evidence.json")
  mismatched_runtime_path = File.join(dir, "mismatched-runtime-evidence.json")
  inconsistent_runtime_rtsp_path = File.join(dir, "inconsistent-runtime-rtsp-evidence.json")
  missing_runtime_opened_rtsp_path = File.join(dir, "missing-opened-rtsp-runtime-evidence.json")
  missing_runtime_selected_rtsp_path = File.join(dir, "missing-selected-rtsp-runtime-evidence.json")
  mismatched_pair_code_runtime_path = File.join(dir, "mismatched-pair-code-runtime-evidence.json")
  android_emulator_path = File.join(dir, "android-emulator-matrix-evidence.json")
  android_no_discovery_path = File.join(dir, "android-no-discovery-matrix-evidence.json")
  android_no_pairing_code_path = File.join(dir, "android-no-pairing-code-matrix-evidence.json")
  android_preview_not_live_path = File.join(dir, "android-preview-not-live-matrix-evidence.json")
  android_no_wifi_network_path = File.join(dir, "android-no-wifi-network-matrix-evidence.json")
  android_direct_mismatch_path = File.join(dir, "android-direct-mismatch-matrix-evidence.json")
  android_non_final_path = File.join(dir, "android-non-final-matrix-evidence.json")
  android_stream_orientation_unverified_path = File.join(dir, "android-stream-orientation-unverified-matrix-evidence.json")
  android_stream_orientation_unlocked_path = File.join(dir, "android-stream-orientation-unlocked-matrix-evidence.json")
  android_stream_orientation_missing_posture_path = File.join(dir, "android-stream-orientation-missing-posture-matrix-evidence.json")
  android_stream_rotation_direction_missing_path = File.join(dir, "android-stream-rotation-direction-missing-matrix-evidence.json")
  android_stream_rotation_degree_invalid_path = File.join(dir, "android-stream-rotation-degree-invalid-matrix-evidence.json")
  android_stream_rotation_target_mismatch_path = File.join(dir, "android-stream-rotation-target-mismatch-matrix-evidence.json")
  android_front_mismatch_path = File.join(dir, "android-front-mismatch-matrix-evidence.json")
  android_front_rotation_target_mismatch_path = File.join(dir, "android-front-rotation-target-mismatch-matrix-evidence.json")
  android_front_orientation_unverified_path = File.join(dir, "android-front-orientation-unverified-matrix-evidence.json")
  android_front_orientation_missing_notes_path = File.join(dir, "android-front-orientation-missing-notes-matrix-evidence.json")
  android_missing_screenshot_path = File.join(dir, "android-missing-screenshot-matrix-evidence.json")
  android_text_screenshot_path = File.join(dir, "android-text-screenshot-matrix-evidence.json")
  android_compact_preview_not_live_path = File.join(dir, "android-compact-preview-not-live-matrix-evidence.json")
  android_missing_snapshot_path = File.join(dir, "android-missing-snapshot-matrix-evidence.json")
  android_text_snapshot_path = File.join(dir, "android-text-snapshot-matrix-evidence.json")
  android_decode_errors_path = File.join(dir, "android-decode-errors-matrix-evidence.json")
  android_high_bitrate_path = File.join(dir, "android-high-bitrate-matrix-evidence.json")
  mismatched_manual_path = File.join(dir, "mismatched-manual-app-evidence-template.json")
  inconsistent_manual_rtsp_path = File.join(dir, "inconsistent-manual-rtsp-app-evidence-template.json")
  mismatched_source_mode_manual_path = File.join(dir, "mismatched-source-mode-manual-app-evidence-template.json")
  mismatched_receiver_process_manual_path = File.join(dir, "mismatched-receiver-process-manual-app-evidence-template.json")
  missing_runtime_artifact_manual_path = File.join(dir, "missing-runtime-artifact-manual-app-evidence-template.json")
  mismatched_runtime_artifact_manual_path = File.join(dir, "mismatched-runtime-artifact-manual-app-evidence-template.json")
  missing_directshow_review_manual_path = File.join(dir, "missing-directshow-review-manual-app-evidence-template.json")
  missing_screenshot_manual_path = File.join(dir, "missing-screenshot-manual-app-evidence-template.json")
  empty_screenshot_manual_path = File.join(dir, "empty-screenshot-manual-app-evidence-template.json")
  reused_directshow_snapshot_manual_path = File.join(dir, "reused-directshow-snapshot-manual-app-evidence-template.json")
  copied_directshow_snapshot_manual_path = File.join(dir, "copied-directshow-snapshot-manual-app-evidence-template.json")
  duplicate_app_screenshot_manual_path = File.join(dir, "duplicate-app-screenshot-manual-app-evidence-template.json")
  duplicate_app_screenshot_content_manual_path = File.join(dir, "duplicate-app-screenshot-content-manual-app-evidence-template.json")
  text_screenshot_manual_path = File.join(dir, "text-screenshot-manual-app-evidence-template.json")
  missing_runtime_log_path = File.join(dir, "missing-log-runtime-evidence.json")
  empty_runtime_log_path = File.join(dir, "empty-log-runtime-evidence.json")
  short_capture_runtime_path = File.join(dir, "short-capture-runtime-evidence.json")
  missing_runtime_stdout_url_path = File.join(dir, "missing-stdout-url-runtime-evidence.json")
  missing_runtime_camera_log_path = File.join(dir, "missing-camera-log-runtime-evidence.json")
  short_capture_log_runtime_path = File.join(dir, "short-capture-log-runtime-evidence.json")
  missing_capture_camera_log_runtime_path = File.join(dir, "missing-capture-camera-log-runtime-evidence.json")
  missing_directshow_snapshot_path = File.join(dir, "missing-directshow-snapshot-runtime-evidence.json")
  text_directshow_snapshot_path = File.join(dir, "text-directshow-snapshot-runtime-evidence.json")
  missing_directshow_snapshot_log_path = File.join(dir, "missing-directshow-snapshot-log-runtime-evidence.json")
  missing_runtime_manual_checklist_path = File.join(dir, "missing-manual-checklist-runtime-evidence.json")
  mismatched_runtime_manual_template_path = File.join(dir, "mismatched-manual-template-runtime-evidence.json")
  write_json(android_path, android_matrix)
  write_json(runtime_path, windows_runtime)
  write_json(manual_path, windows_manual)
  write_json(generated_runtime_path, windows_runtime.merge("sourceMode" => "generated self-test"))
  write_json(localhost_runtime_path, windows_runtime.merge("selectedRtspUrl" => "rtsp://127.0.0.1:8554/"))
  write_json(emulator_runtime_path, windows_runtime.merge("selectedRtspUrl" => "rtsp://10.0.2.16:8554/"))
  write_json(mismatched_runtime_path, windows_runtime.merge("selectedRtspUrl" => "rtsp://192.168.1.99:8554/"))
  write_json(inconsistent_runtime_rtsp_path, windows_runtime.merge("openedRtspUrl" => "rtsp://192.168.1.99:8554/"))
  write_json(missing_runtime_opened_rtsp_path, windows_runtime.merge("openedRtspUrl" => nil))
  write_json(missing_runtime_selected_rtsp_path, windows_runtime.merge("selectedRtspUrl" => nil))
  write_json(mismatched_pair_code_runtime_path, windows_runtime.merge("pairCode" => "654321"))
  write_json(mismatched_manual_path, windows_manual.merge("effectiveRtspUrl" => "rtsp://192.168.1.99:8554/"))
  write_json(inconsistent_manual_rtsp_path, windows_manual.merge("openedRtspUrl" => "rtsp://192.168.1.99:8554/"))
  write_json(mismatched_source_mode_manual_path, windows_manual.merge("sourceMode" => "manual RTSP"))
  write_json(mismatched_receiver_process_manual_path, windows_manual.merge("receiverProcessId" => 9999))
  missing_runtime_artifact_manual = Marshal.load(Marshal.dump(windows_manual))
  missing_runtime_artifact_manual["runtimeArtifacts"]["directShowFrameSnapshot"] = ""
  write_json(missing_runtime_artifact_manual_path, missing_runtime_artifact_manual)
  other_directshow_snapshot_path = File.join(dir, "other-directshow-frame.bmp")
  File.write(other_directshow_snapshot_path, "BMfixture different directshow frame")
  mismatched_runtime_artifact_manual = Marshal.load(Marshal.dump(windows_manual))
  mismatched_runtime_artifact_manual["runtimeArtifacts"]["directShowFrameSnapshot"] = other_directshow_snapshot_path
  write_json(mismatched_runtime_artifact_manual_path, mismatched_runtime_artifact_manual)
  missing_directshow_review_manual = Marshal.load(Marshal.dump(windows_manual))
  missing_directshow_review_manual["directShowFrameMatchesExpectedAndroidStream"] = false
  missing_directshow_review_manual["directShowFrameReviewNote"] = ""
  write_json(missing_directshow_review_manual_path, missing_directshow_review_manual)
  missing_screenshot_manual = Marshal.load(Marshal.dump(windows_manual))
  missing_screenshot_manual["obs"]["screenshotPath"] = File.join(dir, "missing-obs-phonecam.png")
  write_json(missing_screenshot_manual_path, missing_screenshot_manual)
  empty_screenshot_path = File.join(dir, "empty-obs-phonecam.png")
  File.write(empty_screenshot_path, "")
  empty_screenshot_manual = Marshal.load(Marshal.dump(windows_manual))
  empty_screenshot_manual["obs"]["screenshotPath"] = empty_screenshot_path
  write_json(empty_screenshot_manual_path, empty_screenshot_manual)
  reused_directshow_snapshot_manual = Marshal.load(Marshal.dump(windows_manual))
  reused_directshow_snapshot_manual["obs"]["screenshotPath"] = directshow_snapshot_path
  write_json(reused_directshow_snapshot_manual_path, reused_directshow_snapshot_manual)
  copied_directshow_snapshot_path = File.join(dir, "copied-directshow-frame.bmp")
  File.binwrite(copied_directshow_snapshot_path, FIXTURE_DIRECTSHOW_BMP)
  copied_directshow_snapshot_manual = Marshal.load(Marshal.dump(windows_manual))
  copied_directshow_snapshot_manual["obs"]["screenshotPath"] = copied_directshow_snapshot_path
  write_json(copied_directshow_snapshot_manual_path, copied_directshow_snapshot_manual)
  duplicate_app_screenshot_manual = Marshal.load(Marshal.dump(windows_manual))
  duplicate_app_screenshot_manual["browserOrCameraApp"]["screenshotPath"] = obs_screenshot_path
  write_json(duplicate_app_screenshot_manual_path, duplicate_app_screenshot_manual)
  duplicate_app_screenshot_content_path = File.join(dir, "browser-phonecam-copy.png")
  File.binwrite(duplicate_app_screenshot_content_path, FIXTURE_PNG)
  duplicate_app_screenshot_content_manual = Marshal.load(Marshal.dump(windows_manual))
  duplicate_app_screenshot_content_manual["browserOrCameraApp"]["screenshotPath"] = duplicate_app_screenshot_content_path
  write_json(duplicate_app_screenshot_content_manual_path, duplicate_app_screenshot_content_manual)
  text_screenshot_path = File.join(dir, "obs-phonecam.txt")
  File.write(text_screenshot_path, "not an image")
  text_screenshot_manual = Marshal.load(Marshal.dump(windows_manual))
  text_screenshot_manual["obs"]["screenshotPath"] = text_screenshot_path
  write_json(text_screenshot_manual_path, text_screenshot_manual)
  missing_runtime_log = Marshal.load(Marshal.dump(windows_runtime))
  missing_runtime_log["logs"]["summary"] = File.join(dir, "missing-runtime-summary.txt")
  write_json(missing_runtime_log_path, missing_runtime_log)
  empty_runtime_log_file = File.join(dir, "empty-runtime-summary.txt")
  File.write(empty_runtime_log_file, "")
  empty_runtime_log = Marshal.load(Marshal.dump(windows_runtime))
  empty_runtime_log["logs"]["summary"] = empty_runtime_log_file
  write_json(empty_runtime_log_path, empty_runtime_log)
  short_capture_runtime = Marshal.load(Marshal.dump(windows_runtime))
  short_capture_runtime["capture"]["frames"] = 29
  write_json(short_capture_runtime_path, short_capture_runtime)
  missing_stdout_url_file = File.join(dir, "receiver-without-url.stdout.log")
  File.write(missing_stdout_url_file, "Receiver started without the Android URL")
  missing_stdout_url_runtime = Marshal.load(Marshal.dump(windows_runtime))
  missing_stdout_url_runtime["logs"]["receiverStdout"] = missing_stdout_url_file
  write_json(missing_runtime_stdout_url_path, missing_stdout_url_runtime)
  missing_camera_log_file = File.join(dir, "ffmpeg-dshow-devices-without-camera.log")
  File.write(missing_camera_log_file, "DirectShow video device: Other Camera")
  missing_camera_log_runtime = Marshal.load(Marshal.dump(windows_runtime))
  missing_camera_log_runtime["logs"]["directShowDevices"] = missing_camera_log_file
  write_json(missing_runtime_camera_log_path, missing_camera_log_runtime)
  short_capture_log_file = File.join(dir, "ffmpeg-short-capture.log")
  File.write(short_capture_log_file, "Input #0, dshow, from 'video=PhoneCam Virtual Camera':\nframe=29")
  short_capture_log_runtime = Marshal.load(Marshal.dump(windows_runtime))
  short_capture_log_runtime["logs"]["capture"] = short_capture_log_file
  write_json(short_capture_log_runtime_path, short_capture_log_runtime)
  missing_capture_camera_log_file = File.join(dir, "ffmpeg-capture-without-camera.log")
  File.write(missing_capture_camera_log_file, "Input #0, dshow, from 'video=Other Camera':\nframe=30")
  missing_capture_camera_log_runtime = Marshal.load(Marshal.dump(windows_runtime))
  missing_capture_camera_log_runtime["logs"]["capture"] = missing_capture_camera_log_file
  write_json(missing_capture_camera_log_runtime_path, missing_capture_camera_log_runtime)
  missing_directshow_snapshot_runtime = Marshal.load(Marshal.dump(windows_runtime))
  missing_directshow_snapshot_runtime["capture"]["snapshot"] = File.join(dir, "missing-directshow-frame.bmp")
  write_json(missing_directshow_snapshot_path, missing_directshow_snapshot_runtime)
  text_directshow_snapshot_file = File.join(dir, "text-directshow-frame.bmp")
  File.write(text_directshow_snapshot_file, "not an image")
  text_directshow_snapshot_runtime = Marshal.load(Marshal.dump(windows_runtime))
  text_directshow_snapshot_runtime["capture"]["snapshot"] = text_directshow_snapshot_file
  write_json(text_directshow_snapshot_path, text_directshow_snapshot_runtime)
  missing_directshow_snapshot_log_runtime = Marshal.load(Marshal.dump(windows_runtime))
  missing_directshow_snapshot_log_runtime["logs"]["directShowSnapshot"] = File.join(dir, "missing-directshow-snapshot.log")
  write_json(missing_directshow_snapshot_log_path, missing_directshow_snapshot_log_runtime)
  missing_manual_checklist_runtime = Marshal.load(Marshal.dump(windows_runtime))
  missing_manual_checklist_runtime["logs"]["manualAppChecklist"] = File.join(dir, "missing-manual-checklist.txt")
  write_json(missing_runtime_manual_checklist_path, missing_manual_checklist_runtime)
  other_manual_template_file = File.join(dir, "other-manual-app-evidence-template.json")
  File.write(other_manual_template_file, "fixture other manual template")
  mismatched_manual_template_runtime = Marshal.load(Marshal.dump(windows_runtime))
  mismatched_manual_template_runtime["logs"]["manualEvidenceTemplate"] = other_manual_template_file
  write_json(mismatched_runtime_manual_template_path, mismatched_manual_template_runtime)
  emulator_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  emulator_profile = emulator_android_matrix.fetch("profiles").first
  emulator_profile_dir = File.join(dir, "android-emulator-profile")
  FileUtils.mkdir_p(emulator_profile_dir)
  emulator_profile_evidence_path = File.join(emulator_profile_dir, "wifi-evidence.json")
  emulator_profile["evidenceDir"] = emulator_profile_dir
  emulator_profile["evidenceJson"] = emulator_profile_evidence_path
  emulator_profile_evidence = JSON.parse(File.read(android_matrix.fetch("profiles").first.fetch("evidenceJson")))
  emulator_profile_evidence["androidSerial"] = "emulator-5554"
  emulator_profile_evidence["rtspUrl"] = "rtsp://10.0.2.16:8554/"
  emulator_profile_evidence["directDecode"]["openedRtspUrl"] = "rtsp://10.0.2.16:8554/"
  write_json(emulator_profile_evidence_path, emulator_profile_evidence)
  write_json(android_emulator_path, emulator_android_matrix)
  no_discovery_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  no_discovery_profile = no_discovery_android_matrix.fetch("profiles").first
  no_discovery_profile_dir = File.join(dir, "android-no-discovery-profile")
  FileUtils.mkdir_p(no_discovery_profile_dir)
  no_discovery_profile_evidence_path = File.join(no_discovery_profile_dir, "wifi-evidence.json")
  no_discovery_profile["evidenceDir"] = no_discovery_profile_dir
  no_discovery_profile["evidenceJson"] = no_discovery_profile_evidence_path
  no_discovery_profile_evidence = JSON.parse(File.read(android_matrix.fetch("profiles").first.fetch("evidenceJson")))
  no_discovery_profile_evidence["pairCodeDiscoveryDecode"] = {
    "status" => "failed",
    "exitStatus" => 2,
    "pairingCode" => "123456",
    "frames" => 0,
    "resolution" => ""
  }
  write_json(no_discovery_profile_evidence_path, no_discovery_profile_evidence)
  write_json(android_no_discovery_path, no_discovery_android_matrix)
  no_pairing_code_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  no_pairing_code_profile = no_pairing_code_android_matrix.fetch("profiles").first
  no_pairing_code_profile_dir = File.join(dir, "android-no-pairing-code-profile")
  FileUtils.mkdir_p(no_pairing_code_profile_dir)
  no_pairing_code_profile_evidence_path = File.join(no_pairing_code_profile_dir, "wifi-evidence.json")
  no_pairing_code_profile["evidenceDir"] = no_pairing_code_profile_dir
  no_pairing_code_profile["evidenceJson"] = no_pairing_code_profile_evidence_path
  no_pairing_code_profile_evidence = JSON.parse(File.read(android_matrix.fetch("profiles").first.fetch("evidenceJson")))
  no_pairing_code_profile_evidence["pairingCode"] = ""
  no_pairing_code_profile_evidence["pairCodeDiscoveryDecode"]["pairingCode"] = ""
  write_json(no_pairing_code_profile_evidence_path, no_pairing_code_profile_evidence)
  write_json(android_no_pairing_code_path, no_pairing_code_android_matrix)
  preview_not_live_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  preview_not_live_profile = preview_not_live_android_matrix.fetch("profiles").first
  preview_not_live_profile_dir = File.join(dir, "android-preview-not-live-profile")
  FileUtils.mkdir_p(preview_not_live_profile_dir)
  preview_not_live_profile_evidence_path = File.join(preview_not_live_profile_dir, "wifi-evidence.json")
  preview_not_live_profile["evidenceDir"] = preview_not_live_profile_dir
  preview_not_live_profile["evidenceJson"] = preview_not_live_profile_evidence_path
  preview_not_live_profile_evidence = JSON.parse(File.read(android_matrix.fetch("profiles").first.fetch("evidenceJson")))
  preview_not_live_profile_evidence["previewLive"] = false
  write_json(preview_not_live_profile_evidence_path, preview_not_live_profile_evidence)
  write_json(android_preview_not_live_path, preview_not_live_android_matrix)
  no_wifi_network_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  no_wifi_network_profile = no_wifi_network_android_matrix.fetch("profiles").first
  no_wifi_network_profile_dir = File.join(dir, "android-no-wifi-network-profile")
  FileUtils.mkdir_p(no_wifi_network_profile_dir)
  no_wifi_network_profile_evidence_path = File.join(no_wifi_network_profile_dir, "wifi-evidence.json")
  no_wifi_network_profile["evidenceDir"] = no_wifi_network_profile_dir
  no_wifi_network_profile["evidenceJson"] = no_wifi_network_profile_evidence_path
  no_wifi_network_profile_evidence = JSON.parse(File.read(android_matrix.fetch("profiles").first.fetch("evidenceJson")))
  no_wifi_network_profile_evidence["network"] = {
    "wifiEvidenceCaptured" => false,
    "rtspHost" => "",
    "wifiStatusSummary" => "",
    "wifiDumpsysSummary" => "",
    "ipRouteSummary" => ""
  }
  write_json(no_wifi_network_profile_evidence_path, no_wifi_network_profile_evidence)
  write_json(android_no_wifi_network_path, no_wifi_network_android_matrix)
  direct_mismatch_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  direct_mismatch_profile = direct_mismatch_android_matrix.fetch("profiles").first
  direct_mismatch_profile_dir = File.join(dir, "android-direct-mismatch-profile")
  FileUtils.mkdir_p(direct_mismatch_profile_dir)
  direct_mismatch_profile_evidence_path = File.join(direct_mismatch_profile_dir, "wifi-evidence.json")
  direct_mismatch_profile["evidenceDir"] = direct_mismatch_profile_dir
  direct_mismatch_profile["evidenceJson"] = direct_mismatch_profile_evidence_path
  direct_mismatch_profile_evidence = JSON.parse(File.read(android_matrix.fetch("profiles").first.fetch("evidenceJson")))
  direct_mismatch_profile_evidence["directDecode"]["openedRtspUrl"] = "rtsp://192.168.1.99:8554/"
  write_json(direct_mismatch_profile_evidence_path, direct_mismatch_profile_evidence)
  write_json(android_direct_mismatch_path, direct_mismatch_android_matrix)
  non_final_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  non_final_android_matrix["finalMvpEvidence"] = false
  non_final_android_matrix["allowUnverifiedOrientation"] = true
  non_final_profile = non_final_android_matrix.fetch("profiles").first
  non_final_profile_dir = File.join(dir, "android-non-final-profile")
  FileUtils.mkdir_p(non_final_profile_dir)
  non_final_profile_evidence_path = File.join(non_final_profile_dir, "wifi-evidence.json")
  non_final_profile["evidenceDir"] = non_final_profile_dir
  non_final_profile["evidenceJson"] = non_final_profile_evidence_path
  non_final_profile_evidence = JSON.parse(File.read(android_matrix.fetch("profiles").first.fetch("evidenceJson")))
  non_final_profile_evidence["finalMvpEvidence"] = false
  non_final_profile_evidence["doesNotProve"] = [
    "physical Android orientation acceptance",
    "Windows DirectShow registration",
    "OBS/browser camera enumeration"
  ]
  write_json(non_final_profile_evidence_path, non_final_profile_evidence)
  write_json(android_non_final_path, non_final_android_matrix)
  stream_orientation_unverified_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  stream_orientation_unverified_profile = stream_orientation_unverified_android_matrix.fetch("profiles").first
  stream_orientation_unverified_profile_dir = File.join(dir, "android-stream-orientation-unverified-profile")
  FileUtils.mkdir_p(stream_orientation_unverified_profile_dir)
  stream_orientation_unverified_profile_evidence_path = File.join(stream_orientation_unverified_profile_dir, "wifi-evidence.json")
  stream_orientation_unverified_profile["evidenceDir"] = stream_orientation_unverified_profile_dir
  stream_orientation_unverified_profile["evidenceJson"] = stream_orientation_unverified_profile_evidence_path
  stream_orientation_unverified_profile_evidence = JSON.parse(File.read(android_matrix.fetch("profiles").first.fetch("evidenceJson")))
  stream_orientation_unverified_profile_evidence["streamOrientation"]["orientationStatus"] = "not-verified"
  write_json(stream_orientation_unverified_profile_evidence_path, stream_orientation_unverified_profile_evidence)
  write_json(android_stream_orientation_unverified_path, stream_orientation_unverified_android_matrix)
  stream_orientation_unlocked_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  stream_orientation_unlocked_profile = stream_orientation_unlocked_android_matrix.fetch("profiles").first
  stream_orientation_unlocked_profile_dir = File.join(dir, "android-stream-orientation-unlocked-profile")
  FileUtils.mkdir_p(stream_orientation_unlocked_profile_dir)
  stream_orientation_unlocked_profile_evidence_path = File.join(stream_orientation_unlocked_profile_dir, "wifi-evidence.json")
  stream_orientation_unlocked_profile["evidenceDir"] = stream_orientation_unlocked_profile_dir
  stream_orientation_unlocked_profile["evidenceJson"] = stream_orientation_unlocked_profile_evidence_path
  stream_orientation_unlocked_profile_evidence = JSON.parse(File.read(android_matrix.fetch("profiles").first.fetch("evidenceJson")))
  stream_orientation_unlocked_profile_evidence["streamOrientation"]["orientationLockMode"] = ""
  write_json(stream_orientation_unlocked_profile_evidence_path, stream_orientation_unlocked_profile_evidence)
  write_json(android_stream_orientation_unlocked_path, stream_orientation_unlocked_android_matrix)
  stream_orientation_missing_posture_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  stream_orientation_missing_posture_profile = stream_orientation_missing_posture_android_matrix.fetch("profiles").first
  stream_orientation_missing_posture_profile_dir = File.join(dir, "android-stream-orientation-missing-posture-profile")
  FileUtils.mkdir_p(stream_orientation_missing_posture_profile_dir)
  stream_orientation_missing_posture_profile_evidence_path = File.join(stream_orientation_missing_posture_profile_dir, "wifi-evidence.json")
  stream_orientation_missing_posture_profile["evidenceDir"] = stream_orientation_missing_posture_profile_dir
  stream_orientation_missing_posture_profile["evidenceJson"] = stream_orientation_missing_posture_profile_evidence_path
  stream_orientation_missing_posture_profile_evidence = JSON.parse(File.read(android_matrix.fetch("profiles").first.fetch("evidenceJson")))
  stream_orientation_missing_posture_profile_evidence["streamOrientation"]["devicePosture"] = ""
  write_json(stream_orientation_missing_posture_profile_evidence_path, stream_orientation_missing_posture_profile_evidence)
  write_json(android_stream_orientation_missing_posture_path, stream_orientation_missing_posture_android_matrix)
  stream_rotation_direction_missing_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  stream_rotation_direction_missing_profile = stream_rotation_direction_missing_android_matrix.fetch("profiles").first
  stream_rotation_direction_missing_profile_dir = File.join(dir, "android-stream-rotation-direction-missing-profile")
  FileUtils.mkdir_p(stream_rotation_direction_missing_profile_dir)
  stream_rotation_direction_missing_profile_evidence_path = File.join(stream_rotation_direction_missing_profile_dir, "wifi-evidence.json")
  stream_rotation_direction_missing_profile["evidenceDir"] = stream_rotation_direction_missing_profile_dir
  stream_rotation_direction_missing_profile["evidenceJson"] = stream_rotation_direction_missing_profile_evidence_path
  stream_rotation_direction_missing_profile_evidence = JSON.parse(File.read(android_matrix.fetch("profiles").first.fetch("evidenceJson")))
  stream_rotation_direction_missing_profile_evidence.delete("streamRotationDirection")
  stream_rotation_direction_missing_profile_evidence["streamOrientation"].delete("rotationDirection")
  write_json(stream_rotation_direction_missing_profile_evidence_path, stream_rotation_direction_missing_profile_evidence)
  write_json(android_stream_rotation_direction_missing_path, stream_rotation_direction_missing_android_matrix)
  stream_rotation_degree_invalid_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  stream_rotation_degree_invalid_profile = stream_rotation_degree_invalid_android_matrix.fetch("profiles").first
  stream_rotation_degree_invalid_profile_dir = File.join(dir, "android-stream-rotation-degree-invalid-profile")
  FileUtils.mkdir_p(stream_rotation_degree_invalid_profile_dir)
  stream_rotation_degree_invalid_profile_evidence_path = File.join(stream_rotation_degree_invalid_profile_dir, "wifi-evidence.json")
  stream_rotation_degree_invalid_profile["evidenceDir"] = stream_rotation_degree_invalid_profile_dir
  stream_rotation_degree_invalid_profile["evidenceJson"] = stream_rotation_degree_invalid_profile_evidence_path
  stream_rotation_degree_invalid_profile_evidence = JSON.parse(File.read(android_matrix.fetch("profiles").first.fetch("evidenceJson")))
  stream_rotation_degree_invalid_profile_evidence["streamRotationDegrees"] = 45
  stream_rotation_degree_invalid_profile_evidence["streamOrientation"]["outputRotationDegrees"] = 45
  write_json(stream_rotation_degree_invalid_profile_evidence_path, stream_rotation_degree_invalid_profile_evidence)
  write_json(android_stream_rotation_degree_invalid_path, stream_rotation_degree_invalid_android_matrix)
  stream_rotation_target_mismatch_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  stream_rotation_target_mismatch_profile = stream_rotation_target_mismatch_android_matrix.fetch("profiles").first
  stream_rotation_target_mismatch_profile_dir = File.join(dir, "android-stream-rotation-target-mismatch-profile")
  FileUtils.mkdir_p(stream_rotation_target_mismatch_profile_dir)
  stream_rotation_target_mismatch_profile_evidence_path = File.join(stream_rotation_target_mismatch_profile_dir, "wifi-evidence.json")
  stream_rotation_target_mismatch_profile["evidenceDir"] = stream_rotation_target_mismatch_profile_dir
  stream_rotation_target_mismatch_profile["evidenceJson"] = stream_rotation_target_mismatch_profile_evidence_path
  stream_rotation_target_mismatch_profile_evidence = JSON.parse(File.read(android_matrix.fetch("profiles").first.fetch("evidenceJson")))
  stream_rotation_target_mismatch_profile_evidence["streamRotationRequestMode"] = "absolute-degrees"
  stream_rotation_target_mismatch_profile_evidence["streamRequestedOutputRotationDegrees"] = 90
  stream_rotation_target_mismatch_profile_evidence["streamRotationDegrees"] = 0
  stream_rotation_target_mismatch_profile_evidence["streamOrientation"]["rotationRequestMode"] = "absolute-degrees"
  stream_rotation_target_mismatch_profile_evidence["streamOrientation"]["requestedOutputRotationDegrees"] = 90
  stream_rotation_target_mismatch_profile_evidence["streamOrientation"]["outputRotationDegrees"] = 0
  write_json(stream_rotation_target_mismatch_profile_evidence_path, stream_rotation_target_mismatch_profile_evidence)
  write_json(android_stream_rotation_target_mismatch_path, stream_rotation_target_mismatch_android_matrix)
  front_mismatch_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  front_mismatch_profile = front_mismatch_android_matrix.fetch("profiles").find { |profile| profile.fetch("profile") == "Motion" }
  front_mismatch_profile_dir = File.join(dir, "android-front-mismatch-profile")
  FileUtils.mkdir_p(front_mismatch_profile_dir)
  front_mismatch_profile_evidence_path = File.join(front_mismatch_profile_dir, "wifi-evidence.json")
  front_mismatch_profile["evidenceDir"] = front_mismatch_profile_dir
  front_mismatch_profile["evidenceJson"] = front_mismatch_profile_evidence_path
  motion_profile = android_matrix.fetch("profiles").find { |profile| profile.fetch("profile") == "Motion" }
  front_mismatch_profile_evidence = JSON.parse(File.read(motion_profile.fetch("evidenceJson")))
  front_mismatch_profile_evidence["frontCamera"]["openedRtspUrl"] = "rtsp://192.168.1.99:8554/"
  write_json(front_mismatch_profile_evidence_path, front_mismatch_profile_evidence)
  write_json(android_front_mismatch_path, front_mismatch_android_matrix)
  front_rotation_target_mismatch_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  front_rotation_target_mismatch_profile = front_rotation_target_mismatch_android_matrix.fetch("profiles").find { |profile| profile.fetch("profile") == "Motion" }
  front_rotation_target_mismatch_profile_dir = File.join(dir, "android-front-rotation-target-mismatch-profile")
  FileUtils.mkdir_p(front_rotation_target_mismatch_profile_dir)
  front_rotation_target_mismatch_profile_evidence_path = File.join(front_rotation_target_mismatch_profile_dir, "wifi-evidence.json")
  front_rotation_target_mismatch_profile["evidenceDir"] = front_rotation_target_mismatch_profile_dir
  front_rotation_target_mismatch_profile["evidenceJson"] = front_rotation_target_mismatch_profile_evidence_path
  front_rotation_target_mismatch_profile_evidence = JSON.parse(File.read(motion_profile.fetch("evidenceJson")))
  front_rotation_target_mismatch_profile_evidence["frontCamera"]["rotationRequestMode"] = "absolute-degrees"
  front_rotation_target_mismatch_profile_evidence["frontCamera"]["requestedOutputRotationDegrees"] = 180
  front_rotation_target_mismatch_profile_evidence["frontCamera"]["outputRotationDegrees"] = 90
  write_json(front_rotation_target_mismatch_profile_evidence_path, front_rotation_target_mismatch_profile_evidence)
  write_json(android_front_rotation_target_mismatch_path, front_rotation_target_mismatch_android_matrix)
  front_orientation_unverified_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  front_orientation_unverified_profile = front_orientation_unverified_android_matrix.fetch("profiles").find { |profile| profile.fetch("profile") == "Motion" }
  front_orientation_unverified_profile_dir = File.join(dir, "android-front-orientation-unverified-profile")
  FileUtils.mkdir_p(front_orientation_unverified_profile_dir)
  front_orientation_unverified_profile_evidence_path = File.join(front_orientation_unverified_profile_dir, "wifi-evidence.json")
  front_orientation_unverified_profile["evidenceDir"] = front_orientation_unverified_profile_dir
  front_orientation_unverified_profile["evidenceJson"] = front_orientation_unverified_profile_evidence_path
  front_orientation_unverified_profile_evidence = JSON.parse(File.read(motion_profile.fetch("evidenceJson")))
  front_orientation_unverified_profile_evidence["frontCamera"]["orientationStatus"] = "not-verified"
  write_json(front_orientation_unverified_profile_evidence_path, front_orientation_unverified_profile_evidence)
  write_json(android_front_orientation_unverified_path, front_orientation_unverified_android_matrix)
  front_orientation_missing_notes_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  front_orientation_missing_notes_profile = front_orientation_missing_notes_android_matrix.fetch("profiles").find { |profile| profile.fetch("profile") == "Motion" }
  front_orientation_missing_notes_profile_dir = File.join(dir, "android-front-orientation-missing-notes-profile")
  FileUtils.mkdir_p(front_orientation_missing_notes_profile_dir)
  front_orientation_missing_notes_profile_evidence_path = File.join(front_orientation_missing_notes_profile_dir, "wifi-evidence.json")
  front_orientation_missing_notes_profile["evidenceDir"] = front_orientation_missing_notes_profile_dir
  front_orientation_missing_notes_profile["evidenceJson"] = front_orientation_missing_notes_profile_evidence_path
  front_orientation_missing_notes_profile_evidence = JSON.parse(File.read(motion_profile.fetch("evidenceJson")))
  front_orientation_missing_notes_profile_evidence["frontCamera"]["orientationNotes"] = ""
  write_json(front_orientation_missing_notes_profile_evidence_path, front_orientation_missing_notes_profile_evidence)
  write_json(android_front_orientation_missing_notes_path, front_orientation_missing_notes_android_matrix)
  missing_screenshot_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  missing_screenshot_profile = missing_screenshot_android_matrix.fetch("profiles").first
  missing_screenshot_profile_dir = File.join(dir, "android-missing-screenshot-profile")
  FileUtils.mkdir_p(missing_screenshot_profile_dir)
  missing_screenshot_profile_evidence_path = File.join(missing_screenshot_profile_dir, "wifi-evidence.json")
  missing_screenshot_profile["evidenceDir"] = missing_screenshot_profile_dir
  missing_screenshot_profile["evidenceJson"] = missing_screenshot_profile_evidence_path
  missing_screenshot_profile_evidence = JSON.parse(File.read(android_matrix.fetch("profiles").first.fetch("evidenceJson")))
  missing_screenshot_profile_evidence["artifacts"]["streamingScreenshot"] = File.join(missing_screenshot_profile_dir, "missing-screenshot-after-start.png")
  write_json(missing_screenshot_profile_evidence_path, missing_screenshot_profile_evidence)
  write_json(android_missing_screenshot_path, missing_screenshot_android_matrix)
  text_screenshot_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  text_screenshot_profile = text_screenshot_android_matrix.fetch("profiles").first
  text_screenshot_profile_dir = File.join(dir, "android-text-screenshot-profile")
  FileUtils.mkdir_p(text_screenshot_profile_dir)
  text_screenshot_profile_evidence_path = File.join(text_screenshot_profile_dir, "wifi-evidence.json")
  text_screenshot_profile["evidenceDir"] = text_screenshot_profile_dir
  text_screenshot_profile["evidenceJson"] = text_screenshot_profile_evidence_path
  text_screenshot_profile_evidence = JSON.parse(File.read(android_matrix.fetch("profiles").first.fetch("evidenceJson")))
  text_screenshot_file = File.join(text_screenshot_profile_dir, "screenshot-after-start.png")
  File.write(text_screenshot_file, "not a screenshot image")
  text_screenshot_profile_evidence["artifacts"]["streamingScreenshot"] = text_screenshot_file
  write_json(text_screenshot_profile_evidence_path, text_screenshot_profile_evidence)
  write_json(android_text_screenshot_path, text_screenshot_android_matrix)
  compact_preview_not_live_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  compact_preview_not_live_profile = compact_preview_not_live_android_matrix.fetch("profiles").first
  compact_preview_not_live_profile_dir = File.join(dir, "android-compact-preview-not-live-profile")
  FileUtils.mkdir_p(compact_preview_not_live_profile_dir)
  compact_preview_not_live_profile_evidence_path = File.join(compact_preview_not_live_profile_dir, "wifi-evidence.json")
  compact_preview_not_live_profile["evidenceDir"] = compact_preview_not_live_profile_dir
  compact_preview_not_live_profile["evidenceJson"] = compact_preview_not_live_profile_evidence_path
  compact_preview_not_live_profile_evidence = JSON.parse(File.read(android_matrix.fetch("profiles").first.fetch("evidenceJson")))
  compact_preview_not_live_ui = File.join(compact_preview_not_live_profile_dir, "ui-after-start-compact.xml")
  File.write(compact_preview_not_live_ui, 'fixture compact sender UI text="PREVIEW CHECKING" text="Preview: not confirmed"')
  compact_preview_not_live_profile_evidence["artifacts"]["streamingCompactUi"] = compact_preview_not_live_ui
  write_json(compact_preview_not_live_profile_evidence_path, compact_preview_not_live_profile_evidence)
  write_json(android_compact_preview_not_live_path, compact_preview_not_live_android_matrix)
  missing_snapshot_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  missing_snapshot_profile = missing_snapshot_android_matrix.fetch("profiles").first
  missing_snapshot_profile_dir = File.join(dir, "android-missing-snapshot-profile")
  FileUtils.mkdir_p(missing_snapshot_profile_dir)
  missing_snapshot_profile_evidence_path = File.join(missing_snapshot_profile_dir, "wifi-evidence.json")
  missing_snapshot_profile["evidenceDir"] = missing_snapshot_profile_dir
  missing_snapshot_profile["evidenceJson"] = missing_snapshot_profile_evidence_path
  missing_snapshot_profile_evidence = JSON.parse(File.read(android_matrix.fetch("profiles").first.fetch("evidenceJson")))
  missing_snapshot_profile_evidence["directDecode"]["snapshot"] = File.join(missing_snapshot_profile_dir, "missing-receiver-direct-frame.ppm")
  write_json(missing_snapshot_profile_evidence_path, missing_snapshot_profile_evidence)
  write_json(android_missing_snapshot_path, missing_snapshot_android_matrix)
  text_snapshot_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  text_snapshot_profile = text_snapshot_android_matrix.fetch("profiles").first
  text_snapshot_profile_dir = File.join(dir, "android-text-snapshot-profile")
  FileUtils.mkdir_p(text_snapshot_profile_dir)
  text_snapshot_profile_evidence_path = File.join(text_snapshot_profile_dir, "wifi-evidence.json")
  text_snapshot_profile["evidenceDir"] = text_snapshot_profile_dir
  text_snapshot_profile["evidenceJson"] = text_snapshot_profile_evidence_path
  text_snapshot_file = File.join(text_snapshot_profile_dir, "text-receiver-direct-frame.ppm")
  File.write(text_snapshot_file, "not an image")
  text_snapshot_profile_evidence = JSON.parse(File.read(android_matrix.fetch("profiles").first.fetch("evidenceJson")))
  text_snapshot_profile_evidence["directDecode"]["snapshot"] = text_snapshot_file
  write_json(text_snapshot_profile_evidence_path, text_snapshot_profile_evidence)
  write_json(android_text_snapshot_path, text_snapshot_android_matrix)
  decode_errors_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  decode_errors_profile = decode_errors_android_matrix.fetch("profiles").first
  decode_errors_profile_dir = File.join(dir, "android-decode-errors-profile")
  FileUtils.mkdir_p(decode_errors_profile_dir)
  decode_errors_profile_evidence_path = File.join(decode_errors_profile_dir, "wifi-evidence.json")
  decode_errors_profile["evidenceDir"] = decode_errors_profile_dir
  decode_errors_profile["evidenceJson"] = decode_errors_profile_evidence_path
  decode_errors_profile_evidence = JSON.parse(File.read(android_matrix.fetch("profiles").first.fetch("evidenceJson")))
  decode_errors_profile_evidence["directDecode"]["decodeErrors"] = 1
  write_json(decode_errors_profile_evidence_path, decode_errors_profile_evidence)
  write_json(android_decode_errors_path, decode_errors_android_matrix)
  high_bitrate_android_matrix = Marshal.load(Marshal.dump(android_matrix))
  high_bitrate_profile = high_bitrate_android_matrix.fetch("profiles").first
  high_bitrate_profile_dir = File.join(dir, "android-high-bitrate-profile")
  FileUtils.mkdir_p(high_bitrate_profile_dir)
  high_bitrate_profile_evidence_path = File.join(high_bitrate_profile_dir, "wifi-evidence.json")
  high_bitrate_profile["evidenceDir"] = high_bitrate_profile_dir
  high_bitrate_profile["evidenceJson"] = high_bitrate_profile_evidence_path
  high_bitrate_profile_evidence = JSON.parse(File.read(android_matrix.fetch("profiles").first.fetch("evidenceJson")))
  high_bitrate_profile_evidence["directDecode"]["incomingMbps"] = 2.1
  write_json(high_bitrate_profile_evidence_path, high_bitrate_profile_evidence)
  write_json(android_high_bitrate_path, high_bitrate_android_matrix)

  validator = File.join(ROOT, "scripts/validate_mvp_evidence.rb")
  ruby = RbConfig.ruby
  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(status.success?, "MVP evidence validator should accept complete fixture evidence: #{stdout} #{stderr}")
  assert(stdout.include?("MVP evidence validation passed"), "MVP evidence validator success output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--android-only"
  )
  assert(status.success?, "Android-only evidence preflight should accept complete Android fixture evidence: #{stdout} #{stderr}")
  assert(stdout.include?("Android matrix evidence validation passed"), "Android-only validator success output changed")

  bundler = File.join(ROOT, "scripts/bundle_mvp_evidence.rb")
  android_only_bundle_dir = File.join(dir, "android-only-bundled-evidence")
  stdout, stderr, status = Open3.capture3(
    ruby,
    bundler,
    "--android-matrix", android_path,
    "--android-only",
    "--output-dir", android_only_bundle_dir
  )
  assert(status.success?, "Android-only evidence bundler should package complete Android fixture evidence: #{stdout} #{stderr}")
  assert(stdout.include?("Android matrix evidence bundle"), "Android-only evidence bundler success output changed")
  android_only_manifest_path = File.join(android_only_bundle_dir, "bundle-manifest.json")
  assert(File.file?(android_only_manifest_path), "Android-only evidence bundler must write a manifest")
  android_only_manifest = JSON.parse(File.read(android_only_manifest_path))
  assert(android_only_manifest.dig("validation", "androidOnly") == true,
         "Android-only evidence bundle manifest must record androidOnly validation mode")
  assert(android_only_manifest.fetch("bundle").key?("androidMatrix"),
         "Android-only evidence bundle manifest must include androidMatrix")
  assert(!android_only_manifest.fetch("bundle").key?("windowsRuntime") &&
         !android_only_manifest.fetch("bundle").key?("windowsManual"),
         "Android-only evidence bundle manifest must not claim Windows evidence")
  assert(android_only_manifest.fetch("validateCommand").include?("--android-only"),
         "Android-only evidence bundle validateCommand must re-run Android-only validation")
  android_only_manifest_strings = flattened_manifest_strings(android_only_manifest)
  android_only_manifest_strings.each do |manifest_string|
    next if manifest_string.start_with?("ruby ")

    assert(!manifest_string.start_with?("/") && !manifest_string.match?(/\A[A-Za-z]:[\\\/]/),
           "Android-only evidence bundle manifest strings must not contain absolute host paths")
  end
  android_only_matrix_path = File.join(android_only_bundle_dir, android_only_manifest.fetch("bundle").fetch("androidMatrix"))
  android_only_validator_path = File.join(android_only_bundle_dir, android_only_manifest.fetch("tools").fetch("validator"))
  android_only_readme_path = File.join(android_only_bundle_dir, android_only_manifest.fetch("readme"))
  assert(File.file?(android_only_matrix_path), "Android-only evidence bundle must include the matrix JSON")
  assert(File.file?(android_only_validator_path), "Android-only evidence bundle must include a validator copy")
  assert(File.file?(android_only_readme_path), "Android-only evidence bundle must include a root README")
  android_only_readme = File.read(android_only_readme_path)
  assert(android_only_readme.include?("PhoneCam Android Matrix Evidence Bundle") &&
         android_only_readme.include?("Android-only bundle: yes") &&
         android_only_readme.include?("Collect-PhoneCamWindowsEvidence.ps1") &&
         android_only_readme.include?(android_only_manifest.fetch("validateCommand")),
         "Android-only evidence bundle README must document Windows handoff and validation")
  android_only_matrix_text = File.read(android_only_matrix_path)
  assert(!android_only_matrix_text.include?(dir),
         "Android-only evidence bundle must rewrite source absolute paths out of matrix JSON")
  stdout, stderr, status = Open3.capture3(
    ruby,
    android_only_validator_path,
    "--android-matrix", android_only_matrix_path,
    "--android-only"
  )
  assert(status.success?, "MVP evidence validator should accept bundled Android-only fixture evidence: #{stdout} #{stderr}")

  bundle_dir = File.join(dir, "bundled-evidence")
  stdout, stderr, status = Open3.capture3(
    ruby,
    bundler,
    "--android-matrix", android_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path,
    "--output-dir", bundle_dir
  )
  assert(status.success?, "MVP evidence bundler should package complete fixture evidence: #{stdout} #{stderr}")
  manifest_path = File.join(bundle_dir, "bundle-manifest.json")
  assert(File.file?(manifest_path), "MVP evidence bundler must write a manifest")
  bundle_manifest = JSON.parse(File.read(manifest_path))
  assert(bundle_manifest.key?("sourceInputs"), "MVP evidence bundle manifest must include source input fingerprints")
  %w[androidMatrix windowsRuntime windowsManual].each do |name|
    fingerprint = bundle_manifest.fetch("sourceInputs").fetch(name)
    assert(fingerprint.fetch("basename").end_with?(".json"), "MVP evidence bundle sourceInputs.#{name} must record a source basename")
    assert(fingerprint.fetch("bytes").is_a?(Integer) && fingerprint.fetch("bytes").positive?,
           "MVP evidence bundle sourceInputs.#{name} must record source byte size")
    assert(fingerprint.fetch("sha256").match?(/\A[0-9a-f]{64}\z/),
           "MVP evidence bundle sourceInputs.#{name} must record a sha256 fingerprint")
  end
  bundled_android_rel = bundle_manifest.fetch("bundle").fetch("androidMatrix")
  bundled_runtime_rel = bundle_manifest.fetch("bundle").fetch("windowsRuntime")
  bundled_manual_rel = bundle_manifest.fetch("bundle").fetch("windowsManual")
  bundled_validator_rel = bundle_manifest.fetch("tools").fetch("validator")
  bundled_readme_rel = bundle_manifest.fetch("readme")
  assert(bundle_manifest.fetch("validation").key?("skipped"), "MVP evidence bundle manifest must record whether validation was skipped")
  flattened_manifest_strings(bundle_manifest).each do |manifest_string|
    next if manifest_string.start_with?("ruby ")

    assert(!manifest_string.start_with?("/") && !manifest_string.match?(/\A[A-Za-z]:[\\\/]/),
           "MVP evidence bundle manifest strings must not contain absolute host paths")
  end
  assert(!bundle_manifest.fetch("validateCommand").include?(bundle_dir),
         "MVP evidence bundle validateCommand must not contain the original absolute output directory")
  assert(bundle_manifest.fetch("validateCommand").include?(bundled_validator_rel),
         "MVP evidence bundle validateCommand must use the bundled validator")
  bundled_android_path = File.join(bundle_dir, bundled_android_rel)
  bundled_runtime_path = File.join(bundle_dir, bundled_runtime_rel)
  bundled_manual_path = File.join(bundle_dir, bundled_manual_rel)
  bundled_validator_path = File.join(bundle_dir, bundled_validator_rel)
  bundled_readme_path = File.join(bundle_dir, bundled_readme_rel)
  assert(File.file?(bundled_validator_path), "MVP evidence bundle must include a validator copy")
  assert(File.file?(bundled_readme_path), "MVP evidence bundle must include a root README")
  bundled_readme = File.read(bundled_readme_path)
  assert(bundled_readme.include?("Run this command from this folder") &&
         bundled_readme.include?(bundle_manifest.fetch("validateCommand")) &&
         bundled_readme.include?(bundled_validator_rel) &&
         bundled_readme.include?("Source input fingerprints") &&
         bundled_readme.include?("Validation skipped when created: no") &&
         bundled_readme.include?("without --skip-validation"),
         "MVP evidence bundle README must document root-relative validation and source fingerprints")
  stdout, stderr, status = Open3.capture3(
    ruby,
    bundled_validator_path,
    "--android-matrix", bundled_android_path,
    "--windows-runtime", bundled_runtime_path,
    "--windows-manual", bundled_manual_path
  )
  assert(status.success?, "MVP evidence validator should accept bundled complete fixture evidence: #{stdout} #{stderr}")

  bad_bundle_dir = File.join(dir, "bad-bundled-evidence")
  stdout, stderr, status = Open3.capture3(
    ruby,
    bundler,
    "--android-matrix", android_path,
    "--windows-runtime", generated_runtime_path,
    "--windows-manual", manual_path,
    "--output-dir", bad_bundle_dir
  )
  assert(!status.success?, "MVP evidence bundler must reject incomplete/failing evidence by default")
  assert(stderr.include?("refusing to bundle incomplete MVP evidence"),
         "MVP evidence bundler failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", generated_runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject generated self-test Windows runtime evidence")
  assert(stderr.include?("generated self-test"), "MVP evidence validator generated self-test failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", localhost_runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject localhost Windows runtime evidence")
  assert(stderr.include?("real Android LAN address"), "MVP evidence validator localhost failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", emulator_runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject emulator Windows runtime evidence")
  assert(stderr.include?("real Android LAN address"), "MVP evidence validator emulator failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", mismatched_runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Windows runtime evidence tied to a different RTSP source")
  assert(stderr.include?("physical Android matrix RTSP URL"), "MVP evidence validator runtime/source mismatch failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", inconsistent_runtime_rtsp_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Windows runtime evidence with inconsistent RTSP URL fields")
  assert(stderr.include?("Windows runtime recorded RTSP URL fields must all refer to the same endpoint"),
         "MVP evidence validator runtime RTSP field consistency failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", missing_runtime_opened_rtsp_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Windows runtime evidence without an opened RTSP URL")
  assert(stderr.include?("openedRtspUrl must be recorded"), "MVP evidence validator runtime opened RTSP failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", missing_runtime_selected_rtsp_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject auto-discovery runtime evidence without a selected RTSP URL")
  assert(stderr.include?("selectedRtspUrl must be recorded"), "MVP evidence validator runtime selected RTSP failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", mismatched_pair_code_runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Windows runtime evidence tied to a different pair code")
  assert(stderr.include?("pairCode must match"), "MVP evidence validator runtime pair-code mismatch failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", missing_runtime_log_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Windows runtime evidence with missing log artifacts")
  assert(stderr.include?("Windows runtime summary log file must exist"), "MVP evidence validator missing runtime log failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", empty_runtime_log_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Windows runtime evidence with empty log artifacts")
  assert(stderr.include?("Windows runtime summary log file must be non-empty"), "MVP evidence validator empty runtime log failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", short_capture_runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Windows runtime capture below requested frame count")
  assert(stderr.include?("frame count must meet requestedFrames"), "MVP evidence validator requestedFrames failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", missing_runtime_stdout_url_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Windows runtime logs missing the selected RTSP URL")
  assert(stderr.include?("receiver stdout log must contain"), "MVP evidence validator receiver stdout content failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", missing_runtime_camera_log_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Windows runtime logs missing the cameraName")
  assert(stderr.include?("DirectShow device log must contain cameraName"), "MVP evidence validator DirectShow log content failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", short_capture_log_runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Windows runtime capture logs below requested frame count")
  assert(stderr.include?("capture log must show at least requestedFrames"), "MVP evidence validator capture log frame failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", missing_capture_camera_log_runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Windows runtime capture logs missing the cameraName")
  assert(stderr.include?("capture log must contain cameraName"), "MVP evidence validator capture log cameraName failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", missing_directshow_snapshot_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Windows runtime capture without a saved DirectShow frame snapshot")
  assert(stderr.include?("DirectShow captured frame snapshot file must exist"), "MVP evidence validator DirectShow snapshot failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", text_directshow_snapshot_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Windows runtime DirectShow snapshots that are not images")
  assert(stderr.include?("DirectShow captured frame snapshot file must be a PNG, JPEG, or BMP image"),
         "MVP evidence validator DirectShow snapshot image-signature failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", missing_directshow_snapshot_log_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Windows runtime capture without a DirectShow snapshot log")
  assert(stderr.include?("DirectShow snapshot log file must exist"), "MVP evidence validator DirectShow snapshot log failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", missing_runtime_manual_checklist_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Windows runtime evidence missing the generated manual checklist")
  assert(stderr.include?("manual app checklist file must exist"), "MVP evidence validator missing manual checklist failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", mismatched_runtime_manual_template_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Windows runtime evidence whose manual template path does not match --windows-manual")
  assert(stderr.include?("manualEvidenceTemplate path must match"), "MVP evidence validator manual template path mismatch failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", missing_runtime_artifact_manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject manual evidence missing runtime artifact paths")
  assert(stderr.include?("runtimeArtifacts.directShowFrameSnapshot path must be recorded"), "MVP evidence validator missing manual runtime artifact failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", mismatched_runtime_artifact_manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject manual evidence whose runtime artifact paths do not match runtime evidence")
  assert(stderr.include?("runtimeArtifacts.directShowFrameSnapshot must match runtime evidence"), "MVP evidence validator mismatched manual runtime artifact failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", missing_directshow_review_manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject manual evidence without DirectShow snapshot review confirmation")
  assert(stderr.include?("directShowFrameMatchesExpectedAndroidStream must be true"), "MVP evidence validator DirectShow snapshot review failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_emulator_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject emulator Android matrix evidence")
  assert(stderr.include?("physical Android target"), "MVP evidence validator Android emulator failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_no_discovery_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Android matrix evidence without pair-code discovery decode")
  assert(stderr.include?("pair-code discovery decode must be passed"), "MVP evidence validator Android discovery failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_no_pairing_code_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Android matrix evidence without a six-digit pairing code")
  assert(stderr.include?("pairingCode must be six digits"), "MVP evidence validator Android pairing-code failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_preview_not_live_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Android evidence without live sender preview")
  assert(stderr.include?("sender preview must report live"), "MVP evidence validator Android live-preview failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_compact_preview_not_live_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Android evidence whose compact sender UI did not show PREVIEW LIVE")
  assert(stderr.include?('compact streaming UI dump must contain "PREVIEW LIVE"'),
         "MVP evidence validator Android compact preview UI failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_no_wifi_network_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Android matrix evidence without Wi-Fi network evidence")
  assert(stderr.include?("Wi-Fi network evidence must be captured"), "MVP evidence validator Android Wi-Fi evidence failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_direct_mismatch_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Android direct decode evidence tied to a different RTSP URL")
  assert(stderr.include?("direct LAN decode RTSP URL must match the profile RTSP URL"), "MVP evidence validator Android direct decode URL mismatch failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_non_final_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Android matrix evidence marked non-final/calibration-only")
  assert(stderr.include?("final MVP physical Wi-Fi matrix evidence"), "MVP evidence validator Android non-final evidence failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_non_final_path,
    "--android-only"
  )
  assert(!status.success?, "Android-only validator must reject Android matrix evidence marked non-final/calibration-only before Windows handoff")
  assert(stderr.include?("final MVP physical Wi-Fi matrix evidence"), "Android-only validator non-final evidence failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_stream_orientation_unverified_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Android stream evidence without manual orientation verification")
  assert(stderr.include?("stream orientation status must be passed"), "MVP evidence validator Android stream orientation failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_stream_orientation_unlocked_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Android stream evidence without fixed landscape lock metadata")
  assert(stderr.include?("stream orientation orientationLockMode must be fixed-landscape"), "MVP evidence validator Android stream orientation lock failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_stream_orientation_missing_posture_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Android stream evidence without device posture")
  assert(stderr.include?("stream orientation device posture must be recorded"), "MVP evidence validator Android stream orientation posture failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_stream_rotation_direction_missing_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Android stream evidence without left/right rotation direction")
  assert(stderr.include?("stream rotationDirection must be left or right"), "MVP evidence validator Android stream rotation direction failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_stream_rotation_degree_invalid_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Android stream evidence with invalid output rotation degrees")
  assert(stderr.include?("stream output rotation degrees must be recorded as 0/90/180/270"), "MVP evidence validator Android stream rotation degree failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_stream_rotation_target_mismatch_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Android stream evidence whose requested target does not match output rotation")
  assert(stderr.include?("stream output rotation degrees must match the requested target"), "MVP evidence validator Android stream target mismatch failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_front_mismatch_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Android front-camera decode evidence tied to a different RTSP URL")
  assert(stderr.include?("front-camera decode RTSP URL must match the profile RTSP URL"), "MVP evidence validator Android front-camera URL mismatch failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_front_rotation_target_mismatch_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Android front-camera evidence whose requested target does not match output rotation")
  assert(stderr.include?("front-camera output rotation degrees must match the requested target"), "MVP evidence validator Android front-camera target mismatch failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_front_orientation_unverified_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Android front-camera evidence without manual orientation verification")
  assert(stderr.include?("front-camera orientation status must be passed"), "MVP evidence validator Android front-camera orientation failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_front_orientation_missing_notes_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Android front-camera evidence without orientation notes")
  assert(stderr.include?("front-camera orientation notes must be recorded"), "MVP evidence validator Android front-camera orientation-notes failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_missing_screenshot_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Android evidence without captured UI screenshots")
  assert(stderr.include?("Android Efficient streaming screenshot file must exist"), "MVP evidence validator Android screenshot failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_text_screenshot_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Android screenshot artifacts that are not image files")
  assert(stderr.include?("Android Efficient streaming screenshot file must be a PNG, JPEG, or BMP image"),
         "MVP evidence validator Android screenshot image-signature failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_missing_snapshot_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Android evidence without decoded frame snapshots")
  assert(stderr.include?("direct LAN decoded frame snapshot file must exist"), "MVP evidence validator Android decoded snapshot failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_text_snapshot_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Android decoded frame snapshots that are not images")
  assert(stderr.include?("direct LAN decoded frame snapshot file must be a PPM, PNG, JPEG, or BMP image"),
         "MVP evidence validator Android decoded snapshot image-signature failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_decode_errors_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Android decode evidence with errors")
  assert(stderr.include?("decode errors must be zero"), "MVP evidence validator Android decode-error failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_high_bitrate_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject Android decode evidence over the profile bandwidth ceiling")
  assert(stderr.include?("incoming Mbps must stay within the profile bandwidth ceiling"), "MVP evidence validator Android bandwidth ceiling failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", mismatched_manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject manual evidence tied to a different RTSP URL")
  assert(stderr.include?("RTSP URL must match runtime evidence"), "MVP evidence validator manual mismatch failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", inconsistent_manual_rtsp_path
  )
  assert(!status.success?, "MVP evidence validator must reject manual evidence with inconsistent RTSP URL fields")
  assert(stderr.include?("Windows manual app evidence recorded RTSP URL fields must all refer to the same endpoint"),
         "MVP evidence validator manual RTSP field consistency failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", mismatched_source_mode_manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject manual evidence with a sourceMode that differs from runtime evidence")
  assert(stderr.include?("sourceMode must match runtime evidence"), "MVP evidence validator manual sourceMode mismatch failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", mismatched_receiver_process_manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject manual evidence tied to a different receiver process")
  assert(stderr.include?("receiverProcessId must match runtime evidence"), "MVP evidence validator manual receiver process mismatch failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", missing_screenshot_manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject manual evidence without screenshot files")
  assert(stderr.include?("screenshotPath file must exist"), "MVP evidence validator missing screenshot failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", empty_screenshot_manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject manual evidence with empty screenshot files")
  assert(stderr.include?("screenshotPath file must be non-empty"), "MVP evidence validator empty screenshot failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", text_screenshot_manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject manual evidence whose screenshot artifact is not an image")
  assert(stderr.include?("screenshotPath file must be a PNG, JPEG, or BMP image"),
         "MVP evidence validator screenshot image-signature failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", reused_directshow_snapshot_manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject OBS screenshots reused from the DirectShow snapshot")
  assert(stderr.include?("OBS screenshotPath must be a separate app screenshot"),
         "MVP evidence validator reused DirectShow snapshot failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", copied_directshow_snapshot_manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject OBS screenshots copied from the DirectShow snapshot")
  assert(stderr.include?("OBS screenshotPath must not duplicate the DirectShow frame snapshot content"),
         "MVP evidence validator copied DirectShow snapshot content failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", duplicate_app_screenshot_manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject duplicated OBS/browser screenshot files")
  assert(stderr.include?("OBS and browser/camera app screenshots must be distinct files"),
         "MVP evidence validator duplicated app screenshot failure output changed")

  stdout, stderr, status = Open3.capture3(
    ruby,
    validator,
    "--android-matrix", android_path,
    "--windows-runtime", runtime_path,
    "--windows-manual", duplicate_app_screenshot_content_manual_path
  )
  assert(!status.success?, "MVP evidence validator must reject copied OBS/browser screenshot content")
  assert(stderr.include?("OBS and browser/camera app screenshots must have different image content"),
         "MVP evidence validator duplicated app screenshot content failure output changed")
end

workflow_text = read(".github/workflows/build.yml")
assert(workflow_text.include?("PHONECAM_REQUIRE_SOFTCAM=ON"), "Softcam package job must require Softcam at configure time")
assert(workflow_text.include?("ctest --test-dir build/windows-softcam-receiver -C Release --output-on-failure"),
       "Softcam-linked receiver job must run CTest before packaging")
assert(workflow_text.include?("Package-PhoneCamWindows.ps1"), "workflow must build the Windows package")
assert(workflow_text.include?("phonecam-windows-mvp-package"), "workflow must upload the Windows MVP package")
assert(workflow_text.include?("scripts\\validate_mvp_evidence.rb"), "workflow must check packaged final evidence validator")
assert(workflow_text.include?("scripts\\bundle_mvp_evidence.rb"), "workflow must check packaged evidence bundler")
assert(workflow_text.include?("scripts\\Prepare-PhoneCamSoftcam.ps1"), "workflow must check packaged Softcam prep script")
assert(workflow_text.include?("docs\\testing.md"), "workflow must check packaged testing runbook")
assert(workflow_text.include?("docs\\SOFTCAM_BRANDING.md"), "workflow must check packaged Softcam branding guide")
assert(workflow_text.include?("docs\\SOFTCAM-BUILD.txt"), "workflow must check packaged Softcam build metadata")
assert(workflow_text.include?("SOFTCAM-BUILD.txt does not record the PhoneCam virtual camera filter name") &&
       workflow_text.include?("SOFTCAM-BUILD.txt does not record the PhoneCam Softcam CLSID") &&
       workflow_text.include?("{1BF2F2F1-5C41-4C0B-B53B-B606627B60F3}"),
       "workflow must validate packaged Softcam build metadata contents before artifact upload")
assert(workflow_text.include?("docs\\verification-report.md"), "workflow must check packaged verification report")

puts "windows static contracts ok"
