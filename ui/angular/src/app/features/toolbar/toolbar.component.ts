import { Component } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ProjectStateService } from '../../core/state/project-state.service';
import { UiStateService } from '../../core/state/ui-state.service';

@Component({
  selector: 'app-toolbar',
  standalone: true,
  imports: [FormsModule],
  template: `
    <div class="toolbar">
      <div class="toolbar-group">
        <label class="toolbar-label">Project:</label>
        <input
          class="toolbar-input"
          type="text"
          [(ngModel)]="projectDir"
          placeholder="/path/to/project"
        />
        <button class="btn" (click)="openProject()">Open</button>
      </div>

      <div class="toolbar-group">
        <button class="btn btn-primary" (click)="parseAndSchedule()" [disabled]="project.loading()">
          {{ project.loading() ? 'Working...' : 'Parse & Schedule' }}
        </button>
      </div>

      <div class="toolbar-group toolbar-status">
        <span class="status-badge" [class]="'status-' + project.sessionState()">
          {{ project.sessionState() }}
        </span>
        @if (project.errors().length > 0) {
          <span class="status-errors" (click)="ui.messagePanelVisible.set(true)">
            {{ project.errors().length }} errors
          </span>
        }
        @if (project.warnings().length > 0) {
          <span class="status-warnings" (click)="ui.messagePanelVisible.set(true)">
            {{ project.warnings().length }} warnings
          </span>
        }
      </div>
    </div>
  `,
  styles: [`
    .toolbar {
      display: flex;
      align-items: center;
      gap: 12px;
      padding: 6px 12px;
      background: var(--bg-secondary);
      border-bottom: 1px solid var(--border-color);
    }
    .toolbar-group {
      display: flex;
      align-items: center;
      gap: 6px;
    }
    .toolbar-label {
      font-size: 12px;
      color: var(--text-secondary);
    }
    .toolbar-input {
      padding: 4px 8px;
      background: var(--bg-primary);
      border: 1px solid var(--border-color);
      color: var(--text-primary);
      border-radius: 3px;
      font-size: 12px;
      width: 300px;
      &:focus { outline: 1px solid var(--accent-color); border-color: var(--accent-color); }
    }
    .btn {
      padding: 4px 12px;
      border: 1px solid var(--border-color);
      background: var(--bg-active);
      color: var(--text-primary);
      border-radius: 3px;
      cursor: pointer;
      font-size: 12px;
      &:hover { background: var(--bg-hover); }
      &:disabled { opacity: 0.5; cursor: not-allowed; }
    }
    .btn-primary {
      background: #0e639c;
      border-color: #1177bb;
      &:hover { background: #1177bb; }
    }
    .toolbar-status { margin-left: auto; }
    .status-badge {
      padding: 2px 8px;
      border-radius: 3px;
      font-size: 11px;
      font-weight: 500;
      text-transform: uppercase;
    }
    .status-empty { background: var(--bg-active); color: var(--text-muted); }
    .status-parsed { background: #2d4f1e; color: var(--success-color); }
    .status-scheduled { background: #1e3a4f; color: var(--accent-color); }
    .status-error { background: #4f1e1e; color: var(--error-color); }
    .status-errors {
      color: var(--error-color);
      cursor: pointer;
      font-size: 12px;
      &:hover { text-decoration: underline; }
    }
    .status-warnings {
      color: var(--warning-color);
      cursor: pointer;
      font-size: 12px;
      &:hover { text-decoration: underline; }
    }
  `],
})
export class ToolbarComponent {
  projectDir = '';

  constructor(
    public project: ProjectStateService,
    public ui: UiStateService
  ) {}

  async openProject(): Promise<void> {
    if (!this.projectDir) return;
    await this.project.openProject(this.projectDir);
    // Auto parse & schedule after opening
    await this.parseAndSchedule();
  }

  async parseAndSchedule(): Promise<void> {
    const master = this.project.masterFile();
    if (!master) {
      const files = this.project.projectFiles();
      const masterFile = files.find((f) => f.isMaster);
      if (!masterFile) return;
      this.project.masterFile.set(masterFile.path);
    }

    const masterPath = this.project.masterFile();
    if (!masterPath) return;

    const parseResult = await this.project.parse(masterPath);
    if (parseResult.success) {
      await this.project.schedule();
    }
  }
}
