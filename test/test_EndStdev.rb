#!/usr/bin/env ruby -w
# frozen_string_literal: true
# encoding: UTF-8
#
# = test_EndStdev.rb -- The TaskJuggler III Project Management Software
#
# Integration tests for TaskScenario#endStdevSlots, the PERT method-of-moments
# propagation of the end-date standard deviation through a task graph.
#
# These tests exercise the dependency-only algorithm (resource-induced
# predecessors are covered in a separate integration test once the
# ResourceScenario integration is wired up).
#

$:.unshift File.join(File.dirname(__FILE__), '..', 'lib') if __FILE__ == $0
$:.unshift File.dirname(__FILE__)

require 'test/unit'
require 'tmpdir'
require 'taskjuggler/TaskJuggler'

class TestEndStdev < Test::Unit::TestCase

  TOL = 1e-6  # tolerance in slots; floating-point noise only

  def setup
    ENV['TZ'] = 'UTC'
    @mh = TaskJuggler::MessageHandlerInstance.instance
    @mh.reset
    @mh.outputLevel = :none
    @mh.trapSetup = true
  end

  def parse_and_schedule(tjp_text)
    tmpfile = File.join(Dir.tmpdir, "test_endstdev_#{$$}.tjp")
    File.write(tmpfile, tjp_text)
    tj = TaskJuggler.new
    assert(tj.parse([tmpfile]), "Parse failed: #{@mh.messages.map(&:to_s).join("\n")}")
    assert(tj.schedule, "Schedule failed: #{@mh.messages.map(&:to_s).join("\n")}")
    File.delete(tmpfile) rescue nil
    tj
  end

  def ts(project, task_id, scenario_idx = 0)
    project.task(task_id).data[scenario_idx]
  end

  # workingDuration values like "0.1d" are parsed to slot counts via
  #   slots = round(value * unit_seconds / scheduleGranularity)
  # and stored as integers. Tests derive expected σ values from the actually
  # stored σ_effort slots rather than from the input text, which sidesteps
  # rounding artefacts at the timing resolution.
  def sigma_effort_slots(task_scenario)
    task_scenario.instance_variable_get(:@stdev).to_f
  end

  def duration_slots(task_scenario)
    project = task_scenario.instance_variable_get(:@project)
    s = task_scenario.instance_variable_get(:@start)
    e = task_scenario.instance_variable_get(:@end)
    project.dateToIdx(e) - project.dateToIdx(s)
  end

  def effort_slots(task_scenario)
    eff = task_scenario.instance_variable_get(:@effort)
    eff.respond_to?(:to_f) ? eff.to_f : eff.to_f
  end

  def expected_leaf_duration_sigma(ts)
    sigma_effort_slots(ts) * duration_slots(ts) / effort_slots(ts)
  end

  # ─── Leaf-task σ_duration ────────────────────────────────────

  def test_leaf_stdev_scales_with_duration_over_effort
    # A leaf task with effort, stdev, one resource at full allocation.
    # σ_duration = σ_effort × duration/effort; with rate=1, that's σ_effort.
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

    a = ts(tj.project, 'a')
    assert_in_delta(expected_leaf_duration_sigma(a), a.endStdevSlots, TOL,
                    "σ_end(A) should equal σ_effort × duration/effort")
  end

  def test_leaf_no_stdev_gives_zero
    tj = parse_and_schedule(<<~TJP)
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" now 2024-01-01 }
      resource r "R"
      task a "A" {
        start 2024-01-01
        effort 1d
        allocate r
      }
    TJP

    a = ts(tj.project, 'a')
    assert_in_delta(0.0, a.endStdevSlots, TOL)
  end

  def test_milestone_has_zero_sigma
    tj = parse_and_schedule(<<~TJP)
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" now 2024-01-01 }
      task m "M" {
        start 2024-02-01
        milestone
      }
    TJP

    m = ts(tj.project, 'm')
    assert_in_delta(0.0, m.endStdevSlots, TOL)
  end

  # ─── Chain propagation ───────────────────────────────────────

  def test_chain_accumulates_variance_as_rss
    # A→B chain. σ_end(A) = σ_dur(A); σ_end(B) = √(σ_end(A)² + σ_dur(B)²).
    tj = parse_and_schedule(<<~TJP)
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" now 2024-01-01 }
      resource r1 "R1"
      resource r2 "R2"
      task a "A" {
        start 2024-01-01
        effort 5d
        stdev 1d
        allocate r1
      }
      task b "B" {
        effort 5d
        stdev 1d
        allocate r2
        depends a
      }
    TJP

    a = ts(tj.project, 'a')
    b = ts(tj.project, 'b')

    sigma_a = expected_leaf_duration_sigma(a)
    assert_in_delta(sigma_a, a.endStdevSlots, TOL)

    sigma_dur_b = expected_leaf_duration_sigma(b)
    expected_b  = Math.sqrt(sigma_a**2 + sigma_dur_b**2)
    assert_in_delta(expected_b, b.endStdevSlots, TOL,
                    "σ_end(B) should be RSS of σ_end(A) and σ_dur(B)")
  end

  # ─── Diamond / parallel predecessors ─────────────────────────

  def test_diamond_picks_sigma_of_critical_predecessor_only
    # Three parallel leaves A/B/C on separate resources with different
    # efforts (so their end dates differ). D depends on all three. D's
    # critical predecessor is the one that ends last (C); σ contributions
    # from A and B must be ignored. This is the core PERT assumption
    # being validated — ignoring it would OVERestimate σ_end(D) by folding
    # in all predecessors' variance.
    tj = parse_and_schedule(<<~TJP)
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" now 2024-01-01 }
      resource ra "RA"
      resource rb "RB"
      resource rc "RC"
      resource rd "RD"
      task a "A" {
        start 2024-01-01
        effort 3d
        stdev 1d
        allocate ra
      }
      task b "B" {
        start 2024-01-01
        effort 5d
        stdev 1d
        allocate rb
      }
      task c "C" {
        start 2024-01-01
        effort 10d
        stdev 1d
        allocate rc
      }
      task d "D" {
        effort 5d
        stdev 1d
        allocate rd
        depends a, b, c
      }
    TJP

    p = tj.project
    a = ts(p, 'a'); b = ts(p, 'b'); c = ts(p, 'c'); d = ts(p, 'd')

    sigma_c = expected_leaf_duration_sigma(c)
    sigma_dur_d = expected_leaf_duration_sigma(d)
    expected_d = Math.sqrt(sigma_c**2 + sigma_dur_d**2)
    assert_in_delta(expected_d, d.endStdevSlots, TOL,
                    "σ_end(D) must use only critical predecessor C, not RSS of A/B/C")

    # A and B do not contribute: an over-counting implementation that
    # folded all predecessors would give √(σ_a² + σ_b² + σ_c² + σ_dur_d²),
    # strictly larger than the correct answer.
    sigma_a = expected_leaf_duration_sigma(a)
    sigma_b = expected_leaf_duration_sigma(b)
    over_counted = Math.sqrt(sigma_a**2 + sigma_b**2 + sigma_c**2 + sigma_dur_d**2)
    assert(d.endStdevSlots < over_counted,
           "σ_end(D) must be strictly less than the over-counted RSS of all predecessors")
  end

  # ─── Container aggregation ───────────────────────────────────

  def test_container_inherits_sigma_of_critical_child
    # Container with three leaf children of different durations. The
    # container's end date equals the end of the longest child; its σ
    # must equal that child's σ (critical-child rule).
    tj = parse_and_schedule(<<~TJP)
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" now 2024-01-01 }
      resource r1 "R1"
      resource r2 "R2"
      resource r3 "R3"
      task bucket "Bucket" {
        task short "Short" {
          start 2024-01-01
          effort 0.5d
          stdev 0.1d
          allocate r1
        }
        task medium "Medium" {
          start 2024-01-01
          effort 1d
          stdev 0.1d
          allocate r2
        }
        task long "Long" {
          start 2024-01-01
          effort 2d
          stdev 0.1d
          allocate r3
        }
      }
    TJP

    p = tj.project
    bucket = ts(p, 'bucket')
    long_task = ts(p, 'bucket.long')
    assert_in_delta(long_task.endStdevSlots, bucket.endStdevSlots, TOL,
                    "container σ_end should equal σ_end of the critical child")
  end

  # ─── Resource-induced predecessors ──────────────────────────

  def test_resource_contention_propagates_sigma_without_explicit_dep
    # Two tasks on the same resource, no explicit dep. Scheduler serialises
    # them via resource leveling; A runs first, B runs after. σ_start(B)
    # should equal σ_end(A) because A freeing the resource is what
    # determines when B may start. An implementation that only honoured
    # @startpreds would report σ_start(B) = 0.
    tj = parse_and_schedule(<<~TJP)
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" now 2024-01-01 }
      resource r "R"
      task a "A" {
        start 2024-01-01
        effort 5d
        stdev 1d
        allocate r
      }
      task b "B" {
        effort 5d
        stdev 1d
        allocate r
      }
    TJP

    a = ts(tj.project, 'a')
    b = ts(tj.project, 'b')

    sigma_a = a.endStdevSlots
    assert(sigma_a > 0, "σ_end(A) should be non-zero")

    sigma_dur_b = expected_leaf_duration_sigma(b)
    expected_b = Math.sqrt(sigma_a**2 + sigma_dur_b**2)
    assert_in_delta(expected_b, b.endStdevSlots, TOL,
                    "σ_end(B) should pick up σ_end(A) as resource-induced predecessor")
  end

  def test_resource_contention_yields_same_sigma_as_explicit_dep
    # Given the same topology expressed with an explicit dependency vs.
    # implicit resource contention, σ_end(B) must be identical — the
    # binding constraint is the same, only how it was expressed differs.
    tjp_template = <<~ERB
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" now 2024-01-01 }
      resource %<resources>s
      task a "A" {
        start 2024-01-01
        effort 5d
        stdev 1d
        allocate %<alloc_a>s
      }
      task b "B" {
        effort 5d
        stdev 1d
        allocate %<alloc_b>s
        %<dep>s
      }
    ERB

    with_dep = tjp_template % {
      resources: "ra \"RA\"\nresource rb \"RB\"",
      alloc_a: "ra",
      alloc_b: "rb",
      dep: "depends a"
    }
    tj_dep = parse_and_schedule(with_dep)
    sigma_via_dep = ts(tj_dep.project, 'b').endStdevSlots

    with_res = tjp_template % {
      resources: "r \"R\"",
      alloc_a: "r",
      alloc_b: "r",
      dep: ""
    }
    tj_res = parse_and_schedule(with_res)
    sigma_via_res = ts(tj_res.project, 'b').endStdevSlots

    assert_in_delta(sigma_via_dep, sigma_via_res, TOL,
                    "Resource contention and explicit dep should yield the same σ_end(B)")
  end

  # ─── Memoization ─────────────────────────────────────────────

  def test_memo_is_shared_across_calls
    # Second call must reuse the memo, so repeated queries return
    # identical values and do not re-traverse.
    tj = parse_and_schedule(<<~TJP)
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" now 2024-01-01 }
      resource r "R"
      task a "A" {
        start 2024-01-01
        effort 1d
        stdev 0.1d
        allocate r
      }
    TJP

    a = ts(tj.project, 'a')
    memo = {}
    s1 = a.endStdevSlots(memo)
    s2 = a.endStdevSlots(memo)
    assert_equal(s1, s2)
    assert(memo.key?([a, :end]), "memo should record the computed value")
  end

end
