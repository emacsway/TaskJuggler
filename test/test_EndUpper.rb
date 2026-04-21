#!/usr/bin/env ruby -w
# frozen_string_literal: true
# encoding: UTF-8
#
# = test_EndUpper.rb -- The TaskJuggler III Project Management Software
#
# End-to-end integration tests for the `endupper` reportable attribute
# and its column options `sigma` / `percentile`.
#

$:.unshift File.join(File.dirname(__FILE__), '..', 'lib') if __FILE__ == $0
$:.unshift File.dirname(__FILE__)

require 'test/unit'
require 'tmpdir'
require 'taskjuggler/TaskJuggler'
require 'taskjuggler/Query'

class TestEndUpper < Test::Unit::TestCase

  def setup
    ENV['TZ'] = 'UTC'
    @mh = TaskJuggler::MessageHandlerInstance.instance
    @mh.reset
    @mh.outputLevel = :none
    @mh.trapSetup = true
  end

  def parse_and_schedule(tjp_text)
    tmpfile = File.join(Dir.tmpdir, "test_endupper_#{$$}.tjp")
    File.write(tmpfile, tjp_text)
    tj = TaskJuggler.new
    assert(tj.parse([tmpfile]), "Parse failed: #{@mh.messages.map(&:to_s).join("\n")}")
    assert(tj.schedule, "Schedule failed: #{@mh.messages.map(&:to_s).join("\n")}")
    File.delete(tmpfile) rescue nil
    tj
  end

  # Build a Query with a fabricated TableColumnDefinition carrying a given
  # sigmaFactor. Used to exercise query_endupper without running the full
  # table-report pipeline.
  def endupper_query(task, sigma: nil, percentile: nil, scenario_idx: 0)
    sigma_factor =
      if sigma && percentile
        raise ArgumentError, 'specify one of sigma/percentile'
      elsif sigma
        sigma.to_f
      elsif percentile
        require 'taskjuggler/NormalInverse'
        TaskJuggler::NormalInverse.ppf(percentile)
      else
        nil  # default 3.0 applied inside query_endupper
      end

    col = TaskJuggler::TableColumnDefinition.new('endupper', 'title')
    col.sigmaFactor = sigma_factor

    q = TaskJuggler::Query.new(
      'project'     => task.project,
      'property'    => task,
      'scenarioIdx' => scenario_idx,
      'attributeId' => 'endupper',
      'columnDef'   => col,
      'timeFormat'  => '%Y-%m-%d-%H:%M'
    )
    q.process
    q
  end

  def ts(project, task_id, scenario_idx = 0)
    project.task(task_id).data[scenario_idx]
  end

  # ─── Basic behaviour ─────────────────────────────────────────

  def test_endupper_equals_end_for_deterministic_task
    # No stdev → σ = 0 → endupper == end regardless of k.
    tj = parse_and_schedule(<<~TJP)
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" now 2024-01-01 }
      resource r "R"
      task a "A" {
        start 2024-01-01
        effort 1d
        allocate r
      }
    TJP

    task_a = tj.project.task('a')
    sc = task_a.data[0]
    q = endupper_query(task_a, sigma: 3)
    assert(q.ok, q.errorMessage)
    assert_equal(sc.instance_variable_get(:@end), q.to_sort,
                 "endupper should equal end when sigma = 0")
  end

  def test_endupper_advances_end_by_k_sigma_working_slots
    # Task with σ_effort = 1d on single resource. σ_dur in slots = σ_effort
    # × duration/effort (rate=1 → equal). endupper with sigma 1 should
    # advance end by exactly σ_end slots via the scoreboard.
    tj = parse_and_schedule(<<~TJP)
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" now 2024-01-01 }
      resource r "R"
      task a "A" {
        start 2024-01-01
        effort 5d
        stdev 1d
        allocate r
      }
    TJP

    task_a = tj.project.task('a')
    sc = task_a.data[0]
    sigma_slots = sc.endStdevSlots
    assert(sigma_slots > 0, "σ_end(A) should be non-zero")

    expected_offset = (1.0 * sigma_slots).round
    expected_idx = tj.project.dateToIdx(sc.instance_variable_get(:@end)) + expected_offset
    expected_date = tj.project.idxToDate(expected_idx)

    q = endupper_query(task_a, sigma: 1)
    assert(q.ok, q.errorMessage)
    assert_equal(expected_date, q.to_sort,
                 "endupper{sigma 1} should shift end by round(sigma) slots on the scoreboard")
  end

  def test_endupper_monotone_in_sigma_factor
    # For the same task, a larger sigma factor must produce a later date.
    tj = parse_and_schedule(<<~TJP)
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" now 2024-01-01 }
      resource r "R"
      task a "A" {
        start 2024-01-01
        effort 10d
        stdev 2d
        allocate r
      }
    TJP

    task_a = tj.project.task('a')
    q1 = endupper_query(task_a, sigma: 1).to_sort
    q2 = endupper_query(task_a, sigma: 2).to_sort
    q3 = endupper_query(task_a, sigma: 3).to_sort
    assert(q1 < q2, "σ=2 should be later than σ=1")
    assert(q2 < q3, "σ=3 should be later than σ=2")
  end

  def test_default_k_is_three
    # Omitted sigma/percentile ⇒ column gets sigmaFactor=nil ⇒ query uses 3.0.
    tj = parse_and_schedule(<<~TJP)
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" now 2024-01-01 }
      resource r "R"
      task a "A" {
        start 2024-01-01
        effort 10d
        stdev 2d
        allocate r
      }
    TJP

    task_a = tj.project.task('a')
    q_default = endupper_query(task_a).to_sort
    q_three   = endupper_query(task_a, sigma: 3).to_sort
    assert_equal(q_three, q_default,
                 "Default k should be 3 when no sigma/percentile is given")
  end

  def test_percentile_095_matches_sigma_1_6449
    # percentile 0.95 = Φ⁻¹(0.95) ≈ 1.6449. Both should yield the same date
    # (to within slot rounding).
    tj = parse_and_schedule(<<~TJP)
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" now 2024-01-01 }
      resource r "R"
      task a "A" {
        start 2024-01-01
        effort 20d
        stdev 3d
        allocate r
      }
    TJP

    task_a = tj.project.task('a')
    q_pct   = endupper_query(task_a, percentile: 0.95).to_sort
    q_sigma = endupper_query(task_a, sigma: 1.6448536269514722).to_sort
    assert_equal(q_sigma, q_pct,
                 "percentile 0.95 should match sigma 1.6449")
  end

  def test_percentile_05_equals_mean_end
    # percentile 0.5 → k = 0 → endupper = end.
    tj = parse_and_schedule(<<~TJP)
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" now 2024-01-01 }
      resource r "R"
      task a "A" {
        start 2024-01-01
        effort 5d
        stdev 1d
        allocate r
      }
    TJP

    task_a = tj.project.task('a')
    sc = task_a.data[0]
    q = endupper_query(task_a, percentile: 0.5)
    assert_equal(sc.instance_variable_get(:@end), q.to_sort,
                 "percentile 0.5 ⇒ k = 0 ⇒ endupper == end")
  end

  # ─── Grammar-level validation ────────────────────────────────

  def assert_parse_error(tjp_text, expected_id)
    tmpfile = File.join(Dir.tmpdir, "test_endupper_err_#{$$}_#{rand(1000)}.tjp")
    File.write(tmpfile, tjp_text)
    tj = TaskJuggler.new
    begin
      parsed = tj.parse([tmpfile])
    rescue TaskJuggler::TjRuntimeError
      parsed = false
    end
    errors = @mh.messages.select { |m| m.type == :error }
    assert(!parsed || !errors.empty?,
           "Expected parse error #{expected_id}, got successful parse")
    if expected_id
      assert(errors.any? { |m| m.id == expected_id },
             "Expected error id '#{expected_id}', got: " +
             errors.map(&:id).join(', '))
    end
  ensure
    File.delete(tmpfile) rescue nil
  end

  def test_both_sigma_and_percentile_is_a_syntax_error
    assert_parse_error(<<~TJP, 'sigma_percentile_conflict')
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" now 2024-01-01 }
      resource r "R"
      task a "A" {
        start 2024-01-01
        effort 5d
        stdev 1d
        allocate r
      }
      taskreport "out" {
        formats html
        columns name, endupper {
          sigma 1
          percentile 0.84
        }
      }
    TJP
  end

  def test_percentile_out_of_range_is_a_syntax_error
    assert_parse_error(<<~TJP, 'bad_percentile')
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" now 2024-01-01 }
      resource r "R"
      task a "A" {
        start 2024-01-01
        effort 5d
        stdev 1d
        allocate r
      }
      taskreport "out" {
        formats html
        columns name, endupper { percentile 1.5 }
      }
    TJP
  end

  # ─── End-to-end taskreport ───────────────────────────────────

  def test_endupper_in_rendered_taskreport
    # Parse a project with a taskreport that uses endupper, render it,
    # and verify that the output references the expected attribute (not
    # an error).
    tjp = <<~TJP
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" now 2024-01-01 }
      resource r "R"
      task a "A" {
        start 2024-01-01
        effort 5d
        stdev 1d
        allocate r
      }
      taskreport "out" {
        formats csv
        columns name, start, end,
                endupper { sigma 1 title "+1sigma" },
                endupper { sigma 3 title "+3sigma" }
      }
    TJP
    tmpfile = File.join(Dir.tmpdir, "test_endupper_e2e_#{$$}.tjp")
    File.write(tmpfile, tjp)
    tj = TaskJuggler.new
    assert(tj.parse([tmpfile]), "Parse failed: #{@mh.messages.map(&:to_s).join("\n")}")
    assert(tj.schedule, "Schedule failed: #{@mh.messages.map(&:to_s).join("\n")}")
    # Use tmpdir for output so we don't pollute the repo.
    Dir.mktmpdir do |outdir|
      assert(tj.generateReports(outdir),
             "Report generation failed: #{@mh.messages.map(&:to_s).join("\n")}")
      csv_files = Dir["#{outdir}/*.csv"]
      assert(!csv_files.empty?, "No CSV output produced")
      content = File.read(csv_files.first)
      assert(content.include?('+1sigma'), "Report should include '+1sigma' column title")
      assert(content.include?('+3sigma'), "Report should include '+3sigma' column title")
    end
    File.delete(tmpfile) rescue nil
  end

  # ─── Gantt whisker rendering ────────────────────────────────

  def test_gantt_chart_sigma_option_renders_whiskers
    # A `chart` column with `sigma N` must render an additional
    # semi-transparent tail (`.taskbarsigma` / `.milestonesigma` HTML
    # element) past each task's scheduled end. Without the option, no
    # such element is emitted.
    require 'taskjuggler/Tj3Config'
    AppConfig.appName = 'tj3'

    tjp = <<~TJP
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" now 2024-01-01 }
      resource r "R"
      task a "A" {
        start 2024-01-01
        effort 10d
        stdev 2d
        allocate r
      }
      task m "Release" {
        depends a
        milestone
      }
      taskreport "with_whiskers" {
        formats html
        selfcontained yes
        columns name, chart { scale day width 400 sigma 3 }
      }
      taskreport "no_whiskers" {
        formats html
        selfcontained yes
        columns name, chart { scale day width 400 }
      }
    TJP
    tmpfile = File.join(Dir.tmpdir, "test_gantt_whisker_#{$$}.tjp")
    File.write(tmpfile, tjp)
    tj = TaskJuggler.new
    assert(tj.parse([tmpfile]), "Parse failed: #{@mh.messages.map(&:to_s).join("\n")}")
    assert(tj.schedule, "Schedule failed")

    Dir.mktmpdir do |outdir|
      assert(tj.generateReports(outdir), "Report generation failed")
      with = File.read(File.join(outdir, 'with_whiskers.html'))
      without = File.read(File.join(outdir, 'no_whiskers.html'))

      # With whiskers: taskbar and milestone whisker elements are
      # present, each with non-zero width.
      assert(with.scan(/class="taskbarsigma"[^>]*width:(\d+)px/).any? { |w| w.first.to_i > 0 },
             "sigma column option should emit a non-empty .taskbarsigma element")
      assert(with.include?('class="milestonesigma"'),
             "sigma column option should emit a .milestonesigma element for the milestone")

      # Without the option: no whisker div elements at all (CSS may
      # still declare the class, so we check for element usage
      # explicitly).
      assert(!without.match?(/<div[^>]*class="taskbarsigma"/),
             "chart column without sigma option must not emit .taskbarsigma elements")
      assert(!without.match?(/<div[^>]*class="milestonesigma"/),
             "chart column without sigma option must not emit .milestonesigma elements")
    end
    File.delete(tmpfile) rescue nil
  end

  def test_gantt_whisker_width_scales_with_sigma_factor
    # The same task rendered with sigma 1 and sigma 3 must produce
    # whiskers whose widths are roughly in a 1:3 ratio (allowing for
    # slot rounding at coarse chart scales).
    require 'taskjuggler/Tj3Config'
    AppConfig.appName = 'tj3'

    tjp = <<~TJP
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" now 2024-01-01 }
      resource r "R"
      task a "A" {
        start 2024-01-01
        effort 20d
        stdev 3d
        allocate r
      }
      taskreport "r1" {
        formats html
        selfcontained yes
        columns chart { scale day width 600 sigma 1 }
      }
      taskreport "r3" {
        formats html
        selfcontained yes
        columns chart { scale day width 600 sigma 3 }
      }
    TJP
    tmpfile = File.join(Dir.tmpdir, "test_gantt_scale_#{$$}.tjp")
    File.write(tmpfile, tjp)
    tj = TaskJuggler.new
    tj.parse([tmpfile]); tj.schedule
    Dir.mktmpdir do |outdir|
      tj.generateReports(outdir)
      w1 = File.read(File.join(outdir, 'r1.html')).
             match(/class="taskbarsigma"[^>]*width:(\d+)px/)[1].to_i
      w3 = File.read(File.join(outdir, 'r3.html')).
             match(/class="taskbarsigma"[^>]*width:(\d+)px/)[1].to_i
      assert(w3 > w1, "sigma 3 whisker (#{w3}px) should be wider than sigma 1 (#{w1}px)")
      # Expect ratio near 3; allow ±20% for slot-to-pixel quantisation
      # at 'day' scale.
      ratio = w3.to_f / w1
      assert(ratio > 2.4 && ratio < 3.6,
             "w3/w1 should be near 3, got #{ratio}")
    end
    File.delete(tmpfile) rescue nil
  end

end
