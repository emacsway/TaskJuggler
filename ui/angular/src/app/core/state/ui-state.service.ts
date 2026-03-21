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
}
