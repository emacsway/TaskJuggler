import {
  Component,
  ElementRef,
  ViewChild,
  AfterViewInit,
  OnDestroy,
  effect,
} from '@angular/core';
import { EditorStateService } from '../../core/state/editor-state.service';
import { EditorView, basicSetup } from 'codemirror';
import { EditorState } from '@codemirror/state';
import { keymap } from '@codemirror/view';
import { indentWithTab } from '@codemirror/commands';
import { tjpLanguage } from './tjp-language';

@Component({
  selector: 'app-editor-pane',
  standalone: true,
  template: `
    <div class="editor-container">
      <!-- Tabs -->
      <div class="editor-tabs">
        @for (tab of editorState.tabs(); track tab.path) {
          <div
            class="editor-tab"
            [class.active]="tab.path === editorState.activeTabPath()"
            (click)="editorState.activeTabPath.set(tab.path)"
          >
            <span class="tab-name">{{ fileName(tab.path) }}</span>
            @if (tab.dirty) { <span class="tab-dirty">*</span> }
            <span class="tab-close" (click)="closeTab($event, tab.path)">x</span>
          </div>
        }
      </div>

      <!-- Editor area -->
      <div class="editor-area" #editorHost></div>

      @if (!editorState.activeTab()) {
        <div class="no-file">Open a file from the Files panel</div>
      }
    </div>
  `,
  styles: [`
    .editor-container {
      display: flex;
      flex-direction: column;
      height: 100%;
    }
    .editor-tabs {
      display: flex;
      flex-shrink: 0;
      background: var(--bg-primary);
      border-bottom: 1px solid var(--border-color);
      overflow-x: auto;
    }
    .editor-tab {
      display: flex;
      align-items: center;
      gap: 4px;
      padding: 6px 12px;
      cursor: pointer;
      font-size: 12px;
      color: var(--text-secondary);
      border-right: 1px solid var(--border-color);
      white-space: nowrap;
      &:hover { background: var(--bg-hover); }
      &.active {
        background: var(--bg-secondary);
        color: var(--text-primary);
      }
    }
    .tab-dirty { color: var(--warning-color); }
    .tab-close {
      margin-left: 4px;
      opacity: 0.5;
      &:hover { opacity: 1; }
    }
    .editor-area {
      flex: 1;
      overflow: hidden;
    }
    .editor-area :global(.cm-editor) {
      height: 100%;
    }
    .no-file {
      flex: 1;
      display: flex;
      align-items: center;
      justify-content: center;
      color: var(--text-muted);
    }
  `],
})
export class EditorPaneComponent implements AfterViewInit, OnDestroy {
  @ViewChild('editorHost') editorHost!: ElementRef<HTMLDivElement>;

  private editorView: EditorView | null = null;
  private currentPath: string | null = null;

  constructor(public editorState: EditorStateService) {
    effect(() => {
      const tab = this.editorState.activeTab();
      if (tab && this.editorHost) {
        this.loadEditor(tab.path, tab.content);
      }
    });
  }

  ngAfterViewInit(): void {
    const tab = this.editorState.activeTab();
    if (tab) {
      this.loadEditor(tab.path, tab.content);
    }
  }

  ngOnDestroy(): void {
    this.editorView?.destroy();
  }

  fileName(path: string): string {
    return path.split('/').pop() || path;
  }

  closeTab(event: Event, path: string): void {
    event.stopPropagation();
    this.editorState.closeTab(path);
    if (this.currentPath === path) {
      this.editorView?.destroy();
      this.editorView = null;
      this.currentPath = null;
    }
  }

  private loadEditor(path: string, content: string): void {
    if (this.currentPath === path) return;
    this.currentPath = path;

    this.editorView?.destroy();

    const state = EditorState.create({
      doc: content,
      extensions: [
        basicSetup,
        keymap.of([indentWithTab]),
        tjpLanguage(),
        EditorView.updateListener.of((update) => {
          if (update.docChanged) {
            this.editorState.updateContent(path, update.state.doc.toString());
          }
        }),
        EditorView.theme({
          '&': { height: '100%', backgroundColor: 'var(--bg-primary)' },
          '.cm-content': { caretColor: 'var(--accent-color)' },
          '.cm-gutters': {
            backgroundColor: 'var(--bg-secondary)',
            borderRight: '1px solid var(--border-color)',
            color: 'var(--text-muted)',
          },
          '.cm-activeLineGutter': { backgroundColor: 'var(--bg-active)' },
          '.cm-activeLine': { backgroundColor: 'var(--bg-active)' },
          '&.cm-focused .cm-selectionBackground, .cm-selectionBackground': {
            backgroundColor: '#264f78 !important',
          },
        }, { dark: true }),
      ],
    });

    this.editorView = new EditorView({
      state,
      parent: this.editorHost.nativeElement,
    });
  }
}
