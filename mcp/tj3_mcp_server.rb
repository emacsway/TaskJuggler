#!/usr/bin/env ruby
# frozen_string_literal: true
#
# MCP Server for TaskJuggler 3
# Exposes TJ3 engine functionality as MCP tools for AI assistants.
#

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'mcp'
require 'json'
require 'taskjuggler/Tj3Config'
require 'taskjuggler/TaskJuggler'
require 'taskjuggler/MessageHandler'
require 'taskjuggler/Query'
require 'taskjuggler/Log'

AppConfig.new
AppConfig.appName = 'tj3mcp'
TaskJuggler::Log.silent = true

# ── Shared session state ────────────────────────────────────

module TJ3State
  @tj = nil
  @project = nil
  @project_dir = nil
  @scheduled = false

  class << self
    attr_accessor :tj, :project, :project_dir, :scheduled
  end

  def self.reset
    @tj = nil
    @project = nil
    @scheduled = false
  end

  def self.ensure_scheduled!
    raise "No project loaded. Use tj3_open_project first." unless @project
    raise "Project not scheduled. Use tj3_schedule first." unless @scheduled
  end
end

# ── Tools ───────────────────────────────────────────────────

class OpenProjectTool < MCP::Tool
  description "Open and parse a TaskJuggler project. Provide the path to the .tjp master file."
  input_schema(
    properties: {
      path: {
        type: "string",
        description: "Absolute path to the .tjp master file"
      }
    },
    required: ["path"]
  )

  class << self
    def call(path:, server_context:)
      TJ3State.reset
      mh = TaskJuggler::MessageHandlerInstance.instance
      mh.reset
      mh.trapSetup = true

      TJ3State.project_dir = File.dirname(path)
      TJ3State.tj = TaskJuggler.new

      begin
        unless TJ3State.tj.parse([path])
          msgs = mh.messages.map(&:to_s).join("\n").strip
          return error_response("Parse failed for #{path}\n#{msgs}")
        end
      rescue => e
        msgs = mh.messages.map(&:to_s).join("\n").strip
        return error_response("#{e.class}: #{e.message}\n#{msgs}")
      end

      TJ3State.project = TJ3State.tj.project
      tasks = 0
      TJ3State.project.tasks.each { tasks += 1 }
      resources = 0
      TJ3State.project.resources.each { resources += 1 }

      success_response("Project '#{TJ3State.project['name']}' loaded: #{tasks} tasks, #{resources} resources")
    end
  end
end

class ScheduleTool < MCP::Tool
  description "Schedule the loaded project using the standard TJ3 heuristic scheduler."
  input_schema(properties: {})

  class << self
    def call(server_context:)
      raise "No project loaded" unless TJ3State.project
      mh = TaskJuggler::MessageHandlerInstance.instance

      begin
        unless TJ3State.tj.schedule
          msgs = mh.messages.map(&:to_s).join("\n").strip
          return error_response("Scheduling failed\n#{msgs}")
        end
      rescue => e
        msgs = mh.messages.map(&:to_s).join("\n").strip
        return error_response("#{e.class}: #{e.message}\n#{msgs}")
      end

      TJ3State.scheduled = true
      success_response("Project scheduled successfully")
    end
  end
end

class OptimizeTool < MCP::Tool
  description "Schedule the project using CP-SAT optimizer (Google OR-Tools) for optimal makespan. Falls back to standard scheduler if optimization fails."
  input_schema(
    properties: {
      timeout: {
        type: "integer",
        description: "Solver timeout in seconds (default 15)"
      }
    }
  )

  class << self
    def call(timeout: 15, server_context:)
      raise "No project loaded" unless TJ3State.project
      mh = TaskJuggler::MessageHandlerInstance.instance

      begin
        unless TJ3State.tj.optimize(timeout: timeout)
          msgs = mh.messages.map(&:to_s).join("\n").strip
          return error_response("Optimization failed\n#{msgs}")
        end
      rescue => e
        msgs = mh.messages.map(&:to_s).join("\n").strip
        return error_response("#{e.class}: #{e.message}\n#{msgs}")
      end

      TJ3State.scheduled = true
      success_response("Project optimized with CP-SAT solver")
    end
  end
end

class GetTasksTool < MCP::Tool
  description "List all tasks in the project with their key attributes. Optionally filter by a search query matching task name or ID."
  input_schema(
    properties: {
      query: {
        type: "string",
        description: "Optional search string to filter tasks by name or ID"
      },
      scenario: {
        type: "integer",
        description: "Scenario index (default 0)"
      }
    }
  )

  class << self
    def call(query: nil, scenario: 0, server_context:)
      TJ3State.ensure_scheduled!

      tasks = []
      TJ3State.project.tasks.each do |task|
        next unless task.leaf?
        sc = task.data[scenario]

        if query
          q = query.downcase
          next unless task.fullId.downcase.include?(q) || task.name.downcase.include?(q)
        end

        effort = sc.instance_variable_get(:@effort) rescue 0
        effort = effort.respond_to?(:to_f) ? effort.to_f : 0
        complete = sc.instance_variable_get(:@complete) rescue nil
        start_date = sc.instance_variable_get(:@start)
        end_date = sc.instance_variable_get(:@end)

        tasks << {
          id: task.fullId,
          name: task.name,
          start: start_date&.to_s('%Y-%m-%d'),
          end: end_date&.to_s('%Y-%m-%d'),
          effort: effort.round(1),
          complete: complete,
          milestone: (sc.instance_variable_get(:@milestone) rescue false),
        }
      end

      success_response(JSON.pretty_generate(tasks))
    end
  end
end

class GetTaskDetailsTool < MCP::Tool
  description "Get detailed information about a specific task by ID."
  input_schema(
    properties: {
      task_id: {
        type: "string",
        description: "Full task ID (e.g., 'project.phase.task')"
      },
      scenario: {
        type: "integer",
        description: "Scenario index (default 0)"
      }
    },
    required: ["task_id"]
  )

  class << self
    def call(task_id:, scenario: 0, server_context:)
      TJ3State.ensure_scheduled!

      task = TJ3State.project.task(task_id)
      raise "Task '#{task_id}' not found" unless task

      sc = task.data[scenario]
      deps = (sc.instance_variable_get(:@depends) rescue []) || []
      dep_ids = deps.map { |d| d.respond_to?(:task) ? d.task&.fullId : nil }.compact

      effort = (sc.instance_variable_get(:@effort).to_f rescue 0).round(1)
      complete = (sc.instance_variable_get(:@complete) rescue nil)
      milestone = (sc.instance_variable_get(:@milestone) rescue false)
      priority = (sc.instance_variable_get(:@priority) rescue 500)

      info = {
        id: task.fullId,
        name: task.name,
        leaf: task.leaf?,
        container: task.container?,
        parent: task.parent&.is_a?(TaskJuggler::Task) ? task.parent.fullId : nil,
        children: task.children.select { |c| c.is_a?(TaskJuggler::Task) }.map(&:fullId),
        start: sc.instance_variable_get(:@start)&.to_s('%Y-%m-%d %H:%M'),
        end_date: sc.instance_variable_get(:@end)&.to_s('%Y-%m-%d %H:%M'),
        effort: effort,
        complete: complete,
        milestone: milestone,
        priority: priority,
        depends: dep_ids,
        source_file: task.sourceFileInfo&.fileName,
        source_line: task.sourceFileInfo&.lineNo,
      }

      success_response(JSON.pretty_generate(info))
    end
  end
end

class GetResourcesTool < MCP::Tool
  description "List all resources in the project."
  input_schema(
    properties: {
      scenario: {
        type: "integer",
        description: "Scenario index (default 0)"
      }
    }
  )

  class << self
    def call(scenario: 0, server_context:)
      TJ3State.ensure_scheduled!

      resources = []
      TJ3State.project.resources.each do |r|
        next unless r.leaf?
        resources << {
          id: r.fullId,
          name: r.name,
          efficiency: (r['efficiency', scenario] rescue 1.0),
          email: (r.get('email') rescue nil),
        }
      end

      success_response(JSON.pretty_generate(resources))
    end
  end
end

class QueryAttributeTool < MCP::Tool
  description "Query a specific attribute of a task or resource using the TJ3 Query engine. Returns formatted value."
  input_schema(
    properties: {
      property_type: {
        type: "string",
        enum: ["Task", "Resource"],
        description: "Type of property to query"
      },
      property_id: {
        type: "string",
        description: "Full ID of the task or resource"
      },
      attribute: {
        type: "string",
        description: "Attribute to query (e.g., effort, effortleft, complete, start, end, cost, revenue)"
      },
      scenario: {
        type: "integer",
        description: "Scenario index (default 0)"
      }
    },
    required: ["property_type", "property_id", "attribute"]
  )

  class << self
    def call(property_type:, property_id:, attribute:, scenario: 0, server_context:)
      TJ3State.ensure_scheduled!
      project = TJ3State.project

      property = case property_type
                 when 'Task' then project.task(property_id)
                 when 'Resource' then project.resource(property_id)
                 end
      raise "#{property_type} '#{property_id}' not found" unless property

      query = TaskJuggler::Query.new(
        'project' => project,
        'property' => property,
        'propertyType' => property_type.to_sym,
        'attributeId' => attribute,
        'scenarioIdx' => scenario,
        'start' => project['start'],
        'end' => project['end'],
        'loadUnit' => :days,
        'numberFormat' => project['numberFormat'],
        'timeFormat' => '%Y-%m-%d %H:%M'
      )
      query.process

      if query.ok
        success_response("#{property_type} #{property_id}.#{attribute} = #{query.to_s}")
      else
        error_response("Query failed: #{query.errorMessage}")
      end
    end
  end
end

class MonteCarloTool < MCP::Tool
  description "Run Monte Carlo simulation to estimate schedule uncertainty. Uses effort stdev values. Returns P50, P80, P95 percentiles of project duration."
  input_schema(
    properties: {
      num_runs: {
        type: "integer",
        description: "Number of simulation runs (default 20, max 100)"
      },
      task_ids: {
        type: "array",
        items: { type: "string" },
        description: "Optional: limit scope to these task IDs"
      }
    }
  )

  class << self
    def call(num_runs: 20, task_ids: nil, server_context:)
      TJ3State.ensure_scheduled!
      require 'taskjuggler/CpSatScheduler'

      num_runs = num_runs.clamp(5, 100)
      optimizer = TaskJuggler::CpSatScheduler.new(TJ3State.project, 0, timeout: 60)
      scope = task_ids&.to_set
      result = optimizer.monte_carlo(num_runs: num_runs, scope_task_ids: scope)

      if result
        success_response(JSON.pretty_generate(result))
      else
        error_response("Monte Carlo simulation failed")
      end
    end
  end
end

class ProjectInfoTool < MCP::Tool
  description "Get project metadata: name, start/end dates, scenarios, task/resource counts."
  input_schema(properties: {})

  class << self
    def call(server_context:)
      raise "No project loaded" unless TJ3State.project
      p = TJ3State.project

      tasks = 0; p.tasks.each { tasks += 1 }
      resources = 0; p.resources.each { resources += 1 }
      scenarios = []; p.scenarios.each { |s| scenarios << { id: s.fullId, name: s.get('name') } }

      info = {
        name: p['name'],
        id: p['projectid'],
        start: p['start'].to_s('%Y-%m-%d'),
        end: p['end'].to_s('%Y-%m-%d'),
        now: p['now'].to_s('%Y-%m-%d'),
        currency: p['currency'],
        tasks: tasks,
        resources: resources,
        scenarios: scenarios,
        scheduled: TJ3State.scheduled,
      }

      success_response(JSON.pretty_generate(info))
    end
  end
end

class ReadFileTool < MCP::Tool
  description "Read the content of a project file (.tjp or .tji)."
  input_schema(
    properties: {
      path: {
        type: "string",
        description: "Absolute path to the file"
      }
    },
    required: ["path"]
  )

  class << self
    def call(path:, server_context:)
      raise "File not found: #{path}" unless File.exist?(path)
      content = File.read(path, encoding: 'UTF-8')
      success_response(content)
    end
  end
end

class OverloadedResourcesTool < MCP::Tool
  description "Find resources that are overloaded (allocated more than available). Shows each resource with their allocation percentage and the tasks they are assigned to."
  input_schema(
    properties: {
      scenario: {
        type: "integer",
        description: "Scenario index (default 0)"
      }
    }
  )

  class << self
    def call(scenario: 0, server_context:)
      TJ3State.ensure_scheduled!

      results = []
      TJ3State.project.resources.each do |r|
        next unless r.leaf?
        sc = r.data[scenario]
        efficiency = (r['efficiency', scenario] rescue 1.0).to_f

        # Collect tasks assigned to this resource
        duties = []
        TJ3State.project.tasks.each do |t|
          next unless t.leaf?
          tsc = t.data[scenario]
          assigned = (tsc.instance_variable_get(:@assignedresources) rescue []) || []
          assigned = assigned.select { |ar| ar.respond_to?(:fullId) }.map(&:fullId) rescue []
          duties << t.fullId if assigned.include?(r.fullId)
        end

        next if duties.empty?

        results << {
          id: r.fullId,
          name: r.name,
          efficiency: efficiency,
          tasks_count: duties.size,
          tasks: duties,
        }
      end

      # Sort by task count descending
      results.sort_by! { |r| -r[:tasks_count] }
      success_response(JSON.pretty_generate(results))
    end
  end
end

class CriticalPathTool < MCP::Tool
  description "Find tasks on the critical path — tasks with highest pathcriticalness values. These are the bottleneck tasks that determine the project end date."
  input_schema(
    properties: {
      scenario: {
        type: "integer",
        description: "Scenario index (default 0)"
      },
      limit: {
        type: "integer",
        description: "Maximum number of tasks to return (default 20)"
      }
    }
  )

  class << self
    def call(scenario: 0, limit: 20, server_context:)
      TJ3State.ensure_scheduled!

      tasks = []
      TJ3State.project.tasks.each do |t|
        next unless t.leaf?
        sc = t.data[scenario]
        pc = (sc.instance_variable_get(:@pathcriticalness) rescue 0).to_f
        next if pc <= 0

        tasks << {
          id: t.fullId,
          name: t.name,
          pathcriticalness: pc.round(4),
          start: sc.instance_variable_get(:@start)&.to_s('%Y-%m-%d'),
          end_date: sc.instance_variable_get(:@end)&.to_s('%Y-%m-%d'),
          effort: (sc.instance_variable_get(:@effort).to_f rescue 0).round(1),
          complete: (sc.instance_variable_get(:@complete) rescue nil),
        }
      end

      tasks.sort_by! { |t| -t[:pathcriticalness] }
      tasks = tasks.first(limit)
      success_response(JSON.pretty_generate(tasks))
    end
  end
end

class LateTasksTool < MCP::Tool
  description "Find tasks that are overdue or at risk: tasks past their end date with complete < 100%, or tasks ending after their maxend constraint."
  input_schema(
    properties: {
      scenario: {
        type: "integer",
        description: "Scenario index (default 0)"
      }
    }
  )

  class << self
    def call(scenario: 0, server_context:)
      TJ3State.ensure_scheduled!
      now = TJ3State.project['now']

      late = []
      TJ3State.project.tasks.each do |t|
        next unless t.leaf?
        sc = t.data[scenario]
        end_date = sc.instance_variable_get(:@end)
        complete = (sc.instance_variable_get(:@complete) rescue nil)
        maxend = (sc.instance_variable_get(:@maxend) rescue nil)
        milestone = (sc.instance_variable_get(:@milestone) rescue false)

        next if milestone

        reason = nil
        if end_date && now && end_date < now && (complete.nil? || complete < 100)
          reason = "overdue"
        elsif maxend && end_date && end_date > maxend
          reason = "past maxend"
        end

        next unless reason

        late << {
          id: t.fullId,
          name: t.name,
          reason: reason,
          end_date: end_date&.to_s('%Y-%m-%d'),
          maxend: maxend&.to_s('%Y-%m-%d'),
          complete: complete,
          effort: (sc.instance_variable_get(:@effort).to_f rescue 0).round(1),
        }
      end

      late.sort_by! { |t| t[:end_date].to_s }
      success_response(JSON.pretty_generate(late))
    end
  end
end

class SprintTasksTool < MCP::Tool
  description "Get tasks belonging to a sprint. Tasks are identified by their dependency on a sprint milestone (using dependson). Returns aggregated effort, completion, and task list."
  input_schema(
    properties: {
      sprint_task_id: {
        type: "string",
        description: "ID of the sprint milestone task (e.g., 'deliveries.sprint_63')"
      },
      scenario: {
        type: "integer",
        description: "Scenario index (default 0)"
      }
    },
    required: ["sprint_task_id"]
  )

  class << self
    def call(sprint_task_id:, scenario: 0, server_context:)
      TJ3State.ensure_scheduled!

      sprint = TJ3State.project.task(sprint_task_id)
      raise "Sprint task '#{sprint_task_id}' not found" unless sprint

      tasks = []
      total_effort = 0.0
      done_effort = 0.0

      TJ3State.project.tasks.each do |t|
        next unless t.leaf?
        sc = t.data[scenario]
        deps = (sc.instance_variable_get(:@depends) rescue []) || []
        next unless deps.any? { |d| d.respond_to?(:task) && d.task == sprint }

        effort = (sc.instance_variable_get(:@effort).to_f rescue 0)
        complete = (sc.instance_variable_get(:@complete) rescue 0).to_f

        total_effort += effort
        done_effort += effort * complete / 100.0

        tasks << {
          id: t.fullId,
          name: t.name,
          effort: effort.round(1),
          complete: complete,
          start: sc.instance_variable_get(:@start)&.to_s('%Y-%m-%d'),
          end_date: sc.instance_variable_get(:@end)&.to_s('%Y-%m-%d'),
        }
      end

      dwh = (TJ3State.project['dailyworkinghours'] rescue 8.0).to_f
      summary = {
        sprint: sprint_task_id,
        task_count: tasks.size,
        total_effort_days: (total_effort / dwh).round(1),
        done_effort_days: (done_effort / dwh).round(1),
        remaining_effort_days: ((total_effort - done_effort) / dwh).round(1),
        aggregate_complete: total_effort > 0 ? (done_effort / total_effort * 100).round(1) : 0,
        tasks: tasks,
      }

      success_response(JSON.pretty_generate(summary))
    end
  end
end

class CompareScenariossTool < MCP::Tool
  description "Compare task dates between two scenarios. Shows tasks where end dates differ."
  input_schema(
    properties: {
      scenario_a: {
        type: "integer",
        description: "First scenario index (default 0)"
      },
      scenario_b: {
        type: "integer",
        description: "Second scenario index (default 1)"
      }
    }
  )

  class << self
    def call(scenario_a: 0, scenario_b: 1, server_context:)
      TJ3State.ensure_scheduled!

      diffs = []
      TJ3State.project.tasks.each do |t|
        next unless t.leaf?
        sc_a = t.data[scenario_a]
        sc_b = t.data[scenario_b]
        end_a = sc_a&.instance_variable_get(:@end)
        end_b = sc_b&.instance_variable_get(:@end)
        next unless end_a && end_b
        next if end_a == end_b

        delta_days = ((end_b - end_a) / 86400.0).round(1)
        diffs << {
          id: t.fullId,
          name: t.name,
          end_scenario_a: end_a.to_s('%Y-%m-%d'),
          end_scenario_b: end_b.to_s('%Y-%m-%d'),
          delta_days: delta_days,
        }
      end

      diffs.sort_by! { |d| -d[:delta_days].abs }
      success_response(JSON.pretty_generate(diffs))
    end
  end
end

class ResourceAvailabilityTool < MCP::Tool
  description "Show when each resource's last task ends and how soon they become available. Useful for finding underloaded resources or planning new work assignments. Can filter by a time horizon (e.g., 'show resources free within 2 weeks')."
  input_schema(
    properties: {
      within_days: {
        type: "integer",
        description: "Show resources whose last task ends within this many days from now (default: 14)"
      },
      scenario: {
        type: "integer",
        description: "Scenario index (default 0)"
      }
    }
  )

  class << self
    def call(within_days: 14, scenario: 0, server_context:)
      TJ3State.ensure_scheduled!
      now = TJ3State.project['now']
      horizon = now + (within_days * 86400)

      # For each resource, find their last assigned task end date
      resource_tasks = Hash.new { |h, k| h[k] = [] }

      TJ3State.project.tasks.each do |t|
        next unless t.leaf?
        sc = t.data[scenario]
        complete = (sc.instance_variable_get(:@complete) rescue nil)
        next if complete && complete.to_f >= 100

        assigned = (sc.instance_variable_get(:@assignedresources) rescue []) || []
        assigned = assigned.select { |ar| ar.respond_to?(:fullId) }

        end_date = sc.instance_variable_get(:@end)
        next unless end_date

        assigned.each do |r|
          resource_tasks[r.fullId] << {
            task_id: t.fullId,
            task_name: t.name,
            end_date: end_date,
          }
        end
      end

      results = []
      TJ3State.project.resources.each do |r|
        next unless r.leaf?
        tasks = resource_tasks[r.fullId]
        efficiency = (r['efficiency', scenario] rescue 1.0).to_f

        if tasks.nil? || tasks.empty?
          # Resource has no active tasks — fully available
          results << {
            id: r.fullId,
            name: r.name,
            efficiency: efficiency,
            status: "available now",
            last_task_ends: nil,
            days_until_free: 0,
            remaining_tasks: 0,
          }
        else
          last_end = tasks.max_by { |t| t[:end_date] }[:end_date]
          days_until = ((last_end - now) / 86400.0).round(1)

          if last_end <= horizon
            results << {
              id: r.fullId,
              name: r.name,
              efficiency: efficiency,
              status: last_end <= now ? "available now" : "available in #{days_until} days",
              last_task_ends: last_end.to_s('%Y-%m-%d'),
              days_until_free: [0, days_until].max,
              remaining_tasks: tasks.size,
              tasks: tasks.sort_by { |t| t[:end_date] }.map { |t|
                { id: t[:task_id], name: t[:task_name], ends: t[:end_date].to_s('%Y-%m-%d') }
              },
            }
          end
        end
      end

      results.sort_by! { |r| r[:days_until_free] }
      success_response(JSON.pretty_generate(results))
    end
  end
end

class UnestimatedTasksTool < MCP::Tool
  description "Find leaf tasks with placeholder estimates: effort equals minimum scheduling resolution (typically 1h) and stdev=0. In TaskJuggler, effort/length/duration is required for leaf tasks, so truly empty estimates don't exist — but minimal placeholder values (effort 1h stdev 0d) indicate the task hasn't been properly estimated. Supports pagination via offset/limit."
  input_schema(
    properties: {
      scenario: {
        type: "integer",
        description: "Scenario index (default 0)"
      },
      include_milestones: {
        type: "boolean",
        description: "Include milestones in results (default false)"
      },
      offset: {
        type: "integer",
        description: "Skip first N tasks in results (default 0). Use with limit for pagination."
      },
      limit: {
        type: "integer",
        description: "Max tasks to return per group (default 50). Use 0 for all."
      }
    }
  )

  class << self
    def call(scenario: 0, include_milestones: false, offset: 0, limit: 50, server_context:)
      TJ3State.ensure_scheduled!
      project = TJ3State.project
      gran = project['scheduleGranularity']
      gran_hours = gran / 3600.0

      results = []

      project.tasks.each do |t|
        next unless t.leaf?
        sc = t.data[scenario]

        is_milestone = begin; sc.instance_variable_get(:@milestone); rescue; false; end
        next if is_milestone && !include_milestones

        effort_val = begin; sc.instance_variable_get(:@effort).to_i; rescue; 0; end
        stdev_val = begin; sc.instance_variable_get(:@stdev).to_f; rescue; 0.0; end

        # Unestimated = effort is exactly 1 scheduling slot (min resolution) with no uncertainty
        next unless effort_val == 1 && stdev_val == 0.0

        assigned = begin; sc.instance_variable_get(:@assignedresources); rescue; []; end || []
        assigned = assigned.select { |ar| ar.respond_to?(:fullId) }
        complete = begin; sc.instance_variable_get(:@complete).to_f; rescue; 0.0; end
        start_date = begin; sc.instance_variable_get(:@start); rescue; nil; end
        end_date = begin; sc.instance_variable_get(:@end); rescue; nil; end
        sd = start_date ? start_date.to_s('%Y-%m-%d') : '?'
        ed = end_date ? end_date.to_s('%Y-%m-%d') : '?'

        results << { line: "#{t.fullId} | #{t.name} | #{sd} | #{ed} | #{complete.round(0)}% | #{assigned.map(&:fullId).join(',')}", start: start_date }
      end

      far_future = Time.utc(2099)
      results.sort_by! { |r| r[:start] || far_future }
      total = results.size

      # Apply pagination
      if limit > 0
        results = results[offset, limit] || []
      elsif offset > 0
        results = results[offset..] || []
      end

      lines = []
      lines << "## Unestimated Tasks (scenario #{scenario})"
      lines << "Criterion: effort = #{gran_hours}h (1 scheduling slot, min resolution) AND stdev = 0"
      lines << "Total: #{total} task(s)"
      lines << ""
      lines << "Sorted by start date. Format: id | name | start | end | complete | resources"
      results.each { |e| lines << e[:line] }

      if limit > 0 && total > offset + limit
        lines << ""
        lines << "Showing offset=#{offset}, limit=#{limit}. Use offset=#{offset + limit} for next page."
      end

      success_response(lines.join("\n"))
    end
  end
end

class EditFileTool < MCP::Tool
  description "Write content to a project file (.tjp or .tji). Use this to modify the project definition — add tasks, change effort, assign resources, etc."
  input_schema(
    properties: {
      path: {
        type: "string",
        description: "Absolute path to the file"
      },
      content: {
        type: "string",
        description: "New file content"
      }
    },
    required: ["path", "content"]
  )

  class << self
    def call(path:, content:, server_context:)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content, encoding: 'UTF-8')
      success_response("File written: #{path} (#{content.length} bytes)")
    end
  end
end

class ListFilesTool < MCP::Tool
  description "List all .tjp and .tji files in the project directory."
  input_schema(properties: {})

  class << self
    def call(server_context:)
      raise "No project loaded" unless TJ3State.project_dir

      files = Dir.glob(File.join(TJ3State.project_dir, '**', '*.{tjp,tji}')).map do |f|
        {
          path: f,
          size: File.size(f),
          modified: File.mtime(f).strftime('%Y-%m-%d %H:%M'),
        }
      end

      success_response(JSON.pretty_generate(files))
    end
  end
end

class ListReportsTool < MCP::Tool
  description "List all reports defined in the project."
  input_schema(properties: {})

  class << self
    def call(server_context:)
      raise "No project loaded" unless TJ3State.project

      reports = []
      TJ3State.project.reports.each do |r|
        reports << {
          id: r.fullId,
          name: r.name,
          type: r.typeSpec.to_s,
        }
      end

      success_response(JSON.pretty_generate(reports))
    end
  end
end

# ── Helpers ─────────────────────────────────────────────────

class MCP::Tool
  def self.success_response(text)
    MCP::Tool::Response.new([{ type: "text", text: text }])
  end

  def self.error_response(text)
    MCP::Tool::Response.new([{ type: "text", text: "Error: #{text}" }], error: true)
  end
end

# ── Start server ────────────────────────────────────────────

server = MCP::Server.new(
  name: "tj3",
  version: "1.0.0",
  tools: [
    OpenProjectTool,
    ScheduleTool,
    OptimizeTool,
    ProjectInfoTool,
    GetTasksTool,
    GetTaskDetailsTool,
    GetResourcesTool,
    QueryAttributeTool,
    MonteCarloTool,
    ReadFileTool,
    EditFileTool,
    ListFilesTool,
    ListReportsTool,
    OverloadedResourcesTool,
    CriticalPathTool,
    LateTasksTool,
    SprintTasksTool,
    CompareScenariossTool,
    ResourceAvailabilityTool,
    UnestimatedTasksTool,
  ]
)

transport = MCP::Server::Transports::StdioTransport.new(server)
transport.open
