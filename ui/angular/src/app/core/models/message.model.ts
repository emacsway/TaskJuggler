export interface DiagnosticMessage {
  type: 'fatal' | 'error' | 'warning' | 'info';
  id: string;
  message: string;
  file: string | null;
  line: number | null;
  column: number | null;
}
