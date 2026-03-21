export interface ProjectMeta {
  id: string;
  name: string;
  start: string;
  end: string;
  now: string;
  currency: string;
  scenarios: Scenario[];
}

export interface Scenario {
  id: string;
  name: string;
  index: number;
}

export interface SessionInfo {
  id: string;
  state: SessionState;
  projectDir: string;
  errors: number;
  warnings: number;
}

export type SessionState = 'empty' | 'parsed' | 'scheduled' | 'error';
