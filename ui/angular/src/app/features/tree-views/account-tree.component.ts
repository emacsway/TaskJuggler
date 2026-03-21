import { Component, computed, effect } from '@angular/core';
import { NgTemplateOutlet } from '@angular/common';
import { ProjectStateService } from '../../core/state/project-state.service';
import { EditorStateService } from '../../core/state/editor-state.service';
import { UiStateService } from '../../core/state/ui-state.service';
import { TjBackend } from '../../core/backend/backend.interface';
import { Account } from '../../core/models';
import { ResizableColumnsDirective } from '../../shared/directives/resizable-columns.directive';

@Component({
  selector: 'app-account-tree',
  standalone: true,
  imports: [NgTemplateOutlet, ResizableColumnsDirective],
  template: `
    <div class="tree-header"
         appResizableColumns
         [columnWidths]="colWidths"
         (columnWidthsChange)="colWidths = $event">
      <span class="col" [style.width.px]="colWidths[0]">Account</span>
      <span class="col" [style.width.px]="colWidths[1]">ID</span>
    </div>
    <div class="tree-view">
      @for (acc of rootAccounts(); track acc.id) {
        <ng-container *ngTemplateOutlet="accNode; context: { $implicit: acc }"></ng-container>
      }
      @if (project.accounts().length === 0) {
        <div class="empty">No accounts</div>
      }
    </div>

    <ng-template #accNode let-acc>
      <div class="tree-node" (dblclick)="navigateToSource(acc)">
        <span class="col" [style.width.px]="colWidths[0]" [style.padding-left.px]="acc.level * 14 + 4">
          @if (!acc.isLeaf) {
            <span class="toggle" (click)="toggleExpand($event, acc.id)">
              {{ isExpanded(acc.id) ? '&#9660;' : '&#9654;' }}
            </span>
          } @else {
            <span class="toggle-spacer"></span>
          }
          <span class="node-icon">&#9679;</span>
          {{ acc.name }}
        </span>
        <span class="col col-id" [style.width.px]="colWidths[1]" [title]="acc.id">{{ acc.id }}</span>
      </div>
      @if (isExpanded(acc.id)) {
        @for (child of getChildren(acc.id); track child.id) {
          <ng-container *ngTemplateOutlet="accNode; context: { $implicit: child }"></ng-container>
        }
      }
    </ng-template>
  `,
  styles: [`
    :host { display: flex; flex-direction: column; height: 100%; overflow: hidden; }
    .tree-header {
      display: flex; flex-shrink: 0; font-size: 11px; font-weight: 600;
      color: var(--text-secondary); border-bottom: 1px solid var(--border-color);
      background: var(--bg-secondary); text-transform: uppercase;
    }
    .tree-view { flex: 1; overflow: auto; font-size: 12px; }
    .tree-node {
      display: flex; align-items: center; height: 24px; cursor: pointer;
      &:hover { background: var(--bg-hover); }
    }
    .col {
      padding: 0 6px; overflow: hidden; text-overflow: ellipsis;
      white-space: nowrap; flex-shrink: 0; border-right: 1px solid var(--border-color);
    }
    .tree-header .col { padding: 4px 6px; &:last-child { border-right: none; flex: 1; } }
    .tree-node .col:last-child { border-right: none; flex: 1; }
    .col-id { color: var(--text-muted); font-size: 11px; font-family: monospace; }
    .toggle { font-size: 7px; width: 12px; flex-shrink: 0; color: var(--text-muted); cursor: pointer; }
    .toggle-spacer { width: 12px; flex-shrink: 0; display: inline-block; }
    .node-icon { font-size: 7px; flex-shrink: 0; color: #dcdcaa; }
    .empty { padding: 20px; text-align: center; color: var(--text-muted); }
  `],
})
export class AccountTreeComponent {
  private expanded = new Set<string>();
  colWidths = [200, 150];

  constructor(
    public project: ProjectStateService,
    private editor: EditorStateService,
    private ui: UiStateService,
    private backend: TjBackend
  ) {
    effect(() => {
      this.project.accounts().filter(a => a.parentId === null).forEach(a => this.expanded.add(a.id));
    });
  }

  rootAccounts = computed(() => this.project.accounts().filter(a => a.parentId === null));

  getChildren(parentId: string): Account[] {
    return this.project.accounts().filter(a => a.parentId === parentId);
  }

  isExpanded(id: string): boolean { return this.expanded.has(id); }

  toggleExpand(event: Event, id: string): void {
    event.stopPropagation();
    this.expanded.has(id) ? this.expanded.delete(id) : this.expanded.add(id);
  }

  navigateToSource(acc: Account): void {
    if (!acc.sourceFile) return;
    const sid = this.project.sessionId();
    if (!sid) return;
    this.backend.readFile(sid, acc.sourceFile).subscribe(content => {
      this.editor.openFile(acc.sourceFile!, content, acc.sourceLine ?? undefined);
      this.ui.rightPanelMode.set('editor');
    });
  }
}
