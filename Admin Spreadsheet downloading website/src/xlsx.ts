import type { ExportRow, ExportValue } from "./types";

interface ZipEntry {
  name: string;
  content: Uint8Array;
}

const textEncoder = new TextEncoder();
const crcTable = makeCrcTable();

export function downloadXlsx(columns: string[], rows: ExportRow[], fileName: string) {
  const workbook = buildWorkbook(columns, rows);
  const url = URL.createObjectURL(
    new Blob([workbook], {
      type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    }),
  );

  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = fileName;
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
}

function buildWorkbook(columns: string[], rows: ExportRow[]) {
  const entries: ZipEntry[] = [
    {
      name: "[Content_Types].xml",
      content: encodeXml(`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>`),
    },
    {
      name: "_rels/.rels",
      content: encodeXml(`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>`),
    },
    {
      name: "xl/_rels/workbook.xml.rels",
      content: encodeXml(`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>`),
    },
    {
      name: "xl/workbook.xml",
      content: encodeXml(`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Survey Export" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>`),
    },
    {
      name: "xl/styles.xml",
      content: encodeXml(`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
  <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
  <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0"/></cellXfs>
  <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>`),
    },
    {
      name: "xl/worksheets/sheet1.xml",
      content: encodeXml(buildSheetXml(columns, rows)),
    },
  ];

  return makeZip(entries);
}

function buildSheetXml(columns: string[], rows: ExportRow[]) {
  const header = buildRow(1, columns, true);
  const body = rows
    .map((row, index) =>
      buildRow(
        index + 2,
        columns.map((column) => row[column]),
        false,
      ),
    )
    .join("");

  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetViews><sheetView workbookViewId="0"/></sheetViews>
  <sheetFormatPr defaultRowHeight="15"/>
  <sheetData>${header}${body}</sheetData>
  <autoFilter ref="A1:${columnName(columns.length)}${Math.max(rows.length + 1, 1)}"/>
</worksheet>`;
}

function buildRow(rowNumber: number, values: ExportValue[], isHeader: boolean) {
  const cells = values
    .map((value, index) => buildCell(rowNumber, index + 1, value, isHeader))
    .join("");
  return `<row r="${rowNumber}">${cells}</row>`;
}

function buildCell(rowNumber: number, columnNumber: number, value: ExportValue, isHeader: boolean) {
  const ref = `${columnName(columnNumber)}${rowNumber}`;
  const normalized = normalizeValue(value);
  const style = isHeader ? ' s="1"' : "";

  if (typeof normalized === "number" && Number.isFinite(normalized)) {
    return `<c r="${ref}"${style}><v>${normalized}</v></c>`;
  }

  if (normalized === "") {
    return `<c r="${ref}"${style}/>`;
  }

  return `<c r="${ref}" t="inlineStr"${style}><is><t>${escapeXml(String(normalized))}</t></is></c>`;
}

function normalizeValue(value: ExportValue): string | number {
  if (value === null || value === undefined) return "";
  if (typeof value === "number") return value;
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "string") return value;
  return JSON.stringify(value);
}

function columnName(columnNumber: number) {
  let name = "";
  let current = columnNumber;
  while (current > 0) {
    const mod = (current - 1) % 26;
    name = String.fromCharCode(65 + mod) + name;
    current = Math.floor((current - mod) / 26);
  }
  return name;
}

function makeZip(entries: ZipEntry[]) {
  const localParts: Uint8Array[] = [];
  const centralParts: Uint8Array[] = [];
  let offset = 0;

  for (const entry of entries) {
    const name = textEncoder.encode(entry.name);
    const crc = crc32(entry.content);
    const localHeader = makeLocalHeader(name, crc, entry.content.length);
    localParts.push(localHeader, entry.content);

    centralParts.push(makeCentralHeader(name, crc, entry.content.length, offset));
    offset += localHeader.length + entry.content.length;
  }

  const centralSize = centralParts.reduce((sum, part) => sum + part.length, 0);
  const centralOffset = offset;
  const end = makeEndRecord(entries.length, centralSize, centralOffset);
  return concatUint8Arrays([...localParts, ...centralParts, end]);
}

function makeLocalHeader(name: Uint8Array, crc: number, size: number) {
  const header = new Uint8Array(30 + name.length);
  const view = new DataView(header.buffer);
  view.setUint32(0, 0x04034b50, true);
  view.setUint16(4, 20, true);
  view.setUint16(6, 0, true);
  view.setUint16(8, 0, true);
  view.setUint16(10, 0, true);
  view.setUint16(12, 0, true);
  view.setUint32(14, crc, true);
  view.setUint32(18, size, true);
  view.setUint32(22, size, true);
  view.setUint16(26, name.length, true);
  view.setUint16(28, 0, true);
  header.set(name, 30);
  return header;
}

function makeCentralHeader(name: Uint8Array, crc: number, size: number, offset: number) {
  const header = new Uint8Array(46 + name.length);
  const view = new DataView(header.buffer);
  view.setUint32(0, 0x02014b50, true);
  view.setUint16(4, 20, true);
  view.setUint16(6, 20, true);
  view.setUint16(8, 0, true);
  view.setUint16(10, 0, true);
  view.setUint16(12, 0, true);
  view.setUint16(14, 0, true);
  view.setUint32(16, crc, true);
  view.setUint32(20, size, true);
  view.setUint32(24, size, true);
  view.setUint16(28, name.length, true);
  view.setUint16(30, 0, true);
  view.setUint16(32, 0, true);
  view.setUint16(34, 0, true);
  view.setUint16(36, 0, true);
  view.setUint32(38, 0, true);
  view.setUint32(42, offset, true);
  header.set(name, 46);
  return header;
}

function makeEndRecord(entryCount: number, centralSize: number, centralOffset: number) {
  const header = new Uint8Array(22);
  const view = new DataView(header.buffer);
  view.setUint32(0, 0x06054b50, true);
  view.setUint16(4, 0, true);
  view.setUint16(6, 0, true);
  view.setUint16(8, entryCount, true);
  view.setUint16(10, entryCount, true);
  view.setUint32(12, centralSize, true);
  view.setUint32(16, centralOffset, true);
  view.setUint16(20, 0, true);
  return header;
}

function concatUint8Arrays(parts: Uint8Array[]) {
  const totalLength = parts.reduce((sum, part) => sum + part.length, 0);
  const output = new Uint8Array(totalLength);
  let offset = 0;
  for (const part of parts) {
    output.set(part, offset);
    offset += part.length;
  }
  return output;
}

function encodeXml(xml: string) {
  return textEncoder.encode(xml.trim());
}

function escapeXml(value: string) {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function crc32(bytes: Uint8Array) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc = (crc >>> 8) ^ crcTable[(crc ^ byte) & 0xff];
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function makeCrcTable() {
  const table = new Uint32Array(256);
  for (let index = 0; index < 256; index += 1) {
    let value = index;
    for (let bit = 0; bit < 8; bit += 1) {
      value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
    }
    table[index] = value >>> 0;
  }
  return table;
}
