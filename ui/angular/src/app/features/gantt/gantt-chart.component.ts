import { Component, computed, signal, HostListener, effect } from '@angular/core';
import { SlicePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ProjectStateService } from '../../core/state/project-state.service';
import { EditorStateService } from '../../core/state/editor-state.service';
import { UiStateService } from '../../core/state/ui-state.service';
import { TjBackend, CompareResult } from '../../core/backend/backend.interface';
import { GanttTask, GanttData } from '../../core/models';
import { GanttFilterComponent } from './gantt-filter.component';

interface DepLine {
  x1: number; y1: number;
  x2: number; y2: number;
  midX: number;
}

const ZOOM_LEVELS = [
  { label: 'Days', pixelsPerDay: 20 },
  { label: 'Weeks', pixelsPerDay: 6 },
  { label: 'Months', pixelsPerDay: 3 },
  { label: 'Quarters', pixelsPerDay: 1 },
];

@Component({
  selector: 'app-gantt-chart',
  standalone: true,
  imports: [SlicePipe, FormsModule, GanttFilterComponent],
  template: `
    <div class="gantt-container">
      @if (ganttData(); as data) {
        <!-- Zoom toolbar -->
        <div class="gantt-toolbar">
          @if (project.scenarios().length > 1) {
            <span class="toolbar-label">Scenario:</span>
            <select class="toolbar-select" [ngModel]="ui.activeScenario()" (ngModelChange)="switchScenario($event)">
              @for (s of project.scenarios(); track s.id) {
                <option [value]="s.id">{{ s.name }}</option>
              }
            </select>
            <span class="toolbar-sep"></span>
          }
          <span class="toolbar-label">Zoom:</span>
          @for (z of zoomLevels; track z.label; let i = $index) {
            <button
              class="zoom-btn"
              [class.active]="zoomIndex() === i"
              (click)="zoomIndex.set(i)"
            >{{ z.label }}</button>
          }
          <span class="toolbar-sep"></span>
          <button class="zoom-btn" [class.active]="compareMode()"
                  (click)="toggleCompare()"
                  [disabled]="compareLoading()"
                  title="Compare Standard vs Optimized schedule">
            {{ compareLoading() ? 'Comparing...' : compareMode() ? 'Hide Compare' : 'Compare' }}
          </button>
        </div>

        <app-gantt-filter (filterChanged)="onFilterChanged($event)"></app-gantt-filter>

        <div class="gantt-scroll" #ganttScroll>
          <div class="gantt-wrapper" [style.width.px]="chartWidth()">
            <!-- Header -->
            <div class="gantt-header">
              <div class="header-label-spacer" [style.width.px]="labelWidth()">
                <span>Task</span>
                <div class="label-resize-handle" (mousedown)="startLabelResize($event)"></div>
              </div>
              <div class="header-timeline">
                @for (label of timeLabels(); track label.x) {
                  <div class="time-label" [style.left.px]="label.x">{{ label.text }}</div>
                }
              </div>
            </div>

            <!-- Body -->
            <div class="gantt-body">
              <!-- Grid lines -->
              @for (label of timeLabels(); track label.x) {
                <div class="grid-line" [style.left.px]="label.x + labelWidth()"></div>
              }

              <!-- Now line -->
              <div class="now-line" [style.left.px]="nowPosition()"></div>

              <!-- Dependency arrows (SVG overlay) -->
              <svg class="dep-layer" [attr.width]="chartWidth()" [attr.height]="filteredTasks().length * rowHeight">
                @for (dep of dependencyLines(); track $index) {
                  <path
                    [attr.d]="depPath(dep)"
                    class="dep-arrow"
                    marker-end="url(#arrowhead)"
                  />
                }
                <defs>
                  <marker id="arrowhead" markerWidth="6" markerHeight="4" refX="6" refY="2" orient="auto">
                    <polygon points="0 0, 6 2, 0 4" fill="#808080" opacity="0.5" />
                  </marker>
                </defs>
              </svg>

              <!-- Rows -->
              @for (task of filteredTasks(); track task.taskId; let i = $index) {
                <div class="gantt-row" [class.alt]="i % 2 === 1"
                     [class.selected]="ui.selectedTaskId() === task.taskId"
                     (click)="selectTask(task.taskId)"
                     (dblclick)="navigateToSource(task)">
                  <div class="gantt-row-label" [style.width.px]="labelWidth()" [style.padding-left.px]="task.level * 12 + 4">
                    @if (task.isContainer) {
                      <span class="collapse-toggle" (click)="toggleCollapse($event, task)">
                        {{ isCollapsed(task.taskId) ? '&#9654;' : '&#9660;' }}
                      </span>
                    } @else {
                      <span class="collapse-spacer"></span>
                    }
                    <span class="row-icon" [class.milestone]="task.isMilestone" [class.container]="task.isContainer">
                      {{ task.isMilestone ? '&#9670;' : task.isContainer ? '&#9656;' : '&#9679;' }}
                    </span>
                    {{ task.name }}
                  </div>
                  <div class="gantt-row-bar">
                    <!-- Ghost bar (standard schedule) for comparison -->
                    @if (compareMode() && getStdTask(task.taskId); as std) {
                      @if (!task.isMilestone) {
                        <div class="ghost-bar"
                             [style.left.px]="dateToX(std.start) - labelWidth()"
                             [style.width.px]="ghostBarWidth(std)"
                             [title]="'Standard: ' + (std.start | slice:0:10) + ' - ' + (std.end | slice:0:10)"
                        ></div>
                      }
                    }

                    @if (task.isMilestone) {
                      <div
                        class="milestone"
                        [style.left.px]="dateToX(task.start) - labelWidth()"
                        [title]="task.name + ' (' + (task.start | slice:0:10) + ')'"
                      ></div>
                    } @else {
                      <div
                        class="task-bar"
                        [class.container]="task.isContainer"
                        [class.improved]="compareMode() && isImproved(task)"
                        [class.worsened]="compareMode() && isWorsened(task)"
                        [style.left.px]="dateToX(task.start) - labelWidth()"
                        [style.width.px]="barWidth(task)"
                        [title]="compareMode() ? compareTooltip(task) : barTooltip(task)"
                      >
                        @if (task.complete > 0 && !task.isContainer) {
                          <div class="complete-fill" [style.width.%]="task.complete"></div>
                        }
                      </div>
                    }
                  </div>
                </div>
              }
            </div>
          </div>
        </div>
      } @else {
        <div class="placeholder">Schedule a project to see the Gantt chart</div>
      }
    </div>
  `,
  styles: [`
    .gantt-container { display: flex; flex-direction: column; height: 100%; }
    .gantt-toolbar {
      display: flex; align-items: center; gap: 4px;
      padding: 4px 8px;
      background: var(--bg-secondary);
      border-bottom: 1px solid var(--border-color);
      flex-shrink: 0;
    }
    .toolbar-label { font-size: 11px; color: var(--text-secondary); }
    .toolbar-select {
      padding: 2px 6px; background: var(--bg-primary); border: 1px solid var(--border-color);
      color: var(--text-primary); border-radius: 3px; font-size: 11px;
      &:focus { outline: 1px solid var(--accent-color); }
    }
    .toolbar-sep { width: 1px; height: 16px; background: var(--border-color); margin: 0 4px; }
    .zoom-label { font-size: 11px; color: var(--text-secondary); margin-right: 4px; }
    .zoom-btn {
      padding: 2px 8px; font-size: 11px;
      background: var(--bg-active); color: var(--text-secondary);
      border: 1px solid var(--border-color); border-radius: 3px; cursor: pointer;
      &:hover { color: var(--text-primary); }
      &.active { background: #0e639c; color: var(--text-primary); border-color: #1177bb; }
    }
    .gantt-scroll { flex: 1; overflow: auto; }
    .gantt-wrapper { min-width: 100%; position: relative; }
    .gantt-header {
      display: flex; position: sticky; top: 0; height: 28px;
      background: var(--bg-secondary); border-bottom: 1px solid var(--border-color); z-index: 3;
    }
    .header-label-spacer {
      flex-shrink: 0; border-right: 1px solid var(--border-color);
      position: relative; display: flex; align-items: center;
      padding: 0 8px; font-size: 11px; font-weight: 600; color: var(--text-secondary);
      text-transform: uppercase;
    }
    .label-resize-handle {
      position: absolute; right: -3px; top: 0; bottom: 0; width: 6px;
      cursor: col-resize; z-index: 5;
      &:hover { background: var(--accent-color); opacity: 0.5; }
    }
    .header-timeline { flex: 1; position: relative; }
    .time-label {
      position: absolute; top: 0; font-size: 10px; color: var(--text-secondary);
      padding: 6px 4px; border-left: 1px solid var(--border-color); white-space: nowrap;
    }
    .gantt-body { position: relative; }
    .grid-line {
      position: absolute; top: 0; bottom: 0; width: 1px;
      background: var(--border-color); opacity: 0.3; z-index: 0;
    }
    .now-line {
      position: absolute; top: 0; bottom: 0; width: 2px;
      background: var(--gantt-now-line); z-index: 2; opacity: 0.8;
    }
    .dep-layer { position: absolute; top: 0; left: 0; z-index: 1; pointer-events: none; }
    .dep-arrow { fill: none; stroke: var(--gantt-dependency); stroke-width: 0.7; opacity: 0.5; }
    .gantt-row {
      display: flex; height: 28px; border-bottom: 1px solid var(--border-color); cursor: pointer;
      &.alt { background: rgba(255,255,255,0.015); }
      &:hover { background: var(--bg-hover); }
      &.selected { background: #264f78; }
    }
    .gantt-row-label {
      flex-shrink: 0; font-size: 12px; line-height: 28px;
      overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
      border-right: 1px solid var(--border-color); color: var(--text-primary);
      display: flex; align-items: center; gap: 4px;
      background: var(--bg-primary); position: relative; z-index: 2;
    }
    .gantt-row.alt .gantt-row-label { background: rgba(30,30,30,1); }
    .gantt-row:hover .gantt-row-label { background: var(--bg-hover); }
    .gantt-row.selected .gantt-row-label { background: #264f78; }
    .collapse-toggle {
      font-size: 7px; width: 12px; flex-shrink: 0; cursor: pointer;
      color: var(--text-muted); text-align: center;
      &:hover { color: var(--text-primary); }
    }
    .collapse-spacer { width: 12px; flex-shrink: 0; display: inline-block; }
    .row-icon {
      font-size: 7px; color: var(--gantt-task);
      &.milestone { color: var(--gantt-milestone); }
      &.container { color: var(--gantt-container); }
    }
    .gantt-row-bar { flex: 1; position: relative; overflow: hidden; }
    .ghost-bar {
      position: absolute; top: 8px; height: 12px;
      background: #555; border-radius: 3px; min-width: 4px;
      opacity: 0.3; border: 1px dashed #888;
    }
    .task-bar {
      position: absolute; top: 6px; height: 16px;
      background: var(--gantt-task); border-radius: 3px; min-width: 4px;
      overflow: hidden; cursor: pointer;
      &.container { background: var(--gantt-container); height: 8px; top: 10px; border-radius: 2px; }
      &:hover { filter: brightness(1.2); }
      &.improved { background: var(--success-color); }
      &.worsened { background: var(--error-color); }
    }
    .complete-fill {
      height: 100%; background: var(--gantt-complete); border-radius: 3px 0 0 3px;
    }
    .gantt-row-bar .milestone {
      position: absolute; top: 8px; width: 12px; height: 12px;
      background: var(--gantt-milestone); transform: rotate(45deg); margin-left: -6px;
      cursor: pointer;
      &:hover { filter: brightness(1.3); }
    }
    .placeholder {
      display: flex; align-items: center; justify-content: center;
      height: 100%; color: var(--text-muted);
    }
  `],
})
export class GanttChartComponent {
  readonly zoomLevels = ZOOM_LEVELS;
  readonly zoomIndex = signal(2);
  readonly labelWidth = signal(200);
  readonly rowHeight = 28;

  // For label column resize drag
  private draggingLabel = false;
  private dragStartX = 0;
  private dragStartWidth = 0;

  private filterFn = signal<(task: GanttTask) => boolean>(() => true);
  readonly collapsed = signal(new Set<string>());

  // Compare mode
  readonly compareMode = signal(false);
  readonly compareLoading = signal(false);
  private stdTasks = new Map<string, GanttTask>();
  private savedGanttData: GanttData | null = null;

  constructor(
    public project: ProjectStateService,
    public ui: UiStateService,
    private editor: EditorStateService,
    private backend: TjBackend
  ) {
    // Publish filtered task IDs for Monte Carlo scope
    effect(() => {
      const tasks = this.filteredTasks();
      const allData = this.ganttData();
      if (!allData) { this.ui.filteredTaskIds.set(null); return; }

      const isFiltered = tasks.length < allData.tasks.length;
      if (isFiltered) {
        // Include all filtered tasks (both leaf and container) for makespan scope
        this.ui.filteredTaskIds.set(tasks.map(t => t.taskId));
      } else {
        this.ui.filteredTaskIds.set(null);
      }
    });
  }

  onFilterChanged(fn: (task: GanttTask) => boolean): void {
    this.filterFn.set(fn);
  }

  switchScenario(scenarioId: string): void {
    this.ui.activeScenario.set(scenarioId);
    this.project.loadProjectData(scenarioId);
  }

  selectTask(taskId: string): void {
    this.ui.selectedTaskId.set(taskId);
  }

  toggleCompare(): void {
    if (this.compareMode()) {
      this.compareMode.set(false);
      this.stdTasks.clear();
      // Restore original gantt data
      if (this.savedGanttData) {
        this.project.ganttData.set(this.savedGanttData);
        this.savedGanttData = null;
      }
      return;
    }

    const sid = this.project.sessionId();
    const master = this.project.masterFile();
    if (!sid || !master) return;

    this.compareLoading.set(true);
    this.savedGanttData = this.project.ganttData();
    const scenario = this.ui.activeScenario() || undefined;
    this.backend.compareSchedules(sid, master, scenario).subscribe({
      next: (result) => {
        // Standard schedule → ghost bars
        this.stdTasks.clear();
        if (result.standard?.tasks) {
          result.standard.tasks.forEach(t => this.stdTasks.set(t.taskId, t));
        }
        // Optimized schedule → current gantt display
        if (result.optimized) {
          this.project.ganttData.set(result.optimized);
        }
        this.compareMode.set(true);
        this.compareLoading.set(false);
      },
      error: () => {
        this.compareLoading.set(false);
      },
    });
  }

  getStdTask(taskId: string): GanttTask | undefined {
    return this.stdTasks.get(taskId);
  }

  ghostBarWidth(std: GanttTask): number {
    const days = this.daysBetween(std.start, std.end);
    return Math.max(4, days * this.ppd());
  }

  isImproved(task: GanttTask): boolean {
    const std = this.stdTasks.get(task.taskId);
    if (!std) return false;
    return new Date(task.end).getTime() < new Date(std.end).getTime() - 3600000;
  }

  isWorsened(task: GanttTask): boolean {
    const std = this.stdTasks.get(task.taskId);
    if (!std) return false;
    return new Date(task.end).getTime() > new Date(std.end).getTime() + 3600000;
  }

  compareTooltip(task: GanttTask): string {
    const std = this.stdTasks.get(task.taskId);
    if (!std) return this.barTooltip(task);
    const optEnd = task.end?.slice(0, 10);
    const stdEnd = std.end?.slice(0, 10);
    const diffDays = ((new Date(task.end).getTime() - new Date(std.end).getTime()) / 86400000).toFixed(0);
    const sign = Number(diffDays) <= 0 ? '' : '+';
    return `${task.name}\nOptimized: ${task.start?.slice(0,10)} - ${optEnd}\nStandard:  ${std.start?.slice(0,10)} - ${stdEnd}\nDelta: ${sign}${diffDays} days`;
  }

  toggleCollapse(event: Event, task: GanttTask): void {
    event.stopPropagation();
    if (!task.isContainer) return;
    const next = new Set(this.collapsed());
    if (next.has(task.taskId)) {
      next.delete(task.taskId);
    } else {
      next.add(task.taskId);
    }
    this.collapsed.set(next);
  }

  isCollapsed(taskId: string): boolean {
    return this.collapsed().has(taskId);
  }

  startLabelResize(event: MouseEvent): void {
    event.preventDefault();
    this.draggingLabel = true;
    this.dragStartX = event.clientX;
    this.dragStartWidth = this.labelWidth();
  }

  @HostListener('document:mousemove', ['$event'])
  onMouseMove(event: MouseEvent): void {
    if (!this.draggingLabel) return;
    const newWidth = Math.max(100, this.dragStartWidth + (event.clientX - this.dragStartX));
    this.labelWidth.set(newWidth);
  }

  @HostListener('document:mouseup')
  onMouseUp(): void {
    this.draggingLabel = false;
  }

  navigateToSource(task: GanttTask): void {
    if (!task.sourceFile) return;
    const sid = this.project.sessionId();
    if (!sid) return;

    this.backend.readFile(sid, task.sourceFile).subscribe((content) => {
      this.editor.openFile(task.sourceFile!, content, task.sourceLine ?? undefined);
      this.ui.rightPanelMode.set('editor');
    });
  }

  private ppd = computed(() => ZOOM_LEVELS[this.zoomIndex()].pixelsPerDay);

  filteredTasks = computed((): GanttTask[] => {
    const data = this.ganttData();
    if (!data) return [];
    const fn = this.filterFn();
    const collapsedSet = this.collapsed();

    // Find tasks matching filter
    const matching = new Set<string>();
    for (const task of data.tasks) {
      if (fn(task)) matching.add(task.taskId);
    }

    // Also include parents of matching tasks (to preserve tree structure)
    const visible = new Set(matching);
    for (const task of data.tasks) {
      if (matching.has(task.taskId)) {
        for (const other of data.tasks) {
          if (other.isContainer && task.taskId.startsWith(other.taskId + '.')) {
            visible.add(other.taskId);
          }
        }
      }
    }

    // Hide children of collapsed containers
    const result = data.tasks.filter(t => {
      if (!visible.has(t.taskId)) return false;
      for (const cid of collapsedSet) {
        if (t.taskId !== cid && t.taskId.startsWith(cid + '.')) {
          return false;
        }
      }
      return true;
    });

    return result;
  });

  ganttData = computed(() => this.project.ganttData());

  chartWidth = computed(() => {
    const data = this.ganttData();
    if (!data) return 800;
    const days = this.daysBetween(data.projectStart, data.projectEnd);
    return Math.max(800, this.labelWidth() + days * this.ppd());
  });

  nowPosition = computed(() => {
    const data = this.ganttData();
    if (!data) return 0;
    return this.dateToX(data.now);
  });

  timeLabels = computed(() => {
    const data = this.ganttData();
    if (!data) return [];
    const labels: { x: number; text: string }[] = [];
    const start = new Date(data.projectStart);
    const end = new Date(data.projectEnd);

    const ppd = this.ppd();
    if (ppd >= 10) {
      // Weekly labels
      const cur = new Date(start);
      cur.setDate(cur.getDate() - cur.getDay() + 1);
      while (cur <= end) {
        const x = this.daysBetween(data.projectStart, cur.toISOString()) * ppd;
        labels.push({ x, text: cur.toLocaleDateString('en', { month: 'short', day: 'numeric' }) });
        cur.setDate(cur.getDate() + 7);
      }
    } else {
      // Monthly labels
      const cur = new Date(start.getFullYear(), start.getMonth(), 1);
      while (cur <= end) {
        const x = this.daysBetween(data.projectStart, cur.toISOString()) * ppd;
        labels.push({ x, text: cur.toLocaleDateString('en', { year: 'numeric', month: 'short' }) });
        cur.setMonth(cur.getMonth() + 1);
      }
    }
    return labels;
  });

  dependencyLines = computed((): DepLine[] => {
    const tasks = this.filteredTasks();
    if (!tasks.length) return [];
    const lines: DepLine[] = [];
    const taskIndex = new Map<string, number>();
    tasks.forEach((t, i) => taskIndex.set(t.taskId, i));

    for (const task of tasks) {
      for (const dep of task.dependencies) {
        if (!dep.toTaskId) continue;
        const fromIdx = taskIndex.get(dep.toTaskId);
        const toIdx = taskIndex.get(task.taskId);
        if (fromIdx == null || toIdx == null) continue;

        const fromTask = tasks[fromIdx];
        const toTask = tasks[toIdx];

        const x1 = this.dateToX(fromTask.end);
        const y1 = fromIdx * this.rowHeight + this.rowHeight / 2;
        const x2 = this.dateToX(toTask.start);
        const y2 = toIdx * this.rowHeight + this.rowHeight / 2;
        const midX = Math.max(x1 + 8, (x1 + x2) / 2);

        lines.push({ x1, y1, x2, y2, midX });
      }
    }
    return lines;
  });

  dateToX(dateStr: string): number {
    const data = this.ganttData();
    if (!data) return 0;
    return this.labelWidth() + this.daysBetween(data.projectStart, dateStr) * this.ppd();
  }

  barWidth(task: GanttTask): number {
    const days = this.daysBetween(task.start, task.end);
    return Math.max(4, days * this.ppd());
  }

  barTooltip(task: GanttTask): string {
    const start = task.start?.slice(0, 10) || '';
    const end = task.end?.slice(0, 10) || '';
    const complete = task.complete != null ? ` (${task.complete}%)` : '';
    return `${task.name}: ${start} - ${end}${complete}`;
  }

  depPath(dep: DepLine): string {
    // Route: right from source end, then down/up, then right to target start
    return `M${dep.x1},${dep.y1} H${dep.midX} V${dep.y2} H${dep.x2}`;
  }

  private daysBetween(a: string, b: string): number {
    return (new Date(b).getTime() - new Date(a).getTime()) / 86400000;
  }
}
