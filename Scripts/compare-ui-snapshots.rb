#!/usr/bin/env ruby
# frozen_string_literal: true

# A deliberately small visual contract for Maestro screenshots. It ignores
# system chrome and tiny rendering noise, while still making a changed screen
# obvious through a highlighted PNG written to .maestro/diffs.

require "chunky_png"
require "fileutils"
require "optparse"
require "tmpdir"

module UISnapshotComparator
  CHANNEL_TOLERANCE = 8
  MAX_CHANGED_RATIO = 0.001
  TOP_SYSTEM_BAR_RATIO = 0.07
  BOTTOM_SYSTEM_BAR_RATIO = 0.04
  MILESTONES = %w[
    10-browse
    20-testival-detail
    30-testival-schedule
    32-testival-live-status
    40-collaborative-set-detail
    50-sunday-schedule
    60-artist-two-detail
    70-canopy-detail
    80-safety-map
  ].freeze
  PLATFORMS = %w[ios android].freeze

  Result = Struct.new(
    :matches,
    :changed_pixels,
    :compared_pixels,
    :reason,
    keyword_init: true
  )

  module_function

  def capture_paths(root, platforms: PLATFORMS, milestones: MILESTONES)
    platforms.flat_map do |platform|
      milestones.map do |milestone|
        [platform, milestone, File.join(root, platform, "#{milestone}.png")]
      end
    end
  end

  def materially_different?(expected, actual)
    channels = [
      ChunkyPNG::Color.r(expected) - ChunkyPNG::Color.r(actual),
      ChunkyPNG::Color.g(expected) - ChunkyPNG::Color.g(actual),
      ChunkyPNG::Color.b(expected) - ChunkyPNG::Color.b(actual),
      ChunkyPNG::Color.a(expected) - ChunkyPNG::Color.a(actual)
    ]
    channels.any? { |difference| difference.abs > CHANNEL_TOLERANCE }
  end

  def compare(expected_path:, actual_path:, diff_path: nil)
    expected = ChunkyPNG::Image.from_file(expected_path)
    actual = ChunkyPNG::Image.from_file(actual_path)

    if expected.width != actual.width || expected.height != actual.height
      return Result.new(
        matches: false,
        reason: "dimension mismatch: expected #{expected.width}x#{expected.height}, " \
          "got #{actual.width}x#{actual.height}"
      )
    end

    top_rows = (expected.height * TOP_SYSTEM_BAR_RATIO).ceil
    bottom_rows = (expected.height * BOTTOM_SYSTEM_BAR_RATIO).ceil
    comparison_end = expected.height - bottom_rows
    compared_pixels = expected.width * [comparison_end - top_rows, 0].max
    changed_pixels = 0
    diff = diff_path && ChunkyPNG::Image.new(expected.width, expected.height)

    expected.height.times do |y|
      expected.width.times do |x|
        ignored = y < top_rows || y >= comparison_end
        changed = !ignored && materially_different?(expected[x, y], actual[x, y])
        changed_pixels += 1 if changed

        next unless diff

        if changed
          diff[x, y] = ChunkyPNG::Color.rgba(255, 0, 255, 255)
        else
          color = actual[x, y]
          diff[x, y] = ChunkyPNG::Color.rgba(
            ChunkyPNG::Color.r(color),
            ChunkyPNG::Color.g(color),
            ChunkyPNG::Color.b(color),
            ignored ? 45 : 120
          )
        end
      end
    end

    ratio = compared_pixels.zero? ? 1.0 : changed_pixels.fdiv(compared_pixels)
    matches = ratio <= MAX_CHANGED_RATIO
    if matches
      FileUtils.rm_f(diff_path) if diff_path
    elsif diff_path
      FileUtils.mkdir_p(File.dirname(diff_path))
      diff.save(diff_path)
    end

    Result.new(
      matches: matches,
      changed_pixels: changed_pixels,
      compared_pixels: compared_pixels,
      reason: format(
        "%d of %d compared pixels changed (%.4f%%; limit %.4f%%)",
        changed_pixels,
        compared_pixels,
        ratio * 100,
        MAX_CHANGED_RATIO * 100
      )
    )
  end

  def compare_suite(actual_root:, baseline_root:, diff_root:, platforms: PLATFORMS,
                    milestones: MILESTONES)
    failures = []
    capture_paths(actual_root, platforms: platforms, milestones: milestones).each do |platform, milestone, actual_path|
      baseline_path = File.join(baseline_root, platform, "#{milestone}.png")
      diff_path = File.join(diff_root, platform, "#{milestone}.png")

      unless File.file?(baseline_path)
        failures << "#{platform}/#{milestone}: missing baseline #{baseline_path}"
        next
      end
      unless File.file?(actual_path)
        failures << "#{platform}/#{milestone}: missing actual screenshot #{actual_path}"
        next
      end

      result = compare(
        expected_path: baseline_path,
        actual_path: actual_path,
        diff_path: diff_path
      )
      if result.matches
        puts "match #{platform}/#{milestone}: #{result.reason}"
      else
        failures << "#{platform}/#{milestone}: #{result.reason}; diff #{diff_path}"
      end
    end

    raise failures.join("\n") unless failures.empty?
  end

  def record_suite(actual_root:, baseline_root:, platforms: PLATFORMS,
                   milestones: MILESTONES)
    missing = capture_paths(actual_root, platforms: platforms, milestones: milestones).filter_map do |platform, milestone, actual_path|
      "#{platform}/#{milestone}: #{actual_path}" unless File.file?(actual_path)
    end
    raise "missing actual screenshots:\n#{missing.join("\n")}" unless missing.empty?

    capture_paths(actual_root, platforms: platforms, milestones: milestones).each do |platform, milestone, actual_path|
      baseline_path = File.join(baseline_root, platform, "#{milestone}.png")
      FileUtils.mkdir_p(File.dirname(baseline_path))
      FileUtils.cp(actual_path, baseline_path)
      puts "recorded #{platform}/#{milestone}"
    end
  end

  def solid_image(width: 100, height: 100, color: ChunkyPNG::Color.rgb(100, 100, 100))
    ChunkyPNG::Image.new(width, height, color)
  end

  def assert_self_test(condition, message)
    raise "self-test failed: #{message}" unless condition
  end

  def run_self_tests
    Dir.mktmpdir("ome-ui-snapshot-tests") do |directory|
      expected_path = File.join(directory, "expected.png")
      actual_path = File.join(directory, "actual.png")
      diff_path = File.join(directory, "diff.png")
      solid_image.save(expected_path)

      solid_image.save(actual_path)
      assert_self_test(
        compare(expected_path: expected_path, actual_path: actual_path).matches,
        "identical images should match"
      )

      tolerated = solid_image
      tolerated[20, 50] = ChunkyPNG::Color.rgb(108, 108, 108)
      tolerated.save(actual_path)
      assert_self_test(
        compare(expected_path: expected_path, actual_path: actual_path).matches,
        "an eight-point channel difference should be tolerated"
      )

      changed = solid_image
      10.times { |x| changed[x, 50] = ChunkyPNG::Color.rgb(255, 255, 255) }
      changed.save(actual_path)
      threshold_result = compare(
        expected_path: expected_path,
        actual_path: actual_path,
        diff_path: diff_path
      )
      assert_self_test(!threshold_result.matches, "more than 0.1% changed pixels should fail")
      assert_self_test(File.file?(diff_path), "a threshold failure should produce a diff")

      solid_image(width: 99).save(actual_path)
      dimension_result = compare(expected_path: expected_path, actual_path: actual_path)
      assert_self_test(!dimension_result.matches, "different dimensions should fail")
      assert_self_test(
        dimension_result.reason.start_with?("dimension mismatch"),
        "dimension failure should explain the mismatch"
      )

      ignored_bars = solid_image
      ignored_bars[10, 0] = ChunkyPNG::Color.rgb(255, 255, 255)
      ignored_bars[10, 99] = ChunkyPNG::Color.rgb(255, 255, 255)
      ignored_bars.save(actual_path)
      assert_self_test(
        compare(expected_path: expected_path, actual_path: actual_path).matches,
        "top and bottom system bars should be ignored"
      )
    end

    puts "UI snapshot comparator self-tests passed"
  end
end

command = ARGV.shift
options = {
  actual_root: ".maestro/screenshots",
  baseline_root: ".maestro/baselines",
  diff_root: ".maestro/diffs",
  platforms: UISnapshotComparator::PLATFORMS,
  milestones: UISnapshotComparator::MILESTONES
}

OptionParser.new do |parser|
  parser.banner = "Usage: compare-ui-snapshots.rb compare|record|self-test [options]"
  parser.on("--actual-root PATH") { |path| options[:actual_root] = path }
  parser.on("--baseline-root PATH") { |path| options[:baseline_root] = path }
  parser.on("--diff-root PATH") { |path| options[:diff_root] = path }
  parser.on("--platform PLATFORM") do |platform|
    raise OptionParser::InvalidArgument, platform unless UISnapshotComparator::PLATFORMS.include?(platform)

    options[:platforms] = [platform]
  end
  parser.on("--milestone MILESTONE") { |milestone| options[:milestones] = [milestone] }
end.parse!

case command
when "compare"
  UISnapshotComparator.compare_suite(**options)
when "record"
  UISnapshotComparator.record_suite(
    actual_root: options[:actual_root],
    baseline_root: options[:baseline_root],
    platforms: options[:platforms],
    milestones: options[:milestones]
  )
when "self-test"
  UISnapshotComparator.run_self_tests
else
  warn "expected compare, record, or self-test"
  exit 64
end
