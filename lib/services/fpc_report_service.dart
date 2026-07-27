import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fpc_operating_service.dart';

class FpcReportResult {
  final String fileName;
  final int rowCount;
  final Uint8List bytes;

  const FpcReportResult({
    required this.fileName,
    required this.rowCount,
    required this.bytes,
  });
}

class FpcReportService {
  final FpcOperatingService operatingService;

  FpcReportService({FpcOperatingService? operatingService})
    : operatingService = operatingService ?? FpcOperatingService();

  Future<FpcReportResult> generateAndShare({
    required String reportType,
    required String format,
  }) async {
    final membership = await operatingService.loadMembership();
    final rows = await operatingService.loadReportRows(reportType);
    final generatedAt = DateTime.now();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(generatedAt);
    final extension = format == 'pdf' ? 'pdf' : 'xlsx';
    final fileName = '${reportType}_$stamp.$extension';
    final bytes = format == 'pdf'
        ? await _buildPdf(
            title: _title(reportType),
            organization: membership.fpcName,
            generatedAt: generatedAt,
            rows: rows,
          )
        : _buildExcel(
            title: _title(reportType),
            organization: membership.fpcName,
            generatedAt: generatedAt,
            rows: rows,
          );

    await operatingService.executeOperation('record_report_export', {
      'report_type': reportType,
      'format': format,
      'file_name': fileName,
      'row_count': rows.length,
      'parameters': {
        'generated_at': generatedAt.toUtc().toIso8601String(),
        'organization': membership.fpcName,
        'responsible_user':
            Supabase.instance.client.auth.currentUser?.email ?? '',
      },
    });

    await _share(
      bytes: bytes,
      fileName: fileName,
      format: format,
      subject: '${_title(reportType)} - ${membership.fpcName}',
    );
    return FpcReportResult(
      fileName: fileName,
      rowCount: rows.length,
      bytes: bytes,
    );
  }

  Future<FpcReportResult> generatePlatformAndShare({
    required String reportType,
    required String format,
    String fpcId = '',
    String startsOn = '',
    String endsOn = '',
  }) async {
    final client = Supabase.instance.client;
    final (table, fpcColumn, dateColumn) = switch (reportType) {
      'organizations' => ('fpcs', 'id', 'created_at'),
      'farmers' => ('fpc_farmer_links', 'fpc_id', 'created_at'),
      'procurement' => (
        'fpc_procurement_records',
        'fpc_organization_id',
        'received_at',
      ),
      'quality' => ('quality_certificates', 'fpc_id', 'created_at'),
      'inventory' => ('stock_ledger', 'fpc_id', 'occurred_at'),
      'production' => ('production_runs', 'fpc_id', 'created_at'),
      'sales' => ('sales_orders', 'fpc_id', 'ordered_at'),
      'finance' => ('farmer_payment_ledger', 'fpc_id', 'created_at'),
      'audit' => ('audit_events', 'fpc_id', 'created_at'),
      _ => throw const FpcOperatingException(
        'Unsupported platform report type.',
      ),
    };
    dynamic query = client.from(table).select();
    if (fpcId.isNotEmpty) query = query.eq(fpcColumn, fpcId);
    if (startsOn.isNotEmpty) query = query.gte(dateColumn, startsOn);
    if (endsOn.isNotEmpty) {
      query = query.lte(dateColumn, '${endsOn}T23:59:59.999Z');
    }
    final rows = _rows(await query.limit(5000));
    var organization = 'All FPC organizations';
    if (fpcId.isNotEmpty) {
      final fpc = await client
          .from('fpcs')
          .select('name')
          .eq('id', fpcId)
          .maybeSingle();
      organization = '${fpc?['name'] ?? 'Selected FPC'}';
    }
    final generatedAt = DateTime.now();
    final extension = format == 'pdf' ? 'pdf' : 'xlsx';
    final fileName =
        'platform_${reportType}_${DateFormat('yyyyMMdd_HHmm').format(generatedAt)}.$extension';
    final title = 'Platform ${_title(reportType)}';
    final bytes = format == 'pdf'
        ? await _buildPdf(
            title: title,
            organization: organization,
            generatedAt: generatedAt,
            rows: rows,
          )
        : _buildExcel(
            title: title,
            organization: organization,
            generatedAt: generatedAt,
            rows: rows,
          );
    await client.from('platform_report_exports').insert({
      'report_type': reportType,
      'format': format,
      if (fpcId.isNotEmpty) 'fpc_filter': fpcId,
      'parameters': {'starts_on': startsOn, 'ends_on': endsOn},
      'file_name': fileName,
      'row_count': rows.length,
      'generated_by': client.auth.currentUser?.id,
    });
    await _share(
      bytes: bytes,
      fileName: fileName,
      format: format,
      subject: '$title - $organization',
    );
    return FpcReportResult(
      fileName: fileName,
      rowCount: rows.length,
      bytes: bytes,
    );
  }

  Future<void> _share({
    required Uint8List bytes,
    required String fileName,
    required String format,
    required String subject,
  }) => SharePlus.instance.share(
    ShareParams(
      subject: subject,
      files: [
        XFile.fromData(
          bytes,
          mimeType: format == 'pdf'
              ? 'application/pdf'
              : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          name: fileName,
        ),
      ],
    ),
  );

  Future<Uint8List> _buildPdf({
    required String title,
    required String organization,
    required DateTime generatedAt,
    required List<Map<String, dynamic>> rows,
  }) async {
    final regularFont = await PdfGoogleFonts.notoSansDevanagariRegular();
    final boldFont = await PdfGoogleFonts.notoSansDevanagariBold();
    final document = pw.Document(
      title: title,
      author: organization,
      creator: 'Kalsubai Farms FPC Operating System',
    );
    final columns = _columns(rows).take(8).toList(growable: false);
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(organization),
            pw.Text(
              'Generated ${DateFormat('dd MMM yyyy, HH:mm').format(generatedAt)}',
            ),
            pw.Text(
              'Responsible user: ${Supabase.instance.client.auth.currentUser?.email ?? ''}',
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}'),
        ),
        build: (_) => [
          pw.Text('${rows.length} records'),
          pw.SizedBox(height: 8),
          if (rows.isEmpty)
            pw.Text('No records matched this report.')
          else
            pw.TableHelper.fromTextArray(
              headers: columns.map(_humanize).toList(),
              data: rows
                  .map((row) => columns.map((key) => _value(row[key])).toList())
                  .toList(),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 8,
              ),
              cellStyle: const pw.TextStyle(fontSize: 7),
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.green100,
              ),
            ),
        ],
      ),
    );
    return document.save();
  }

  Uint8List _buildExcel({
    required String title,
    required String organization,
    required DateTime generatedAt,
    required List<Map<String, dynamic>> rows,
  }) {
    final workbook = Excel.createExcel();
    final sheet = workbook['Report'];
    workbook.delete('Sheet1');
    final columns = _columns(rows);
    sheet.appendRow([TextCellValue(title)]);
    sheet.appendRow([
      TextCellValue('Organization'),
      TextCellValue(organization),
    ]);
    sheet.appendRow([
      TextCellValue('Generated at'),
      TextCellValue(generatedAt.toUtc().toIso8601String()),
    ]);
    sheet.appendRow([
      TextCellValue('Responsible user'),
      TextCellValue(Supabase.instance.client.auth.currentUser?.email ?? ''),
    ]);
    sheet.appendRow(
      columns.map((column) => TextCellValue(_humanize(column))).toList(),
    );
    for (final row in rows) {
      sheet.appendRow(
        columns.map((column) => TextCellValue(_value(row[column]))).toList(),
      );
    }
    for (var index = 0; index < columns.length; index++) {
      sheet.setColumnAutoFit(index);
    }
    final bytes = workbook.encode();
    if (bytes == null) {
      throw const FpcOperatingException('Could not create the Excel report.');
    }
    return Uint8List.fromList(bytes);
  }

  List<String> _columns(List<Map<String, dynamic>> rows) {
    final keys = <String>{};
    for (final row in rows) {
      keys.addAll(
        row.keys.where(
          (key) => !{'source_payload', 'immutable_snapshot'}.contains(key),
        ),
      );
    }
    return keys.toList(growable: false);
  }

  List<Map<String, dynamic>> _rows(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  String _value(Object? value) {
    if (value == null) return '';
    if (value is Map || value is List) return jsonEncode(value);
    return '$value';
  }

  String _humanize(String value) => value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  String _title(String reportType) => '${_humanize(reportType)} Report';
}
