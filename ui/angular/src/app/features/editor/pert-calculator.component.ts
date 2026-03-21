import { Component, computed, output, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

export interface PertResult {
  effort: number;
  stdev: number;
  unit: string;
}

@Component({
  selector: 'app-pert-calculator',
  standalone: true,
  imports: [FormsModule],
  template: `
    <div class="pert-overlay" (click)="close.emit()">
      <div class="pert-dialog" (click)="$event.stopPropagation()">
        <div class="pert-title">PERT Effort Estimator</div>
        <div class="pert-desc">Enter optimistic, most likely, and pessimistic estimates</div>

        <div class="pert-fields">
          <div class="pert-row">
            <label>Optimistic (O):</label>
            <input type="number" [ngModel]="optimistic()" (ngModelChange)="optimistic.set($event)" min="0" step="0.5" class="pert-input"/>
          </div>
          <div class="pert-row">
            <label>Most Likely (M):</label>
            <input type="number" [ngModel]="mostLikely()" (ngModelChange)="mostLikely.set($event)" min="0" step="0.5" class="pert-input"/>
          </div>
          <div class="pert-row">
            <label>Pessimistic (P):</label>
            <input type="number" [ngModel]="pessimistic()" (ngModelChange)="pessimistic.set($event)" min="0" step="0.5" class="pert-input"/>
          </div>
          <div class="pert-row">
            <label>Unit:</label>
            <select [ngModel]="unit()" (ngModelChange)="unit.set($event)" class="pert-select">
              <option value="d">days</option>
              <option value="h">hours</option>
              <option value="w">weeks</option>
              <option value="m">months</option>
            </select>
          </div>
        </div>

        @if (isValid()) {
          <div class="pert-formula">
            <div class="formula-line">E = (O + 4M + P) / 6 = ({{ optimistic() }} + 4&times;{{ mostLikely() }} + {{ pessimistic() }}) / 6</div>
            <div class="formula-line">&sigma; = (P - O) / 6 = ({{ pessimistic() }} - {{ optimistic() }}) / 6</div>
          </div>

          <div class="pert-results">
            <div class="result-row">
              <span class="result-label">effort</span>
              <span class="result-value">{{ effortValue() }}{{ unit() }}</span>
            </div>
            <div class="result-row">
              <span class="result-label">stdev</span>
              <span class="result-value">{{ stdevValue() }}{{ unit() }}</span>
            </div>
          </div>

          <div class="pert-preview">
            <code>effort {{ effortValue() }}{{ unit() }}</code><br/>
            <code>stdev {{ stdevValue() }}{{ unit() }}</code>
          </div>
        }

        <div class="pert-actions">
          <button class="btn-cancel" (click)="close.emit()">Cancel</button>
          <button class="btn-insert" [disabled]="!isValid()" (click)="insert()">Insert</button>
        </div>
      </div>
    </div>
  `,
  styles: [`
    .pert-overlay {
      position: fixed; inset: 0; z-index: 100;
      background: rgba(0,0,0,0.5);
      display: flex; align-items: center; justify-content: center;
    }
    .pert-dialog {
      background: var(--bg-secondary); border: 1px solid var(--border-color);
      border-radius: 6px; padding: 16px 20px; width: 380px;
      box-shadow: 0 8px 32px rgba(0,0,0,0.4);
    }
    .pert-title {
      font-size: 14px; font-weight: 600; color: var(--text-primary);
      margin-bottom: 4px;
    }
    .pert-desc {
      font-size: 11px; color: var(--text-secondary); margin-bottom: 12px;
    }
    .pert-fields { display: flex; flex-direction: column; gap: 6px; }
    .pert-row {
      display: flex; align-items: center; justify-content: space-between;
      label { font-size: 12px; color: var(--text-primary); width: 130px; }
    }
    .pert-input, .pert-select {
      width: 140px; padding: 4px 8px; font-size: 13px;
      background: var(--bg-primary); border: 1px solid var(--border-color);
      color: var(--text-primary); border-radius: 3px;
      &:focus { outline: 1px solid var(--accent-color); border-color: var(--accent-color); }
    }
    .pert-formula {
      margin-top: 12px; padding: 8px;
      background: var(--bg-primary); border-radius: 4px;
      font-size: 11px; color: var(--text-secondary); font-family: monospace;
    }
    .formula-line { margin-bottom: 2px; }
    .pert-results {
      margin-top: 8px; display: flex; gap: 16px;
    }
    .result-row {
      display: flex; flex-direction: column; align-items: center;
    }
    .result-label {
      font-size: 10px; color: var(--text-muted); text-transform: uppercase;
    }
    .result-value {
      font-size: 20px; font-weight: 700; color: var(--accent-color);
      font-family: monospace;
    }
    .pert-preview {
      margin-top: 8px; padding: 8px;
      background: var(--bg-primary); border-radius: 4px;
      font-size: 12px; color: var(--success-color);
      code { font-family: 'JetBrains Mono', 'Fira Code', monospace; }
    }
    .pert-actions {
      margin-top: 12px; display: flex; justify-content: flex-end; gap: 8px;
    }
    .btn-cancel, .btn-insert {
      padding: 5px 16px; font-size: 12px; border-radius: 3px; cursor: pointer;
      border: 1px solid var(--border-color);
    }
    .btn-cancel {
      background: var(--bg-active); color: var(--text-primary);
      &:hover { background: var(--bg-hover); }
    }
    .btn-insert {
      background: #0e639c; color: white; border-color: #1177bb;
      &:hover { background: #1177bb; }
      &:disabled { opacity: 0.4; cursor: not-allowed; }
    }
  `],
})
export class PertCalculatorComponent {
  readonly close = output<void>();
  readonly insertResult = output<PertResult>();

  readonly optimistic = signal(0);
  readonly mostLikely = signal(0);
  readonly pessimistic = signal(0);
  readonly unit = signal('d');

  isValid = computed(() =>
    this.optimistic() >= 0 &&
    this.mostLikely() >= this.optimistic() &&
    this.pessimistic() >= this.mostLikely() &&
    this.pessimistic() > 0
  );

  effortValue = computed(() => {
    const e = (this.optimistic() + 4 * this.mostLikely() + this.pessimistic()) / 6;
    return this.round(e);
  });

  stdevValue = computed(() => {
    const s = (this.pessimistic() - this.optimistic()) / 6;
    return this.round(s);
  });

  insert(): void {
    if (!this.isValid()) return;
    this.insertResult.emit({
      effort: this.effortValue(),
      stdev: this.stdevValue(),
      unit: this.unit(),
    });
  }

  private round(v: number): number {
    return Math.round(v * 10) / 10;
  }
}
