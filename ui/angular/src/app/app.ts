import { Component, HostListener } from '@angular/core';
import { ToolbarComponent } from './features/toolbar/toolbar.component';
import { FileExplorerComponent } from './features/file-explorer/file-explorer.component';
import { EditorPaneComponent } from './features/editor/editor-pane.component';
import { MessagePanelComponent } from './features/messages/message-panel.component';
import { TaskTreeComponent } from './features/tree-views/task-tree.component';
import { ResourceTreeComponent } from './features/tree-views/resource-tree.component';
import { AccountTreeComponent } from './features/tree-views/account-tree.component';
import { GanttChartComponent } from './features/gantt/gantt-chart.component';
import { ReportViewerComponent } from './features/report-viewer/report-viewer.component';
import { MonteCarloComponent } from './features/monte-carlo/monte-carlo.component';
import { UiStateService } from './core/state/ui-state.service';
import { ProjectStateService } from './core/state/project-state.service';
import { UiPersistenceService } from './core/state/ui-persistence.service';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [
    ToolbarComponent,
    FileExplorerComponent,
    EditorPaneComponent,
    MessagePanelComponent,
    TaskTreeComponent,
    ResourceTreeComponent,
    AccountTreeComponent,
    GanttChartComponent,
    ReportViewerComponent,
    MonteCarloComponent,
  ],
  templateUrl: './app.html',
  styleUrl: './app.scss',
})
export class App {
  resizing: 'left' | 'bottom' | null = null;

  constructor(
    public ui: UiStateService,
    public project: ProjectStateService,
    private persistence: UiPersistenceService
  ) {
    this.persistence.init();
  }

  startResizeLeft(event: MouseEvent): void {
    event.preventDefault();
    this.resizing = 'left';
  }

  startResizeBottom(event: MouseEvent): void {
    event.preventDefault();
    this.resizing = 'bottom';
  }

  @HostListener('document:mousemove', ['$event'])
  onMouseMove(event: MouseEvent): void {
    if (!this.resizing) return;
    event.preventDefault();

    if (this.resizing === 'left') {
      const width = Math.max(200, Math.min(600, event.clientX));
      this.ui.leftPanelWidth.set(width);
    } else if (this.resizing === 'bottom') {
      const height = Math.max(80, Math.min(400, window.innerHeight - event.clientY));
      this.ui.messagePanelHeight.set(height);
    }
  }

  @HostListener('document:mouseup')
  onMouseUp(): void {
    this.resizing = null;
  }

  @HostListener('document:keydown', ['$event'])
  onKeyDown(event: KeyboardEvent): void {
    // Skip if user is typing in an input/textarea/editor
    const tag = (event.target as HTMLElement)?.tagName;
    if (tag === 'INPUT' || tag === 'TEXTAREA') return;
    if ((event.target as HTMLElement)?.closest('.cm-editor')) return;

    if (event.altKey) {
      switch (event.key.toLowerCase()) {
        case 'f': this.ui.leftPanelTab.set('files'); event.preventDefault(); break;
        case 't': this.ui.leftPanelTab.set('tasks'); event.preventDefault(); break;
        case 'r': this.ui.leftPanelTab.set('resources'); event.preventDefault(); break;
        case 'a': this.ui.leftPanelTab.set('accounts'); event.preventDefault(); break;
        case 'e': this.ui.rightPanelMode.set('editor'); event.preventDefault(); break;
        case 'g': this.ui.rightPanelMode.set('gantt'); event.preventDefault(); break;
        case 'p': this.ui.rightPanelMode.set('report'); event.preventDefault(); break;
        case 'c': this.ui.rightPanelMode.set('montecarlo'); event.preventDefault(); break;
        case 'm': this.ui.messagePanelVisible.update(v => !v); event.preventDefault(); break;
      }
    }
  }
}
