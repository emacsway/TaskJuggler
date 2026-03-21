require 'sinatra/base'
require 'sinatra/json'
require 'rack/cors'
require 'securerandom'
require 'json'

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'taskjuggler/TaskJuggler'
require 'taskjuggler/MessageHandler'
require 'taskjuggler/Query'

require_relative 'lib/tj3_session'
require_relative 'lib/tj3_serializer'
require_relative 'lib/message_collector'

class Tj3App < Sinatra::Base
  use Rack::Cors do
    allow do
      origins '*'
      resource '/api/*', headers: :any, methods: [:get, :post, :put, :delete, :options]
    end
  end

  configure do
    set :sessions_store, {}
    set :show_exceptions, false
  end

  before '/api/*' do
    content_type :json
  end

  helpers do
    def sessions
      settings.sessions_store
    end

    def find_session!(id)
      session = sessions[id]
      halt 404, json(error: "Session '#{id}' not found") unless session
      session
    end

    def request_json
      return {} if request.body.nil?
      body = request.body.read
      body.empty? ? {} : JSON.parse(body)
    rescue JSON::ParserError
      halt 400, json(error: 'Invalid JSON')
    end
  end

  # ── Session management ──────────────────────────────────────────

  # Create a new project session
  post '/api/sessions' do
    data = request_json
    project_dir = data['projectDir']
    halt 400, json(error: 'projectDir is required') unless project_dir
    halt 400, json(error: "Directory not found: #{project_dir}") unless File.directory?(project_dir)

    id = SecureRandom.hex(8)
    sessions[id] = Tj3Session.new(id, project_dir)
    json(id: id, state: 'empty', projectDir: project_dir)
  end

  # Get session state
  get '/api/sessions/:id' do
    session = find_session!(params[:id])
    json session.to_h
  end

  # List all sessions
  get '/api/sessions' do
    json sessions.map { |id, s| s.to_h }
  end

  # Destroy session
  delete '/api/sessions/:id' do
    sessions.delete(params[:id])
    json(ok: true)
  end

  # ── File management ─────────────────────────────────────────────

  # List project files
  get '/api/sessions/:id/files' do
    session = find_session!(params[:id])
    json session.list_files
  end

  # Read file content
  get '/api/sessions/:id/files/*' do
    session = find_session!(params[:id])
    path = params['splat'].join('/')
    content = session.read_file(path)
    halt 404, json(error: "File not found: #{path}") if content.nil?
    json(path: path, content: content)
  end

  # Write/update file content
  put '/api/sessions/:id/files/*' do
    session = find_session!(params[:id])
    path = params['splat'].join('/')
    data = request_json
    halt 400, json(error: 'content is required') unless data['content']
    session.write_file(path, data['content'])
    json(path: path, ok: true)
  end

  # Create new file
  post '/api/sessions/:id/files' do
    session = find_session!(params[:id])
    data = request_json
    halt 400, json(error: 'path and content are required') unless data['path'] && data['content']
    session.write_file(data['path'], data['content'])
    json(path: data['path'], ok: true)
  end

  # Delete file
  delete '/api/sessions/:id/files/*' do
    session = find_session!(params[:id])
    path = params['splat'].join('/')
    session.delete_file(path)
    json(ok: true)
  end

  # ── Engine operations ───────────────────────────────────────────

  # Parse project files
  post '/api/sessions/:id/parse' do
    session = find_session!(params[:id])
    data = request_json
    master_file = data['masterFile']
    halt 400, json(error: 'masterFile is required') unless master_file

    result = session.parse(master_file)
    json result
  end

  # Schedule project
  post '/api/sessions/:id/schedule' do
    session = find_session!(params[:id])
    result = session.schedule
    json result
  end

  # SSE stream for scheduling progress
  get '/api/sessions/:id/schedule/stream' do
    session = find_session!(params[:id])
    content_type 'text/event-stream'
    cache_control :no_cache

    stream(:keep_open) do |out|
      session.schedule_with_progress do |event|
        out << "event: #{event[:event]}\ndata: #{event[:data].to_json}\n\n"
        out.close if event[:event] == 'complete'
      end
    end
  end

  # Get messages (errors/warnings)
  get '/api/sessions/:id/messages' do
    session = find_session!(params[:id])
    json session.messages
  end

  # ── Project data queries ────────────────────────────────────────

  # Project metadata
  get '/api/sessions/:id/project' do
    session = find_session!(params[:id])
    halt 409, json(error: 'Project not scheduled yet') unless session.scheduled?
    json Tj3Serializer.project_meta(session.project)
  end

  # Tasks
  get '/api/sessions/:id/tasks' do
    session = find_session!(params[:id])
    halt 409, json(error: 'Project not scheduled yet') unless session.scheduled?
    scenario = params[:scenario] || 0
    scenario_idx = resolve_scenario(session.project, scenario)
    json Tj3Serializer.tasks(session.project, scenario_idx)
  end

  # Single task
  get '/api/sessions/:id/tasks/:task_id' do
    session = find_session!(params[:id])
    halt 409, json(error: 'Project not scheduled yet') unless session.scheduled?
    scenario_idx = resolve_scenario(session.project, params[:scenario] || 0)
    task = session.project.task(params[:task_id])
    halt 404, json(error: "Task not found: #{params[:task_id]}") unless task
    json Tj3Serializer.task(task, scenario_idx)
  end

  # Resources
  get '/api/sessions/:id/resources' do
    session = find_session!(params[:id])
    halt 409, json(error: 'Project not scheduled yet') unless session.scheduled?
    scenario_idx = resolve_scenario(session.project, params[:scenario] || 0)
    json Tj3Serializer.resources(session.project, scenario_idx)
  end

  # Single resource
  get '/api/sessions/:id/resources/:res_id' do
    session = find_session!(params[:id])
    halt 409, json(error: 'Project not scheduled yet') unless session.scheduled?
    scenario_idx = resolve_scenario(session.project, params[:scenario] || 0)
    resource = session.project.resource(params[:res_id])
    halt 404, json(error: "Resource not found: #{params[:res_id]}") unless resource
    json Tj3Serializer.resource(resource, scenario_idx)
  end

  # Accounts
  get '/api/sessions/:id/accounts' do
    session = find_session!(params[:id])
    halt 409, json(error: 'Project not scheduled yet') unless session.scheduled?
    json Tj3Serializer.accounts(session.project)
  end

  # Scenarios
  get '/api/sessions/:id/scenarios' do
    session = find_session!(params[:id])
    halt 409, json(error: 'Project not parsed yet') unless session.parsed? || session.scheduled?
    json Tj3Serializer.scenarios(session.project)
  end

  # Gantt data
  get '/api/sessions/:id/gantt' do
    session = find_session!(params[:id])
    halt 409, json(error: 'Project not scheduled yet') unless session.scheduled?
    scenario_idx = resolve_scenario(session.project, params[:scenario] || 0)
    json Tj3Serializer.gantt_data(session.project, scenario_idx)
  end

  # Flexible query
  post '/api/sessions/:id/query' do
    session = find_session!(params[:id])
    halt 409, json(error: 'Project not scheduled yet') unless session.scheduled?
    data = request_json
    result = session.execute_query(data)
    json result
  end

  # ── Reports ─────────────────────────────────────────────────────

  # List reports
  get '/api/sessions/:id/reports' do
    session = find_session!(params[:id])
    halt 409, json(error: 'Project not parsed yet') unless session.parsed? || session.scheduled?
    json Tj3Serializer.reports(session.project)
  end

  # Generate report
  post '/api/sessions/:id/reports/:report_id/generate' do
    session = find_session!(params[:id])
    halt 409, json(error: 'Project not scheduled yet') unless session.scheduled?
    data = request_json
    format = data['format'] || 'html'
    result = session.generate_report(params[:report_id], format)
    json result
  end

  # ── Error handling ──────────────────────────────────────────────

  error do
    json(error: env['sinatra.error'].message)
  end

  not_found do
    json(error: 'Not found')
  end

  private

  def resolve_scenario(project, scenario)
    return scenario.to_i if scenario.is_a?(Integer) || scenario =~ /\A\d+\z/
    idx = project.scenarioIdx(scenario.to_s)
    halt 400, json(error: "Unknown scenario: #{scenario}") unless idx
    idx
  end
end
