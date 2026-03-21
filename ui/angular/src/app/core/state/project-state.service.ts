import { Injectable, signal, computed } from '@angular/core';
import { TjBackend, ParseResult, ScheduleResult } from '../backend/backend.interface';
import {
  SessionState,
  ProjectMeta,
  Task,
  Resource,
  Account,
  Scenario,
  DiagnosticMessage,
  ReportDefinition,
  ProjectFile,
  GanttData,
} from '../models';

@Injectable({ providedIn: 'root' })
export class ProjectStateService {
  readonly sessionId = signal<string | null>(null);
  readonly sessionState = signal<SessionState>('empty');
  readonly projectMeta = signal<ProjectMeta | null>(null);
  readonly tasks = signal<Task[]>([]);
  readonly resources = signal<Resource[]>([]);
  readonly accounts = signal<Account[]>([]);
  readonly scenarios = signal<Scenario[]>([]);
  readonly messages = signal<DiagnosticMessage[]>([]);
  readonly reports = signal<ReportDefinition[]>([]);
  readonly projectFiles = signal<ProjectFile[]>([]);
  readonly ganttData = signal<GanttData | null>(null);
  readonly loading = signal(false);

  readonly errors = computed(() => this.messages().filter((m) => m.type === 'error'));
  readonly warnings = computed(() => this.messages().filter((m) => m.type === 'warning'));
  readonly isParsed = computed(() => ['parsed', 'scheduled'].includes(this.sessionState()));
  readonly isScheduled = computed(() => this.sessionState() === 'scheduled');

  constructor(private backend: TjBackend) {}

  async openProject(projectDir: string): Promise<void> {
    this.loading.set(true);
    try {
      const session = await firstValue(this.backend.createSession(projectDir));
      this.sessionId.set(session.id);
      this.sessionState.set(session.state);

      const files = await firstValue(this.backend.listFiles(session.id));
      this.projectFiles.set(files);
    } finally {
      this.loading.set(false);
    }
  }

  async parse(masterFile: string): Promise<ParseResult> {
    const sid = this.sessionId();
    if (!sid) throw new Error('No active session');

    this.loading.set(true);
    try {
      const result = await firstValue(this.backend.parse(sid, masterFile));
      this.sessionState.set(result.state as SessionState);
      this.messages.set(result.messages);

      if (result.success) {
        const [scenarios, reports, files] = await Promise.all([
          firstValue(this.backend.getScenarios(sid)),
          firstValue(this.backend.listReports(sid)),
          firstValue(this.backend.listFiles(sid)),
        ]);
        this.scenarios.set(scenarios);
        this.reports.set(reports);
        this.projectFiles.set(files);
      }

      return result;
    } finally {
      this.loading.set(false);
    }
  }

  async schedule(): Promise<ScheduleResult> {
    const sid = this.sessionId();
    if (!sid) throw new Error('No active session');

    this.loading.set(true);
    try {
      const result = await firstValue(this.backend.schedule(sid));
      this.sessionState.set(result.state as SessionState);
      this.messages.set(result.messages);

      if (result.success) {
        await this.loadProjectData();
      }

      return result;
    } finally {
      this.loading.set(false);
    }
  }

  async loadProjectData(scenario?: string): Promise<void> {
    const sid = this.sessionId();
    if (!sid) return;

    const [meta, tasks, resources, accounts, gantt] = await Promise.all([
      firstValue(this.backend.getProjectMeta(sid)),
      firstValue(this.backend.getTasks(sid, scenario)),
      firstValue(this.backend.getResources(sid, scenario)),
      firstValue(this.backend.getAccounts(sid)),
      firstValue(this.backend.getGanttData(sid, scenario)),
    ]);

    this.projectMeta.set(meta);
    this.tasks.set(tasks);
    this.resources.set(resources);
    this.accounts.set(accounts);
    this.ganttData.set(gantt);
  }

  reset(): void {
    this.sessionId.set(null);
    this.sessionState.set('empty');
    this.projectMeta.set(null);
    this.tasks.set([]);
    this.resources.set([]);
    this.accounts.set([]);
    this.scenarios.set([]);
    this.messages.set([]);
    this.reports.set([]);
    this.projectFiles.set([]);
    this.ganttData.set(null);
  }
}

function firstValue<T>(obs: import('rxjs').Observable<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    obs.subscribe({ next: resolve, error: reject });
  });
}
