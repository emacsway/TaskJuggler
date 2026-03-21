import { Component } from '@angular/core';
import { ProjectStateService } from '../../core/state/project-state.service';
import { EditorStateService } from '../../core/state/editor-state.service';
import { UiStateService } from '../../core/state/ui-state.service';
import { TjBackend } from '../../core/backend/backend.interface';
import { ProjectFile } from '../../core/models';

@Component({
  selector: 'app-file-explorer',
  standalone: true,
  template: `
    <div class="file-explorer">
      @for (file of project.projectFiles(); track file.path) {
        <div
          class="file-item"
          [class.master]="file.isMaster"
          (click)="openFile(file)"
        >
          <span class="file-icon">{{ file.isMaster ? '&#9733;' : '&#9702;' }}</span>
          <span class="file-name">{{ file.path }}</span>
        </div>
      }
      @if (project.projectFiles().length === 0) {
        <div class="empty">No project loaded</div>
      }
    </div>
  `,
  styles: [`
    .file-explorer { padding: 4px 0; }
    .file-item {
      display: flex;
      align-items: center;
      gap: 6px;
      padding: 4px 12px;
      cursor: pointer;
      font-size: 13px;
      &:hover { background: var(--bg-hover); }
      &.master .file-name { font-weight: 600; }
    }
    .file-icon { font-size: 10px; color: var(--text-secondary); width: 14px; text-align: center; }
    .file-name { color: var(--text-primary); }
    .empty {
      padding: 20px;
      text-align: center;
      color: var(--text-muted);
      font-size: 12px;
    }
  `],
})
export class FileExplorerComponent {
  constructor(
    public project: ProjectStateService,
    private editor: EditorStateService,
    private ui: UiStateService,
    private backend: TjBackend
  ) {}

  openFile(file: ProjectFile): void {
    const sid = this.project.sessionId();
    if (!sid) return;

    this.backend.readFile(sid, file.path).subscribe((content) => {
      this.editor.openFile(file.path, content);
      this.ui.rightPanelMode.set('editor');
    });
  }
}
