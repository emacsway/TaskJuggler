import { Component, computed, effect } from '@angular/core';
import { NgTemplateOutlet, SlicePipe, DecimalPipe } from '@angular/common';
import { ProjectStateService } from '../../core/state/project-state.service';
import { EditorStateService } from '../../core/state/editor-state.service';
import { UiStateService } from '../../core/state/ui-state.service';
import { TjBackend } from '../../core/backend/backend.interface';
import { Task } from '../../core/models';
import { ResizableColumnsDirective } from '../../shared/directives/resizable-columns.directive';

@Component({
  selector: 'app-task-tree',
  standalone: true,
  imports: [NgTemplateOutlet, SlicePipe, DecimalPipe, ResizableColumnsDirective],
  template: `
    <div class="tree-header"
         appResizableColumns
         [columnWidths]="colWidths"
         (columnWidthsChange)="colWidths = $event">
      <span class="col" [style.width.px]="colWidths[0]">Task</span>
      <span class="col" [style.width.px]="colWidths[1]">ID</span>
      <span class="col" [style.width.px]="colWidths[2]">Start</span>
      <span class="col" [style.width.px]="colWidths[3]">End</span>
      <span class="col" [style.width.px]="colWidths[4]">Effort</span>
      <span class="col" [style.width.px]="colWidths[5]">Done</span>
    </div>
    <div class="tree-view">
      @for (task of rootTasks(); track task.id) {
        <ng-container *ngTemplateOutlet="taskNode; context: { $implicit: task }"></ng-container>
      }
      @if (project.tasks().length === 0) {
        <div class="empty">No tasks (parse & schedule project first)</div>
      }
    </div>

    <ng-template #taskNode let-task>
      <div
        class="tree-node"
        [class.selected]="ui.selectedTaskId() === task.id"
        (click)="selectTask(task)"
        (dblclick)="navigateToSource(task)"
      >
        <span class="col" [style.width.px]="colWidths[0]" [style.padding-left.px]="task.level * 14 + 4">
          @if (!task.isLeaf) {
            <span class="toggle" (click)="toggleExpand($event, task.id)">
              {{ isExpanded(task.id) ? '&#9660;' : '&#9654;' }}
            </span>
          } @else {
            <span class="toggle-spacer"></span>
          }
          <span class="node-icon" [class.milestone]="task.isMilestone" [class.container]="task.isContainer">
            {{ task.isMilestone ? '&#9670;' : task.isContainer ? '&#9656;' : '&#9679;' }}
          </span>
          {{ task.name }}
        </span>
        <span class="col col-id" [style.width.px]="colWidths[1]" [title]="task.id">{{ task.id }}</span>
        <span class="col col-date" [style.width.px]="colWidths[2]">{{ task.start | slice:0:10 }}</span>
        <span class="col col-date" [style.width.px]="colWidths[3]">{{ task.end | slice:0:10 }}</span>
        <span class="col col-num" [style.width.px]="colWidths[4]">
          @if (task.effort != null && task.effort > 0) {
            {{ task.effort | number:'1.1-1' }}d
          }
        </span>
        <span class="col col-num" [style.width.px]="colWidths[5]">
          @if (task.complete != null) {
            <span class="complete-badge" [class.done]="task.complete >= 100">{{ task.complete }}%</span>
          }
        </span>
      </div>
      @if (isExpanded(task.id)) {
        @for (child of getChildren(task.id); track child.id) {
          <ng-container *ngTemplateOutlet="taskNode; context: { $implicit: child }"></ng-container>
        }
      }
    </ng-template>
  `,
  styles: [`
    :host { display: flex; flex-direction: column; height: 100%; overflow: hidden; }
    .tree-header {
      display: flex;
      flex-shrink: 0;
      font-size: 11px;
      font-weight: 600;
      color: var(--text-secondary);
      border-bottom: 1px solid var(--border-color);
      background: var(--bg-secondary);
      text-transform: uppercase;
    }
    .tree-view { flex: 1; overflow: auto; font-size: 12px; }
    .tree-node {
      display: flex;
      align-items: center;
      height: 24px;
      cursor: pointer;
      &:hover { background: var(--bg-hover); }
      &.selected { background: var(--bg-active); }
    }
    .col {
      padding: 0 6px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      flex-shrink: 0;
      border-right: 1px solid var(--border-color);
    }
    .tree-header .col {
      padding: 4px 6px;
      &:last-child { border-right: none; flex: 1; }
    }
    .tree-node .col:last-child { border-right: none; flex: 1; }
    .col-id { color: var(--text-muted); font-size: 11px; font-family: monospace; }
    .col-date { color: var(--text-secondary); font-size: 11px; }
    .col-num { text-align: right; color: var(--text-secondary); font-size: 11px; }
    .toggle { font-size: 7px; width: 12px; flex-shrink: 0; color: var(--text-muted); cursor: pointer; }
    .toggle-spacer { width: 12px; flex-shrink: 0; display: inline-block; }
    .node-icon {
      font-size: 7px; flex-shrink: 0;
      color: var(--gantt-task);
      &.milestone { color: var(--gantt-milestone); }
      &.container { color: var(--gantt-container); }
    }
    .complete-badge {
      font-size: 10px;
      padding: 0 4px;
      border-radius: 3px;
      background: var(--bg-active);
      color: var(--text-secondary);
      &.done { background: #2d4f1e; color: var(--success-color); }
    }
    .empty { padding: 20px; text-align: center; color: var(--text-muted); }
  `],
})
export class TaskTreeComponent {
  private expanded = new Set<string>();

  // Default column widths: Task, ID, Start, End, Effort, Done
  colWidths = [200, 150, 82, 82, 55, 50];

  constructor(
    public project: ProjectStateService,
    private editor: EditorStateService,
    public ui: UiStateService,
    private backend: TjBackend
  ) {
    effect(() => {
      const tasks = this.project.tasks();
      tasks.filter(t => t.parentId === null).forEach(t => this.expanded.add(t.id));
    });
  }

  rootTasks = computed(() =>
    this.project.tasks().filter((t) => t.parentId === null)
  );

  getChildren(parentId: string): Task[] {
    return this.project.tasks().filter((t) => t.parentId === parentId);
  }

  isExpanded(id: string): boolean {
    return this.expanded.has(id);
  }

  toggleExpand(event: Event, id: string): void {
    event.stopPropagation();
    if (this.expanded.has(id)) {
      this.expanded.delete(id);
    } else {
      this.expanded.add(id);
    }
  }

  selectTask(task: Task): void {
    this.ui.selectedTaskId.set(task.id);
  }

  navigateToSource(task: Task): void {
    if (!task.sourceFile) return;
    const sid = this.project.sessionId();
    if (!sid) return;

    this.backend.readFile(sid, task.sourceFile).subscribe((content) => {
      this.editor.openFile(task.sourceFile!, content, task.sourceLine ?? undefined);
      this.ui.rightPanelMode.set('editor');
    });
  }
}
