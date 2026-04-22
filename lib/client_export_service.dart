// ════════════════════════════════════════════════════════════
//  client_export_service.dart — Billify Export Module
//  Provides professional Excel (.xlsx) and PDF export
//  for the Clients list.
//
//  Dependencies to add in pubspec.yaml:
//    excel: ^4.0.3
//    pdf: ^3.10.8
//    printing: ^5.12.0
//    path_provider: ^2.1.3
//    share_plus: ^9.0.0
// ════════════════════════════════════════════════════════════

import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'client_screens.dart' show ClientModel;
import 'main.dart' show BillifyColors;

// ─────────────────────────────────────────────────────────────
//  Brand palette (mirrors BillifyColors for use in export libs)
// ─────────────────────────────────────────────────────────────

const _kBrandGreen = PdfColor.fromInt(0xFF2E7D32);
const _kBrandGreenLight = PdfColor.fromInt(0xFFE8F5E9);
const _kStatusPending = PdfColor.fromInt(0xFFD32F2F);
const _kStatusAdvance = PdfColor.fromInt(0xFF1565C0);
const _kStatusCompleted = PdfColor.fromInt(0xFF2E7D32);
const _kStatusOverdue = PdfColor.fromInt(0xFFE65100);
const _kGrey = PdfColor.fromInt(0xFF616161);
const _kGreyLight = PdfColor.fromInt(0xFFF5F5F5);
const _kDivider = PdfColor.fromInt(0xFFE0E0E0);
const _kWhite = PdfColors.white;
const _kBlack = PdfColor.fromInt(0xFF1A1A2E);

// Excel brand colors (ARGB hex strings)
const _exBrandGreen = 'FF2E7D32';
const _exBrandGreenFg = 'FFFFFFFF';
const _exHeaderBg = 'FF1A1A2E';
const _exAltRow = 'FFF9FBF9';
const _exPending = 'FFFFEBEE';
const _exAdvance = 'FFE3F2FD';
const _exCompleted = 'FFE8F5E9';
const _exOverdue = 'FFFFF3E0';
const _exBorderColor = 'FFE0E0E0';

// ─────────────────────────────────────────────────────────────
//  Helper utilities
// ─────────────────────────────────────────────────────────────

final _fmt = NumberFormat('#,##,###.##');
final _dateFmt = DateFormat('dd MMM yyyy');

String _rupees(double v) => '₹${_fmt.format(v)}';

String _statusLabel(String s) => s.isEmpty ? 'Pending' : s;

PdfColor _pdfStatusColor(String s) {
  switch (s.toLowerCase()) {
    case 'completed':
      return _kStatusCompleted;
    case 'advance':
      return _kStatusAdvance;
    case 'overdue':
      return _kStatusOverdue;
    default:
      return _kStatusPending;
  }
}

PdfColor _pdfStatusBg(String s) {
  switch (s.toLowerCase()) {
    case 'completed':
      return const PdfColor.fromInt(0xFFE8F5E9);
    case 'advance':
      return const PdfColor.fromInt(0xFFE3F2FD);
    case 'overdue':
      return const PdfColor.fromInt(0xFFFFF3E0);
    default:
      return const PdfColor.fromInt(0xFFFFEBEE);
  }
}

String _exStatusBg(String s) {
  switch (s.toLowerCase()) {
    case 'completed':
      return _exCompleted;
    case 'advance':
      return _exAdvance;
    case 'overdue':
      return _exOverdue;
    default:
      return _exPending;
  }
}

// ════════════════════════════════════════════════════════════
//  EXPORT SERVICE
// ════════════════════════════════════════════════════════════

class ClientExportService {
  ClientExportService._();

  // ──────────────────────────────────────────────────────────
  //  EXCEL EXPORT
  // ──────────────────────────────────────────────────────────

  static Future<void> exportToExcel(
      BuildContext context,
      List<ClientModel> clients, {
        String? exportTitle,
      }) async {
    final title = exportTitle ?? 'Billify – Client Report';
    final excel = xl.Excel.createExcel();

    // Remove default sheet and build everything in one sheet
    excel.delete('Sheet1');
    final sheet = excel['Clients Report'];
    _buildExcelSingleSheet(sheet, clients, title);

    // Save & share
    final bytes = excel.save();
    if (bytes == null) {
      _showError(context, 'Failed to generate Excel file.');
      return;
    }

    await _shareBytes(
      context,
      Uint8List.fromList(bytes),
      'clients_export_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      mimeType:
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      subject: title,
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  EXCEL SHEET BUILDER  —  Premium single-sheet layout
  //
  //  Columns A–J (indices 0–9):
  //   A=#  B=Name  C=Mobile  D=ClientCat  E=ShootCat
  //   F=ReelCat  G=PayType  H=Amount  I=Status  J=Date
  //
  //  Sections:
  //   [0] BANNER          — merged A:J, 2 rows
  //   [1] SUMMARY (A:E)   — side-by-side with PAYMENT STATUS (F:J)
  //   [2] CLIENT DETAILS  — merged heading A:J + column headers + data + total
  //   [3] REEL BREAKDOWN  — merged heading A:J + column headers + data
  // ══════════════════════════════════════════════════════════════
  static void _buildExcelSingleSheet(
      xl.Sheet sheet, List<ClientModel> clients, String title) {

    // ── Column widths  A     B      C      D      E      F      G      H      I      J
    const widths =    [5.5, 26.0,  15.0,  18.0,  20.0,  22.0,  15.0,  16.0,  14.0,  18.0];
    for (var i = 0; i < widths.length; i++) {
      sheet.setColumnWidth(i, widths[i]);
    }

    // ── Pre-compute stats
    final totalRevenue = clients.fold<double>(0, (s, c) => s + c.totalPaymentAmount);
    final completed  = clients.where((c) => c.paymentStatus.toLowerCase() == 'completed').length;
    final pending    = clients.where((c) => c.paymentStatus.toLowerCase() == 'pending').length;
    final advance    = clients.where((c) => c.paymentStatus.toLowerCase() == 'advance').length;
    final overdue    = clients.where((c) => c.paymentStatus.toLowerCase() == 'overdue').length;
    final totalReels = clients.fold<int>(0, (s, c) => s + c.reelCount);

    int row = 0;

    // ═══════════════════════════════════════════════════════
    // SECTION 0 — BANNER
    //  Row 0: dark bg, green accent col A, "BILLIFY" title
    //  Row 1: dark bg, subtitle + generated timestamp
    // ═══════════════════════════════════════════════════════

    // Row 0 — title
    sheet.setRowHeight(row, 40);
    _exCell(sheet, row, 0, value: '', bgColor: _exBrandGreen);
    _exMerge(sheet, row, 1, row, 5);
    _exCell(sheet, row, 1, value: '  BILLIFY',
        bold: true, fontSize: 20, fgColor: _exBrandGreenFg,
        bgColor: _exHeaderBg, halign: xl.HorizontalAlign.Left);
    _exMerge(sheet, row, 6, row, 9);
    _exCell(sheet, row, 6, value: title,
        italic: true, fontSize: 9, fgColor: 'FFAAAAAA',
        bgColor: _exHeaderBg, halign: xl.HorizontalAlign.Right);
    row++;

    // Row 1 — subtitle / timestamp
    sheet.setRowHeight(row, 20);
    _exCell(sheet, row, 0, value: '', bgColor: _exBrandGreen);
    _exMerge(sheet, row, 1, row, 5);
    _exCell(sheet, row, 1, value: 'Client Management Report',
        italic: true, fontSize: 9, fgColor: 'FF888888', bgColor: _exHeaderBg);
    _exMerge(sheet, row, 6, row, 9);
    _exCell(sheet, row, 6,
        value: 'Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
        italic: true, fontSize: 8, fgColor: 'FF666666',
        bgColor: _exHeaderBg, halign: xl.HorizontalAlign.Right);
    row++;

    // blank spacer row
    sheet.setRowHeight(row, 10);
    for (var c = 0; c < 10; c++) {
      _exCell(sheet, row, c, value: '', bgColor: 'FFFFFFFF');
    }
    row++;

    // ═══════════════════════════════════════════════════════
    // ═══════════════════════════════════════════════════════
    // SECTION 1 — KPI CARDS  (5 cards across A:J, 2 cols each)
    //
    //  Each card (2 cols wide):
    //   Row +0 (h=4):  solid colour top accent bar
    //   Row +1 (h=36): big value, bold, font 18
    //   Row +2 (h=18): small muted label
    //   Row +3 (h=8):  bottom padding
    //
    //  Cards: Clients | Revenue | Reels | Completed% | At Risk
    // ═══════════════════════════════════════════════════════

    final completedPct = clients.isEmpty
        ? '0%'
        : '${(completed / clients.length * 100).toStringAsFixed(0)}%';
    final atRisk = pending + overdue;

    // [startCol, endCol, accentHex, bgHex, value, label, valueFgHex]
    final cards = <List<dynamic>>[
      [0, 1, _exBrandGreen, 'FFF0FAF1', clients.length.toString(),  'TOTAL CLIENTS',   _exBrandGreen],
      [2, 3, 'FF1565C0',    'FFE8F0FE', _rupeesInt(totalRevenue),   'TOTAL REVENUE',   'FF1565C0'   ],
      [4, 5, 'FF00838F',    'FFE0F7FA', totalReels.toString(),       'TOTAL REELS',     'FF00838F'   ],
      [6, 7, 'FF2E7D32',    'FFE8F5E9', completedPct,               'COMPLETION RATE', 'FF2E7D32'   ],
      [8, 9, 'FFE65100',    'FFFFF3E0', atRisk.toString(),           'AT RISK',         'FFE65100'   ],
    ];

    // Row A: coloured accent top bar (h=4)
    sheet.setRowHeight(row, 4);
    for (final card in cards) {
      final c0 = card[0] as int; final c1 = card[1] as int;
      _exMerge(sheet, row, c0, row, c1);
      _exCell(sheet, row, c0, value: '', bgColor: card[2] as String,
          topBorderThick: true,
          leftBorderThick: c0 == 0, rightBorderThick: c1 == 9);
    }
    row++;

    // Row B: big value (h=36)
    sheet.setRowHeight(row, 36);
    for (final card in cards) {
      final c0 = card[0] as int; final c1 = card[1] as int;
      _exMerge(sheet, row, c0, row, c1);
      _exCell(sheet, row, c0,
          value: card[4] as String,
          bold: true, fontSize: 18,
          fgColor: card[6] as String, bgColor: card[3] as String,
          halign: xl.HorizontalAlign.Center,
          border: true,
          leftBorderThick: c0 == 0, rightBorderThick: c1 == 9);
    }
    row++;

    // Row C: small label (h=18)
    sheet.setRowHeight(row, 18);
    for (final card in cards) {
      final c0 = card[0] as int; final c1 = card[1] as int;
      _exMerge(sheet, row, c0, row, c1);
      _exCell(sheet, row, c0,
          value: card[5] as String,
          fontSize: 7, fgColor: 'FF888888', bgColor: card[3] as String,
          halign: xl.HorizontalAlign.Center,
          border: true,
          leftBorderThick: c0 == 0, rightBorderThick: c1 == 9);
    }
    row++;

    // Row D: bottom padding (h=8)
    sheet.setRowHeight(row, 8);
    for (final card in cards) {
      final c0 = card[0] as int; final c1 = card[1] as int;
      _exMerge(sheet, row, c0, row, c1);
      _exCell(sheet, row, c0, value: '', bgColor: card[3] as String,
          border: true,
          leftBorderThick: c0 == 0, rightBorderThick: c1 == 9);
    }
    row++;

    // spacer
    sheet.setRowHeight(row, 14);
    for (var c = 0; c < 10; c++) {
      _exCell(sheet, row, c, value: '', bgColor: 'FFFFFFFF');
    }
    row++;

    // ═══════════════════════════════════════════════════════
    // SECTION 2 — CLIENT DETAILS
    // ═══════════════════════════════════════════════════════

    // FIX-B3: Merged heading — write value ONLY to anchor cell (col 0).
    // Do NOT loop over cols 1–9 after merging; that breaks the merge.
    sheet.setRowHeight(row, 26);
    _exMerge(sheet, row, 0, row, 9);
    _exCell(sheet, row, 0, value: '  CLIENT DETAILS',
        bold: true, fontSize: 11, fgColor: _exBrandGreenFg,
        bgColor: _exBrandGreen, halign: xl.HorizontalAlign.Left,
        border: true, topBorderThick: true,
        leftBorderThick: true, rightBorderThick: true);
    // No loop here — merged cells must not be written individually
    row++;

    // Column headers (10 cols, all bordered)
    sheet.setRowHeight(row, 20);
    const clientHeaders = [
      '#', 'Client Name', 'Mobile', 'Client Category',
      'Shoot Category', 'Reel Category', 'Payment Type',
      'Total Amount', 'Status', 'Created Date',
    ];
    for (var c = 0; c < clientHeaders.length; c++) {
      _exCell(sheet, row, c,
          value: clientHeaders[c],
          bold: true, fontSize: 8,
          fgColor: _exBrandGreenFg, bgColor: _exHeaderBg,
          border: true,
          leftBorderThick: c == 0,
          rightBorderThick: c == 9,
          halign: c == 7 ? xl.HorizontalAlign.Right : xl.HorizontalAlign.Left);
    }
    row++;

    // Data rows
    for (var r = 0; r < clients.length; r++) {
      final c      = clients[r];
      final isAlt  = r.isOdd;
      final bg     = isAlt ? _exAltRow : 'FFFFFFFF';
      final sBg    = _exStatusBg(c.paymentStatus);
      final sFg    = _exStatusFg(c.paymentStatus);
      sheet.setRowHeight(row, 19);

      _exCell(sheet, row, 0,
          value: '${r + 1}', numericValue: (r + 1).toDouble(),
          fontSize: 8, bgColor: bg, border: true,
          leftBorderThick: true, halign: xl.HorizontalAlign.Center);
      _exCell(sheet, row, 1,
          value: c.name, bold: true, fontSize: 9, bgColor: bg, border: true);
      _exCell(sheet, row, 2,
          value: c.mobile, fontSize: 8, bgColor: bg, border: true);
      _exCell(sheet, row, 3,
          value: c.displayCategory, fontSize: 8, bgColor: bg, border: true);
      _exCell(sheet, row, 4,
          value: c.primaryReel.displayShootCategory,
          fontSize: 8, bgColor: bg, border: true);
      _exCell(sheet, row, 5,
          value: c.primaryReel.displayReelCategory,
          fontSize: 8, bgColor: bg, border: true);
      _exCell(sheet, row, 6,
          value: c.primaryReel.displayPaymentType,
          fontSize: 8, bgColor: bg, border: true);
      _exCell(sheet, row, 7,
          value: _rupeesInt(c.totalPaymentAmount),
          numericValue: c.totalPaymentAmount,
          bold: true, fontSize: 9, isCurrency: true,
          fgColor: _exBrandGreen, bgColor: bg,
          border: true, halign: xl.HorizontalAlign.Right);
      _exCell(sheet, row, 8,
          value: _statusLabel(c.paymentStatus).toUpperCase(),
          bold: true, fontSize: 8,
          fgColor: sFg, bgColor: sBg,
          border: true, halign: xl.HorizontalAlign.Center);
      _exCell(sheet, row, 9,
          value: _dateFmt.format(c.createdAt),
          fontSize: 8, bgColor: bg,
          border: true, rightBorderThick: true);
      row++;
    }

    // Grand total row
    final total = clients.fold<double>(0, (s, c) => s + c.totalPaymentAmount);
    sheet.setRowHeight(row, 24);
    _exCell(sheet, row, 0, value: '',
        bgColor: _exBrandGreen,
        border: true, topBorderThick: true, leftBorderThick: true);
    _exCell(sheet, row, 1,
        value: '  GRAND TOTAL  —  ${clients.length} clients',
        bold: true, fontSize: 10, fgColor: _exBrandGreenFg,
        bgColor: _exBrandGreen,
        border: true, topBorderThick: true,
        halign: xl.HorizontalAlign.Left);
    _exCell(sheet, row, 2, value: '', bgColor: _exBrandGreen, border: true, topBorderThick: true);
    _exCell(sheet, row, 3, value: '', bgColor: _exBrandGreen, border: true, topBorderThick: true);
    _exCell(sheet, row, 4, value: '', bgColor: _exBrandGreen, border: true, topBorderThick: true);
    _exCell(sheet, row, 5, value: '', bgColor: _exBrandGreen, border: true, topBorderThick: true);
    _exCell(sheet, row, 6, value: '', bgColor: _exBrandGreen, border: true, topBorderThick: true);
    _exCell(sheet, row, 7,
        value: _rupeesInt(total),
        numericValue: total,
        bold: true, fontSize: 11, isCurrency: true, fgColor: _exBrandGreenFg,
        bgColor: _exBrandGreen,
        border: true, topBorderThick: true,
        halign: xl.HorizontalAlign.Right);
    _exCell(sheet, row, 8, value: '',
        bgColor: _exBrandGreen, border: true, topBorderThick: true);
    _exCell(sheet, row, 9, value: '',
        bgColor: _exBrandGreen,
        border: true, topBorderThick: true, rightBorderThick: true);
    row++;

    // spacer
    sheet.setRowHeight(row, 14);
    for (var c = 0; c < 10; c++) {
      _exCell(sheet, row, c, value: '', bgColor: 'FFFFFFFF');
    }
    row++;

    // ═══════════════════════════════════════════════════════
    // SECTION 3 — REEL BREAKDOWN
    // ═══════════════════════════════════════════════════════

    // FIX-B3: same merge fix — only write to anchor cell col 0, no loop after
    sheet.setRowHeight(row, 26);
    _exMerge(sheet, row, 0, row, 9);
    _exCell(sheet, row, 0, value: '  REEL BREAKDOWN',
        bold: true, fontSize: 11, fgColor: _exBrandGreenFg,
        bgColor: _exHeaderBg, halign: xl.HorizontalAlign.Left,
        border: true, topBorderThick: true,
        leftBorderThick: true, rightBorderThick: true);
    row++;

    // Column headers
    sheet.setRowHeight(row, 20);
    const reelHeaders = [
      '#', 'Client Name', 'Reel #', 'Shoot Category',
      'Reel Category', 'Payment Type', 'Amount', 'Status',
      'Project Date', 'Notes',
    ];
    for (var c = 0; c < reelHeaders.length; c++) {
      _exCell(sheet, row, c,
          value: reelHeaders[c],
          bold: true, fontSize: 8,
          fgColor: _exBrandGreenFg, bgColor: _exHeaderBg,
          border: true,
          leftBorderThick: c == 0,
          rightBorderThick: c == 9,
          halign: c == 6 ? xl.HorizontalAlign.Right : xl.HorizontalAlign.Left);
    }
    row++;

    // Data rows — use clientIdx so each client group shares the same # value
    var clientIdx = 1;
    for (final c in clients) {
      for (final reel in c.reels) {
        final isAlt = row.isOdd;
        final bg    = isAlt ? _exAltRow : 'FFFFFFFF';
        final sBg   = _exStatusBg(reel.paymentStatus);
        final sFg   = _exStatusFg(reel.paymentStatus);
        sheet.setRowHeight(row, 19);

        _exCell(sheet, row, 0,
            value: clientIdx.toString(),
            numericValue: clientIdx.toDouble(),
            fontSize: 8, bgColor: bg,
            border: true, leftBorderThick: true,
            halign: xl.HorizontalAlign.Center);
        _exCell(sheet, row, 1,
            value: c.name, bold: true, fontSize: 9, bgColor: bg, border: true);
        _exCell(sheet, row, 2,
            value: 'R${reel.index}', fontSize: 8,
            bgColor: bg, border: true, halign: xl.HorizontalAlign.Center);
        _exCell(sheet, row, 3,
            value: reel.displayShootCategory,
            fontSize: 8, bgColor: bg, border: true);
        _exCell(sheet, row, 4,
            value: reel.displayReelCategory,
            fontSize: 8, bgColor: bg, border: true);
        _exCell(sheet, row, 5,
            value: reel.displayPaymentType,
            fontSize: 8, bgColor: bg, border: true);
        _exCell(sheet, row, 6,
            value: _rupeesInt(reel.paymentAmount),
            numericValue: reel.paymentAmount,
            bold: true, fontSize: 9, isCurrency: true,
            fgColor: _exBrandGreen, bgColor: bg,
            border: true, halign: xl.HorizontalAlign.Right);
        _exCell(sheet, row, 7,
            value: _statusLabel(reel.paymentStatus).toUpperCase(),
            bold: true, fontSize: 8,
            fgColor: sFg, bgColor: sBg,
            border: true, halign: xl.HorizontalAlign.Center);
        _exCell(sheet, row, 8,
            value: reel.projectStartDate != null
                ? _dateFmt.format(reel.projectStartDate!)
                : '—',
            fontSize: 8, bgColor: bg, border: true);
        _exCell(sheet, row, 9,
            value: '', fontSize: 8, bgColor: bg,
            border: true, rightBorderThick: true);
        row++;
      }
      clientIdx++;
    }

    // Closing accent bar — caps the reel table bottom edge
    sheet.setRowHeight(row, 6);
    for (var c = 0; c < 10; c++) {
      _exCell(sheet, row, c, value: '',
          bgColor: _exHeaderBg,
          topBorderThick: true,
          leftBorderThick: c == 0,
          rightBorderThick: c == 9);
    }
  }

  // ── Helpers ────────────────────────────────────────────────

  /// Rupee string — integer display, no decimals
  static String _rupeesInt(double v) =>
      '₹${NumberFormat('#,##,###').format(v.round())}';

  static String _pct(int count, int total) =>
      total == 0 ? '0%' : '${(count / total * 100).toStringAsFixed(1)}%';

  static String _exStatusFg(String s) {
    switch (s.toLowerCase()) {
      case 'completed': return 'FF1B5E20';
      case 'advance':   return 'FF0D47A1';
      case 'overdue':   return 'FFBf360C';
      default:          return 'FFB71C1C';
    }
  }

  /// Merge a rectangular range of cells
  static void _exMerge(
      xl.Sheet sheet, int startRow, int startCol, int endRow, int endCol) {
    sheet.merge(
      xl.CellIndex.indexByColumnRow(columnIndex: startCol, rowIndex: startRow),
      xl.CellIndex.indexByColumnRow(columnIndex: endCol,   rowIndex: endRow),
    );
  }

  // ── Excel cell builder ─────────────────────────────────────
  static void _exCell(
      xl.Sheet sheet,
      int rowIdx,
      int colIdx, {
        required String value,
        bool bold             = false,
        bool italic           = false,
        double fontSize       = 9,
        String? bgColor,
        String? fgColor,
        String? color,
        bool border           = false,
        bool topBorderThick   = false,
        bool leftBorderThick  = false,
        bool rightBorderThick = false,
        xl.HorizontalAlign halign = xl.HorizontalAlign.Left,
        double? numericValue,
        bool isCurrency       = false,
      }) {
    final cell = sheet.cell(xl.CellIndex.indexByColumnRow(
        columnIndex: colIdx, rowIndex: rowIdx));

    // Store real number when provided; text otherwise
    if (numericValue != null) {
      cell.value = xl.DoubleCellValue(numericValue);
    } else {
      cell.value = xl.TextCellValue(value);
    }

    // Use rupee format for currency cells, plain integer format for counts
    final numFmt = numericValue != null
        ? (isCurrency
        ? xl.CustomNumericNumFormat(formatCode: r'₹#,##,##0;(₹#,##,##0)')
        : xl.CustomNumericNumFormat(formatCode: '#,##0'))
        : xl.NumFormat.standard_0;

    final textColor = fgColor ?? color ?? 'FF212121';

    xl.Border mkBorder(bool thick) => xl.Border(
      borderStyle: thick ? xl.BorderStyle.Medium : xl.BorderStyle.Thin,
      borderColorHex: xl.ExcelColor.fromHexString(
          thick ? 'FF888888' : _exBorderColor),
    );
    final noBorder = xl.Border();

    cell.cellStyle = xl.CellStyle(
      bold:       bold,
      italic:     italic,
      fontSize:   fontSize.toInt(),
      fontColorHex: xl.ExcelColor.fromHexString(textColor),
      backgroundColorHex: bgColor != null
          ? xl.ExcelColor.fromHexString(bgColor)
          : xl.ExcelColor.fromHexString('FFFFFFFF'),
      numberFormat:    numFmt,
      horizontalAlign: halign,
      verticalAlign:   xl.VerticalAlign.Center,
      leftBorder:   leftBorderThick  ? mkBorder(true)
          : border           ? mkBorder(false)
          : noBorder,
      rightBorder:  rightBorderThick ? mkBorder(true)
          : border           ? mkBorder(false)
          : noBorder,
      topBorder:    topBorderThick   ? mkBorder(true)
          : border           ? mkBorder(false)
          : noBorder,
      bottomBorder: border ? mkBorder(false) : noBorder,
    );
  }

  // ──────────────────────────────────────────────────────────
  //  PDF EXPORT
  // ──────────────────────────────────────────────────────────

  static Future<void> exportToPdf(
      BuildContext context,
      List<ClientModel> clients, {
        String? exportTitle,
      }) async {
    final title = exportTitle ?? 'Billify – Client Report';
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: await PdfGoogleFonts.nunitoRegular(),
        bold: await PdfGoogleFonts.nunitoBold(),
        italic: await PdfGoogleFonts.nunitoItalic(),
        boldItalic: await PdfGoogleFonts.nunitoBoldItalic(),
      ),
    );

    final poppins = await PdfGoogleFonts.poppinsRegular();
    final poppinsBold = await PdfGoogleFonts.poppinsBold();

    // ── Page 1: Cover + Summary ────────────────────────────
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        build: (ctx) =>
            _buildPdfCoverPage(ctx, clients, title, poppins, poppinsBold),
      ),
    );

    // ── Page 2+: Client table (paginated) ──────────────────
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        header: (ctx) => _buildPdfPageHeader(ctx, title, poppinsBold),
        footer: (ctx) => _buildPdfPageFooter(ctx),
        build: (ctx) => [
          _buildPdfClientTable(clients, poppins, poppinsBold),
          pw.SizedBox(height: 20),
          _buildPdfReelTable(clients, poppins, poppinsBold),
        ],
      ),
    );

    // Share / print
    await _sharePdfBytes(context, await pdf.save(), title);
  }

  // ── PDF: Cover page ────────────────────────────────────────

  static pw.Widget _buildPdfCoverPage(
      pw.Context ctx,
      List<ClientModel> clients,
      String title,
      pw.Font regular,
      pw.Font bold,
      ) {
    final total = clients.fold<double>(0, (s, c) => s + c.totalPaymentAmount);
    final completed =
        clients.where((c) => c.paymentStatus.toLowerCase() == 'completed').length;
    final pending =
        clients.where((c) => c.paymentStatus.toLowerCase() == 'pending').length;
    final advance =
        clients.where((c) => c.paymentStatus.toLowerCase() == 'advance').length;
    final overdue =
        clients.where((c) => c.paymentStatus.toLowerCase() == 'overdue').length;

    return pw.Stack(
      children: [
        // Background accent bar
        pw.Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: pw.Container(
            height: 220,
            color: _kBlack,
          ),
        ),
        pw.Positioned(
          top: 0,
          left: 0,
          child: pw.Container(
            width: 8,
            height: 220,
            color: _kBrandGreen,
          ),
        ),
        // Main content
        pw.Padding(
          padding: const pw.EdgeInsets.all(40),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Logo / Brand area
              pw.SizedBox(height: 16),
              pw.Text(
                'BILLIFY',
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 28,
                  color: _kBrandGreen,
                  letterSpacing: 6,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Client Management Report',
                style: pw.TextStyle(
                  font: regular,
                  fontSize: 13,
                  color: _kWhite,
                  letterSpacing: 1.5,
                ),
              ),
              pw.SizedBox(height: 120),
              // Report title
              pw.Text(
                title.toUpperCase(),
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 18,
                  color: _kBlack,
                  letterSpacing: 1,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Generated on ${DateFormat('dd MMMM yyyy, hh:mm a').format(DateTime.now())}',
                style: pw.TextStyle(
                    font: regular, fontSize: 10, color: _kGrey),
              ),
              pw.SizedBox(height: 36),

              // KPI cards grid
              pw.Text(
                'REPORT HIGHLIGHTS',
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 9,
                  color: _kBrandGreen,
                  letterSpacing: 2,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Divider(color: _kBrandGreen, thickness: 1.5),
              pw.SizedBox(height: 14),
              pw.Row(
                children: [
                  _pdfKpiCard('TOTAL CLIENTS', clients.length.toString(),
                      bold, regular),
                  pw.SizedBox(width: 12),
                  _pdfKpiCard('TOTAL REVENUE', _rupees(total), bold, regular,
                      accent: _kBrandGreen),
                  pw.SizedBox(width: 12),
                  _pdfKpiCard('TOTAL REELS',
                      clients.fold<int>(0, (s, c) => s + c.reelCount).toString(),
                      bold, regular),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Row(
                children: [
                  _pdfStatusCard('COMPLETED', completed, _kStatusCompleted,
                      const PdfColor.fromInt(0xFFE8F5E9), bold, regular),
                  pw.SizedBox(width: 12),
                  _pdfStatusCard('ADVANCE', advance, _kStatusAdvance,
                      const PdfColor.fromInt(0xFFE3F2FD), bold, regular),
                  pw.SizedBox(width: 12),
                  _pdfStatusCard('PENDING', pending, _kStatusPending,
                      const PdfColor.fromInt(0xFFFFEBEE), bold, regular),
                  pw.SizedBox(width: 12),
                  _pdfStatusCard('OVERDUE', overdue, _kStatusOverdue,
                      const PdfColor.fromInt(0xFFFFF3E0), bold, regular),
                ],
              ),
              pw.Spacer(),
              pw.Divider(color: _kDivider),
              pw.Text(
                'Confidential — Billify Internal Report',
                style: pw.TextStyle(
                    font: regular, fontSize: 8, color: _kGrey),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _pdfKpiCard(
      String label, String value, pw.Font bold, pw.Font regular,
      {PdfColor accent = _kBlack}) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _kDivider),
          color: _kGreyLight,
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(
                  font: bold, fontSize: 7, color: _kGrey, letterSpacing: 1),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              value,
              style: pw.TextStyle(font: bold, fontSize: 18, color: accent),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _pdfStatusCard(
      String label,
      int count,
      PdfColor color,
      PdfColor bg,
      pw.Font bold,
      pw.Font regular,
      ) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: pw.BoxDecoration(
          color: bg,
          border: pw.Border(left: pw.BorderSide(color: color, width: 3)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              count.toString(),
              style: pw.TextStyle(font: bold, fontSize: 20, color: color),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              label,
              style: pw.TextStyle(
                  font: bold, fontSize: 7, color: color, letterSpacing: 0.8),
            ),
          ],
        ),
      ),
    );
  }

  // ── PDF: Page header / footer ──────────────────────────────

  static pw.Widget _buildPdfPageHeader(
      pw.Context ctx, String title, pw.Font bold) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
            bottom: pw.BorderSide(color: _kBrandGreen, width: 1.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'BILLIFY',
            style: pw.TextStyle(
                font: bold,
                fontSize: 10,
                color: _kBrandGreen,
                letterSpacing: 3),
          ),
          pw.Text(
            title,
            style: pw.TextStyle(font: bold, fontSize: 9, color: _kGrey),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPdfPageFooter(pw.Context ctx) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _kDivider)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Billify — Confidential Client Report',
            style: const pw.TextStyle(fontSize: 8, color: _kGrey),
          ),
          pw.Text(
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: _kGrey),
          ),
        ],
      ),
    );
  }

  // ── PDF: Client summary table ──────────────────────────────

  static pw.Widget _buildPdfClientTable(
      List<ClientModel> clients, pw.Font regular, pw.Font bold) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _pdfSectionTitle('CLIENT SUMMARY', bold),
        pw.SizedBox(height: 8),
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(0.5),  // #
            1: pw.FlexColumnWidth(1.8),  // Name
            2: pw.FlexColumnWidth(1.2),  // Mobile
            3: pw.FlexColumnWidth(1.2),  // Category
            4: pw.FlexColumnWidth(1.3),  // Shoot Type
            5: pw.FlexColumnWidth(1.5),  // Reel Type
            6: pw.FlexColumnWidth(1.1),  // Payment
            7: pw.FlexColumnWidth(1.2),  // Amount
            8: pw.FlexColumnWidth(1.0),  // Status
          },
          border: pw.TableBorder.all(color: _kDivider, width: 0.5),
          children: [
            _pdfHeaderRow(
              ['#', 'Client Name', 'Mobile', 'Category',
                'Shoot Type', 'Reel Type', 'Payment', 'Amount', 'Status'],
              bold,
            ),
            for (var i = 0; i < clients.length; i++)
              _pdfClientRow(i, clients[i], regular, bold),
            _pdfTotalRow(clients, bold),
          ],
        ),
      ],
    );
  }

  static pw.TableRow _pdfHeaderRow(List<String> labels, pw.Font bold) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: _kBlack),
      children: labels
          .map((l) => _pdfCell(l, bold,
          color: _kWhite, fontSize: 8, isHeader: true))
          .toList(),
    );
  }

  static pw.TableRow _pdfClientRow(
      int index, ClientModel c, pw.Font regular, pw.Font bold) {
    final isAlt = index.isOdd;
    final bg = isAlt ? _kGreyLight : _kWhite;
    final statusColor = _pdfStatusColor(c.paymentStatus);
    final statusBg = _pdfStatusBg(c.paymentStatus);
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: bg),
      children: [
        _pdfCell('${index + 1}', regular, fontSize: 7.5),
        _pdfCell(c.name, bold, fontSize: 8),
        _pdfCell(c.mobile, regular, fontSize: 7.5),
        _pdfCell(c.displayCategory, regular, fontSize: 7.5),
        _pdfCell(c.primaryReel.displayShootCategory, regular, fontSize: 7.5),
        _pdfCell(c.primaryReel.displayReelCategory, regular, fontSize: 7.5),
        _pdfCell(c.primaryReel.displayPaymentType, regular, fontSize: 7.5),
        _pdfCell(_rupees(c.totalPaymentAmount), bold,
            fontSize: 8, color: _kBrandGreen),
        _pdfStatusBadgeCell(
            _statusLabel(c.paymentStatus), statusColor, statusBg, bold),
      ],
    );
  }

  static pw.TableRow _pdfTotalRow(List<ClientModel> clients, pw.Font bold) {
    final total = clients.fold<double>(0, (s, c) => s + c.totalPaymentAmount);
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: _kBrandGreen),
      children: [
        _pdfCell('', bold, color: _kWhite),
        _pdfCell('TOTAL  (${clients.length} clients)', bold,
            color: _kWhite, fontSize: 8.5),
        _pdfCell('', bold, color: _kWhite),
        _pdfCell('', bold, color: _kWhite),
        _pdfCell('', bold, color: _kWhite),
        _pdfCell('', bold, color: _kWhite),
        _pdfCell('', bold, color: _kWhite),
        _pdfCell(_rupees(total), bold, color: _kWhite, fontSize: 9),
        _pdfCell('', bold, color: _kWhite),
      ],
    );
  }

  // ── PDF: Reel breakdown table ──────────────────────────────

  static pw.Widget _buildPdfReelTable(
      List<ClientModel> clients, pw.Font regular, pw.Font bold) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _pdfSectionTitle('REEL BREAKDOWN', bold),
        pw.SizedBox(height: 8),
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(0.5),
            1: pw.FlexColumnWidth(1.8),
            2: pw.FlexColumnWidth(0.7),
            3: pw.FlexColumnWidth(1.5),
            4: pw.FlexColumnWidth(1.8),
            5: pw.FlexColumnWidth(1.1),
            6: pw.FlexColumnWidth(1.2),
            7: pw.FlexColumnWidth(1.0),
            8: pw.FlexColumnWidth(1.2),
          },
          border: pw.TableBorder.all(color: _kDivider, width: 0.5),
          children: [
            _pdfHeaderRow([
              '#', 'Client', 'Reel', 'Shoot Cat.', 'Reel Cat.',
              'Payment', 'Amount', 'Status', 'Proj. Date'
            ], bold),
            for (var ci = 0; ci < clients.length; ci++) ...[
              for (final reel in clients[ci].reels)
                _pdfReelRow(ci, clients[ci], reel, regular, bold),
            ],
          ],
        ),
      ],
    );
  }

  static pw.TableRow _pdfReelRow(
      int ci, ClientModel c, dynamic reel, pw.Font regular, pw.Font bold) {
    final isAlt = ci.isOdd;
    final bg = isAlt ? _kGreyLight : _kWhite;
    final statusColor = _pdfStatusColor(reel.paymentStatus as String);
    final statusBg = _pdfStatusBg(reel.paymentStatus as String);
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: bg),
      children: [
        _pdfCell('${ci + 1}', regular, fontSize: 7.5),
        _pdfCell(c.name, bold, fontSize: 7.5),
        _pdfCell('R${reel.index}', regular, fontSize: 7.5),
        _pdfCell(reel.displayShootCategory as String, regular, fontSize: 7.5),
        _pdfCell(reel.displayReelCategory as String, regular, fontSize: 7.5),
        _pdfCell(reel.displayPaymentType as String, regular, fontSize: 7.5),
        _pdfCell(_rupees(reel.paymentAmount as double), bold,
            fontSize: 7.5, color: _kBrandGreen),
        _pdfStatusBadgeCell(_statusLabel(reel.paymentStatus as String),
            statusColor, statusBg, bold),
        _pdfCell(
          reel.projectStartDate != null
              ? _dateFmt.format(reel.projectStartDate as DateTime)
              : '—',
          regular,
          fontSize: 7.5,
        ),
      ],
    );
  }

  // ── PDF cell helpers ───────────────────────────────────────

  static pw.Widget _pdfCell(
      String text,
      pw.Font font, {
        double fontSize = 9,
        PdfColor color = _kBlack,
        bool isHeader = false,
      }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
            font: font,
            fontSize: fontSize,
            color: color,
            fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal),
      ),
    );
  }

  static pw.Widget _pdfStatusBadgeCell(
      String label, PdfColor color, PdfColor bg, pw.Font bold) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: pw.BoxDecoration(
          color: bg,
          border: pw.Border(left: pw.BorderSide(color: color, width: 2)),
        ),
        child: pw.Text(
          label.toUpperCase(),
          style: pw.TextStyle(
              font: bold, fontSize: 6.5, color: color, letterSpacing: 0.5),
        ),
      ),
    );
  }

  static pw.Widget _pdfSectionTitle(String label, pw.Font bold) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: const pw.BoxDecoration(
        color: _kBrandGreen,
      ),
      child: pw.Text(
        label,
        style: pw.TextStyle(
            font: bold,
            fontSize: 9,
            color: _kWhite,
            letterSpacing: 2),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  //  FILE SHARING UTILITIES
  // ──────────────────────────────────────────────────────────

  static Future<void> _shareBytes(
      BuildContext context,
      Uint8List bytes,
      String filename, {
        required String mimeType,
        String? subject,
      }) async {
    try {
      // Share directly from memory — no path_provider / getTemporaryDirectory
      // needed, which avoids MissingPluginException on unregistered platforms.
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: filename, mimeType: mimeType)],
        subject: subject,
      );
    } catch (e) {
      _showError(context, 'Export failed: $e');
    }
  }

  static Future<void> _sharePdfBytes(
      BuildContext context,
      Uint8List bytes,
      String title,
      ) async {
    try {
      await Printing.sharePdf(
        bytes: bytes,
        filename:
        'clients_export_${DateTime.now().millisecondsSinceEpoch}.pdf',
        subject: title,
      );
    } catch (e) {
      _showError(context, 'PDF export failed: $e');
    }
  }

  static void _showError(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: BillifyColors.unpaid,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  EXPORT BOTTOM SHEET  (call from ClientListScreen)
// ════════════════════════════════════════════════════════════

class ClientExportSheet extends StatefulWidget {
  final List<ClientModel> clients;

  const ClientExportSheet({super.key, required this.clients});

  @override
  State<ClientExportSheet> createState() => _ClientExportSheetState();
}

class _ClientExportSheetState extends State<ClientExportSheet> {
  bool _exportingExcel = false;
  bool _exportingPdf = false;

  @override
  Widget build(BuildContext context) {
    final total = widget.clients
        .fold<double>(0, (s, c) => s + c.totalPaymentAmount);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 20),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: BillifyColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Text(
              'EXPORT DATA',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
                color: BillifyColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.clients.length} clients · ${NumberFormat('#,##,###.##').format(total)} total revenue',
              style: GoogleFonts.nunito(
                fontSize: 12,
                color: BillifyColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            // Excel button
            _ExportOptionTile(
              icon: Icons.table_chart_rounded,
              iconColor: const Color(0xFF1D6F42),
              iconBg: const Color(0xFFE8F5E9),
              title: 'Export as Excel',
              subtitle: 'Summary · Client Details · Reel Breakdown  (.xlsx)',
              badgeLabel: 'XLSX',
              badgeColor: const Color(0xFF1D6F42),
              isLoading: _exportingExcel,
              onTap: _exportingPdf ? null : _doExcel,
            ),
            const SizedBox(height: 12),
            // PDF button
            _ExportOptionTile(
              icon: Icons.picture_as_pdf_rounded,
              iconColor: const Color(0xFFB71C1C),
              iconBg: const Color(0xFFFFEBEE),
              title: 'Export as PDF',
              subtitle: 'Cover page · Client table · Reel breakdown  (.pdf)',
              badgeLabel: 'PDF',
              badgeColor: const Color(0xFFB71C1C),
              isLoading: _exportingPdf,
              onTap: _exportingExcel ? null : _doPdf,
            ),
            const SizedBox(height: 16),
            // Info note
            Container(
              padding: const EdgeInsets.all(10),
              color: const Color(0xFFF5F5F5),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 14, color: BillifyColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Exports include only the clients currently visible (respecting active filters).',
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        color: BillifyColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _doExcel() async {
    setState(() => _exportingExcel = true);
    try {
      await ClientExportService.exportToExcel(context, widget.clients);
    } finally {
      if (mounted) setState(() => _exportingExcel = false);
    }
  }

  Future<void> _doPdf() async {
    setState(() => _exportingPdf = true);
    try {
      await ClientExportService.exportToPdf(context, widget.clients);
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }
}

// ── Single export option tile ──────────────────────────────

class _ExportOptionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final String badgeLabel;
  final Color badgeColor;
  final bool isLoading;
  final VoidCallback? onTap;

  const _ExportOptionTile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.badgeLabel,
    required this.badgeColor,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null && !isLoading;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: disabled ? 0.45 : 1.0,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(
              color: isLoading
                  ? badgeColor.withOpacity(0.5)
                  : BillifyColors.outlineVariant.withOpacity(0.6),
              width: isLoading ? 1.5 : 0.5,
            ),
            color: isLoading ? iconBg.withOpacity(0.5) : Colors.white,
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 44,
                height: 44,
                color: iconBg,
                child: Center(
                  child: isLoading
                      ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: iconColor),
                  )
                      : Icon(icon, color: iconColor, size: 22),
                ),
              ),
              const SizedBox(width: 14),
              // Labels
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: BillifyColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          color: badgeColor.withOpacity(0.12),
                          child: Text(
                            badgeLabel,
                            style: GoogleFonts.poppins(
                              fontSize: 7,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: badgeColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isLoading ? 'Generating, please wait…' : subtitle,
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        color: BillifyColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Chevron
              if (!isLoading)
                Icon(Icons.chevron_right_rounded,
                    color: BillifyColors.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}