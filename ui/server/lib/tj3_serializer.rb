class Tj3Serializer

  def self.project_meta(project)
    scenarios = []
    project.scenarios.each do |s|
      scenarios << { id: s.fullId, name: s.name, index: s.sequenceNo }
    end

    {
      id: project['projectid'],
      name: project['name'],
      start: format_time(project['start']),
      end: format_time(project['end']),
      now: format_time(project['now']),
      currency: project['currency'],
      scenarios: scenarios
    }
  end

  def self.scenarios(project)
    result = []
    project.scenarios.each do |s|
      result << { id: s.fullId, name: s.name, index: s.sequenceNo }
    end
    result
  end

  def self.tasks(project, scenario_idx)
    result = []
    project.tasks.each do |task|
      result << task_hash(task, scenario_idx)
    end
    result
  end

  def self.task(task, scenario_idx)
    task_hash(task, scenario_idx)
  end

  def self.resources(project, scenario_idx)
    result = []
    project.resources.each do |resource|
      result << resource_hash(resource, scenario_idx)
    end
    result
  end

  def self.resource(resource, scenario_idx)
    resource_hash(resource, scenario_idx)
  end

  def self.accounts(project)
    result = []
    project.accounts.each do |account|
      result << account_hash(account)
    end
    result
  end

  def self.reports(project)
    result = []
    project.reports.each do |report|
      result << {
        id: report.fullId,
        name: report.name,
        typeSpec: report.typeSpec.to_s,
        formats: safe_get(report, 'formats')&.map(&:to_s) || []
      }
    end
    result
  end

  def self.gantt_data(project, scenario_idx)
    tasks = []
    project.tasks.each do |task|
      tasks << gantt_task_hash(task, scenario_idx)
    end

    {
      projectStart: format_time(project['start']),
      projectEnd: format_time(project['end']),
      now: format_time(project['now']),
      tasks: tasks
    }
  end

  private

  def self.task_hash(task, scenario_idx)
    {
      id: task.fullId,
      name: task.name,
      parentId: task.parent&.is_a?(TaskJuggler::Task) ? task.parent.fullId : nil,
      children: task.children.select { |c| c.is_a?(TaskJuggler::Task) }.map(&:fullId),
      level: task.level,
      isLeaf: task.leaf?,
      isMilestone: safe_scenario_attr(task, 'milestone', scenario_idx) || false,
      isContainer: task.container?,
      start: format_time(safe_scenario_attr(task, 'start', scenario_idx)),
      end: format_time(safe_scenario_attr(task, 'end', scenario_idx)),
      effort: safe_scenario_attr(task, 'effort', scenario_idx),
      duration: safe_scenario_attr(task, 'duration', scenario_idx),
      complete: safe_scenario_attr(task, 'complete', scenario_idx),
      priority: safe_scenario_attr(task, 'priority', scenario_idx),
      scheduled: safe_scenario_attr(task, 'scheduled', scenario_idx),
      responsible: safe_list_ids(task, 'responsible', scenario_idx),
      assignedResources: safe_list_ids(task, 'assignedresources', scenario_idx),
      depends: serialize_dependencies(safe_scenario_attr(task, 'depends', scenario_idx)),
      precedes: serialize_dependencies(safe_scenario_attr(task, 'precedes', scenario_idx)),
      flags: safe_get(task, 'flags') || [],
      note: safe_get(task, 'note')&.to_s,
      sourceFile: task.sourceFileInfo&.fileName,
      sourceLine: task.sourceFileInfo&.lineNo
    }
  end

  def self.resource_hash(resource, scenario_idx)
    {
      id: resource.fullId,
      name: resource.name,
      parentId: resource.parent&.is_a?(TaskJuggler::Resource) ? resource.parent.fullId : nil,
      children: resource.children.select { |c| c.is_a?(TaskJuggler::Resource) }.map(&:fullId),
      level: resource.level,
      isLeaf: resource.leaf?,
      email: safe_get(resource, 'email'),
      efficiency: safe_scenario_attr(resource, 'efficiency', scenario_idx),
      rate: safe_scenario_attr(resource, 'rate', scenario_idx),
      sourceFile: resource.sourceFileInfo&.fileName,
      sourceLine: resource.sourceFileInfo&.lineNo
    }
  end

  def self.account_hash(account)
    {
      id: account.fullId,
      name: account.name,
      parentId: account.parent&.is_a?(TaskJuggler::Account) ? account.parent.fullId : nil,
      children: account.children.select { |c| c.is_a?(TaskJuggler::Account) }.map(&:fullId),
      level: account.level,
      isLeaf: account.leaf?,
      sourceFile: account.sourceFileInfo&.fileName,
      sourceLine: account.sourceFileInfo&.lineNo
    }
  end

  def self.gantt_task_hash(task, scenario_idx)
    deps = safe_scenario_attr(task, 'depends', scenario_idx) || []
    dependencies = deps.map do |dep|
      {
        fromTaskId: task.fullId,
        toTaskId: dep.respond_to?(:task) ? dep.task&.fullId : nil,
        onEnd: dep.respond_to?(:onEnd) ? dep.onEnd : true
      }
    end.compact

    {
      taskId: task.fullId,
      name: task.name,
      level: task.level,
      isMilestone: safe_scenario_attr(task, 'milestone', scenario_idx) || false,
      isContainer: task.container?,
      start: format_time(safe_scenario_attr(task, 'start', scenario_idx)),
      end: format_time(safe_scenario_attr(task, 'end', scenario_idx)),
      complete: safe_scenario_attr(task, 'complete', scenario_idx) || 0,
      dependencies: dependencies,
      assignedResources: safe_list_ids(task, 'assignedresources', scenario_idx)
    }
  end

  def self.serialize_dependencies(deps)
    return [] unless deps.is_a?(Array)
    deps.map do |dep|
      {
        taskId: dep.respond_to?(:task) ? dep.task&.fullId : nil,
        onEnd: dep.respond_to?(:onEnd) ? dep.onEnd : true,
        gapDuration: dep.respond_to?(:gapDuration) ? dep.gapDuration : 0,
        gapLength: dep.respond_to?(:gapLength) ? dep.gapLength : 0
      }
    end
  end

  def self.safe_scenario_attr(property, attr, scenario_idx)
    property[attr, scenario_idx]
  rescue => e
    nil
  end

  def self.safe_get(property, attr)
    property.get(attr)
  rescue
    nil
  end

  def self.safe_list_ids(property, attr, scenario_idx)
    val = safe_scenario_attr(property, attr, scenario_idx)
    return [] unless val.is_a?(Array)
    val.map { |v| v.respond_to?(:fullId) ? v.fullId : v.to_s }
  end

  def self.format_time(time)
    return nil unless time
    time.respond_to?(:to_s) ? time.to_s('%Y-%m-%dT%H:%M:%S') : time.to_s
  end
end
