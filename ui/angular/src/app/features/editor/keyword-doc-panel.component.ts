import { Component, signal, computed } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { KeywordDoc } from '../../core/backend/backend.interface';

@Component({
  selector: 'app-keyword-doc-panel',
  standalone: true,
  imports: [FormsModule],
  template: `
    <div class="doc-panel">
      <div class="doc-header">
        <!-- Back navigation -->
        @if (history().length > 1) {
          <button class="nav-btn" (click)="goBack()" title="Back">&larr;</button>
        }
        <span class="doc-title">{{ currentDoc()?.keyword || 'Documentation' }}</span>
        <!-- Search -->
        <input class="doc-search" type="text" placeholder="Search keywords..."
               [ngModel]="searchQuery()" (ngModelChange)="searchQuery.set($event)"/>
        <button class="close-btn" (click)="close()">&times;</button>
      </div>

      @if (searchQuery()) {
        <!-- Search results -->
        <div class="doc-body">
          @for (kw of searchResults(); track kw) {
            <div class="search-item" (click)="navigate(kw)">{{ kw }}</div>
          }
          @if (searchResults().length === 0) {
            <div class="doc-empty">No keywords matching "{{ searchQuery() }}"</div>
          }
        </div>
      } @else if (currentDoc(); as doc) {
        <!-- Keyword documentation -->
        <div class="doc-body">
          @if (doc.syntax) {
            <div class="doc-section">
              <div class="doc-label">Syntax</div>
              <code class="doc-syntax">{{ doc.syntax }}</code>
            </div>
          }

          <div class="doc-section">
            <div class="doc-label">Description</div>
            <div class="doc-text">{{ doc.fullDoc }}</div>
          </div>

          @if (doc.contexts.length > 0) {
            <div class="doc-section">
              <div class="doc-label">Valid in</div>
              <div class="doc-links">
                @for (ctx of doc.contexts; track ctx) {
                  <span class="doc-link" (click)="navigate(ctx)">{{ ctx }}</span>
                }
              </div>
            </div>
          }

          @if (doc.children.length > 0) {
            <div class="doc-section">
              <div class="doc-label">Attributes</div>
              <div class="doc-links">
                @for (child of doc.children; track child) {
                  <span class="doc-link" (click)="navigate(child)">{{ child }}</span>
                }
              </div>
            </div>
          }

          @if (doc.seeAlso.length > 0) {
            <div class="doc-section">
              <div class="doc-label">See also</div>
              <div class="doc-links">
                @for (ref of doc.seeAlso; track ref) {
                  <span class="doc-link" (click)="navigate(ref)">{{ ref }}</span>
                }
              </div>
            </div>
          }

          <div class="doc-section doc-flags">
            @if (doc.scenarioSpecific) { <span class="doc-flag">scenario-specific</span> }
            @if (doc.inheritedFromProject) { <span class="doc-flag">inherited from project</span> }
            @if (doc.inheritedFromParent) { <span class="doc-flag">inherited from parent</span> }
          </div>
        </div>
      } @else {
        <div class="doc-body">
          <div class="doc-empty">Hover over a keyword and click "docs" to view documentation</div>
        </div>
      }
    </div>
  `,
  styles: [`
    .doc-panel {
      display: flex; flex-direction: column; height: 100%;
      background: var(--bg-primary); border-left: 1px solid var(--border-color);
    }
    .doc-header {
      display: flex; align-items: center; gap: 6px;
      padding: 6px 8px; background: var(--bg-secondary);
      border-bottom: 1px solid var(--border-color); flex-shrink: 0;
    }
    .nav-btn {
      background: none; border: none; color: var(--text-secondary);
      cursor: pointer; font-size: 14px; padding: 0 4px;
      &:hover { color: var(--text-primary); }
    }
    .doc-title { font-size: 13px; font-weight: 600; color: var(--accent-color); }
    .doc-search {
      margin-left: auto; width: 140px; padding: 2px 6px; font-size: 11px;
      background: var(--bg-primary); border: 1px solid var(--border-color);
      color: var(--text-primary); border-radius: 3px;
      &:focus { outline: 1px solid var(--accent-color); }
    }
    .close-btn {
      background: none; border: none; color: var(--text-secondary);
      cursor: pointer; font-size: 16px;
      &:hover { color: var(--text-primary); }
    }
    .doc-body { flex: 1; overflow-y: auto; padding: 8px 12px; }
    .doc-section { margin-bottom: 10px; }
    .doc-label {
      font-size: 10px; font-weight: 600; text-transform: uppercase;
      color: var(--text-muted); margin-bottom: 3px;
    }
    .doc-syntax {
      display: block; padding: 6px 8px; font-size: 12px;
      background: var(--bg-secondary); border-radius: 3px;
      color: var(--accent-color); font-family: monospace;
      white-space: pre-wrap;
    }
    .doc-text {
      font-size: 12px; line-height: 1.5; color: var(--text-primary);
      white-space: pre-wrap;
    }
    .doc-links { display: flex; flex-wrap: wrap; gap: 4px; }
    .doc-link {
      padding: 1px 6px; font-size: 11px; border-radius: 3px; cursor: pointer;
      background: var(--bg-active); color: var(--accent-color);
      &:hover { background: var(--bg-hover); text-decoration: underline; }
    }
    .doc-flags { display: flex; gap: 6px; flex-wrap: wrap; }
    .doc-flag {
      font-size: 10px; padding: 1px 6px; border-radius: 3px;
      background: #2d3a1e; color: var(--success-color);
    }
    .search-item {
      padding: 4px 8px; font-size: 12px; cursor: pointer;
      color: var(--text-primary); border-radius: 3px;
      &:hover { background: var(--bg-hover); }
    }
    .doc-empty {
      padding: 20px; text-align: center; color: var(--text-muted); font-size: 12px;
    }
  `],
})
export class KeywordDocPanelComponent {
  private allDocs = signal<Record<string, KeywordDoc>>({});
  readonly searchQuery = signal('');
  readonly history = signal<string[]>([]);

  readonly currentDoc = computed(() => {
    const h = this.history();
    if (h.length === 0) return null;
    return this.allDocs()[h[h.length - 1]] || null;
  });

  readonly searchResults = computed(() => {
    const q = this.searchQuery().toLowerCase();
    if (!q) return [];
    return Object.keys(this.allDocs())
      .filter(k => k.includes(q))
      .sort()
      .slice(0, 50);
  });

  setDocs(docs: Record<string, KeywordDoc>): void {
    this.allDocs.set(docs);
  }

  open(keyword: string): void {
    this.searchQuery.set('');
    const base = keyword.split('.').pop() || keyword;
    if (this.allDocs()[base]) {
      this.history.set([base]);
    }
  }

  navigate(keyword: string): void {
    this.searchQuery.set('');
    const base = keyword.split('.').pop() || keyword;
    if (this.allDocs()[base]) {
      this.history.update(h => [...h, base]);
    }
  }

  goBack(): void {
    this.history.update(h => h.slice(0, -1));
  }

  close(): void {
    this.history.set([]);
  }
}
