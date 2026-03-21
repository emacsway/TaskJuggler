import { Component, computed, effect } from '@angular/core';
import { NgTemplateOutlet } from '@angular/common';
import { ProjectStateService } from '../../core/state/project-state.service';
import { EditorStateService } from '../../core/state/editor-state.service';
import { UiStateService } from '../../core/state/ui-state.service';
import { TjBackend } from '../../core/backend/backend.interface';
import { Resource } from '../../core/models';
import { ResizableColumnsDirective } from '../../shared/directives/resizable-columns.directive';

@Component({
  selector: 'app-resource-tree',
  standalone: true,
  imports: [NgTemplateOutlet, ResizableColumnsDirective],
  template: `
    <div class="tree-header"
         appResizableColumns
         [columnWidths]="colWidths"
         (columnWidthsChange)="colWidths = $event">
      <span class="col" [style.width.px]="colWidths[0]">Resource</span>
      <span class="col" [style.width.px]="colWidths[1]">ID</span>
      <span class="col" [style.width.px]="colWidths[2]">Email</span>
      <span class="col" [style.width.px]="colWidths[3]">Eff.</span>
      <span class="col" [style.width.px]="colWidths[4]">Rate</span>
    </div>
    <div class="tree-view">
      @for (res of rootResources(); track res.id) {
        <ng-container *ngTemplateOutlet="resNode; context: { $implicit: res }"></ng-container>
      }
      @if (project.resources().length === 0) {
        <div class="empty">No resources</div>
      }
    </div>

    <ng-template #resNode let-res>
      <div class="tree-node" (dblclick)="navigateToSource(res)">
        <span class="col" [style.width.px]="colWidths[0]" [style.padding-left.px]="res.level * 14 + 4">
          @if (!res.isLeaf) {
            <span class="toggle" (click)="toggleExpand($event, res.id)">
              {{ isExpanded(res.id) ? '&#9660;' : '&#9654;' }}
            </span>
          } @else {
            <span class="toggle-spacer"></span>
          }
          <span class="node-icon">&#9679;</span>
          {{ res.name }}
        </span>
        <span class="col col-id" [style.width.px]="colWidths[1]" [title]="res.id">{{ res.id }}</span>
        <span class="col col-detail" [style.width.px]="colWidths[2]">{{ res.email || '' }}</span>
        <span class="col col-num" [style.width.px]="colWidths[3]">{{ res.efficiency != null ? res.efficiency : '' }}</span>
        <span class="col col-num" [style.width.px]="colWidths[4]">{{ res.rate != null && res.rate > 0 ? res.rate : '' }}</span>
      </div>
      @if (isExpanded(res.id)) {
        @for (child of getChildren(res.id); track child.id) {
          <ng-container *ngTemplateOutlet="resNode; context: { $implicit: child }"></ng-container>
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
    .col-detail { color: var(--text-secondary); font-size: 11px; }
    .col-num { text-align: right; color: var(--text-secondary); font-size: 11px; }
    .toggle { font-size: 7px; width: 12px; flex-shrink: 0; color: var(--text-muted); cursor: pointer; }
    .toggle-spacer { width: 12px; flex-shrink: 0; display: inline-block; }
    .node-icon { font-size: 7px; flex-shrink: 0; color: #4ec9b0; }
    .empty { padding: 20px; text-align: center; color: var(--text-muted); }
  `],
})
export class ResourceTreeComponent {
  private expanded = new Set<string>();

  // Default column widths: Resource, ID, Email, Eff, Rate
  colWidths = [180, 120, 160, 45, 60];

  constructor(
    public project: ProjectStateService,
    private editor: EditorStateService,
    private ui: UiStateService,
    private backend: TjBackend
  ) {
    effect(() => {
      const resources = this.project.resources();
      resources.filter(r => r.parentId === null).forEach(r => this.expanded.add(r.id));
    });
  }

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
      this.editor.openFile(res.sourceFile!, content, res.sourceLine ?? undefined);
      this.ui.rightPanelMode.set('editor');
    });
  }
}
