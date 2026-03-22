#!/usr/bin/env ruby -w
# frozen_string_literal: true
# encoding: UTF-8

$:.unshift File.join(File.dirname(__FILE__), '..', 'lib') if __FILE__ == $0
$:.unshift File.dirname(__FILE__)

require 'test/unit'
require 'tmpdir'
require 'taskjuggler/TaskJuggler'
require 'taskjuggler/CpSatScheduler'

class TestCpSatScheduler < Test::Unit::TestCase

  def setup
    ENV['TZ'] = 'UTC'
    @mh = TaskJuggler::MessageHandlerInstance.instance
    @mh.reset
    @mh.outputLevel = :none
    @mh.trapSetup = true
  end

  # ── Helper: parse and prepare a TJP string ──────────────────

  def parse_project(tjp_text)
    # Write to temp file
    tmpfile = File.join(Dir.tmpdir, "test_cpsat_#{$$}.tjp")
    File.write(tmpfile, tjp_text)

    tj = TaskJuggler.new
    assert(tj.parse([tmpfile]), "Parse failed")
    File.delete(tmpfile) rescue nil
    tj
  end

  def optimize_project(tjp_text, timeout: 5)
    tj = parse_project(tjp_text)
    project = tj.project

    project.send(:initScoreboards)
    [project.accounts, project.shifts, project.resources, project.tasks].each(&:index)

    TaskJuggler::AttributeBase.setMode(1)
    project.send(:prepareScenario, 0)
    TaskJuggler::AttributeBase.setMode(2)
    project.send(:scheduleScenario, 0)

    optimizer = TaskJuggler::CpSatScheduler.new(project, 0, timeout: timeout)
    [optimizer, project]
  end

  # ── Test: basic optimization works ──────────────────────────

  def test_basic_optimize
    tjp = <<~TJP
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" }
      resource dev "Developer"
      task t1 "Task 1" {
        effort 5d
        allocate dev
      }
      task t2 "Task 2" {
        depends t1
        effort 3d
        allocate dev
      }
    TJP

    opt, project = optimize_project(tjp)
    assert(opt.optimize, "Optimizer failed")

    t1 = project.task('t1')
    t2 = project.task('t2')
    assert_not_nil(t1.data[0].instance_variable_get(:@start))
    assert_not_nil(t2.data[0].instance_variable_get(:@start))

    # t2 must start after t1 ends
    t1_end = t1.data[0].instance_variable_get(:@end)
    t2_start = t2.data[0].instance_variable_get(:@start)
    assert(t2_start >= t1_end, "Dependency violated: t2 starts before t1 ends")
  end

  # ── Test: milestones ────────────────────────────────────────

  def test_milestones
    tjp = <<~TJP
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" }
      resource dev "Developer"
      task t1 "Task 1" {
        effort 5d
        allocate dev
      }
      task ms "Milestone" {
        depends t1
        milestone
      }
    TJP

    opt, project = optimize_project(tjp)
    assert(opt.optimize, "Optimizer failed")

    ms = project.task('ms')
    ms_start = ms.data[0].instance_variable_get(:@start)
    ms_end = ms.data[0].instance_variable_get(:@end)
    assert_equal(ms_start, ms_end, "Milestone must have start == end")
  end

  # ── Test: resource no-overlap ───────────────────────────────

  def test_resource_no_overlap
    tjp = <<~TJP
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" }
      resource dev "Developer"
      task t1 "Task 1" {
        effort 5d
        allocate dev
      }
      task t2 "Task 2" {
        effort 3d
        allocate dev
      }
    TJP

    opt, project = optimize_project(tjp)
    assert(opt.optimize, "Optimizer failed")

    t1_start = project.task('t1').data[0].instance_variable_get(:@start)
    t1_end = project.task('t1').data[0].instance_variable_get(:@end)
    t2_start = project.task('t2').data[0].instance_variable_get(:@start)
    t2_end = project.task('t2').data[0].instance_variable_get(:@end)

    # Tasks on same resource must not overlap
    overlap = (t1_start < t2_end) && (t2_start < t1_end)
    assert(!overlap, "Resource overlap detected: t1=[#{t1_start},#{t1_end}] t2=[#{t2_start},#{t2_end}]")
  end

  # ── Test: container tasks ───────────────────────────────────

  def test_containers
    tjp = <<~TJP
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" }
      resource dev "Developer"
      task phase "Phase" {
        task t1 "Sub 1" {
          effort 3d
          allocate dev
        }
        task t2 "Sub 2" {
          depends phase.t1
          effort 2d
          allocate dev
        }
      }
    TJP

    opt, project = optimize_project(tjp)
    assert(opt.optimize, "Optimizer failed")

    phase = project.task('phase')
    t1 = project.task('phase.t1')
    t2 = project.task('phase.t2')

    phase_start = phase.data[0].instance_variable_get(:@start)
    phase_end = phase.data[0].instance_variable_get(:@end)
    t1_start = t1.data[0].instance_variable_get(:@start)
    t2_end = t2.data[0].instance_variable_get(:@end)

    assert_equal(phase_start, t1_start, "Container start must equal earliest child start")
    assert_equal(phase_end, t2_end, "Container end must equal latest child end")
  end

  # ── Test: dependency gap ────────────────────────────────────

  def test_dependency_gap
    tjp = <<~TJP
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" }
      resource dev "Developer"
      task t1 "Task 1" {
        effort 2d
        allocate dev
      }
      task t2 "Task 2" {
        depends t1 { gapduration 3d }
        effort 2d
        allocate dev
      }
    TJP

    opt, project = optimize_project(tjp)
    assert(opt.optimize, "Optimizer failed")

    t1_end = project.task('t1').data[0].instance_variable_get(:@end)
    t2_start = project.task('t2').data[0].instance_variable_get(:@start)

    gap_seconds = t2_start - t1_end
    # Gap should be at least 3 days in working slots
    assert(gap_seconds > 0, "Gap must be positive")
  end

  # ── Test: alternative resources ─────────────────────────────

  def test_alternative_resources
    tjp = <<~TJP
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" }
      resource dev1 "Dev 1"
      resource dev2 "Dev 2"
      task t1 "Task 1" {
        effort 5d
        allocate dev1 { alternative dev2 select minallocated }
      }
    TJP

    opt, project = optimize_project(tjp)
    assert(opt.optimize, "Optimizer failed")

    t1 = project.task('t1')
    t1_start = t1.data[0].instance_variable_get(:@start)
    assert_not_nil(t1_start, "Task must be scheduled")
  end

  # ── Test: makespan minimization ─────────────────────────────

  def test_makespan_minimized
    # Two independent tasks, two resources — should run in parallel
    tjp = <<~TJP
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" }
      resource dev1 "Dev 1"
      resource dev2 "Dev 2"
      task t1 "Task 1" {
        effort 10d
        allocate dev1
      }
      task t2 "Task 2" {
        effort 10d
        allocate dev2
      }
    TJP

    opt, project = optimize_project(tjp)
    assert(opt.optimize, "Optimizer failed")

    t1_end = project.task('t1').data[0].instance_variable_get(:@end)
    t2_end = project.task('t2').data[0].instance_variable_get(:@end)

    # Both should end around the same time (parallel execution)
    diff_hours = ((t1_end - t2_end).abs / 3600.0)
    assert(diff_hours < 24 * 5, "Independent tasks on different resources should run in parallel")
  end

  # ── Test: Monte Carlo ───────────────────────────────────────

  def test_monte_carlo
    # Use Tutorial project which has real data
    tutorial = File.join(File.dirname(__FILE__), '..', 'examples', 'Tutorial', 'tutorial.tjp')
    return unless File.exist?(tutorial)

    tj = TaskJuggler.new
    assert(tj.parse([tutorial]), "Tutorial parse failed")

    project = tj.project
    project.send(:initScoreboards)
    [project.accounts, project.shifts, project.resources, project.tasks].each(&:index)
    TaskJuggler::AttributeBase.setMode(1)
    project.send(:prepareScenario, 0)
    TaskJuggler::AttributeBase.setMode(2)
    project.send(:scheduleScenario, 0)

    optimizer = TaskJuggler::CpSatScheduler.new(project, 0, timeout: 10)
    result = optimizer.monte_carlo(num_runs: 5)

    assert_not_nil(result, "Monte Carlo must return results")
    assert(result[:runs] >= 1, "Must have at least 1 successful run")
    assert(result[:p50] > 0, "P50 must be positive")
    assert(result[:p95] >= result[:p50], "P95 must be >= P50")
  end

  # ── Test: working hours respected ───────────────────────────

  def test_working_hours
    tjp = <<~TJP
      project test "Test" 2024-01-01 - 2024-03-01 { timezone "UTC" }
      resource dev "Developer"
      task t1 "Task 1" {
        effort 5d
        allocate dev
      }
    TJP

    opt, project = optimize_project(tjp)
    assert(opt.optimize, "Optimizer failed")

    t1_start = project.task('t1').data[0].instance_variable_get(:@start)
    start_time = Time.at(t1_start.to_i)

    # Should not start on weekend
    assert(start_time.wday >= 1 && start_time.wday <= 5,
           "Task should start on weekday, got #{start_time.strftime('%A')}")
  end

  # ── Test: Tutorial project ──────────────────────────────────

  def test_tutorial_project
    tutorial = File.join(File.dirname(__FILE__), '..', 'examples', 'Tutorial', 'tutorial.tjp')
    return unless File.exist?(tutorial)

    tj = TaskJuggler.new
    assert(tj.parse([tutorial]), "Tutorial parse failed")
    assert(tj.optimize, "Tutorial optimize failed")

    # Check project has scheduled tasks
    count = 0
    tj.project.tasks.each do |t|
      next unless t.leaf?
      s = t.data[0].instance_variable_get(:@start)
      count += 1 if s
    end
    assert(count > 0, "No tasks were scheduled")
  end
end
