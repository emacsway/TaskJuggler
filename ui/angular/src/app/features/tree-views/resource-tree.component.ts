import { Component, computed, effect } from '@angular/core';
import { NgTemplateOutlet } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ProjectStateService } from '../../core/state/project-state.service';
import { EditorStateService } from '../../core/state/editor-state.service';
import { UiStateService } from '../../core/state/ui-state.service';
import { TjBackend } from '../../core/backend/backend.interface';
import { Resource } from '../../core/models';
import { ResizableColumnsDirective } from '../../shared/directives/resizable-columns.directive';

@Component({
  selector: 'app-resource-tree',
  standalone: true,
  imports: [NgTemplateOutlet, ResizableColumnsDirective, FormsModule],
  template: `
    <div class="search-bar">
      <input type="text" class="search-input" placeholder="Filter resources..."
             [(ngModel)]="searchQuery" (ngModelChange)="onSearch()"/>
    </div>
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
      <div class="tree-node" [hidden]="!isVisible(res)" (dblclick)="navigateToSource(res)">
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
    .search-bar {
      flex-shrink: 0; padding: 4px 6px;
      background: var(--bg-secondary); border-bottom: 1px solid var(--border-color);
    }
    .search-input {
      width: 100%; padding: 3px 6px;
      background: var(--bg-primary); border: 1px solid var(--border-color);
      color: var(--text-primary); border-radius: 3px; font-size: 12px;
      &:focus { outline: 1px solid var(--accent-color); border-color: var(--accent-color); }
    }
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
  searchQuery = '';
  private matchingIds = new Set<string>();

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

  onSearch(): void {
    this.matchingIds.clear();
    const q = this.searchQuery.toLowerCase().trim();
    if (!q) return;
    const resources = this.project.resources();
    for (const r of resources) {
      if (r.name.toLowerCase().includes(q) || r.id.toLowerCase().includes(q)) {
        this.matchingIds.add(r.id);
        this.expandParents(r.parentId, resources);
      }
    }
  }

  isVisible(res: Resource): boolean {
    if (!this.searchQuery.trim()) return true;
    return this.matchingIds.has(res.id);
  }

  private expandParents(parentId: string | null, resources: Resource[]): void {
    if (!parentId) return;
    this.expanded.add(parentId);
    this.matchingIds.add(parentId);
    const parent = resources.find(r => r.id === parentId);
    if (parent) this.expandParents(parent.parentId, resources);
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
