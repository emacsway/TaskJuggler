import { Component, computed } from '@angular/core';
import { NgTemplateOutlet } from '@angular/common';
import { ProjectStateService } from '../../core/state/project-state.service';
import { EditorStateService } from '../../core/state/editor-state.service';
import { UiStateService } from '../../core/state/ui-state.service';
import { TjBackend } from '../../core/backend/backend.interface';
import { ProjectFile } from '../../core/models';

interface FileNode {
  name: string;
  path: string | null;      // null for directories
  isMaster: boolean;
  children: FileNode[];
  level: number;
}

@Component({
  selector: 'app-file-explorer',
  standalone: true,
  imports: [NgTemplateOutlet],
  template: `
    <div class="file-explorer">
      @for (node of fileTree(); track node.name) {
        <ng-container>
          @if (node.children.length > 0) {
            <div class="dir-item" [style.padding-left.px]="node.level * 16 + 8"
                 (click)="toggleDir(node.name)">
              <span class="dir-toggle">{{ isDirExpanded(node.name) ? '&#9660;' : '&#9654;' }}</span>
              <span class="dir-name">{{ node.name }}</span>
            </div>
            @if (isDirExpanded(node.name)) {
              @for (child of node.children; track child.name) {
                <ng-container *ngTemplateOutlet="fileNodeTpl; context: { $implicit: child }"></ng-container>
              }
            }
          } @else if (node.path) {
            <div class="file-item" [class.master]="node.isMaster"
                 [style.padding-left.px]="node.level * 16 + 8"
                 (click)="openFile(node)">
              <span class="file-icon">{{ node.isMaster ? '&#9733;' : '&#9702;' }}</span>
              <span class="file-name">{{ node.name }}</span>
            </div>
          }
        </ng-container>
      }
      @if (project.projectFiles().length === 0) {
        <div class="empty">No project loaded</div>
      }
    </div>

    <ng-template #fileNodeTpl let-node>
      @if (node.children.length > 0) {
        <div class="dir-item" [style.padding-left.px]="node.level * 16 + 8"
             (click)="toggleDir(node.path || node.name)">
          <span class="dir-toggle">{{ isDirExpanded(node.path || node.name) ? '&#9660;' : '&#9654;' }}</span>
          <span class="dir-name">{{ node.name }}</span>
        </div>
        @if (isDirExpanded(node.path || node.name)) {
          @for (child of node.children; track child.name) {
            <ng-container *ngTemplateOutlet="fileNodeTpl; context: { $implicit: child }"></ng-container>
          }
        }
      } @else if (node.path) {
        <div class="file-item" [class.master]="node.isMaster"
             [style.padding-left.px]="node.level * 16 + 8"
             (click)="openFile(node)">
          <span class="file-icon">{{ node.isMaster ? '&#9733;' : '&#9702;' }}</span>
          <span class="file-name">{{ node.name }}</span>
        </div>
      }
    </ng-template>
  `,
  styles: [`
    .file-explorer { padding: 4px 0; font-size: 13px; }
    .dir-item {
      display: flex;
      align-items: center;
      gap: 4px;
      padding: 3px 8px;
      cursor: pointer;
      &:hover { background: var(--bg-hover); }
    }
    .dir-toggle { font-size: 7px; width: 12px; color: var(--text-muted); }
    .dir-name { color: var(--text-primary); font-weight: 500; }
    .file-item {
      display: flex;
      align-items: center;
      gap: 4px;
      padding: 3px 8px;
      cursor: pointer;
      &:hover { background: var(--bg-hover); }
      &.master .file-name { font-weight: 600; }
    }
    .file-icon { font-size: 10px; color: var(--text-secondary); width: 12px; text-align: center; }
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
  private expandedDirs = new Set<string>();

  constructor(
    public project: ProjectStateService,
    private editor: EditorStateService,
    private ui: UiStateService,
    private backend: TjBackend
  ) {
    // Expand all dirs by default
    this.expandedDirs.add('*');
  }

  fileTree = computed((): FileNode[] => {
    const files = this.project.projectFiles();
    if (!files.length) return [];

    // Find common prefix to strip
    const prefix = this.commonPrefix(files.map(f => f.path));

    // Build tree
    const root: FileNode[] = [];
    for (const file of files) {
      const rel = file.path.startsWith(prefix) ? file.path.slice(prefix.length) : file.path;
      const parts = rel.split('/').filter(Boolean);
      this.insertIntoTree(root, parts, file, 0);
    }

    // Collapse single-child directory chains
    return this.flattenSingleChildDirs(root);
  });

  isDirExpanded(key: string): boolean {
    return this.expandedDirs.has('*') || this.expandedDirs.has(key);
  }

  toggleDir(key: string): void {
    // On first toggle, switch from "expand all" to explicit tracking
    if (this.expandedDirs.has('*')) {
      this.expandedDirs.delete('*');
      // Expand all current dirs explicitly
      this.collectDirKeys(this.fileTree()).forEach(k => this.expandedDirs.add(k));
    }

    if (this.expandedDirs.has(key)) {
      this.expandedDirs.delete(key);
    } else {
      this.expandedDirs.add(key);
    }
  }

  openFile(node: FileNode): void {
    if (!node.path) return;
    const sid = this.project.sessionId();
    if (!sid) return;

    this.backend.readFile(sid, node.path).subscribe((content) => {
      this.editor.openFile(node.path!, content);
      this.ui.rightPanelMode.set('editor');
    });
  }

  private commonPrefix(paths: string[]): string {
    if (paths.length === 0) return '';
    const parts0 = paths[0].split('/');
    let depth = 0;
    outer:
    for (let i = 0; i < parts0.length - 1; i++) {
      for (const p of paths) {
        if (p.split('/')[i] !== parts0[i]) break outer;
      }
      depth = i + 1;
    }
    return parts0.slice(0, depth).join('/') + (depth > 0 ? '/' : '');
  }

  private insertIntoTree(nodes: FileNode[], parts: string[], file: ProjectFile, level: number): void {
    if (parts.length === 1) {
      nodes.push({
        name: parts[0],
        path: file.path,
        isMaster: file.isMaster,
        children: [],
        level,
      });
      return;
    }

    const dirName = parts[0];
    let dir = nodes.find(n => n.name === dirName && n.children.length > 0 && !n.path);
    if (!dir) {
      dir = { name: dirName, path: null, isMaster: false, children: [], level };
      nodes.push(dir);
    }
    this.insertIntoTree(dir.children, parts.slice(1), file, level + 1);
  }

  private flattenSingleChildDirs(nodes: FileNode[]): FileNode[] {
    return nodes.map(node => {
      if (node.children.length === 1 && node.children[0].children.length > 0) {
        // Merge parent/child directory names
        const child = node.children[0];
        const merged: FileNode = {
          name: node.name + '/' + child.name,
          path: child.path,
          isMaster: child.isMaster,
          children: this.flattenSingleChildDirs(child.children),
          level: node.level,
        };
        // Fix children levels
        this.adjustLevels(merged.children, merged.level + 1);
        return merged;
      }
      return {
        ...node,
        children: this.flattenSingleChildDirs(node.children),
      };
    });
  }

  private adjustLevels(nodes: FileNode[], level: number): void {
    for (const n of nodes) {
      n.level = level;
      this.adjustLevels(n.children, level + 1);
    }
  }

  private collectDirKeys(nodes: FileNode[]): string[] {
    const keys: string[] = [];
    for (const n of nodes) {
      if (n.children.length > 0) {
        keys.push(n.path || n.name);
        keys.push(...this.collectDirKeys(n.children));
      }
    }
    return keys;
  }
}
