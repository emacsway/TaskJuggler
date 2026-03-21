import { Component, signal } from '@angular/core';
import { DomSanitizer, SafeHtml } from '@angular/platform-browser';
import { ProjectStateService } from '../../core/state/project-state.service';
import { TjBackend } from '../../core/backend/backend.interface';
import { ReportDefinition } from '../../core/models';

@Component({
  selector: 'app-report-viewer',
  standalone: true,
  template: `
    <div class="report-viewer">
      <div class="report-sidebar">
        <div class="report-sidebar-title">Reports</div>
        @for (report of project.reports(); track report.id) {
          <div
            class="report-item"
            [class.active]="activeReportId() === report.id"
            (click)="generateReport(report)"
          >
            <span class="report-type">{{ report.typeSpec }}</span>
            <span class="report-name">{{ report.name || report.id }}</span>
          </div>
        }
        @if (project.reports().length === 0) {
          <div class="empty">No reports defined</div>
        }
      </div>
      <div class="report-content">
        @if (reportHtml()) {
          <div class="report-html" #reportContainer
               [innerHTML]="reportHtml()"
               (click)="onReportClick($event)"></div>
        } @else if (loading()) {
          <div class="placeholder">Generating report...</div>
        } @else {
          <div class="placeholder">Select a report from the list</div>
        }
      </div>
    </div>
  `,
  styles: [`
    .report-viewer { display: flex; height: 100%; }
    .report-sidebar {
      width: 220px; flex-shrink: 0;
      border-right: 1px solid var(--border-color); overflow-y: auto;
    }
    .report-sidebar-title {
      padding: 8px 12px; font-size: 11px; font-weight: 600;
      text-transform: uppercase; color: var(--text-secondary);
    }
    .report-item {
      display: flex; flex-direction: column; padding: 6px 12px; cursor: pointer;
      &:hover { background: var(--bg-hover); }
      &.active { background: var(--bg-active); }
    }
    .report-type { font-size: 10px; color: var(--text-muted); }
    .report-name { font-size: 12px; color: var(--text-primary); }
    .report-content { flex: 1; overflow: auto; padding: 8px; }
    .report-html {
      background: white; color: black; padding: 16px;
      border-radius: 4px; min-height: 100%;
    }
    .placeholder {
      display: flex; align-items: center; justify-content: center;
      height: 100%; color: var(--text-muted);
    }
    .empty { padding: 20px; text-align: center; color: var(--text-muted); font-size: 12px; }
  `],
})
export class ReportViewerComponent {
  activeReportId = signal<string | null>(null);
  reportHtml = signal<SafeHtml | null>(null);
  loading = signal(false);

  constructor(
    public project: ProjectStateService,
    private backend: TjBackend,
    private sanitizer: DomSanitizer
  ) {}

  generateReport(report: ReportDefinition): void {
    const sid = this.project.sessionId();
    if (!sid) return;

    this.activeReportId.set(report.id);
    this.loading.set(true);
    this.reportHtml.set(null);

    this.backend.generateReport(sid, report.id, 'html').subscribe({
      next: (output) => {
        if (output.ok && output.content) {
          this.reportHtml.set(this.sanitizer.bypassSecurityTrustHtml(output.content));
        }
        this.loading.set(false);
      },
      error: () => {
        this.loading.set(false);
      },
    });
  }

  onReportClick(event: MouseEvent): void {
    // Walk up from click target to find an <a> element
    let el = event.target as HTMLElement | null;
    while (el && el.tagName !== 'A') {
      el = el.parentElement;
      if (el?.classList?.contains('report-html')) break;
    }
    if (!el || el.tagName !== 'A') return;

    const href = el.getAttribute('href');
    if (!href) return;

    // Prevent default navigation
    event.preventDefault();
    event.stopPropagation();

    // Match report by href filename
    // TJ3 links look like "Report_Name.html" or "path/Report_Name.html"
    const fileName = href.split('/').pop()?.replace('.html', '') || '';
    const report = this.findReportByFileName(fileName);

    if (report) {
      this.generateReport(report);
    } else {
      console.warn(`Report not found for link: "${fileName}" (href: "${href}")`);
    }
  }

  private findReportByFileName(fileName: string): ReportDefinition | null {
    const reports = this.project.reports();

    // TJ3 uses report name as filename (e.g. "FactAllSprintBacklog.html" -> name "FactAllSprintBacklog")
    // Exact match on name is the primary lookup
    let match = reports.find(r => r.name === fileName);
    if (match) return match;

    // Exact match on id
    match = reports.find(r => r.id === fileName);
    if (match) return match;

    // Case-insensitive name match
    const lower = fileName.toLowerCase();
    match = reports.find(r => r.name.toLowerCase() === lower);
    if (match) return match;

    return null;
  }
}
