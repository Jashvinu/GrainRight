import { AlertTriangle, CheckCircle2, Database, Download, FileSpreadsheet, RefreshCw } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { fetchExportPayload, fetchSummary, hasExportConfig } from "./exportClient";
import type { ExportSummary, PreviewRow } from "./types";
import { downloadXlsx } from "./xlsx";

type LoadState = "idle" | "loading" | "ready" | "error";

const emptySummary: ExportSummary = {
  generatedAt: "",
  totalSubmittedForms: 0,
  rowsReadyForExport: 0,
  latestSubmittedAt: null,
  preview: [],
};

export default function App() {
  const [summary, setSummary] = useState<ExportSummary>(emptySummary);
  const [loadState, setLoadState] = useState<LoadState>("idle");
  const [downloadState, setDownloadState] = useState<LoadState>("idle");
  const [error, setError] = useState("");

  const configured = hasExportConfig();

  useEffect(() => {
    if (!configured) {
      setLoadState("error");
      setError("Missing VITE_ADMIN_EXPORT_FUNCTION_URL in the admin website environment.");
      return;
    }

    const controller = new AbortController();
    loadSummary(controller.signal);
    return () => controller.abort();
  }, [configured]);

  async function loadSummary(signal?: AbortSignal) {
    setLoadState("loading");
    setError("");
    try {
      const result = await fetchSummary(signal);
      setSummary(result);
      setLoadState("ready");
    } catch (loadError) {
      if (signal?.aborted) return;
      setLoadState("error");
      setError(loadError instanceof Error ? loadError.message : "Failed to load export status.");
    }
  }

  async function handleDownload() {
    setDownloadState("loading");
    setError("");
    try {
      const payload = await fetchExportPayload();
      const stamp = new Date().toISOString().slice(0, 10);
      downloadXlsx(payload.columns, payload.rows, `grainright-survey-export-${stamp}.xlsx`);
      setSummary({
        generatedAt: payload.generatedAt,
        totalSubmittedForms: payload.totalSubmittedForms,
        rowsReadyForExport: payload.rowsReadyForExport,
        latestSubmittedAt: payload.latestSubmittedAt,
        preview: payload.preview,
      });
      setDownloadState("ready");
    } catch (downloadError) {
      setDownloadState("error");
      setError(downloadError instanceof Error ? downloadError.message : "Failed to download export.");
    }
  }

  const lastChecked = useMemo(() => formatDateTime(summary.generatedAt), [summary.generatedAt]);

  return (
    <main className="admin-shell">
      <header className="topbar">
        <div>
          <p className="brand-label">GrainRight Admin</p>
          <h1>Survey spreadsheet export</h1>
        </div>
        <div className="topbar-status" aria-live="polite">
          {loadState === "ready" ? <CheckCircle2 size={18} /> : <Database size={18} />}
          <span>{loadState === "ready" ? "Database connected" : "Export service"}</span>
        </div>
      </header>

      <section className="notice" role="note">
        <AlertTriangle size={18} />
        <span>This page is public and can download private survey fields including mobile and Aadhaar data.</span>
      </section>

      <section className="status-strip" aria-label="Export status">
        <StatusMetric label="Submitted forms" value={formatNumber(summary.totalSubmittedForms)} />
        <StatusMetric label="Rows ready" value={formatNumber(summary.rowsReadyForExport)} />
        <StatusMetric label="Latest submission" value={formatDateTime(summary.latestSubmittedAt)} />
        <StatusMetric label="Last checked" value={lastChecked} />
      </section>

      <section className="download-area">
        <div className="download-copy">
          <FileSpreadsheet size={32} />
          <div>
            <h2>Flat Excel export</h2>
            <p>One worksheet, one submitted form per row, with child crop and agronomy tables expanded into columns.</p>
          </div>
        </div>
        <div className="download-actions">
          <button
            className="icon-button"
            type="button"
            onClick={() => loadSummary()}
            disabled={loadState === "loading" || downloadState === "loading" || !configured}
            aria-label="Refresh export status"
            title="Refresh export status"
          >
            <RefreshCw size={18} />
          </button>
          <button
            className="primary-button"
            type="button"
            onClick={handleDownload}
            disabled={downloadState === "loading" || loadState === "loading" || !configured}
          >
            <Download size={19} />
            <span>{downloadState === "loading" ? "Preparing..." : "Download Excel"}</span>
          </button>
        </div>
      </section>

      {error ? (
        <section className="error-panel" role="alert">
          {error}
        </section>
      ) : null}

      <section className="table-section">
        <div className="section-heading">
          <h2>Recent submissions</h2>
          <span>{loadState === "loading" ? "Loading..." : `${summary.preview.length} shown`}</span>
        </div>
        <RecentTable rows={summary.preview} />
      </section>
    </main>
  );
}

function StatusMetric({ label, value }: { label: string; value: string }) {
  return (
    <div className="status-metric">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function RecentTable({ rows }: { rows: PreviewRow[] }) {
  if (rows.length === 0) {
    return <div className="empty-table">No submitted forms found.</div>;
  }

  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Farmer</th>
            <th>Village</th>
            <th>Main crop</th>
            <th>Submitted</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.id ?? `${row.farmer_name}-${row.submitted_at}`}>
              <td>{row.farmer_name || "-"}</td>
              <td>{row.village || "-"}</td>
              <td>{row.main_crop || "-"}</td>
              <td>{formatDateTime(row.submitted_at)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function formatNumber(value: number) {
  return new Intl.NumberFormat("en-IN").format(value);
}

function formatDateTime(value: string | null) {
  if (!value) return "-";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat("en-IN", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}
