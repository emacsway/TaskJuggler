#!/usr/bin/env ruby -w
# frozen_string_literal: true
# encoding: UTF-8
#
# = CpSatScheduler.rb -- The TaskJuggler III Project Management Software
#
# Alternative scheduling engine using Google OR-Tools CP-SAT solver.
# Produces optimal or near-optimal schedules by minimizing project makespan.
#
# Usage:
#   scheduler = CpSatScheduler.new(project, scenarioIdx)
#   scheduler.optimize  # returns true on success

require 'or-tools'
require 'taskjuggler/MessageHandler'
require 'taskjuggler/Log'

class TaskJuggler

  class CpSatScheduler

    include MessageHandler

    # Struct to hold CP-SAT variables for each task
    TaskVars = Struct.new(
      :task,          # TJ3 Task object
      :start_var,     # CP-SAT IntVar for start slot
      :end_var,       # CP-SAT IntVar for end slot
      :size_var,      # CP-SAT IntVar or integer for duration in slots
      :interval_var,  # CP-SAT IntervalVar
      :resource_id,   # Assigned resource ID (for effort tasks)
      :is_leaf,       # Boolean
      :is_milestone,  # Boolean
      keyword_init: true
    )

    def initialize(project, scenarioIdx, options = {})
      @project = project
      @scIdx = scenarioIdx
      @model = ORTools::CpModel.new
      @solver = ORTools::CpSolver.new

      @gran = @project['scheduleGranularity']
      @project_start = @project['start']
      @project_end = @project['end']
      @calendar_horizon = seconds_to_slots(@project_end - @project_start)

      # Build working-slot ↔ calendar-slot lookup tables
      build_working_time_map
      @horizon = @working_to_calendar.size  # model works in working slots

      @task_vars = {}
      @resource_intervals = Hash.new { |h, k| h[k] = [] }
      @timeout = options[:timeout] || 30
      @log_level = options[:log_level] || 0

      Log.enter('cp_sat', "Building CP-SAT model (#{@horizon} working slots of #{@calendar_horizon} total)")
    end

    # Main entry point. Returns true on success.
    def optimize
      build_variables
      add_dependency_constraints
      add_resource_constraints
      add_container_constraints
      add_bound_constraints
      add_warm_start_hints
      set_objective
      success = solve
      write_back if success
      Log.exit('cp_sat')
      success
    end

    private

    # ── Phase 1: Variables ──────────────────────────────────────

    def build_variables
      @project.tasks.each do |task|
        is_leaf = task.leaf?
        sc = task.data[@scIdx]
        is_milestone = sc.instance_variable_get(:@milestone) rescue false

        if is_leaf
          build_leaf_task_vars(task, sc, is_milestone)
        else
          build_container_task_vars(task)
        end
      end

      Log.msg { "Variables: #{@task_vars.size} tasks (#{@task_vars.count { |_, v| v.is_leaf }} leaf)" }
    end

    def build_leaf_task_vars(task, sc, is_milestone)
      id = task.fullId

      if is_milestone
        start_var = @model.new_int_var(0, @horizon, "#{id}_start")
        size_var = @model.new_int_var(0, 0, "#{id}_size")
        interval = @model.new_interval_var(start_var, size_var, start_var, "#{id}_interval")
        @task_vars[id] = TaskVars.new(
          task: task, start_var: start_var, end_var: start_var,
          size_var: size_var, interval_var: interval,
          resource_id: nil, is_leaf: true, is_milestone: true
        )
        return
      end

      # Determine task size (duration in slots)
      effort = sc.instance_variable_get(:@effort) rescue 0
      duration = sc.instance_variable_get(:@duration) rescue 0
      length = sc.instance_variable_get(:@length) rescue 0

      # Convert EffortDistribution to numeric
      effort = effort.respond_to?(:to_f) ? effort.to_f : (effort || 0)
      duration = duration.respond_to?(:to_f) ? duration.to_f : (duration || 0)
      length = length.respond_to?(:to_f) ? length.to_f : (length || 0)

      size_slots, resource_id = compute_task_size(task, sc, effort, duration, length)

      if size_slots <= 0
        # Task with fixed start+end or zero duration — try to derive
        fixed_start = sc.instance_variable_get(:@start) rescue nil
        fixed_end = sc.instance_variable_get(:@end) rescue nil
        if fixed_start && fixed_end
          size_slots = [1, seconds_to_slots(fixed_end - fixed_start)].max
        else
          size_slots = 1  # minimum 1 slot
        end
      end

      start_var = @model.new_int_var(0, @horizon, "#{id}_start")
      end_var = @model.new_int_var(0, @horizon, "#{id}_end")
      size_var = @model.new_int_var(size_slots, size_slots, "#{id}_size")
      interval = @model.new_interval_var(start_var, size_var, end_var, "#{id}_interval")

      @task_vars[id] = TaskVars.new(
        task: task, start_var: start_var, end_var: end_var,
        size_var: size_var, interval_var: interval,
        resource_id: resource_id, is_leaf: true, is_milestone: false
      )
    end

    def build_container_task_vars(task)
      id = task.fullId
      start_var = @model.new_int_var(0, @horizon, "#{id}_start")
      end_var = @model.new_int_var(0, @horizon, "#{id}_end")

      @task_vars[id] = TaskVars.new(
        task: task, start_var: start_var, end_var: end_var,
        size_var: nil, interval_var: nil,
        resource_id: nil, is_leaf: false, is_milestone: false
      )
    end

    # Compute task duration in slots from effort/duration/length
    # Returns [size_slots, assigned_resource_id]
    def compute_task_size(task, sc, effort, duration, length)
      if effort > 0
        # Effort is in working-time slots. Model works in working slots — direct.
        total_eff, res_id = best_resource_efficiency(task, sc)
        total_eff = 1.0 if total_eff <= 0
        size = (effort / total_eff).ceil
        [size, res_id]
      elsif duration > 0
        # Duration is in seconds (calendar time). Convert to working slots.
        [calendar_duration_to_working_slots(duration), nil]
      elsif length > 0
        # Length is already in working-time slots.
        [length.ceil, nil]
      else
        [0, nil]
      end
    end

    # Find best resource efficiency for effort calculation
    def best_resource_efficiency(task, sc)
      allocations = sc.instance_variable_get(:@allocate) rescue []
      return [1.0, nil] unless allocations.is_a?(Array) && !allocations.empty?

      total_efficiency = 0.0
      best_res_id = nil

      allocations.each do |alloc|
        next unless alloc.respond_to?(:candidates)

        best_eff = 0.0
        best_candidate = nil

        alloc.candidates(@scIdx).each do |candidate|
          if candidate.respond_to?(:all)
            # Resource group — take first leaf
            candidate.all.each do |r|
              next unless r.leaf?
              eff = r['efficiency', @scIdx] rescue 1.0
              eff = eff.respond_to?(:to_f) ? eff.to_f : 1.0
              if eff > best_eff
                best_eff = eff
                best_candidate = r
              end
            end
          else
            eff = candidate['efficiency', @scIdx] rescue 1.0
            eff = eff.respond_to?(:to_f) ? eff.to_f : 1.0
            if eff > best_eff
              best_eff = eff
              best_candidate = candidate
            end
          end
        end

        total_efficiency += best_eff
        best_res_id ||= best_candidate&.fullId
      end

      [total_efficiency, best_res_id]
    end

    # ── Phase 2: Constraints ────────────────────────────────────

    def add_dependency_constraints
      count = 0
      @project.tasks.each do |task|
        next unless task.leaf?
        tv = @task_vars[task.fullId]
        next unless tv

        sc = task.data[@scIdx]

        # depends (predecessors) — use instance_variable_get since get() may not work post-Xref
        deps = sc.instance_variable_get(:@depends) rescue []
        (deps || []).each do |dep|
          dep_task = dep.respond_to?(:task) ? dep.task : nil
          next unless dep_task

          dep_tv = @task_vars[dep_task.fullId]
          next unless dep_tv

          gap = compute_gap(dep)
          source_var = dep.onEnd ? dep_tv.end_var : dep_tv.start_var
          @model.add(tv.start_var >= source_var + gap)
          count += 1
        end

        # precedes (successors)
        precs = sc.instance_variable_get(:@precedes) rescue []
        (precs || []).each do |dep|
          dep_task = dep.respond_to?(:task) ? dep.task : nil
          next unless dep_task

          dep_tv = @task_vars[dep_task.fullId]
          next unless dep_tv

          gap = compute_gap(dep)
          @model.add(dep_tv.start_var >= tv.end_var + gap)
          count += 1
        end
      end

      Log.msg { "Dependency constraints: #{count}" }
    end

    def compute_gap(dep)
      gap_dur = dep.respond_to?(:gapDuration) ? (dep.gapDuration || 0) : 0
      gap_len = dep.respond_to?(:gapLength) ? (dep.gapLength || 0) : 0
      # Convert gapDuration (seconds) to slots
      gap_dur_slots = seconds_to_slots(gap_dur)
      # gapLength is already in slots
      # Take the larger of the two
      [gap_dur_slots, gap_len].max
    end

    def add_resource_constraints
      alt_count = 0

      @project.tasks.each do |task|
        next unless task.leaf?
        tv = @task_vars[task.fullId]
        next unless tv && tv.is_leaf && !tv.is_milestone && tv.interval_var

        sc = task.data[@scIdx]
        allocations = sc.instance_variable_get(:@allocate) rescue []
        next unless allocations.is_a?(Array) && !allocations.empty?

        allocations.each do |alloc|
          next unless alloc.respond_to?(:candidates)
          candidates = alloc.candidates(@scIdx) rescue []
          next if candidates.empty?

          # Resolve each candidate to leaf resource IDs
          res_ids = candidates.map { |c|
            if c.respond_to?(:all)
              c.all.select(&:leaf?).map(&:fullId)
            else
              [c.fullId]
            end
          }.flatten.uniq

          if res_ids.size == 1
            # Single candidate — direct assignment
            @resource_intervals[res_ids[0]] << tv.interval_var
          elsif res_ids.size > 1
            # Multiple candidates — create optional intervals, solver picks one
            alt_count += 1
            presence_vars = []

            res_ids.each do |rid|
              presence = @model.new_bool_var("#{task.fullId}_on_#{rid}")
              presence_vars << presence

              opt_interval = @model.new_optional_interval_var(
                tv.start_var, tv.size_var, tv.end_var, presence,
                "#{task.fullId}_opt_#{rid}"
              )
              @resource_intervals[rid] << opt_interval
            end

            # Exactly one resource must be chosen for this allocation
            @model.add(@model.sum(presence_vars) == 1)
          end
        end
      end

      # Add NoOverlap constraint for each resource
      @resource_intervals.each do |res_id, intervals|
        next if intervals.size < 2
        @model.add_no_overlap(intervals)
      end

      Log.msg { "Resource constraints: #{@resource_intervals.size} resources, " \
                "#{@resource_intervals.values.sum(&:size)} intervals, " \
                "#{alt_count} alternative choices" }
    end

    def add_container_constraints
      count = 0
      # Process containers bottom-up (deeper levels first)
      containers = @task_vars.values.reject(&:is_leaf).sort_by { |tv| -tv.task.level }

      containers.each do |tv|
        children_starts = []
        children_ends = []

        tv.task.children.each do |child|
          next unless child.is_a?(TaskJuggler::Task)
          child_tv = @task_vars[child.fullId]
          next unless child_tv
          children_starts << child_tv.start_var
          children_ends << child_tv.end_var
        end

        next if children_starts.empty?

        @model.add_min_equality(tv.start_var, children_starts)
        @model.add_max_equality(tv.end_var, children_ends)
        count += 1
      end

      Log.msg { "Container constraints: #{count}" }
    end

    def add_bound_constraints
      @task_vars.each do |_id, tv|
        next unless tv.is_leaf
        task = tv.task
        sc = task.data[@scIdx]

        # Fixed start — use as lower bound (not hard equality)
        begin
          fixed_start = sc.instance_variable_get(:@start)
          if fixed_start && task.provided('start', @scIdx)
            slot = date_to_slot(fixed_start)
            @model.add(tv.start_var >= slot) if slot >= 0 && slot <= @horizon
          end
        rescue; end

        # Fixed end — use as upper bound
        begin
          fixed_end = sc.instance_variable_get(:@end)
          if fixed_end && task.provided('end', @scIdx)
            slot = date_to_slot(fixed_end)
            @model.add(tv.end_var <= slot) if slot >= 0 && slot <= @horizon
          end
        rescue; end

        # Min/max bounds
        %w(minstart maxstart minend maxend).each do |attr|
          val = sc.instance_variable_get(:"@#{attr}") rescue nil
          next unless val

          slot = date_to_slot(val)
          next if slot < 0 || slot > @horizon

          case attr
          when 'minstart' then @model.add(tv.start_var >= slot)
          when 'maxstart' then @model.add(tv.start_var <= slot)
          when 'minend'   then @model.add(tv.end_var >= slot)
          when 'maxend'   then @model.add(tv.end_var <= slot)
          end
        end
      end
    end

    # ── Warm Start Hints ─────────────────────────────────────────

    # If tasks already have dates (from prepareScenario or a prior schedule run),
    # use them as hints to speed up the solver.
    def add_warm_start_hints
      count = 0
      @task_vars.each do |_id, tv|
        sc = tv.task.data[@scIdx]
        start_date = sc.instance_variable_get(:@start) rescue nil
        end_date = sc.instance_variable_get(:@end) rescue nil

        if start_date
          slot = date_to_slot(start_date).clamp(0, @horizon)
          @model.add_hint(tv.start_var, slot)
          count += 1
        end

        if end_date
          slot = date_to_slot(end_date).clamp(0, @horizon)
          @model.add_hint(tv.end_var, slot) unless tv.is_milestone
        end
      end

      Log.msg { "Warm start hints: #{count} tasks" }
    rescue => e
      # Hints are optional — if they fail, continue without
      Log.msg { "Warm start hints failed: #{e.message}" }
    end

    # ── Phase 3: Objective ──────────────────────────────────────

    def set_objective
      # Collect end vars of top-level tasks
      top_end_vars = @task_vars.values
        .select { |tv| tv.task.parent.nil? || !tv.task.parent.is_a?(TaskJuggler::Task) }
        .map(&:end_var)

      return if top_end_vars.empty?

      makespan = @model.new_int_var(0, @horizon, 'makespan')
      @model.add_max_equality(makespan, top_end_vars)
      @makespan = makespan

      # Add priority weighting as secondary objective.
      # Skip for large projects — the expression tree becomes too large and causes model_invalid.
      leaf_count = @task_vars.count { |_, v| v.is_leaf }
      if leaf_count > 100
        @model.minimize(makespan)
        return
      end
      priority_terms = []
      @task_vars.each do |_id, tv|
        next unless tv.is_leaf && !tv.is_milestone

        priority = (tv.task.data[@scIdx].instance_variable_get(:@priority) rescue 500) || 500
        priority = priority.respond_to?(:to_i) ? priority.to_i : 500
        forward = (tv.task.data[@scIdx].instance_variable_get(:@forward) rescue true)

        weight = 1001 - priority.clamp(1, 1000)
        if forward
          priority_terms << [weight, tv.start_var]
        else
          priority_terms << [weight, tv.end_var]
        end
      end

      if priority_terms.empty?
        @model.minimize(makespan)
      else
        big_weight = @horizon * 1001
        expr = big_weight * makespan
        priority_terms.each { |w, v| expr = expr + w * v }
        @model.minimize(expr)
      end
    end

    # ── Phase 4: Solve ──────────────────────────────────────────

    def solve
      @solver.parameters.max_time_in_seconds = @timeout

      status = @solver.solve(@model)

      case status
      when :optimal
        Log.msg { "Optimal solution found. Makespan: #{@solver.value(@makespan)} slots " \
                             "(#{slots_to_days(@solver.value(@makespan))} days)" }
        true
      when :feasible
        Log.msg { "Feasible solution found (timeout). Makespan: #{@solver.value(@makespan)} slots " \
                             "(#{slots_to_days(@solver.value(@makespan))} days)" }
        true
      when :infeasible
        error('cp_sat_infeasible', 'CP-SAT: Problem is infeasible — constraints are contradictory')
        false
      else
        error('cp_sat_failed', "CP-SAT: Solver returned status #{status}")
        false
      end
    end

    # ── Phase 5: Write Back ─────────────────────────────────────

    def write_back
      @task_vars.each do |_id, tv|
        next unless tv.is_leaf

        start_slot = @solver.value(tv.start_var)
        end_slot = tv.is_milestone ? start_slot : @solver.value(tv.end_var)

        start_date = slot_to_date(start_slot)
        end_date = slot_to_date(end_slot)

        sc = tv.task.data[@scIdx]
        sc.instance_variable_set(:@start, start_date)
        sc.instance_variable_set(:@end, end_date)
        sc.instance_variable_set(:@scheduled, true)
        sc.instance_variable_set(:@milestone, true) if tv.is_milestone
      end

      # Set container dates bottom-up
      containers = @task_vars.values.reject(&:is_leaf).sort_by { |tv| -tv.task.level }
      containers.each do |tv|
        start_slot = @solver.value(tv.start_var)
        end_slot = @solver.value(tv.end_var)

        sc = tv.task.data[@scIdx]
        sc.instance_variable_set(:@start, slot_to_date(start_slot))
        sc.instance_variable_set(:@end, slot_to_date(end_slot))
        sc.instance_variable_set(:@scheduled, true)
      end

      Log.msg { "Wrote back #{@task_vars.size} task dates" }
    end

    # ── Helpers ─────────────────────────────────────────────────

    # Build bidirectional mapping between working slots and calendar slots.
    # working_to_calendar[i] = calendar slot index for i-th working slot
    # calendar_to_working[j] = working slot index for calendar slot j (or nil if non-working)
    def build_working_time_map
      @working_to_calendar = []
      @calendar_to_working = Array.new(@calendar_horizon)

      wh = @project['workinghours']
      days = wh.instance_variable_get(:@days) rescue nil

      unless days
        # Fallback: all slots are working
        @calendar_horizon.times { |i| @working_to_calendar << i; @calendar_to_working[i] = i }
        return
      end

      @calendar_horizon.times do |cal_slot|
        time = @project_start + cal_slot * @gran
        t = Time.at(time.to_i)
        dow = t.wday  # 0=Sun
        hour_sec = t.hour * 3600 + t.min * 60

        is_working = false
        (days[dow] || []).each do |range|
          if hour_sec >= range[0] && hour_sec < range[1]
            is_working = true
            break
          end
        end

        if is_working
          @calendar_to_working[cal_slot] = @working_to_calendar.size
          @working_to_calendar << cal_slot
        end
      end
    end

    def seconds_to_slots(seconds)
      (seconds.to_f / @gran).to_i
    end

    # Convert a calendar date to a working slot index
    def date_to_slot(date)
      cal_slot = seconds_to_slots(date - @project_start)
      # Find nearest working slot
      ws = @calendar_to_working[cal_slot.clamp(0, @calendar_horizon - 1)]
      return ws if ws
      # If non-working, find next working slot
      (cal_slot...@calendar_horizon).each do |i|
        ws = @calendar_to_working[i]
        return ws if ws
      end
      @horizon - 1
    end

    # Convert a working slot index to a calendar date
    def slot_to_date(working_slot)
      ws = working_slot.clamp(0, @working_to_calendar.size - 1)
      cal_slot = @working_to_calendar[ws] || 0
      @project_start + cal_slot * @gran
    end

    def slots_to_days(working_slots)
      dwh = (@project['dailyworkinghours'] rescue 8.0) || 8.0
      (working_slots.to_f / dwh).round(1)
    end

    # Convert calendar duration (seconds) to working slots
    def calendar_duration_to_working_slots(seconds)
      cal_slots = seconds_to_slots(seconds)
      # Count how many working slots fall within cal_slots from project start
      # This is approximate but consistent
      dwh = (@project['dailyworkinghours'] rescue 8.0) || 8.0
      (cal_slots.to_f * dwh / 24.0).ceil
    end
  end

end
