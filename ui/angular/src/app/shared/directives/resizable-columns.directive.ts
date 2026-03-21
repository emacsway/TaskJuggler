import {
  Directive,
  ElementRef,
  AfterViewInit,
  OnDestroy,
  Input,
  Output,
  EventEmitter,
  NgZone,
} from '@angular/core';

/**
 * Adds invisible drag handles between .col-resize children of the host element.
 * On drag, emits the updated widths array via columnWidthsChange.
 *
 * The actual column widths must be applied via [style.width.px] in the template —
 * this directive only handles drag interaction.
 */
@Directive({
  selector: '[appResizableColumns]',
  standalone: true,
})
export class ResizableColumnsDirective implements AfterViewInit, OnDestroy {
  @Input() columnWidths: number[] = [];
  @Output() columnWidthsChange = new EventEmitter<number[]>();

  private handles: HTMLDivElement[] = [];
  private dragIndex = -1;
  private startX = 0;
  private startWidth = 0;

  private moveHandler = (e: MouseEvent) => this.onMove(e);
  private upHandler = () => this.onUp();

  constructor(
    private el: ElementRef<HTMLElement>,
    private zone: NgZone
  ) {}

  ngAfterViewInit(): void {
    setTimeout(() => this.createHandles());
  }

  ngOnDestroy(): void {
    this.handles.forEach((h) => h.remove());
    document.removeEventListener('mousemove', this.moveHandler);
    document.removeEventListener('mouseup', this.upHandler);
  }

  private createHandles(): void {
    const cols = this.getResizableCols();
    if (cols.length < 2) return;

    // Insert a drag handle after each column except the last
    for (let i = 0; i < cols.length - 1; i++) {
      const handle = document.createElement('div');
      Object.assign(handle.style, {
        position: 'absolute',
        right: '-3px',
        top: '0',
        bottom: '0',
        width: '7px',
        cursor: 'col-resize',
        zIndex: '10',
      });
      handle.addEventListener('mousedown', (e) => {
        e.preventDefault();
        e.stopPropagation();
        this.onDown(e, i);
      });

      cols[i].style.position = 'relative';
      cols[i].appendChild(handle);
      this.handles.push(handle);
    }
  }

  private onDown(e: MouseEvent, idx: number): void {
    this.dragIndex = idx;
    this.startX = e.clientX;
    this.startWidth = this.columnWidths[idx] || 100;
    document.addEventListener('mousemove', this.moveHandler);
    document.addEventListener('mouseup', this.upHandler);
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
  }

  private onMove(e: MouseEvent): void {
    const newWidth = Math.max(40, this.startWidth + (e.clientX - this.startX));
    // Run inside Angular zone so change detection picks up the emit
    this.zone.run(() => {
      const updated = [...this.columnWidths];
      updated[this.dragIndex] = newWidth;
      this.columnWidths = updated;
      this.columnWidthsChange.emit(updated);
    });
  }

  private onUp(): void {
    this.dragIndex = -1;
    document.removeEventListener('mousemove', this.moveHandler);
    document.removeEventListener('mouseup', this.upHandler);
    document.body.style.cursor = '';
    document.body.style.userSelect = '';
  }

  private getResizableCols(): HTMLElement[] {
    return Array.from(this.el.nativeElement.children).filter(
      (el) => el.classList.contains('col')
    ) as HTMLElement[];
  }
}
