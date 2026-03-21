import { Component, computed } from '@angular/core';
import { NgTemplateOutlet, SlicePipe } from '@angular/common';
import { ProjectStateService } from '../../core/state/project-state.service';
import { EditorStateService } from '../../core/state/editor-state.service';
import { UiStateService } from '../../core/state/ui-state.service';
import { TjBackend } from '../../core/backend/backend.interface';
import { Task } from '../../core/models';

@Component({
  selector: 'app-task-tree',
  standalone: true,
  imports: [NgTemplateOutlet, SlicePipe],
  template: `
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
        [style.padding-left.px]="task.level * 16 + 8"
        (click)="navigateToSource(task)"
      >
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
        <span class="node-name">{{ task.name }}</span>
        @if (task.complete != null) {
          <span class="node-attr">{{ task.complete }}%</span>
        }
        @if (task.start) {
          <span class="node-date">{{ task.start | slice:0:10 }}</span>
        }
      </div>
      @if (isExpanded(task.id)) {
        @for (child of getChildren(task.id); track child.id) {
          <ng-container *ngTemplateOutlet="taskNode; context: { $implicit: child }"></ng-container>
        }
      }
    </ng-template>
  `,
  styles: [`
    .tree-view { padding: 4px 0; font-size: 13px; }
    .tree-node {
      display: flex;
      align-items: center;
      gap: 4px;
      padding: 3px 8px;
      cursor: pointer;
      &:hover { background: var(--bg-hover); }
    }
    .toggle { font-size: 8px; width: 14px; cursor: pointer; color: var(--text-secondary); }
    .toggle-spacer { width: 14px; }
    .node-icon {
      font-size: 8px;
      color: var(--gantt-task);
      &.milestone { color: var(--gantt-milestone); }
      &.container { color: var(--gantt-container); }
    }
    .node-name { flex: 1; color: var(--text-primary); }
    .node-attr { color: var(--success-color); font-size: 11px; }
    .node-date { color: var(--text-secondary); font-size: 11px; }
    .empty { padding: 20px; text-align: center; color: var(--text-muted); font-size: 12px; }
  `],
})
export class TaskTreeComponent {
  private expanded = new Set<string>();

  constructor(
    public project: ProjectStateService,
    private editor: EditorStateService,
    private ui: UiStateService,
    private backend: TjBackend
  ) {
    // Expand top-level tasks by default
    const tasks = this.project.tasks();
    tasks.filter(t => t.parentId === null).forEach(t => this.expanded.add(t.id));
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

  navigateToSource(task: Task): void {
    if (!task.sourceFile) return;
    const sid = this.project.sessionId();
    if (!sid) return;

    this.backend.readFile(sid, task.sourceFile).subscribe((content) => {
      this.editor.openFile(task.sourceFile!, content);
      this.ui.rightPanelMode.set('editor');
    });
  }
}
