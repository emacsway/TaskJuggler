require 'base64'
require 'taskjuggler/TaskJuggler'
require 'taskjuggler/MessageHandler'
require 'taskjuggler/Query'
require 'taskjuggler/Log'

class Tj3Session
  attr_reader :id, :project_dir, :state, :project

  def initialize(id, project_dir)
    @id = id
    @project_dir = project_dir
    @state = :empty
    @tj = nil
    @project = nil
    @messages = []
  end

  def to_h
    {
      id: @id,
      state: @state.to_s,
      projectDir: @project_dir,
      errors: @messages.count { |m| m[:type] == 'error' },
      warnings: @messages.count { |m| m[:type] == 'warning' }
    }
  end

  def parsed?
    @state == :parsed || @state == :scheduled
  end

  def scheduled?
    @state == :scheduled
  end

  # ── File operations ───────────────────────────────────────────

  def list_files
    # Scan project directory
    tjp_files = Dir.glob(File.join(@project_dir, '**', '*.tjp'))
    tji_files = Dir.glob(File.join(@project_dir, '**', '*.tji'))
    all_files = (tjp_files + tji_files).to_set

    # After parse, also include files the engine discovered (may be outside project dir)
    if @project
      @project.sourceFiles.each do |abs|
        all_files.add(abs) if abs.is_a?(String) && File.exist?(abs)
      end rescue nil
    end

    all_files.map do |f|
      {
        path: f,  # absolute path — backend file API handles both
        isMaster: File.extname(f) == '.tjp',
        size: File.size(f),
        modified: File.mtime(f).iso8601
      }
    end
  end

  def read_file(path)
    # Accept both absolute paths and paths relative to project dir
    full = if path.start_with?('/')
             path
           else
             File.join(@project_dir, path)
           end
    return nil unless File.exist?(full)
    File.read(full, encoding: 'UTF-8')
  end

  def write_file(path, content)
    full = if path.start_with?('/')
             path
           else
             File.join(@project_dir, path)
           end
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content, encoding: 'UTF-8')
  end

  def delete_file(path)
    full = File.join(@project_dir, path)
    File.delete(full) if File.exist?(full)
  end

  # ── Engine operations ─────────────────────────────────────────

  def parse(master_file)
    @tj = ::TaskJuggler.new
    TaskJuggler::Log.silent = true

    MessageCollector.clear

    master_path = File.join(@project_dir, master_file)
    success = @tj.parse([master_path])

    @messages = MessageCollector.collect
    if success
      @project = @tj.project
      @state = :parsed
      Tj3Serializer.project_dir = @project_dir
    else
      @state = :error
    end

    { success: success, state: @state.to_s, messages: @messages }
  end

  def schedule
    return { success: false, error: 'Project not parsed' } unless parsed?

    MessageCollector.clear
    success = @tj.schedule

    @messages += MessageCollector.collect
    @state = success ? :scheduled : :error

    { success: success, state: @state.to_s, messages: @messages }
  end

  def optimize(options = {})
    return { success: false, error: 'Project not parsed' } unless parsed?

    MessageCollector.clear
    success = @tj.optimize(options)

    @messages += MessageCollector.collect
    @state = success ? :scheduled : :error

    { success: success, state: @state.to_s, messages: @messages, mode: 'optimizer' }
  end

  def monte_carlo(num_runs: 20, timeout: 60)
    return { error: 'Project not scheduled' } unless scheduled?

    require 'taskjuggler/CpSatScheduler'
    optimizer = TaskJuggler::CpSatScheduler.new(@project, 0, timeout: timeout)
    result = optimizer.monte_carlo(num_runs: num_runs)
    result || { error: 'Monte Carlo failed' }
  end

  def schedule_with_progress(&block)
    return unless parsed?

    MessageCollector.clear

    # Report start
    block.call({ event: 'progress', data: { phase: 'scheduling', percent: 0 } })

    success = @tj.schedule

    @messages += MessageCollector.collect
    @state = success ? :scheduled : :error

    block.call({
      event: 'complete',
      data: {
        success: success,
        state: @state.to_s,
        errors: @messages.count { |m| m[:type] == 'error' },
        warnings: @messages.count { |m| m[:type] == 'warning' }
      }
    })
  end

  def messages
    @messages
  end

  # ── Query ─────────────────────────────────────────────────────

  def execute_query(params)
    property_type = params['propertyType']
    property_id = params['propertyId']
    attribute_id = params['attributeId']
    scenario_idx = (params['scenarioIdx'] || 0).to_i

    property = case property_type
               when 'Task' then @project.task(property_id)
               when 'Resource' then @project.resource(property_id)
               when 'Account' then @project.account(property_id)
               end

    return { ok: false, error: "#{property_type} '#{property_id}' not found" } unless property

    query = TaskJuggler::Query.new(
      'project' => @project,
      'property' => property,
      'propertyType' => property_type.to_sym,
      'attributeId' => attribute_id,
      'scenarioIdx' => scenario_idx,
      'start' => @project['start'],
      'end' => @project['end'],
      'loadUnit' => :days,
      'numberFormat' => @project['numberFormat'],
      'timeFormat' => '%Y-%m-%d %H:%M'
    )

    query.process

    if query.ok
      { ok: true, string: query.to_s, numerical: safe_to_num(query) }
    else
      { ok: false, error: query.errorMessage }
    end
  end

  # ── Reports ───────────────────────────────────────────────────

  def generate_report(report_id, format = 'html')
    report = @project.report(report_id)
    return { ok: false, error: "Report '#{report_id}' not found" } unless report

    output_dir = File.join(@project_dir, '.tj3ui_reports')
    FileUtils.mkdir_p(output_dir)
    @project.outputDir = output_dir + '/'

    # Clean previous output so we can identify the newly generated file
    old_files = Dir.glob(File.join(output_dir, "*.#{format}")).to_set

    success = @tj.generateReport(report_id, false, [format.to_sym])

    if success
      # Find the newly created file
      new_files = Dir.glob(File.join(output_dir, "*.#{format}"))
      html_file = new_files.find { |f| !old_files.include?(f) }

      # Fallback: match by report name (TJ3 uses name as filename)
      html_file ||= new_files.find { |f| File.basename(f, ".#{format}") == report.name }

      # Last resort: newest file by mtime
      html_file ||= new_files.max_by { |f| File.mtime(f) }

      content = html_file ? File.read(html_file, encoding: 'UTF-8') : nil

      # Inline CSS: replace <link> to external CSS with embedded <style>
      if content && format == 'html'
        content = inline_css(content)
        content = inline_images(content)
      end

      { ok: true, reportId: report_id, format: format, content: content }
    else
      { ok: false, error: 'Report generation failed', messages: MessageCollector.collect }
    end
  end

  private

  def relative_path(full_path)
    full_path.sub("#{@project_dir}/", '')
  end

  def safe_to_num(query)
    query.to_num
  rescue
    nil
  end

  # Replace <link rel="stylesheet" href="...tjreport.css"> with inline <style>
  def inline_css(html)
    # TJ3 root is 3 levels up from ui/server/lib/
    tj3_root = File.expand_path('../../..', File.dirname(__FILE__))
    css_path = File.join(tj3_root, 'data', 'css', 'tjreport.css')

    unless File.exist?(css_path)
      # Fallback: look in the report output directory
      css_path = File.join(@project_dir, '.tj3ui_reports', 'css', 'tjreport.css')
    end

    return html unless File.exist?(css_path)

    css_content = File.read(css_path, encoding: 'UTF-8')
    html.sub(/<link[^>]*tjreport\.css[^>]*>/, "<style>\n#{css_content}\n</style>")
  end

  # Replace relative image src with inline base64 data URIs
  def inline_images(html)
    tj3_root = File.expand_path('../../..', File.dirname(__FILE__))
    report_dir = File.join(@project_dir, '.tj3ui_reports')

    html.gsub(/(<img\s[^>]*?)src="([^"]+)"/) do |match|
      prefix = $1
      src = $2

      # Skip already-inlined or absolute URLs
      next match if src.start_with?('data:') || src.start_with?('http')

      # Try to find the image file
      img_path = nil
      [report_dir, tj3_root, File.join(tj3_root, 'data')].each do |base|
        candidate = File.join(base, src)
        if File.exist?(candidate)
          img_path = candidate
          break
        end
      end

      if img_path
        ext = File.extname(img_path).delete('.').downcase
        mime = case ext
               when 'png' then 'image/png'
               when 'jpg', 'jpeg' then 'image/jpeg'
               when 'gif' then 'image/gif'
               when 'svg' then 'image/svg+xml'
               else 'application/octet-stream'
               end
        data = Base64.strict_encode64(File.binread(img_path))
        "#{prefix}src=\"data:#{mime};base64,#{data}\""
      else
        match
      end
    end
  end
end
