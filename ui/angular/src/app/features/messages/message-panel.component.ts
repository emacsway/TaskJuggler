import { Component } from '@angular/core';
import { ProjectStateService } from '../../core/state/project-state.service';
import { EditorStateService } from '../../core/state/editor-state.service';
import { UiStateService } from '../../core/state/ui-state.service';
import { TjBackend } from '../../core/backend/backend.interface';
import { DiagnosticMessage } from '../../core/models';

@Component({
  selector: 'app-message-panel',
  standalone: true,
  template: `
    <div class="message-panel-inner">
      <div class="message-header">
        <span class="message-title">Problems</span>
        @if (project.errors().length > 0) {
          <span class="count-badge error-badge">{{ project.errors().length }} errors</span>
        }
        @if (project.warnings().length > 0) {
          <span class="count-badge warning-badge">{{ project.warnings().length }} warnings</span>
        }
        <button class="close-btn" (click)="ui.messagePanelVisible.set(false)">&times;</button>
      </div>
      <div class="message-list">
        @for (msg of project.messages(); track $index) {
          <div
            class="message-item"
            [class]="'msg-' + msg.type"
            [class.clickable]="msg.file"
            (click)="navigateToSource(msg)"
          >
            <span class="msg-icon">
              @if (msg.type === 'error' || msg.type === 'fatal') {
                <span class="icon-error">&otimes;</span>
              } @else {
                <span class="icon-warning">&#9888;</span>
              }
            </span>
            <span class="msg-text">{{ msg.message }}</span>
            @if (msg.file) {
              <span class="msg-location">{{ msg.file }}:{{ msg.line }}</span>
            }
          </div>
        }
        @if (project.messages().length === 0) {
          <div class="no-messages">No problems detected</div>
        }
      </div>
    </div>
  `,
  styles: [`
    .message-panel-inner {
      display: flex;
      flex-direction: column;
      height: 100%;
    }
    .message-header {
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 4px 12px;
      background: var(--bg-secondary);
      border-bottom: 1px solid var(--border-color);
      flex-shrink: 0;
    }
    .message-title { font-size: 12px; font-weight: 600; }
    .count-badge {
      font-size: 11px;
      padding: 0 6px;
      border-radius: 10px;
    }
    .error-badge { background: #5c2020; color: var(--error-color); }
    .warning-badge { background: #4d3a00; color: var(--warning-color); }
    .close-btn {
      margin-left: auto;
      background: none;
      border: none;
      color: var(--text-secondary);
      cursor: pointer;
      font-size: 16px;
      &:hover { color: var(--text-primary); }
    }
    .message-list {
      flex: 1;
      overflow-y: auto;
    }
    .message-item {
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 4px 12px;
      font-size: 12px;
      &.clickable { cursor: pointer; }
      &:hover { background: var(--bg-hover); }
    }
    .msg-icon { width: 16px; font-size: 14px; flex-shrink: 0; }
    .icon-error { color: var(--error-color); }
    .icon-warning { color: var(--warning-color); }
    .msg-text { flex: 1; color: var(--text-primary); }
    .msg-location {
      color: var(--accent-color);
      font-size: 11px;
      white-space: nowrap;
      text-decoration: underline;
      cursor: pointer;
    }
    .no-messages {
      padding: 12px;
      text-align: center;
      color: var(--text-muted);
      font-size: 12px;
    }
  `],
})
export class MessagePanelComponent {
  constructor(
    public project: ProjectStateService,
    private editor: EditorStateService,
    public ui: UiStateService,
    private backend: TjBackend
  ) {}

  navigateToSource(msg: DiagnosticMessage): void {
    if (!msg.file) return;
    const sid = this.project.sessionId();
    if (!sid) return;

    this.backend.readFile(sid, msg.file).subscribe((content) => {
      this.editor.openFile(msg.file!, content, msg.line ?? undefined);
      this.ui.rightPanelMode.set('editor');
    });
  }
}
