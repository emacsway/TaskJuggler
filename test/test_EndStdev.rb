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

    sigma_a = expected_leaf_duration_sigma(a)
    sigma_b = expected_leaf_duration_sigma(b)
    sigma_c = expected_leaf_duration_sigma(c)
    sigma_dur_d = expected_leaf_duration_sigma(d)

    # With well-separated mean ends (3d/5d/10d), Clark-1961 merging
    # reduces to the σ of the dominant predecessor (C) to within a
    # fraction of a slot. σ_end(D) must therefore be approximately the
    # critical-path value, NOT the RSS of all predecessors.
    critical_path = Math.sqrt(sigma_c**2 + sigma_dur_d**2)
    over_counted  = Math.sqrt(sigma_a**2 + sigma_b**2 + sigma_c**2 + sigma_dur_d**2)
    result        = d.endStdevSlots

    rel_err_vs_crit = (result - critical_path).abs / critical_path
    assert(rel_err_vs_crit < 0.01,
           "σ_end(D) must be within 1% of critical-path value for well-separated means; " \
           "got rel_err=#{rel_err_vs_crit}")
    assert(result < over_counted,
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

  # ─── σ of remaining work only ───────────────────────────────

  def test_completed_task_has_zero_sigma
    # Task ends before `now`: its σ has been resolved (the actual
    # effort spent is now known). σ_end must be 0, or downstream σ
    # would accumulate variance from work that no longer carries any.
    tj = parse_and_schedule(<<~TJP)
      project test "Test" 2024-01-01 - 2024-12-31 {
        timezone "UTC"
        now 2024-03-01
      }
      resource r "R"
      task a "A" {
        start 2024-01-01
        effort 5d
        stdev 1d
        allocate r
      }
    TJP
    a = ts(tj.project, 'a')
    assert_in_delta(0.0, a.endStdevSlots, TOL,
                    "σ_end of a fully-completed task (end < now) must be 0")
  end

  def test_in_progress_task_uses_only_remaining_sigma
    # Task spans `now`: σ must reflect only the remaining portion of
    # effort, not the total. Compare σ_end at two different `now`
    # positions — a later now must produce a strictly smaller σ.
    make_project = lambda do |now_date|
      tjp = <<~TJP
        project test "Test" 2024-01-01 - 2024-12-31 {
          timezone "UTC"
          now #{now_date}
        }
        resource r "R"
        task a "A" {
          start 2024-01-01
          effort 20d
          stdev 4d
          allocate r
        }
      TJP
      parse_and_schedule(tjp)
    end

    sigma_at_start  = ts(make_project.call('2024-01-01').project, 'a').endStdevSlots
    sigma_mid       = ts(make_project.call('2024-01-15').project, 'a').endStdevSlots
    sigma_near_end  = ts(make_project.call('2024-01-25').project, 'a').endStdevSlots

    assert(sigma_at_start > 0, "σ should be non-zero before task starts")
    assert(sigma_mid < sigma_at_start,
           "σ mid-task (#{sigma_mid}) should be smaller than σ at task start (#{sigma_at_start})")
    assert(sigma_near_end < sigma_mid,
           "σ near task end (#{sigma_near_end}) should be smaller than σ mid-task (#{sigma_mid})")
  end

  def test_completed_predecessor_contributes_no_sigma_downstream
    # A→B chain where A is already done. B's σ_start must be 0
    # (past is resolved), so B's σ_end is purely its own durationStdev.
    tj = parse_and_schedule(<<~TJP)
      project test "Test" 2024-01-01 - 2024-12-31 {
        timezone "UTC"
        now 2024-02-15
      }
      resource r1 "R1"
      resource r2 "R2"
      task a "A" {
        start 2024-01-01
        effort 5d
        stdev 1d
        allocate r1
      }
      task b "B" {
        start 2024-02-15
        effort 5d
        stdev 1d
        allocate r2
        depends a
      }
    TJP

    a = ts(tj.project, 'a')
    b = ts(tj.project, 'b')

    assert_in_delta(0.0, a.endStdevSlots, TOL,
                    "completed predecessor should have σ_end = 0")
    # B has not started yet: its σ_dur is the full durationStdev, and
    # σ_start = σ_end(a) = 0.
    sigma_b_own = expected_leaf_duration_sigma(b)
    assert_in_delta(sigma_b_own, b.endStdevSlots, TOL,
                    "B's σ_end should collapse to its own σ_dur when predecessor is done")
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
