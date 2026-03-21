import { Component, computed } from '@angular/core';
import { NgTemplateOutlet } from '@angular/common';
import { ProjectStateService } from '../../core/state/project-state.service';
import { EditorStateService } from '../../core/state/editor-state.service';
import { UiStateService } from '../../core/state/ui-state.service';
import { TjBackend } from '../../core/backend/backend.interface';
import { Resource } from '../../core/models';

@Component({
  selector: 'app-resource-tree',
  standalone: true,
  imports: [NgTemplateOutlet],
  template: `
    <div class="tree-view">
      @for (res of rootResources(); track res.id) {
        <ng-container *ngTemplateOutlet="resNode; context: { $implicit: res }"></ng-container>
      }
      @if (project.resources().length === 0) {
        <div class="empty">No resources</div>
      }
    </div>

    <ng-template #resNode let-res>
      <div
        class="tree-node"
        [style.padding-left.px]="res.level * 16 + 8"
        (click)="navigateToSource(res)"
      >
        @if (!res.isLeaf) {
          <span class="toggle" (click)="toggleExpand($event, res.id)">
            {{ isExpanded(res.id) ? '&#9660;' : '&#9654;' }}
          </span>
        } @else {
          <span class="toggle-spacer"></span>
        }
        <span class="node-icon">&#9679;</span>
        <span class="node-name">{{ res.name }}</span>
        @if (res.email) {
          <span class="node-attr">{{ res.email }}</span>
        }
      </div>
      @if (isExpanded(res.id)) {
        @for (child of getChildren(res.id); track child.id) {
          <ng-container *ngTemplateOutlet="resNode; context: { $implicit: child }"></ng-container>
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
    .node-icon { font-size: 8px; color: #4ec9b0; }
    .node-name { flex: 1; color: var(--text-primary); }
    .node-attr { color: var(--text-secondary); font-size: 11px; }
    .empty { padding: 20px; text-align: center; color: var(--text-muted); font-size: 12px; }
  `],
})
export class ResourceTreeComponent {
  private expanded = new Set<string>();

  constructor(
    public project: ProjectStateService,
    private editor: EditorStateService,
    private ui: UiStateService,
    private backend: TjBackend
  ) {}

  rootResources = computed(() =>
    this.project.resources().filter((r) => r.parentId === null)
  );

  getChildren(parentId: string): Resource[] {
    return this.project.resources().filter((r) => r.parentId === parentId);
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

  navigateToSource(res: Resource): void {
    if (!res.sourceFile) return;
    const sid = this.project.sessionId();
    if (!sid) return;

    this.backend.readFile(sid, res.sourceFile).subscribe((content) => {
      this.editor.openFile(res.sourceFile!, content);
      this.ui.rightPanelMode.set('editor');
    });
  }
}
