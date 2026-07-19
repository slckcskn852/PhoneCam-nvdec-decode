#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "tmpdir"
require "time"

options = {
  output_dir: File.join(Dir.tmpdir, "phonecam-mvp-evidence-bundle-#{Time.now.utc.strftime("%Y%m%d-%H%M%S")}"),
  android_only: false
}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/bundle_mvp_evidence.rb --android-matrix PATH [--android-only | --windows-runtime PATH --windows-manual PATH] [--output-dir DIR] [--force] [--skip-validation]"
  parser.on("--android-matrix PATH", "Path to Android Wi-Fi profile matrix JSON evidence") do |value|
    options[:android_matrix] = value
  end
  parser.on("--android-only", "Bundle only physical Android matrix evidence for Windows handoff") do
    options[:android_only] = true
  end
  parser.on("--windows-runtime PATH", "Path to Windows runtime-evidence.json") do |value|
    options[:windows_runtime] = value
  end
  parser.on("--windows-manual PATH", "Path to completed manual-app-evidence-template.json") do |value|
    options[:windows_manual] = value
  end
  parser.on("--output-dir DIR", "Bundle output directory") do |value|
    options[:output_dir] = value
  end
  parser.on("--force", "Replace output directory if it already exists") do
    options[:force] = true
  end
  parser.on("--skip-validation", "Copy evidence without running the final MVP validator first or after bundling") do
    options[:skip_validation] = true
  end
end.parse!

def require_file(path, label)
  raise "#{label} path is required" if path.nil? || path.strip.empty?
  raise "#{label} file not found: #{path}" unless File.file?(path)

  File.expand_path(path)
end

def absolute_path?(path)
  path.start_with?("/") || path.start_with?("\\\\") || path.match?(/\A[A-Za-z]:[\\\/]/)
end

def normalize_path(path)
  File.expand_path(path).tr("\\", "/")
end

def under_path?(path, root)
  normalized_path = normalize_path(path)
  normalized_root = normalize_path(root)
  normalized_path == normalized_root || normalized_path.start_with?("#{normalized_root}/")
end

def relative_path(path, base)
  Pathname.new(path).relative_path_from(Pathname.new(base)).to_s
rescue ArgumentError
  path
end

def copy_tree(source_dir, dest_dir)
  FileUtils.mkdir_p(dest_dir)
  Dir.children(source_dir).each do |child|
    source_child = File.join(source_dir, child)
    next if under_path?(dest_dir, source_child)

    FileUtils.cp_r(source_child, File.join(dest_dir, child))
  end
end

def external_copy_path(path, dest_root, external_map)
  expanded = File.expand_path(path)
  return external_map[expanded] if external_map.key?(expanded)

  digest = Digest::SHA256.hexdigest(expanded)[0, 12]
  basename = File.basename(expanded)
  dest = File.join(dest_root, "external", "#{digest}-#{basename}")
  FileUtils.mkdir_p(File.dirname(dest))
  if File.directory?(expanded)
    FileUtils.cp_r(expanded, dest)
  else
    FileUtils.cp(expanded, dest)
  end
  external_map[expanded] = dest
end

def source_candidate_for(value, source_json_dir)
  return value if absolute_path?(value)

  File.expand_path(value, source_json_dir)
end

def rewrite_paths(value, source_root, dest_root, source_json_dir, dest_json_dir, external_map)
  case value
  when Hash
    value.each_with_object({}) do |(key, child), memo|
      memo[key] = rewrite_paths(child, source_root, dest_root, source_json_dir, dest_json_dir, external_map)
    end
  when Array
    value.map { |child| rewrite_paths(child, source_root, dest_root, source_json_dir, dest_json_dir, external_map) }
  when String
    return value if value.empty? || value.start_with?("rtsp://")

    candidate = source_candidate_for(value, source_json_dir)
    if under_path?(candidate, source_root)
      rel_from_root = relative_path(candidate, source_root)
      dest_candidate = File.join(dest_root, rel_from_root)
      return relative_path(dest_candidate, dest_json_dir)
    end

    if File.exist?(candidate)
      copied = external_copy_path(candidate, dest_root, external_map)
      return relative_path(copied, dest_json_dir)
    end

    value
  else
    value
  end
end

def rewrite_json_tree(source_root, dest_root)
  external_map = {}
  Dir.glob(File.join(source_root, "**", "*.json")).sort.each do |source_json|
    rel = relative_path(source_json, source_root)
    dest_json = File.join(dest_root, rel)
    next unless File.file?(dest_json)

    data = JSON.parse(File.read(source_json))
    rewritten = rewrite_paths(
      data,
      source_root,
      dest_root,
      File.dirname(source_json),
      File.dirname(dest_json),
      external_map
    )
    File.write(dest_json, JSON.pretty_generate(rewritten))
  rescue JSON::ParserError
    next
  end
end

def run_validator(android_matrix, windows_runtime, windows_manual, label, android_only: false, validator: File.join(File.expand_path("..", __dir__), "scripts", "validate_mvp_evidence.rb"))
  args = [
    RbConfig.ruby,
    validator,
    "--android-matrix", android_matrix
  ]
  if android_only
    args << "--android-only"
  else
    args += ["--windows-runtime", windows_runtime, "--windows-manual", windows_manual]
  end

  stdout, stderr, status = Open3.capture3(*args)
  return if status.success?

  output = [stdout, stderr].reject(&:empty?).join("\n")
  raise "#{label} failed validation; refusing to bundle incomplete MVP evidence.\n#{output}"
end

def relative_manifest_path(path, base)
  relative_path(path, base).tr("\\", "/")
end

def file_fingerprint(path)
  {
    "basename" => File.basename(path),
    "bytes" => File.size(path),
    "sha256" => Digest::SHA256.file(path).hexdigest
  }
end

android_matrix = require_file(options[:android_matrix], "Android matrix evidence")
windows_runtime = nil
windows_manual = nil
unless options[:android_only]
  windows_runtime = require_file(options[:windows_runtime], "Windows runtime evidence")
  windows_manual = require_file(options[:windows_manual], "Windows manual app evidence")
end

unless options[:skip_validation]
  run_validator(android_matrix, windows_runtime, windows_manual, "Source evidence", android_only: options[:android_only])
end

output_dir = File.expand_path(options[:output_dir])
if File.exist?(output_dir)
  raise "Output directory already exists: #{output_dir}. Pass --force to replace it." unless options[:force]

  FileUtils.rm_rf(output_dir)
end

FileUtils.mkdir_p(output_dir)

bundle_paths = {}

source_groups = [
  ["android", android_matrix, { android_matrix: android_matrix }]
]
unless options[:android_only]
  if File.dirname(windows_runtime) == File.dirname(windows_manual)
    source_groups << ["windows", windows_runtime, { windows_runtime: windows_runtime, windows_manual: windows_manual }]
  else
    source_groups << ["windows-runtime", windows_runtime, { windows_runtime: windows_runtime }]
    source_groups << ["windows-manual", windows_manual, { windows_manual: windows_manual }]
  end
end

source_groups.each do |name, json_path, group_paths|
  source_root = File.dirname(json_path)
  dest_root = File.join(output_dir, name)
  copy_tree(source_root, dest_root)
  rewrite_json_tree(source_root, dest_root)
  group_paths.each do |key, source_path|
    bundle_paths[key] = File.join(dest_root, File.basename(source_path))
  end
end

tools_dir = File.join(output_dir, "tools")
FileUtils.mkdir_p(tools_dir)
validator_bundle_path = File.join(tools_dir, "validate_mvp_evidence.rb")
FileUtils.cp(File.join(File.expand_path("..", __dir__), "scripts", "validate_mvp_evidence.rb"), validator_bundle_path)

bundle_relative_paths = bundle_paths.transform_values { |path| relative_manifest_path(path, output_dir) }
validator_relative_path = relative_manifest_path(validator_bundle_path, output_dir)
readme_relative_path = "README.txt"
validate_command_parts = [
  "ruby",
  validator_relative_path,
  "--android-matrix",
  bundle_relative_paths.fetch(:android_matrix)
]
if options[:android_only]
  validate_command_parts << "--android-only"
else
  validate_command_parts += [
    "--windows-runtime",
    bundle_relative_paths.fetch(:windows_runtime),
    "--windows-manual",
    bundle_relative_paths.fetch(:windows_manual)
  ]
end
validate_command = validate_command_parts.join(" ")
source_inputs = {
  "androidMatrix" => file_fingerprint(android_matrix)
}
unless options[:android_only]
  source_inputs["windowsRuntime"] = file_fingerprint(windows_runtime)
  source_inputs["windowsManual"] = file_fingerprint(windows_manual)
end

bundle_manifest_paths = {
  "androidMatrix" => bundle_relative_paths.fetch(:android_matrix)
}
unless options[:android_only]
  bundle_manifest_paths["windowsRuntime"] = bundle_relative_paths.fetch(:windows_runtime)
  bundle_manifest_paths["windowsManual"] = bundle_relative_paths.fetch(:windows_manual)
end

manifest = {
  "generatedAt" => Time.now.utc.iso8601,
  "sourceInputs" => source_inputs,
  "bundle" => bundle_manifest_paths,
  "tools" => {
    "validator" => validator_relative_path
  },
  "readme" => readme_relative_path,
  "validation" => {
    "skipped" => !!options[:skip_validation],
    "androidOnly" => !!options[:android_only]
  },
  "validateCommand" => validate_command
}

manifest_path = File.join(output_dir, "bundle-manifest.json")
File.write(manifest_path, JSON.pretty_generate(manifest))

bundle_title = options[:android_only] ? "PhoneCam Android Matrix Evidence Bundle" : "PhoneCam MVP Evidence Bundle"
bundle_summary = if options[:android_only]
                   "This handoff bundle proves only the physical Android Wi-Fi/profile/orientation matrix. It is intended to be copied to the Windows host before DirectShow/OBS evidence is collected."
                 else
                   "This bundle proves the Android matrix, Windows DirectShow runtime capture, and OBS/browser manual evidence only when the validation command below passes from the bundle root."
                 end
bundled_evidence_lines = [
  "- Android matrix: #{bundle_relative_paths.fetch(:android_matrix)}"
]
fingerprint_lines = [
  "- Android matrix: #{source_inputs.fetch("androidMatrix").fetch("basename")} (#{source_inputs.fetch("androidMatrix").fetch("bytes")} bytes, sha256 #{source_inputs.fetch("androidMatrix").fetch("sha256")})"
]
unless options[:android_only]
  bundled_evidence_lines += [
    "- Windows runtime: #{bundle_relative_paths.fetch(:windows_runtime)}",
    "- Windows manual app evidence: #{bundle_relative_paths.fetch(:windows_manual)}"
  ]
  fingerprint_lines += [
    "- Windows runtime: #{source_inputs.fetch("windowsRuntime").fetch("basename")} (#{source_inputs.fetch("windowsRuntime").fetch("bytes")} bytes, sha256 #{source_inputs.fetch("windowsRuntime").fetch("sha256")})",
    "- Windows manual app evidence: #{source_inputs.fetch("windowsManual").fetch("basename")} (#{source_inputs.fetch("windowsManual").fetch("bytes")} bytes, sha256 #{source_inputs.fetch("windowsManual").fetch("sha256")})"
  ]
end

readme_lines = [
  bundle_title,
  "=" * bundle_title.length,
  "",
  "Run this command from this folder to re-validate the bundled evidence:",
  "",
  "  #{validate_command}",
  "",
  "Bundled evidence paths:",
  *bundled_evidence_lines,
  "- Validator: #{validator_relative_path}",
  "- Manifest: bundle-manifest.json",
  "",
  "Source input fingerprints:",
  *fingerprint_lines,
  "",
  "Validation skipped when created: #{options[:skip_validation] ? "yes" : "no"}",
  "Android-only bundle: #{options[:android_only] ? "yes" : "no"}",
  "",
  bundle_summary
]
unless options[:android_only]
  readme_lines << "A final MVP archive should be created without --skip-validation."
else
  readme_lines << "Pass the bundled android/matrix-evidence.json path to Collect-PhoneCamWindowsEvidence.ps1 on Windows; it should remain valid after copying because JSON artifact paths were rewritten relative to this bundle."
end
File.write(File.join(output_dir, readme_relative_path), "#{readme_lines.join("\n")}\n")

unless options[:skip_validation]
  run_validator(
    bundle_paths.fetch(:android_matrix),
    options[:android_only] ? nil : bundle_paths.fetch(:windows_runtime),
    options[:android_only] ? nil : bundle_paths.fetch(:windows_manual),
    "Bundled evidence",
    android_only: options[:android_only],
    validator: validator_bundle_path
  )
end

puts "#{options[:android_only] ? "Android matrix evidence bundle" : "MVP evidence bundle"}: #{output_dir}"
puts "Manifest: #{manifest_path}"
puts "README: #{File.join(output_dir, readme_relative_path)}"
puts "Validate bundled evidence:"
puts manifest.fetch("validateCommand")
