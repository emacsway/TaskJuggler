export interface ReportDefinition {
  id: string;
  name: string;
  typeSpec: string;
  formats: string[];
}

export interface ReportOutput {
  ok: boolean;
  reportId: string;
  format: string;
  content: string | null;
  error?: string;
}
