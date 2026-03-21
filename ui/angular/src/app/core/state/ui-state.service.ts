import { Injectable, signal } from '@angular/core';

export type LeftPanelTab = 'files' | 'tasks' | 'resources' | 'accounts';
export type RightPanelMode = 'editor' | 'report' | 'gantt';

@Injectable({ providedIn: 'root' })
export class UiStateService {
  readonly leftPanelTab = signal<LeftPanelTab>('files');
  readonly rightPanelMode = signal<RightPanelMode>('editor');
  readonly leftPanelWidth = signal(280);
  readonly messagePanelHeight = signal(200);
  readonly messagePanelVisible = signal(true);

  /** Currently selected task ID (shared between Gantt and Task tree) */
  readonly selectedTaskId = signal<string | null>(null);

  /** Active scenario name */
  readonly activeScenario = signal<string | null>(null);
}
