import { Observable } from 'rxjs';
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

export interface ScheduleProgress {
  phase: string;
  scenario?: string;
  percent: number;
}

export interface ParseResult {
  success: boolean;
  state: string;
  messages: DiagnosticMessage[];
}

export interface ScheduleResult {
  success: boolean;
  state: string;
  messages: DiagnosticMessage[];
}

export interface QueryRequest {
  propertyType: 'Task' | 'Resource' | 'Account';
  propertyId: string;
  attributeId: string;
  scenarioIdx?: number;
}

export interface QueryResult {
  ok: boolean;
  string?: string | null;
  numerical?: number | null;
  error?: string;
}

export interface SyntaxData {
  /** context name -> list of valid child keywords */
  contextMap: Record<string, string[]>;
  /** keyword -> list of valid enum values */
  valueMap: Record<string, string[]>;
}

export abstract class TjBackend {
  // Session lifecycle
  abstract createSession(projectDir: string): Observable<SessionInfo>;
  abstract getSession(sessionId: string): Observable<SessionInfo>;
  abstract destroySession(sessionId: string): Observable<void>;

  // File operations
  abstract listFiles(sessionId: string): Observable<ProjectFile[]>;
  abstract readFile(sessionId: string, path: string): Observable<string>;
  abstract writeFile(sessionId: string, path: string, content: string): Observable<void>;
  abstract createFile(sessionId: string, path: string, content: string): Observable<void>;
  abstract deleteFile(sessionId: string, path: string): Observable<void>;

  // Engine operations
  abstract parse(sessionId: string, masterFile: string): Observable<ParseResult>;
  abstract schedule(sessionId: string): Observable<ScheduleResult>;
  abstract scheduleWithProgress(sessionId: string): Observable<ScheduleProgress>;
  abstract getMessages(sessionId: string): Observable<DiagnosticMessage[]>;

  // Data queries
  abstract getProjectMeta(sessionId: string): Observable<ProjectMeta>;
  abstract getTasks(sessionId: string, scenario?: string): Observable<Task[]>;
  abstract getResources(sessionId: string, scenario?: string): Observable<Resource[]>;
  abstract getAccounts(sessionId: string): Observable<Account[]>;
  abstract getScenarios(sessionId: string): Observable<Scenario[]>;
  abstract getGanttData(sessionId: string, scenario?: string): Observable<GanttData>;
  abstract query(sessionId: string, request: QueryRequest): Observable<QueryResult>;

  // Syntax reference
  abstract getSyntax(): Observable<SyntaxData>;

  // Reports
  abstract listReports(sessionId: string): Observable<ReportDefinition[]>;
  abstract generateReport(sessionId: string, reportId: string, format?: string): Observable<ReportOutput>;
}
