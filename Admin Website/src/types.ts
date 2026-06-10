export type ExportValue =
  | string
  | number
  | boolean
  | null
  | undefined
  | ExportValue[]
  | { [key: string]: ExportValue };

export type ExportRow = Record<string, ExportValue>;

export interface PreviewRow {
  id: string | null;
  farmer_name: string | null;
  village: string | null;
  main_crop: string | null;
  submitted_at: string | null;
}

export interface ExportSummary {
  generatedAt: string;
  totalSubmittedForms: number;
  rowsReadyForExport: number;
  latestSubmittedAt: string | null;
  preview: PreviewRow[];
}

export interface ExportPayload extends ExportSummary {
  columns: string[];
  rows: ExportRow[];
}
