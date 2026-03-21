# TaskJuggler 3 UI

A cross-platform web-based UI for [TaskJuggler 3](http://www.taskjuggler.org) project management software.

## Architecture

```
Angular SPA (frontend)  <──HTTP/JSON──>  Sinatra (backend)  ──>  TJ3 Engine (Ruby)
```

- **Frontend**: Angular 19 + TypeScript + CodeMirror 6 (editor) + custom Gantt chart
- **Backend**: Sinatra REST API wrapping the TJ3 scheduling engine
- **Layout**: VS Code-inspired dark theme with split panels

## Prerequisites

- **Ruby** >= 2.0 (tested with 3.2)
- **Bundler** (`gem install bundler`)
- **Node.js** >= 18
- **npm** >= 9

## Quick Start

### 1. Install dependencies

```bash
# Ruby backend
cd ui/server
bundle install

# Angular frontend
cd ../angular
npm install
```

### 2. Start the backend

```bash
cd ui/server
bundle exec rackup -p 4567
```

The API will be available at `http://localhost:4567/api`.

### 3. Start the frontend

In a separate terminal:

```bash
cd ui/angular
npx ng serve
```

Open `http://localhost:4200` in your browser.

### 4. Use the application

1. Enter the path to a TJ3 project directory in the toolbar (e.g. the included example: the absolute path to `examples/Tutorial`)
2. Click **Open**
3. Click on a `.tjp` file in the Files panel to view/edit it
4. Click **Parse & Schedule** to run the TJ3 engine
5. Switch between **Editor**, **Gantt**, and **Reports** tabs in the right panel
6. Errors and warnings appear in the bottom **Problems** panel — click to navigate to source

## Project Structure

```
ui/
  server/                        # Ruby HTTP backend
    app.rb                       # Sinatra REST API routes
    config.ru                    # Rack config
    Gemfile                      # Ruby dependencies
    lib/
      tj3_session.rb             # TJ3 engine wrapper (parse/schedule/query)
      tj3_serializer.rb          # PropertyTreeNode -> JSON serialization
      message_collector.rb       # Error/warning collection with file:line info

  angular/                       # Angular 19 frontend
    src/app/
      core/
        backend/
          backend.interface.ts   # Abstract TjBackend (swappable)
          http-backend.service.ts# HTTP implementation
        models/                  # TypeScript interfaces (Task, Resource, etc.)
        state/                   # Angular Signals state management
      features/
        toolbar/                 # Project open, parse, schedule controls
        file-explorer/           # .tjp/.tji file tree
        editor/                  # CodeMirror 6 with TJP syntax highlighting
        tree-views/              # Task and Resource hierarchical trees
        gantt/                   # Gantt chart (bars, milestones, now-line)
        report-viewer/           # HTML report renderer
        messages/                # Error/warning panel with source navigation
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/sessions` | Create project session (`{"projectDir": "..."}`) |
| GET | `/api/sessions/:id/files` | List .tjp/.tji files |
| GET | `/api/sessions/:id/files/*path` | Read file content |
| PUT | `/api/sessions/:id/files/*path` | Update file content |
| POST | `/api/sessions/:id/parse` | Parse project (`{"masterFile": "project.tjp"}`) |
| POST | `/api/sessions/:id/schedule` | Schedule project |
| GET | `/api/sessions/:id/project` | Project metadata |
| GET | `/api/sessions/:id/tasks` | Task tree (with `?scenario=plan`) |
| GET | `/api/sessions/:id/resources` | Resource tree |
| GET | `/api/sessions/:id/accounts` | Account tree |
| GET | `/api/sessions/:id/gantt` | Gantt chart data |
| GET | `/api/sessions/:id/reports` | List defined reports |
| POST | `/api/sessions/:id/reports/:rid/generate` | Generate report HTML |
| GET | `/api/sessions/:id/messages` | Errors/warnings with file:line |
| POST | `/api/sessions/:id/query` | Flexible attribute query |

## Swappable Backend

The frontend communicates through an abstract `TjBackend` interface. The current implementation uses HTTP, but the architecture supports:

- **Phase 1** (current): `HttpBackendService` — Sinatra server on localhost
- **Phase 2** (planned): `WasmBackendService` — ruby.wasm, runs entirely in the browser
- **Phase 3** (planned): Tauri desktop wrapper with Ruby sidecar

## License

GPL-2.0 (same as TaskJuggler)
