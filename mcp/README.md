# TaskJuggler 3 MCP Server

An [MCP (Model Context Protocol)](https://modelcontextprotocol.io/) server that exposes the TaskJuggler 3 engine to AI assistants. Allows Claude, GPT, and other MCP-compatible clients to load, schedule, query, and edit TJ3 projects through natural language.

## Prerequisites

- Ruby (same version used to run TaskJuggler)
- The `mcp` gem:
  ```
  gem install mcp
  ```
- For optimization features: the `or-tools` gem:
  ```
  gem install or-tools
  ```

## Setup

### Claude Code

Add `.mcp.json` to your project root (or TaskJuggler repo root):

```json
{
  "mcpServers": {
    "tj3": {
      "command": "ruby",
      "args": ["/path/to/TaskJuggler/mcp/tj3_mcp_server.rb"]
    }
  }
}
```

Then restart Claude Code. The server starts automatically via stdio transport.

### Claude Desktop

Add to `claude_desktop_config.json` (`~/.config/Claude/` on Linux, `~/Library/Application Support/Claude/` on macOS):

```json
{
  "mcpServers": {
    "tj3": {
      "command": "ruby",
      "args": ["/path/to/TaskJuggler/mcp/tj3_mcp_server.rb"]
    }
  }
}
```

### Other MCP clients

The server uses stdio transport (JSON-RPC over stdin/stdout). Launch with:
```
ruby /path/to/TaskJuggler/mcp/tj3_mcp_server.rb
```

## Usage

Talk to your AI assistant in natural language. The typical workflow:

1. **Load a project**: "Open project /path/to/index.tjp"
2. **Schedule it**: "Schedule the project" (standard scheduler) or "Optimize the project" (CP-SAT)
3. **Query**: "Show all tasks", "What are the critical path tasks?", "Who is overloaded?"

### Example prompts

```
Load project /home/user/myproject/index.tjp and schedule it

Show me overdue tasks in the fact scenario

Which resources are becoming available in the next 2 weeks?

What tasks depend on sprint_42?

Show unestimated tasks (placeholder effort)

Compare plan vs fact scenario — what shifted?

Run Monte Carlo simulation with 500 iterations

What is the effort for task MVP_1234?

Show the critical path
```

## Tools

### Project lifecycle

| Tool | Description |
|------|-------------|
| `open_project` | Parse a .tjp project file |
| `schedule` | Run standard TJ3 heuristic scheduler |
| `optimize` | Schedule with CP-SAT optimizer (or-tools) |
| `project_info` | Project metadata: name, dates, scenarios, counts |

### Querying tasks and resources

| Tool | Description |
|------|-------------|
| `get_tasks` | List tasks, optionally filtered by name/ID |
| `get_task_details` | Detailed info for a specific task |
| `get_resources` | List all resources |
| `query_attribute` | Query any attribute via TJ3 Query engine |
| `list_reports` | List all defined reports |

### Analysis

| Tool | Description |
|------|-------------|
| `critical_path` | Tasks with highest pathcriticalness (bottlenecks) |
| `late_tasks` | Overdue or at-risk tasks |
| `overloaded_resources` | Resources allocated beyond capacity |
| `resource_availability` | Resources becoming free within N days |
| `unestimated_tasks` | Tasks with placeholder effort (1h, stdev=0) |
| `sprint_tasks` | Tasks belonging to a sprint (via `dependson`) |
| `compare_scenarios` | Diff task dates between two scenarios |
| `monte_carlo` | Monte Carlo simulation for schedule uncertainty |

### File operations

| Tool | Description |
|------|-------------|
| `read_file` | Read a .tjp/.tji file |
| `edit_file` | Write/modify a project file |
| `list_files` | List all .tjp/.tji files in the project |

## Architecture

```
AI Client (Claude Code, Claude Desktop, etc.)
    │
    │  stdio (JSON-RPC)
    │
    ▼
tj3_mcp_server.rb
    │
    │  Ruby API
    │
    ▼
TaskJuggler 3 Engine
    │
    ├── Parser (.tjp/.tji)
    ├── Scheduler (heuristic)
    ├── CP-SAT Optimizer (or-tools)
    └── Query Engine
```

The server maintains a singleton project state (`TJ3State`). One project can be loaded at a time. Loading a new project replaces the previous one.

## Notes

- The project must be scheduled (or optimized) before querying task attributes, running analysis, or using Monte Carlo.
- Scenario indices: typically `0` = plan, `1` = fact. Use `project_info` to see available scenarios.
- The `unestimated_tasks` tool detects placeholder estimates (effort = 1 scheduling slot with stdev = 0). In TJ3, all leaf tasks must have effort/length/duration, so truly empty estimates don't exist.
- Large result sets are paginated (default 50 items) to stay within context window limits.
- Error messages from the TJ3 engine are forwarded to the AI client for diagnosis.
