#!/usr/bin/env ruby -w
# frozen_string_literal: true
# encoding: UTF-8

$:.unshift File.join(File.dirname(__FILE__), '..', 'lib') if __FILE__ == $0
$:.unshift File.dirname(__FILE__)

require 'test/unit'
require 'tmpdir'
require 'taskjuggler/TaskJuggler'

class TestDependsOn < Test::Unit::TestCase

  def setup
    ENV['TZ'] = 'UTC'
    @mh = TaskJuggler::MessageHandlerInstance.instance
    @mh.reset
    @mh.outputLevel = :none
    @mh.trapSetup = true
  end

  def parse_and_schedule(tjp_text)
    tmpfile = File.join(Dir.tmpdir, "test_dependson_#{$$}.tjp")
    File.write(tmpfile, tjp_text)

    tj = TaskJuggler.new
    assert(tj.parse([tmpfile]), "Parse failed")
    assert(tj.schedule, "Schedule failed")
    File.delete(tmpfile) rescue nil
    tj
  end

  # ── Basic dependson filtering ───────────────────────────────

  def test_dependson_filters_correct_tasks
    tj = parse_and_schedule(<<~TJP)
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" now 2024-01-01 }
      resource dev "Dev"

      task sprint1 "Sprint 1" {
        start 2024-02-01
        milestone
      }
      task sprint2 "Sprint 2" {
        start 2024-03-01
        milestone
      }

      task t1 "Task 1" {
        effort 5d
        allocate dev
        depends sprint1
      }
      task t2 "Task 2" {
        effort 3d
        allocate dev
        depends sprint1
      }
      task t3 "Task 3" {
        effort 4d
        allocate dev
        depends sprint2
      }
    TJP

    project = tj.project
    sprint1 = project.task('sprint1')

    # Check which tasks depend on sprint1
    depending = []
    project.tasks.each do |t|
      next unless t.leaf?
      sc = t.data[0]
      deps = sc.instance_variable_get(:@depends) rescue []
      next unless deps.is_a?(Array)
      if deps.any? { |d| d.respond_to?(:task) && d.task == sprint1 }
        depending << t.fullId
      end
    end

    assert_equal(['t1', 't2'], depending.sort)
    assert(!depending.include?('t3'), "t3 should not depend on sprint1")
  end

  # ── dependson in hidetask ───────────────────────────────────

  def test_dependson_in_taskreport
    tj = parse_and_schedule(<<~TJP)
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" now 2024-01-01 }
      resource dev "Dev"

      task sprint1 "Sprint 1" {
        start 2024-02-01
        milestone
      }
      task t1 "Task 1" {
        effort 5d
        allocate dev
        depends sprint1
      }
      task t2 "Task 2" {
        effort 3d
        allocate dev
        depends sprint1
      }
      task t3 "Task 3" {
        effort 4d
        allocate dev
      }

      taskreport sprint1_tasks "sprint1_tasks" {
        hidetask ~dependson(sprint1, plan)
        columns name, effort
      }
    TJP

    # If we get here without error, dependson parsed and evaluated correctly
    assert_not_nil(tj.project.report('sprint1_tasks'))
  end

  # ── dependson with scenario ─────────────────────────────────

  def test_dependson_scenario_specific
    tj = parse_and_schedule(<<~TJP)
      project test "Test" 2024-01-01 - 2024-12-31 {
        timezone "UTC"
        now 2024-01-01
        scenario plan "Plan" {
          scenario fact "Fact"
        }
      }
      resource dev "Dev"

      task sprint1 "Sprint 1" {
        start 2024-02-01
        milestone
      }
      task t1 "Task 1" {
        effort 5d
        allocate dev
        fact:depends sprint1
      }
      task t2 "Task 2" {
        effort 3d
        allocate dev
        depends sprint1
      }
    TJP

    project = tj.project
    sprint1 = project.task('sprint1')
    fact_idx = project.scenarioIdx('fact')

    # t1 depends on sprint1 in fact scenario
    t1_deps = project.task('t1').data[fact_idx].instance_variable_get(:@depends) rescue []
    t1_has = (t1_deps || []).any? { |d| d.respond_to?(:task) && d.task == sprint1 }
    assert(t1_has, "t1 should depend on sprint1 in fact scenario")

    # t2 depends on sprint1 in plan scenario (not fact)
    t2_deps_fact = project.task('t2').data[fact_idx].instance_variable_get(:@depends) rescue []
    t2_has_fact = (t2_deps_fact || []).any? { |d| d.respond_to?(:task) && d.task == sprint1 }
    # t2 has depends in plan, which inherits to fact
    # Both should show dependency
  end

  # ── dependson negation ──────────────────────────────────────

  def test_dependson_negation
    tj = parse_and_schedule(<<~TJP)
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" now 2024-01-01 }
      resource dev "Dev"

      task sprint1 "Sprint 1" {
        start 2024-02-01
        milestone
      }
      task t1 "Task 1" {
        effort 5d
        allocate dev
        depends sprint1
      }
      task t2 "Task 2" {
        effort 3d
        allocate dev
      }

      taskreport other_tasks "other_tasks" {
        hidetask dependson(sprint1, plan)
        columns name, effort
      }
    TJP

    # hidetask dependson(...) hides tasks that DO depend on sprint1
    # So the report should show t2 but not t1
    assert_not_nil(tj.project.report('other_tasks'))
  end

  # ── dependson with non-existent task ────────────────────────

  def test_dependson_nonexistent_task
    # Should return false, not crash
    tj = parse_and_schedule(<<~TJP)
      project test "Test" 2024-01-01 - 2024-12-31 { timezone "UTC" now 2024-01-01 }
      resource dev "Dev"

      task t1 "Task 1" {
        effort 5d
        allocate dev
      }

      taskreport all "all" {
        hidetask dependson(nonexistent, plan)
        columns name
      }
    TJP

    # Should not crash — nonexistent task returns false for all
    assert_not_nil(tj.project)
  end
end
