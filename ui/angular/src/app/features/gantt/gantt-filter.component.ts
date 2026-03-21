import { Component, signal, output, computed } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { NgTemplateOutlet } from '@angular/common';
import { ProjectStateService } from '../../core/state/project-state.service';
import { GanttTask } from '../../core/models';

export interface FilterRule {
  type: 'rule';
  id: number;
  field: string;
  operator: string;
  value: string;
  negate: boolean;
}

export interface FilterGroup {
  type: 'group';
  id: number;
  logic: 'and' | 'or';
  children: FilterItem[];
  negate: boolean;
}

export type FilterItem = FilterRule | FilterGroup;

const FILTER_FIELDS = [
  { key: 'name',        label: 'Name',              type: 'string' },
  { key: 'taskId',      label: 'ID',                type: 'string' },
  { key: 'ischildof',   label: 'Is child of (ID)',  type: 'string', ops: 'func' },
  { key: 'complete',    label: 'Complete %',         type: 'number' },
  { key: 'level',       label: 'Tree Level',         type: 'number' },
  { key: 'isMilestone', label: 'Milestone',          type: 'boolean' },
  { key: 'isContainer', label: 'Container',          type: 'boolean' },
  { key: 'isLeaf',      label: 'Leaf (no children)', type: 'boolean' },
  { key: 'start',       label: 'Start',              type: 'date' },
  { key: 'end',         label: 'End',                type: 'date' },
  { key: 'resources',   label: 'Assigned Resource',  type: 'string' },
];

const OPS_BY_TYPE: Record<string, { key: string; label: string }[]> = {
  string: [
    { key: 'contains', label: 'contains' },
    { key: 'eq',       label: '=' },
    { key: 'neq',      label: '!=' },
    { key: 'starts',   label: 'starts with' },
  ],
  number: [
    { key: 'eq',  label: '=' },
    { key: 'neq', label: '!=' },
    { key: 'gt',  label: '>' },
    { key: 'lt',  label: '<' },
    { key: 'gte', label: '>=' },
    { key: 'lte', label: '<=' },
  ],
  date: [
    { key: 'gt',  label: 'after' },
    { key: 'lt',  label: 'before' },
    { key: 'eq',  label: '=' },
  ],
  boolean: [
    { key: 'eq', label: 'is' },
  ],
  func: [
    { key: 'eq', label: 'matches' },
  ],
};

@Component({
  selector: 'app-gantt-filter',
  standalone: true,
  imports: [FormsModule, NgTemplateOutlet],
  template: `
    <div class="filter-panel">
      <div class="filter-toggle" (click)="open.set(!open())">
        <span>Filter</span>
        @if (activeCount() > 0) {
          <span class="filter-badge">{{ activeCount() }}</span>
        }
        <span class="toggle-icon">{{ open() ? '&#9660;' : '&#9654;' }}</span>
      </div>

      @if (open()) {
        <div class="filter-body">
          <ng-container *ngTemplateOutlet="groupTpl; context: { $implicit: root, depth: 0, parent: null, index: 0 }"></ng-container>

          <div class="filter-actions">
            @if (countRules(root) > 0) {
              <button class="clear-btn" (click)="clearAll()">Clear All</button>
            }
          </div>
        </div>
      }
    </div>

    <!-- Recursive group template -->
    <ng-template #groupTpl let-group let-depth="depth" let-parent="parent" let-index="index">
      <div class="group" [class.nested]="depth > 0" [class.negated]="group.negate">
        <div class="group-header">
          @if (depth > 0) {
            <label class="negate-toggle" title="NOT">
              <input type="checkbox" [(ngModel)]="group.negate" (ngModelChange)="apply()"/>
              <span>~</span>
            </label>
          }
          <select [(ngModel)]="group.logic" (ngModelChange)="apply()" class="filter-select logic-select">
            <option value="and">AND</option>
            <option value="or">OR</option>
          </select>
          <button class="add-btn" (click)="addRule(group)">+ Rule</button>
          <button class="add-btn" (click)="addGroup(group)">+ Group</button>
          @if (depth > 0) {
            <button class="remove-btn" (click)="removeItem(parent, index)">&times;</button>
          }
        </div>

        @for (child of group.children; track child.id; let i = $index) {
          @if (child.type === 'rule') {
            <div class="rule-row">
              <label class="negate-toggle" title="NOT">
                <input type="checkbox" [(ngModel)]="child.negate" (ngModelChange)="apply()"/>
                <span>~</span>
              </label>

              <select [(ngModel)]="child.field" (ngModelChange)="onFieldChange(child)" class="filter-select field-select">
                @for (f of fields; track f.key) {
                  <option [value]="f.key">{{ f.label }}</option>
                }
              </select>

              <select [(ngModel)]="child.operator" (ngModelChange)="apply()" class="filter-select op-select">
                @for (op of getOps(child); track op.key) {
                  <option [value]="op.key">{{ op.label }}</option>
                }
              </select>

              @if (getFieldType(child) === 'boolean') {
                <select [(ngModel)]="child.value" (ngModelChange)="apply()" class="filter-select val-select">
                  <option value="true">Yes</option>
                  <option value="false">No</option>
                </select>
              } @else if (child.field === 'ischildof') {
                <select [(ngModel)]="child.value" (ngModelChange)="apply()" class="filter-select val-select-wide">
                  <option value="">-- select --</option>
                  @for (t of containerTasks(); track t.taskId) {
                    <option [value]="t.taskId">{{ t.name }} ({{ t.taskId }})</option>
                  }
                </select>
              } @else {
                <input
                  class="filter-input"
                  [type]="getFieldType(child) === 'date' ? 'date' : getFieldType(child) === 'number' ? 'number' : 'text'"
                  [(ngModel)]="child.value"
                  (ngModelChange)="apply()"
                />
              }

              <button class="remove-btn" (click)="removeItem(group, i)">&times;</button>
            </div>
          } @else {
            <ng-container *ngTemplateOutlet="groupTpl; context: { $implicit: child, depth: depth + 1, parent: group, index: i }"></ng-container>
          }
        }
      </div>
    </ng-template>
  `,
  styles: [`
    .filter-panel {
      background: var(--bg-secondary);
      border-bottom: 1px solid var(--border-color);
      flex-shrink: 0;
    }
    .filter-toggle {
      display: flex; align-items: center; gap: 6px;
      padding: 4px 8px; cursor: pointer; font-size: 11px;
      color: var(--text-secondary);
      &:hover { color: var(--text-primary); }
    }
    .filter-badge {
      background: #0e639c; color: white; font-size: 10px;
      padding: 0 5px; border-radius: 8px;
    }
    .toggle-icon { font-size: 7px; margin-left: auto; }
    .filter-body { padding: 4px 8px 8px; }
    .group {
      &.nested {
        margin: 3px 0 3px 12px;
        padding: 4px 6px;
        border-left: 2px solid var(--accent-color);
        background: rgba(79, 193, 255, 0.03);
        border-radius: 0 3px 3px 0;
      }
      &.negated { border-left-color: var(--error-color); }
    }
    .group-header {
      display: flex; align-items: center; gap: 4px;
      margin-bottom: 3px;
    }
    .logic-select { font-weight: 600; width: 55px; }
    .rule-row {
      display: flex; align-items: center; gap: 4px;
      margin-bottom: 3px; margin-left: 12px;
    }
    .negate-toggle {
      font-size: 12px; font-weight: bold; color: var(--text-muted);
      cursor: pointer; width: 20px; text-align: center; flex-shrink: 0;
      input { display: none; }
      &:has(input:checked) span { color: var(--error-color); }
    }
    .filter-select, .filter-input {
      padding: 2px 4px; font-size: 11px;
      background: var(--bg-primary); border: 1px solid var(--border-color);
      color: var(--text-primary); border-radius: 3px;
      &:focus { outline: 1px solid var(--accent-color); }
    }
    .field-select { width: 120px; }
    .op-select { width: 85px; }
    .val-select, .filter-input { width: 120px; }
    .val-select-wide { width: 200px; }
    .remove-btn {
      background: none; border: none; color: var(--text-muted);
      cursor: pointer; font-size: 14px; padding: 0 4px; flex-shrink: 0;
      &:hover { color: var(--error-color); }
    }
    .filter-actions { display: flex; gap: 8px; margin-top: 4px; }
    .add-btn {
      padding: 2px 8px; font-size: 10px; border-radius: 3px; cursor: pointer;
      border: 1px solid var(--border-color); background: var(--bg-active); color: var(--text-primary);
      &:hover { background: var(--bg-hover); }
    }
    .clear-btn {
      padding: 2px 8px; font-size: 11px; border-radius: 3px; cursor: pointer;
      border: 1px solid var(--border-color); background: none; color: var(--text-secondary);
      &:hover { color: var(--error-color); }
    }
  `],
})
export class GanttFilterComponent {
  readonly fields = FILTER_FIELDS;
  readonly open = signal(false);
  readonly filterChanged = output<(task: GanttTask) => boolean>();

  private nextId = 1;
  root: FilterGroup = { type: 'group', id: this.nextId++, logic: 'and', children: [], negate: false };

  constructor(private project: ProjectStateService) {}

  /** Container tasks for ischildof dropdown */
  containerTasks = computed(() => {
    const data = this.project.ganttData();
    return data?.tasks.filter(t => t.isContainer) || [];
  });

  activeCount = computed(() => this.countRules(this.root));

  countRules(group: FilterGroup): number {
    let n = 0;
    for (const c of group.children) {
      n += c.type === 'rule' ? 1 : this.countRules(c);
    }
    return n;
  }

  addRule(group: FilterGroup): void {
    group.children.push({
      type: 'rule',
      id: this.nextId++,
      field: 'name',
      operator: 'contains',
      value: '',
      negate: false,
    });
  }

  addGroup(parent: FilterGroup): void {
    parent.children.push({
      type: 'group',
      id: this.nextId++,
      logic: 'or',
      children: [],
      negate: false,
    });
  }

  removeItem(parent: FilterGroup, index: number): void {
    parent.children.splice(index, 1);
    this.apply();
  }

  clearAll(): void {
    this.root.children = [];
    this.apply();
  }

  onFieldChange(rule: FilterRule): void {
    const fieldDef = FILTER_FIELDS.find(f => f.key === rule.field);
    const opsKey = fieldDef?.ops || fieldDef?.type || 'string';
    const ops = OPS_BY_TYPE[opsKey] || OPS_BY_TYPE['string'];
    rule.operator = ops[0].key;
    rule.value = (fieldDef?.type === 'boolean') ? 'true' : '';
    this.apply();
  }

  getFieldType(rule: FilterRule): string {
    return FILTER_FIELDS.find(f => f.key === rule.field)?.type || 'string';
  }

  getOps(rule: FilterRule): { key: string; label: string }[] {
    const fieldDef = FILTER_FIELDS.find(f => f.key === rule.field);
    const opsKey = fieldDef?.ops || fieldDef?.type || 'string';
    return OPS_BY_TYPE[opsKey] || OPS_BY_TYPE['string'];
  }

  apply(): void {
    if (this.countRules(this.root) === 0) {
      this.filterChanged.emit(() => true);
      return;
    }
    const pred = this.buildGroupPredicate(this.root);
    this.filterChanged.emit(pred);
  }

  private buildGroupPredicate(group: FilterGroup): (task: GanttTask) => boolean {
    const childPreds = group.children
      .map(c => c.type === 'rule' ? this.buildRulePredicate(c) : this.buildGroupPredicate(c))
      .filter(Boolean) as ((task: GanttTask) => boolean)[];

    if (childPreds.length === 0) return () => true;

    const combined = (task: GanttTask): boolean => {
      if (group.logic === 'and') {
        return childPreds.every(p => p(task));
      } else {
        return childPreds.some(p => p(task));
      }
    };

    return group.negate ? (task) => !combined(task) : combined;
  }

  private buildRulePredicate(rule: FilterRule): ((task: GanttTask) => boolean) | null {
    const { field, operator, value, negate } = rule;
    if (value === '' && this.getFieldType(rule) !== 'boolean') return null;

    const pred = (task: GanttTask): boolean => {
      // Special function: ischildof
      if (field === 'ischildof') {
        return task.taskId.startsWith(value + '.') || task.taskId === value;
      }

      const raw = this.getFieldValue(task, field);
      const type = this.getFieldType(rule);

      switch (type) {
        case 'string': {
          const s = String(raw || '').toLowerCase();
          const v = value.toLowerCase();
          switch (operator) {
            case 'contains': return s.includes(v);
            case 'eq':       return s === v;
            case 'neq':      return s !== v;
            case 'starts':   return s.startsWith(v);
            default:         return true;
          }
        }
        case 'number': {
          const n = Number(raw) || 0;
          const v = Number(value) || 0;
          switch (operator) {
            case 'eq':  return n === v;
            case 'neq': return n !== v;
            case 'gt':  return n > v;
            case 'lt':  return n < v;
            case 'gte': return n >= v;
            case 'lte': return n <= v;
            default:    return true;
          }
        }
        case 'date': {
          const d = raw ? new Date(raw as string).getTime() : 0;
          const v = new Date(value).getTime();
          switch (operator) {
            case 'gt': return d > v;
            case 'lt': return d < v;
            case 'eq': return Math.abs(d - v) < 86400000;
            default:   return true;
          }
        }
        case 'boolean': {
          const b = Boolean(raw);
          return value === 'true' ? b : !b;
        }
        default: return true;
      }
    };

    return negate ? (task) => !pred(task) : pred;
  }

  private getFieldValue(task: GanttTask, field: string): unknown {
    switch (field) {
      case 'name':        return task.name;
      case 'taskId':      return task.taskId;
      case 'complete':    return task.complete;
      case 'level':       return task.level;
      case 'isMilestone': return task.isMilestone;
      case 'isContainer': return task.isContainer;
      case 'isLeaf':      return !task.isContainer;
      case 'start':       return task.start;
      case 'end':         return task.end;
      case 'resources':   return task.assignedResources?.join(', ') || '';
      default:            return '';
    }
  }
}
