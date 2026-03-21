import { Component, computed, ElementRef, ViewChild } from '@angular/core';
import { ProjectStateService } from '../../core/state/project-state.service';
import { GanttTask } from '../../core/models';

@Component({
  selector: 'app-gantt-chart',
  standalone: true,
  template: `
    <div class="gantt-container">
      @if (ganttData(); as data) {
        <div class="gantt-wrapper" #ganttWrapper>
          <!-- Header (time scale) -->
          <div class="gantt-header" [style.width.px]="chartWidth()">
            @for (label of timeLabels(); track label.x) {
              <div class="time-label" [style.left.px]="label.x">{{ label.text }}</div>
            }
          </div>

          <!-- Rows -->
          <div class="gantt-body" [style.width.px]="chartWidth()">
            <!-- Now line -->
            <div class="now-line" [style.left.px]="nowPosition()"></div>

            @for (task of data.tasks; track task.taskId) {
              <div class="gantt-row">
                <!-- Task name -->
                <div class="gantt-row-label" [style.padding-left.px]="task.level * 12 + 8">
                  {{ task.name }}
                </div>
                <!-- Bar area -->
                <div class="gantt-row-bar">
                  @if (task.isMilestone) {
                    <div
                      class="milestone"
                      [style.left.px]="dateToX(task.start)"
                    ></div>
                  } @else {
                    <div
                      class="task-bar"
                      [class.container]="task.isContainer"
                      [style.left.px]="dateToX(task.start)"
                      [style.width.px]="barWidth(task)"
                    >
                      @if (task.complete > 0) {
                        <div class="complete-bar" [style.width.%]="task.complete"></div>
                      }
                    </div>
                  }
                </div>
              </div>
            }
          </div>
        </div>
      } @else {
        <div class="placeholder">Schedule a project to see the Gantt chart</div>
      }
    </div>
  `,
  styles: [`
    .gantt-container {
      height: 100%;
      overflow: auto;
    }
    .gantt-wrapper {
      min-width: 100%;
      position: relative;
    }
    .gantt-header {
      position: sticky;
      top: 0;
      height: 28px;
      background: var(--bg-secondary);
      border-bottom: 1px solid var(--border-color);
      z-index: 2;
    }
    .time-label {
      position: absolute;
      top: 0;
      font-size: 10px;
      color: var(--text-secondary);
      padding: 6px 4px;
      border-left: 1px solid var(--border-color);
      white-space: nowrap;
    }
    .gantt-body {
      position: relative;
    }
    .now-line {
      position: absolute;
      top: 0;
      bottom: 0;
      width: 2px;
      background: var(--gantt-now-line);
      z-index: 1;
      opacity: 0.7;
    }
    .gantt-row {
      display: flex;
      height: 28px;
      border-bottom: 1px solid var(--border-color);
      &:hover { background: var(--bg-hover); }
    }
    .gantt-row-label {
      width: 200px;
      flex-shrink: 0;
      font-size: 12px;
      line-height: 28px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      border-right: 1px solid var(--border-color);
      color: var(--text-primary);
    }
    .gantt-row-bar {
      flex: 1;
      position: relative;
    }
    .task-bar {
      position: absolute;
      top: 6px;
      height: 16px;
      background: var(--gantt-task);
      border-radius: 3px;
      min-width: 4px;
      &.container {
        background: var(--gantt-container);
        height: 10px;
        top: 9px;
        border-radius: 2px;
      }
    }
    .complete-bar {
      height: 100%;
      background: var(--gantt-complete);
      border-radius: 3px 0 0 3px;
    }
    .milestone {
      position: absolute;
      top: 8px;
      width: 12px;
      height: 12px;
      background: var(--gantt-milestone);
      transform: rotate(45deg);
      margin-left: -6px;
    }
    .placeholder {
      display: flex;
      align-items: center;
      justify-content: center;
      height: 100%;
      color: var(--text-muted);
    }
  `],
})
export class GanttChartComponent {
  @ViewChild('ganttWrapper') ganttWrapper!: ElementRef;

  private pixelsPerDay = 3;

  constructor(public project: ProjectStateService) {}

  ganttData = computed(() => this.project.ganttData());

  chartWidth = computed(() => {
    const data = this.ganttData();
    if (!data) return 800;
    const days = this.daysBetween(data.projectStart, data.projectEnd);
    return Math.max(800, 200 + days * this.pixelsPerDay);
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

    const current = new Date(start.getFullYear(), start.getMonth(), 1);
    while (current <= end) {
      const x = this.dateToX(current.toISOString());
      const text = current.toLocaleDateString('en', { year: 'numeric', month: 'short' });
      labels.push({ x, text });
      current.setMonth(current.getMonth() + 1);
    }

    return labels;
  });

  dateToX(dateStr: string): number {
    const data = this.ganttData();
    if (!data) return 0;
    const days = this.daysBetween(data.projectStart, dateStr);
    return 200 + days * this.pixelsPerDay;
  }

  barWidth(task: GanttTask): number {
    const days = this.daysBetween(task.start, task.end);
    return Math.max(4, days * this.pixelsPerDay);
  }

  private daysBetween(a: string, b: string): number {
    const msPerDay = 86400000;
    return (new Date(b).getTime() - new Date(a).getTime()) / msPerDay;
  }
}
