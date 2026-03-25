#!/usr/bin/env ruby -w
# frozen_string_literal: true
# encoding: UTF-8

$:.unshift File.join(File.dirname(__FILE__), '..', 'lib') if __FILE__ == $0
$:.unshift File.dirname(__FILE__)

require 'test/unit'
require 'tmpdir'
require 'fileutils'
require 'taskjuggler/TaskJuggler'

class TestTraceReport < Test::Unit::TestCase

  def setup
    ENV['TZ'] = 'UTC'
    @mh = TaskJuggler::MessageHandlerInstance.instance
    @mh.reset
    @mh.outputLevel = :none
    @mh.trapSetup = true
    @tmpDir = File.join(Dir.tmpdir, "test_tracereport_#{$$}")
    FileUtils.mkdir_p(@tmpDir)
  end

  def teardown
    FileUtils.rm_rf(@tmpDir) rescue nil
  end

  def run_tracereport(tjp)
    tmpfile = File.join(@tmpDir, 'project.tjp')
    File.write(tmpfile, tjp)

    tj = TaskJuggler.new
    assert(tj.parse([tmpfile]), "Parse failed")
    assert(tj.schedule, "Schedule failed")
    tj.project.enableTraceReports(true)
    tj.generateReports(@tmpDir + '/')
    tj
  end

  def read_csv(name)
    csv_file = File.join(@tmpDir, "#{name}.csv")
    assert(File.exist?(csv_file), "CSV file #{name}.csv not generated")
    File.read(csv_file)
  end

  # ── Expression columns: sum ─────────────────────────────────

  def test_sum_expression
    run_tracereport(<<~TJP)
      project test "Test" 2024-01-01 - 2024-06-01 { timezone "UTC" now 2024-03-15 }
      resource dev "Dev"
      task t1 "Task 1" { effort 10d
allocate dev
complete 100 }
      task t2 "Task 2" { effort 20d
allocate dev
complete 50 }
      task t3 "Task 3" { effort 15d
allocate dev
complete 0 }
      tracereport burndown "burndown" {
        columns "sum(effort * complete / 100)" { title "Done" }
        hideresource @all
      }
    TJP

    csv = read_csv('burndown')
    lines = csv.strip.split("\n")
    assert_match(/Done/, lines[0])
    # 10*100/100 + 20*50/100 + 15*0/100 = 10+10+0 = 20
    done = lines[1].split(';')[1].to_f
    assert_in_delta(20.0, done, 0.1, "sum(effort * complete / 100) should be 20")
  end

  # ── Expression columns: round ───────────────────────────────

  def test_round_expression
    run_tracereport(<<~TJP)
      project test "Test" 2024-01-01 - 2024-06-01 { timezone "UTC" now 2024-03-15 }
      resource dev "Dev"
      task t1 "Task 1" { effort 10d
allocate dev
complete 33 }
      tracereport report "report" {
        columns "round(sum(effort * complete / 100), 1)" { title "Done" }
        hideresource @all
      }
    TJP

    csv = read_csv('report')
    done = csv.strip.split("\n")[1].split(';')[1].to_f
    # 10 * 33 / 100 = 3.3
    assert_in_delta(3.3, done, 0.1, "round should produce 1 decimal place")
  end

  # ── Expression columns: remaining effort ────────────────────

  def test_remaining_effort_expression
    run_tracereport(<<~TJP)
      project test "Test" 2024-01-01 - 2024-06-01 { timezone "UTC" now 2024-03-15 }
      resource dev1 "Dev1"
      resource dev2 "Dev2"
      task t1 "Task 1" { effort 10d
allocate dev1
complete 100 }
      task t2 "Task 2" { effort 20d
allocate dev2
complete 50 }
      task t3 "Task 3" { effort 15d
allocate dev1
complete 0 }
      tracereport burndown "burndown" {
        columns "round(sum(effort * (100 - complete) / 100), 1)" { title "Remaining" },
                "round(sum(effort * complete / 100), 1)" { title "Done" }
        hideresource @all
      }
    TJP

    csv = read_csv('burndown')
    values = csv.strip.split("\n")[1].split(';')
    remaining = values[1].to_f
    done = values[2].to_f
    assert_in_delta(25.0, remaining, 0.1, "Remaining should be 25")
    assert_in_delta(20.0, done, 0.1, "Done should be 20")
  end

  # ── Expression columns with dependson filter ────────────────

  def test_expression_with_dependson_filter
    run_tracereport(<<~TJP)
      project test "Test" 2024-01-01 - 2024-06-01 { timezone "UTC" now 2024-03-15 }
      resource dev "Dev"
      task sprint1 "Sprint 1" { start 2024-02-01
milestone }
      task sprint2 "Sprint 2" { start 2024-03-01
milestone }
      task t1 "T1" { effort 10d
allocate dev
depends sprint1
complete 100 }
      task t2 "T2" { effort 20d
allocate dev
depends sprint1
complete 50 }
      task t3 "T3" { effort 15d
allocate dev
depends sprint2
complete 0 }
      tracereport sprint1_burndown "sprint1_burndown" {
        columns "sum(effort * complete / 100)" { title "Done" }
        hidetask ~dependson(sprint1, plan)
        hideresource @all
      }
    TJP

    csv = read_csv('sprint1_burndown')
    done = csv.strip.split("\n")[1].split(';')[1].to_f
    # Only t1 and t2: 10*100/100 + 20*50/100 = 10+10 = 20 (t3 excluded)
    assert_in_delta(20.0, done, 0.1, "Only sprint1 tasks should be aggregated")
  end

  # ── Mixed: regular columns + expression columns ─────────────

  def test_mixed_columns
    run_tracereport(<<~TJP)
      project test "Test" 2024-01-01 - 2024-06-01 { timezone "UTC" now 2024-03-15 }
      resource dev "Dev"
      task t1 "Task 1" { effort 10d
allocate dev
complete 80 }
      tracereport mixed "mixed" {
        columns complete, "sum(effort * complete / 100)" { title "Done" }
        hideresource @all
      }
    TJP

    csv = read_csv('mixed')
    lines = csv.strip.split("\n")
    # Header should have per-task complete column AND aggregate Done column
    assert_match(/complete/, lines[0])
    assert_match(/Done/, lines[0])
  end

  # ── Avg aggregate ───────────────────────────────────────────

  def test_avg_expression
    run_tracereport(<<~TJP)
      project test "Test" 2024-01-01 - 2024-06-01 { timezone "UTC" now 2024-03-15 }
      resource dev "Dev"
      task t1 "Task 1" { effort 10d
allocate dev
complete 100 }
      task t2 "Task 2" { effort 10d
allocate dev
complete 50 }
      task t3 "Task 3" { effort 10d
allocate dev
complete 0 }
      tracereport avg_report "avg_report" {
        columns "round(avg(complete), 1)" { title "Avg Complete" }
        hideresource @all
      }
    TJP

    csv = read_csv('avg_report')
    avg = csv.strip.split("\n")[1].split(';')[1].to_f
    # avg(100, 50, 0) = 50
    assert_in_delta(50.0, avg, 0.1, "avg(complete) should be 50")
  end

  # ── Multi-aggregate expression: weighted percentage ────────

  def test_weighted_percentage
    run_tracereport(<<~TJP)
      project test "Test" 2024-01-01 - 2024-06-01 { timezone "UTC" now 2024-03-15 }
      resource dev "Dev"
      task t1 "Task 1" { effort 10d
allocate dev
complete 100 }
      task t2 "Task 2" { effort 20d
allocate dev
complete 50 }
      task t3 "Task 3" { effort 10d
allocate dev
complete 0 }
      tracereport weighted "weighted" {
        columns "round(sum(effort * complete / 100) / sum(effort) * 100, 1)" { title "Done %" }
        hideresource @all
      }
    TJP

    csv = read_csv('weighted')
    pct = csv.strip.split("\n")[1].split(';')[1].to_f
    # (10*100/100 + 20*50/100 + 10*0/100) / (10+20+10) * 100 = 20/40*100 = 50.0
    assert_in_delta(50.0, pct, 0.1, "weighted complete should be 50%")
  end
end
