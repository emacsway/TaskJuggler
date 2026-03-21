import {
  Component,
  ElementRef,
  ViewChild,
  AfterViewInit,
  OnDestroy,
  effect,
} from '@angular/core';
import { EditorStateService } from '../../core/state/editor-state.service';
import { ProjectStateService } from '../../core/state/project-state.service';
import { TjBackend } from '../../core/backend/backend.interface';
import { EditorView, basicSetup } from 'codemirror';
import { EditorState } from '@codemirror/state';
import { keymap } from '@codemirror/view';
import { indentWithTab } from '@codemirror/commands';
import { linter, setDiagnostics } from '@codemirror/lint';
import { tjpLanguage } from './tjp-language';
import { tjpAutocomplete } from './tjp-autocomplete';
import { mapDiagnostics } from './tjp-linter';
import { PertCalculatorComponent, PertResult } from './pert-calculator.component';

@Component({
  selector: 'app-editor-pane',
  standalone: true,
  imports: [PertCalculatorComponent],
  template: `
    <div class="editor-container">
      <div class="editor-tabs">
        @for (tab of editorState.tabs(); track tab.path) {
          <div
            class="editor-tab"
            [class.active]="tab.path === editorState.activeTabPath()"
            (click)="editorState.activeTabPath.set(tab.path)"
          >
            <span class="tab-name">{{ fileName(tab.path) }}</span>
            @if (tab.dirty) { <span class="tab-dirty">&bull;</span> }
            <span class="tab-close" (click)="closeTab($event, tab.path)">&times;</span>
          </div>
        }
        @if (editorState.dirtyFiles().length > 0) {
          <button class="save-btn" (click)="saveAll()">Save All</button>
        }
      </div>

      <div class="editor-area" #editorHost></div>

      @if (!editorState.activeTab()) {
        <div class="no-file">Open a file from the Files panel</div>
      }
    </div>

    @if (showPert) {
      <app-pert-calculator
        (close)="showPert = false"
        (insertResult)="onPertInsert($event)"
      ></app-pert-calculator>
    }
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
      align-items: center;
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
    .tab-dirty { color: var(--warning-color); font-size: 16px; line-height: 1; }
    .tab-close {
      margin-left: 4px;
      opacity: 0.4;
      font-size: 14px;
      &:hover { opacity: 1; }
    }
    .save-btn {
      margin-left: auto;
      margin-right: 8px;
      padding: 2px 10px;
      font-size: 11px;
      background: #0e639c;
      color: var(--text-primary);
      border: none;
      border-radius: 3px;
      cursor: pointer;
      &:hover { background: #1177bb; }
    }
    .editor-area {
      flex: 1;
      overflow: hidden;
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
  showPert = false;

  constructor(
    public editorState: EditorStateService,
    private projectState: ProjectStateService,
    private backend: TjBackend
  ) {
    // React to active tab changes
    effect(() => {
      const tab = this.editorState.activeTab();
      if (tab && this.editorHost) {
        this.loadEditor(tab.path, tab.content);
      }
    });

    // React to navigation requests (click on error/task -> scroll to line)
    effect(() => {
      const nav = this.editorState.pendingNavigation();
      if (nav && this.editorView && this.currentPath === nav.path) {
        this.scrollToLine(nav.line);
        this.editorState.pendingNavigation.set(null);
      }
    });

    // React to diagnostic messages -> update linter squiggles
    effect(() => {
      const messages = this.projectState.messages();
      if (this.editorView && this.currentPath) {
        const diagnostics = mapDiagnostics(this.editorView, messages, this.currentPath);
        this.editorView.dispatch(setDiagnostics(this.editorView.state, diagnostics));
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

  saveAll(): void {
    const sid = this.projectState.sessionId();
    if (!sid) return;

    for (const tab of this.editorState.tabs()) {
      if (tab.dirty) {
        this.backend.writeFile(sid, tab.path, tab.content).subscribe(() => {
          this.editorState.markSaved(tab.path);
        });
      }
    }
  }

  onPertInsert(result: PertResult): void {
    this.showPert = false;
    if (!this.editorView) return;

    const view = this.editorView;
    const pos = view.state.selection.main.head;
    const line = view.state.doc.lineAt(pos);

    // Detect indentation of current line
    const indent = line.text.match(/^(\s*)/)?.[1] || '    ';

    // Check if cursor is on a line that already has "effort"
    const hasEffort = /^\s*effort\b/.test(line.text);

    let text: string;
    if (hasEffort) {
      // Replace current line and add stdev after
      const replacement = `${indent}effort ${result.effort}${result.unit}\n${indent}stdev ${result.stdev}${result.unit}`;
      view.dispatch({
        changes: { from: line.from, to: line.to, insert: replacement },
      });
    } else {
      // Insert at cursor position
      text = `effort ${result.effort}${result.unit}\n${indent}stdev ${result.stdev}${result.unit}`;
      view.dispatch({
        changes: { from: pos, insert: text },
      });
    }

    view.focus();
  }

  private scrollToLine(line: number): void {
    if (!this.editorView) return;
    const doc = this.editorView.state.doc;
    const lineNum = Math.min(line, doc.lines);
    if (lineNum < 1) return;

    const lineObj = doc.line(lineNum);
    this.editorView.dispatch({
      selection: { anchor: lineObj.from },
      scrollIntoView: true,
    });
    this.editorView.focus();
  }

  private loadEditor(path: string, content: string): void {
    if (this.currentPath === path) return;
    this.currentPath = path;

    this.editorView?.destroy();

    const state = EditorState.create({
      doc: content,
      extensions: [
        basicSetup,
        keymap.of([
          indentWithTab,
          {
            key: 'Mod-s',
            run: () => { this.saveAll(); return true; },
          },
          {
            key: 'Ctrl-Shift-e',
            run: () => { this.showPert = true; return true; },
          },
        ]),
        tjpLanguage(),
        tjpAutocomplete(
          () => ({
            tasks: this.projectState.tasks().map(t => t.id),
            resources: this.projectState.resources().map(r => r.id),
          }),
          () => { this.showPert = true; }
        ),
        linter(() => []),
        EditorView.updateListener.of((update) => {
          if (update.docChanged) {
            this.editorState.updateContent(path, update.state.doc.toString());
          }
        }),
        EditorView.theme({
          '&': { height: '100%', backgroundColor: '#1e1e1e' },
          '.cm-content': { caretColor: '#4fc1ff', fontFamily: "'JetBrains Mono', 'Fira Code', 'Cascadia Code', monospace", fontSize: '13px' },
          '.cm-gutters': {
            backgroundColor: '#252526',
            borderRight: '1px solid #3c3c3c',
            color: '#5a5a5a',
          },
          '.cm-activeLineGutter': { backgroundColor: '#37373d' },
          '.cm-activeLine': { backgroundColor: '#37373d' },
          '&.cm-focused .cm-selectionBackground, .cm-selectionBackground': {
            backgroundColor: '#264f78 !important',
          },
          '.cm-diagnostic-error': { borderLeftColor: '#f44747' },
          '.cm-diagnostic-warning': { borderLeftColor: '#cca700' },
          '.cm-lintRange-error': { backgroundImage: 'none', textDecoration: 'wavy underline #f44747' },
          '.cm-lintRange-warning': { backgroundImage: 'none', textDecoration: 'wavy underline #cca700' },
        }, { dark: true }),
      ],
    });

    this.editorView = new EditorView({
      state,
      parent: this.editorHost.nativeElement,
    });

    // Apply pending diagnostics
    const messages = this.projectState.messages();
    if (messages.length > 0) {
      const diagnostics = mapDiagnostics(this.editorView, messages, path);
      this.editorView.dispatch(setDiagnostics(this.editorView.state, diagnostics));
    }

    // Apply pending navigation
    const nav = this.editorState.pendingNavigation();
    if (nav && nav.path === path) {
      setTimeout(() => {
        this.scrollToLine(nav.line);
        this.editorState.pendingNavigation.set(null);
      });
    }
  }
}
