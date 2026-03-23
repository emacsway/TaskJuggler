import { Component, signal, computed } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ProjectStateService } from '../../core/state/project-state.service';
import { UiStateService } from '../../core/state/ui-state.service';
import { TjBackend, MonteCarloResult } from '../../core/backend/backend.interface';

@Component({
  selector: 'app-monte-carlo',
  standalone: true,
  imports: [FormsModule],
  template: `
    <div class="mc-container">
      <div class="mc-header">
        <h3>Monte Carlo Simulation</h3>
        <p class="mc-desc">Estimate schedule uncertainty using effort stdev values</p>
      </div>

      <div class="mc-controls">
        <label>Runs:</label>
        <input type="number" [(ngModel)]="numRuns" min="5" max="100" step="5" class="mc-input"/>
        <button class="mc-btn" (click)="run()" [disabled]="loading()">
          {{ loading() ? 'Running...' : 'Run Simulation' }}
        </button>
        @if (scopeInfo()) {
          <span class="mc-scope">{{ scopeInfo() }}</span>
        }
      </div>

      @if (result(); as r) {
        <div class="mc-results">
          <!-- Percentile cards -->
          <div class="mc-cards">
            <div class="mc-card">
              <div class="card-label">P50 (median)</div>
              <div class="card-value">{{ r.p50 }}</div>
              <div class="card-unit">working days</div>
            </div>
            <div class="mc-card highlight">
              <div class="card-label">P80</div>
              <div class="card-value">{{ r.p80 }}</div>
              <div class="card-unit">working days</div>
            </div>
            <div class="mc-card warn">
              <div class="card-label">P95</div>
              <div class="card-value">{{ r.p95 }}</div>
              <div class="card-unit">working days</div>
            </div>
          </div>

          <div class="mc-range">
            Range: {{ r.min }} — {{ r.max }} working days ({{ r.runs }} runs)
          </div>

          <!-- Histogram -->
          <div class="mc-histogram">
            <div class="hist-title">Distribution of project duration</div>
            <div class="hist-chart">
              @for (bin of histogram(); track bin.label) {
                <div class="hist-col" [title]="bin.label + ': ' + bin.count + ' runs'">
                  <div class="hist-bar" [style.height.%]="bin.pct">
                    @if (bin.count > 0) {
                      <span class="hist-count">{{ bin.count }}</span>
                    }
                  </div>
                  <div class="hist-label">{{ bin.label }}</div>
                </div>
              }
            </div>
            <!-- P-markers -->
            <div class="hist-markers">
              <span class="marker p50" [style.left.%]="pctPosition(r.p50)">P50</span>
              <span class="marker p80" [style.left.%]="pctPosition(r.p80)">P80</span>
              <span class="marker p95" [style.left.%]="pctPosition(r.p95)">P95</span>
            </div>
          </div>
        </div>
      } @else if (!loading()) {
        <div class="mc-empty">
          Configure runs and click "Run Simulation" to estimate schedule uncertainty.
          Tasks with <code>stdev</code> values will have their effort sampled from a normal distribution.
        </div>
      }
    </div>
  `,
  styles: [`
    .mc-container { padding: 16px; height: 100%; overflow: auto; }
    .mc-header h3 { margin: 0 0 4px; font-size: 16px; color: var(--text-primary); }
    .mc-desc { font-size: 12px; color: var(--text-secondary); margin: 0 0 12px; }
    .mc-controls {
      display: flex; align-items: center; gap: 8px; margin-bottom: 16px;
      label { font-size: 12px; color: var(--text-secondary); }
    }
    .mc-input {
      width: 60px; padding: 4px 8px; font-size: 13px;
      background: var(--bg-primary); border: 1px solid var(--border-color);
      color: var(--text-primary); border-radius: 3px;
    }
    .mc-btn {
      padding: 5px 16px; font-size: 12px; border-radius: 3px; cursor: pointer;
      background: #4d3a00; border: 1px solid #7a5c00; color: var(--warning-color);
      &:hover { background: #5c4600; }
      &:disabled { opacity: 0.5; cursor: not-allowed; }
    }
    .mc-scope {
      font-size: 11px; color: var(--accent-color);
      padding: 3px 8px; background: var(--bg-active); border-radius: 3px;
    }
    .mc-results { }
    .mc-cards {
      display: flex; gap: 12px; margin-bottom: 12px;
    }
    .mc-card {
      flex: 1; padding: 12px; border-radius: 6px;
      background: var(--bg-secondary); border: 1px solid var(--border-color);
      text-align: center;
      &.highlight { border-color: var(--accent-color); }
      &.warn { border-color: var(--warning-color); }
    }
    .card-label { font-size: 10px; font-weight: 600; text-transform: uppercase; color: var(--text-muted); }
    .card-value { font-size: 28px; font-weight: 700; color: var(--text-primary); font-family: monospace; }
    .mc-card.highlight .card-value { color: var(--accent-color); }
    .mc-card.warn .card-value { color: var(--warning-color); }
    .card-unit { font-size: 10px; color: var(--text-secondary); }
    .mc-range { font-size: 11px; color: var(--text-secondary); margin-bottom: 16px; }
    .mc-histogram { }
    .hist-title { font-size: 12px; font-weight: 600; color: var(--text-secondary); margin-bottom: 8px; }
    .hist-chart {
      display: flex; align-items: flex-end; gap: 2px;
      height: 120px; border-bottom: 1px solid var(--border-color);
      padding-bottom: 2px;
    }
    .hist-col {
      flex: 1; display: flex; flex-direction: column; align-items: center;
      justify-content: flex-end; height: 100%;
    }
    .hist-bar {
      width: 100%; background: var(--accent-color); border-radius: 2px 2px 0 0;
      min-height: 0; position: relative; opacity: 0.7;
    }
    .hist-count {
      position: absolute; top: -14px; left: 50%; transform: translateX(-50%);
      font-size: 9px; color: var(--text-secondary);
    }
    .hist-label { font-size: 9px; color: var(--text-muted); margin-top: 4px; }
    .hist-markers {
      position: relative; height: 20px; margin-top: 4px;
    }
    .marker {
      position: absolute; font-size: 9px; font-weight: 700;
      transform: translateX(-50%);
      &.p50 { color: var(--success-color); }
      &.p80 { color: var(--accent-color); }
      &.p95 { color: var(--warning-color); }
    }
    .mc-empty {
      padding: 40px; text-align: center; color: var(--text-muted); font-size: 13px;
      code { background: var(--bg-active); padding: 1px 4px; border-radius: 3px; }
    }
  `],
})
export class MonteCarloComponent {
  numRuns = 20;
  readonly loading = signal(false);
  readonly result = signal<MonteCarloResult | null>(null);

  constructor(
    private project: ProjectStateService,
    private ui: UiStateService,
    private backend: TjBackend
  ) {}

  scopeInfo = computed(() => {
    const ids = this.ui.filteredTaskIds();
    if (!ids) return null;
    return `Scope: ${ids.length} filtered tasks`;
  });

  histogram = computed(() => {
    const r = this.result();
    if (!r || !r.makespans.length) return [];

    const values = r.makespans;
    const min = Math.min(...values);
    const max = Math.max(...values);
    const range = max - min || 1;
    const numBins = Math.min(15, values.length);
    const binSize = range / numBins;

    const bins: { label: string; count: number; pct: number }[] = [];
    for (let i = 0; i < numBins; i++) {
      const lo = min + i * binSize;
      const hi = lo + binSize;
      const count = values.filter(v => i === numBins - 1 ? v >= lo && v <= hi : v >= lo && v < hi).length;
      bins.push({
        label: lo.toFixed(0),
        count,
        pct: 0,
      });
    }

    const maxCount = Math.max(...bins.map(b => b.count), 1);
    bins.forEach(b => b.pct = (b.count / maxCount) * 100);

    return bins;
  });

  pctPosition(value: number): number {
    const r = this.result();
    if (!r) return 0;
    const min = r.min;
    const max = r.max;
    const range = max - min || 1;
    return ((value - min) / range) * 100;
  }

  run(): void {
    const sid = this.project.sessionId();
    if (!sid) return;

    this.loading.set(true);
    this.result.set(null);

    const taskIds = this.ui.filteredTaskIds() || undefined;
    const scenario = this.ui.activeScenario() || undefined;
    this.backend.monteCarlo(sid, this.numRuns, taskIds, scenario).subscribe({
      next: (r) => {
        this.result.set(r);
        this.loading.set(false);
      },
      error: () => {
        this.loading.set(false);
      },
    });
  }
}
