import { Component } from '@angular/core';
import { ToolbarComponent } from './features/toolbar/toolbar.component';
import { FileExplorerComponent } from './features/file-explorer/file-explorer.component';
import { EditorPaneComponent } from './features/editor/editor-pane.component';
import { MessagePanelComponent } from './features/messages/message-panel.component';
import { TaskTreeComponent } from './features/tree-views/task-tree.component';
import { ResourceTreeComponent } from './features/tree-views/resource-tree.component';
import { GanttChartComponent } from './features/gantt/gantt-chart.component';
import { ReportViewerComponent } from './features/report-viewer/report-viewer.component';
import { UiStateService } from './core/state/ui-state.service';
import { ProjectStateService } from './core/state/project-state.service';

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
    GanttChartComponent,
    ReportViewerComponent,
  ],
  templateUrl: './app.html',
  styleUrl: './app.scss',
})
export class App {
  constructor(
    public ui: UiStateService,
    public project: ProjectStateService
  ) {}
}
