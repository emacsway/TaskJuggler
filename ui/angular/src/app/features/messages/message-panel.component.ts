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
        <span class="message-count">{{ project.messages().length }}</span>
        <button class="close-btn" (click)="ui.messagePanelVisible.set(false)">x</button>
      </div>
      <div class="message-list">
        @for (msg of project.messages(); track $index) {
          <div
            class="message-item"
            [class]="'msg-' + msg.type"
            (click)="navigateToSource(msg)"
          >
            <span class="msg-icon">
              {{ msg.type === 'error' || msg.type === 'fatal' ? '&#10006;' : '&#9888;' }}
            </span>
            <span class="msg-text">{{ msg.message }}</span>
            @if (msg.file) {
              <span class="msg-location">{{ msg.file }}:{{ msg.line }}</span>
            }
          </div>
        }
        @if (project.messages().length === 0) {
          <div class="no-messages">No problems</div>
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
    .message-count {
      font-size: 11px;
      background: var(--bg-active);
      padding: 0 6px;
      border-radius: 10px;
      color: var(--text-secondary);
    }
    .close-btn {
      margin-left: auto;
      background: none;
      border: none;
      color: var(--text-secondary);
      cursor: pointer;
      font-size: 14px;
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
      cursor: pointer;
      font-size: 12px;
      &:hover { background: var(--bg-hover); }
    }
    .msg-icon { width: 14px; font-size: 12px; }
    .msg-error .msg-icon, .msg-fatal .msg-icon { color: var(--error-color); }
    .msg-warning .msg-icon { color: var(--warning-color); }
    .msg-info .msg-icon { color: var(--accent-color); }
    .msg-text { flex: 1; color: var(--text-primary); }
    .msg-location {
      color: var(--text-secondary);
      font-size: 11px;
      white-space: nowrap;
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
      this.editor.openFile(msg.file!, content);
      this.ui.rightPanelMode.set('editor');
    });
  }
}
