import { Injectable, effect } from '@angular/core';
import { UiStateService } from './ui-state.service';

const KEY = 'tj3ui_state';

interface PersistedState {
  leftPanelWidth: number;
  messagePanelHeight: number;
  messagePanelVisible: boolean;
  lastProjectDir?: string;
}

@Injectable({ providedIn: 'root' })
export class UiPersistenceService {
  constructor(private ui: UiStateService) {}

  init(): void {
    this.restore();

    // Auto-save on changes
    effect(() => {
      const state: PersistedState = {
        leftPanelWidth: this.ui.leftPanelWidth(),
        messagePanelHeight: this.ui.messagePanelHeight(),
        messagePanelVisible: this.ui.messagePanelVisible(),
      };
      try {
        localStorage.setItem(KEY, JSON.stringify(state));
      } catch {}
    });
  }

  get lastProjectDir(): string | undefined {
    try {
      const raw = localStorage.getItem(KEY);
      if (raw) return JSON.parse(raw).lastProjectDir;
    } catch {}
    return undefined;
  }

  set lastProjectDir(dir: string) {
    try {
      const raw = localStorage.getItem(KEY);
      const state = raw ? JSON.parse(raw) : {};
      state.lastProjectDir = dir;
      localStorage.setItem(KEY, JSON.stringify(state));
    } catch {}
  }

  private restore(): void {
    try {
      const raw = localStorage.getItem(KEY);
      if (!raw) return;
      const state: PersistedState = JSON.parse(raw);
      if (state.leftPanelWidth) this.ui.leftPanelWidth.set(state.leftPanelWidth);
      if (state.messagePanelHeight) this.ui.messagePanelHeight.set(state.messagePanelHeight);
      if (state.messagePanelVisible != null) this.ui.messagePanelVisible.set(state.messagePanelVisible);
    } catch {}
  }
}
