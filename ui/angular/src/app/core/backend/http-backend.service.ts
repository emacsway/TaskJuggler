import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, map } from 'rxjs';
import { environment } from '../../../environments/environment';
import {
  SessionInfo,
  ProjectMeta,
  Scenario,
  Task,
  Resource,
  Account,
  GanttData,
  DiagnosticMessage,
  ReportDefinition,
  ReportOutput,
  ProjectFile,
} from '../models';
import {
  TjBackend,
  ParseResult,
  ScheduleResult,
  ScheduleProgress,
  QueryRequest,
  QueryResult,
  SyntaxData,
} from './backend.interface';

@Injectable({ providedIn: 'root' })
export class HttpBackendService extends TjBackend {
  private baseUrl = environment.apiUrl;

  constructor(private http: HttpClient) {
    super();
  }

  // ── Session lifecycle ──────────────────────────────────────

  createSession(projectDir: string): Observable<SessionInfo> {
    return this.http.post<SessionInfo>(`${this.baseUrl}/sessions`, { projectDir });
  }

  getSession(sessionId: string): Observable<SessionInfo> {
    return this.http.get<SessionInfo>(`${this.baseUrl}/sessions/${sessionId}`);
  }

  destroySession(sessionId: string): Observable<void> {
    return this.http.delete<void>(`${this.baseUrl}/sessions/${sessionId}`);
  }

  // ── File operations ────────────────────────────────────────

  listFiles(sessionId: string): Observable<ProjectFile[]> {
    return this.http.get<ProjectFile[]>(`${this.baseUrl}/sessions/${sessionId}/files`);
  }

  readFile(sessionId: string, path: string): Observable<string> {
    return this.http
      .get<{ path: string; content: string }>(`${this.baseUrl}/sessions/${sessionId}/file`, {
        params: { path },
      })
      .pipe(map((r) => r.content));
  }

  writeFile(sessionId: string, path: string, content: string): Observable<void> {
    return this.http.put<void>(`${this.baseUrl}/sessions/${sessionId}/file`, { content }, {
      params: { path },
    });
  }

  createFile(sessionId: string, path: string, content: string): Observable<void> {
    return this.http.post<void>(`${this.baseUrl}/sessions/${sessionId}/files`, { path, content });
  }

  deleteFile(sessionId: string, path: string): Observable<void> {
    return this.http.delete<void>(`${this.baseUrl}/sessions/${sessionId}/files/${path}`);
  }

  // ── Engine operations ──────────────────────────────────────

  parse(sessionId: string, masterFile: string): Observable<ParseResult> {
    return this.http.post<ParseResult>(`${this.baseUrl}/sessions/${sessionId}/parse`, { masterFile });
  }

  schedule(sessionId: string): Observable<ScheduleResult> {
    return this.http.post<ScheduleResult>(`${this.baseUrl}/sessions/${sessionId}/schedule`, {});
  }

  scheduleWithProgress(sessionId: string): Observable<ScheduleProgress> {
    return new Observable<ScheduleProgress>((subscriber) => {
      const eventSource = new EventSource(
        `${this.baseUrl}/sessions/${sessionId}/schedule/stream`
      );

      eventSource.addEventListener('progress', (event: MessageEvent) => {
        subscriber.next(JSON.parse(event.data));
      });

      eventSource.addEventListener('complete', (event: MessageEvent) => {
        subscriber.next({ phase: 'complete', percent: 100, ...JSON.parse(event.data) });
        subscriber.complete();
        eventSource.close();
      });

      eventSource.onerror = () => {
        subscriber.error(new Error('SSE connection lost'));
        eventSource.close();
      };

      return () => eventSource.close();
    });
  }

  getMessages(sessionId: string): Observable<DiagnosticMessage[]> {
    return this.http.get<DiagnosticMessage[]>(`${this.baseUrl}/sessions/${sessionId}/messages`);
  }

  // ── Data queries ───────────────────────────────────────────

  getProjectMeta(sessionId: string): Observable<ProjectMeta> {
    return this.http.get<ProjectMeta>(`${this.baseUrl}/sessions/${sessionId}/project`);
  }

  getTasks(sessionId: string, scenario?: string): Observable<Task[]> {
    const params: Record<string, string> = {};
    if (scenario) params['scenario'] = scenario;
    return this.http.get<Task[]>(`${this.baseUrl}/sessions/${sessionId}/tasks`, { params });
  }

  getResources(sessionId: string, scenario?: string): Observable<Resource[]> {
    const params: Record<string, string> = {};
    if (scenario) params['scenario'] = scenario;
    return this.http.get<Resource[]>(`${this.baseUrl}/sessions/${sessionId}/resources`, { params });
  }

  getAccounts(sessionId: string): Observable<Account[]> {
    return this.http.get<Account[]>(`${this.baseUrl}/sessions/${sessionId}/accounts`);
  }

  getScenarios(sessionId: string): Observable<Scenario[]> {
    return this.http.get<Scenario[]>(`${this.baseUrl}/sessions/${sessionId}/scenarios`);
  }

  getGanttData(sessionId: string, scenario?: string): Observable<GanttData> {
    const params: Record<string, string> = {};
    if (scenario) params['scenario'] = scenario;
    return this.http.get<GanttData>(`${this.baseUrl}/sessions/${sessionId}/gantt`, { params });
  }

  query(sessionId: string, request: QueryRequest): Observable<QueryResult> {
    return this.http.post<QueryResult>(`${this.baseUrl}/sessions/${sessionId}/query`, request);
  }

  // ── Syntax ─────────────────────────────────────────────────

  getSyntax(): Observable<SyntaxData> {
    return this.http.get<SyntaxData>(`${this.baseUrl}/syntax`);
  }

  // ── Reports ────────────────────────────────────────────────

  listReports(sessionId: string): Observable<ReportDefinition[]> {
    return this.http.get<ReportDefinition[]>(`${this.baseUrl}/sessions/${sessionId}/reports`);
  }

  generateReport(sessionId: string, reportId: string, format = 'html'): Observable<ReportOutput> {
    return this.http.post<ReportOutput>(
      `${this.baseUrl}/sessions/${sessionId}/reports/${reportId}/generate`,
      { format }
    );
  }
}
