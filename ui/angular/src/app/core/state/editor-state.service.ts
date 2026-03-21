import { Injectable, signal, computed } from '@angular/core';

export interface EditorTab {
  path: string;
  content: string;
  dirty: boolean;
}

@Injectable({ providedIn: 'root' })
export class EditorStateService {
  readonly tabs = signal<EditorTab[]>([]);
  readonly activeTabPath = signal<string | null>(null);

  readonly activeTab = computed(() => {
    const path = this.activeTabPath();
    return this.tabs().find((t) => t.path === path) ?? null;
  });

  readonly dirtyFiles = computed(() =>
    this.tabs()
      .filter((t) => t.dirty)
      .map((t) => t.path)
  );

  openFile(path: string, content: string): void {
    const existing = this.tabs().find((t) => t.path === path);
    if (!existing) {
      this.tabs.update((tabs) => [...tabs, { path, content, dirty: false }]);
    }
    this.activeTabPath.set(path);
  }

  closeTab(path: string): void {
    this.tabs.update((tabs) => tabs.filter((t) => t.path !== path));
    if (this.activeTabPath() === path) {
      const remaining = this.tabs();
      this.activeTabPath.set(remaining.length > 0 ? remaining[remaining.length - 1].path : null);
    }
  }

  updateContent(path: string, content: string): void {
    this.tabs.update((tabs) =>
      tabs.map((t) => (t.path === path ? { ...t, content, dirty: true } : t))
    );
  }

  markSaved(path: string): void {
    this.tabs.update((tabs) =>
      tabs.map((t) => (t.path === path ? { ...t, dirty: false } : t))
    );
  }

  closeAll(): void {
    this.tabs.set([]);
    this.activeTabPath.set(null);
  }
}
