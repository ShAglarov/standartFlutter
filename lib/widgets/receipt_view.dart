import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';

import '../services/file_export_helper.dart';

/// Чек об оплате — диалог и PDF.
///
/// ПЕРЕНЕСЕНО ИЗ teploservice_flutter БЕЗ ИЗМЕНЕНИЙ ЛОГИКИ
///     Тот же код, что у кассира в `cashier_detail_screen.dart`:
///     вид диалога, вид PDF, расчёт сумм и условия показа QR. Жилец
///     обязан получить ровно тот документ, который ему выдали бы в
///     кассе, — иначе он придёт с чеком, который не совпадает.
///
/// ДАННЫЕ СЧИТАЕТ БЭКЕНД
///     Всё приходит готовым из `receipt-data` (у жильца —
///     `/residents/me/receipt/{doc_id}`): периоды оплаты, раскладка
///     долга, QR-строка. Клиент их только печатает. Пересчитывать
///     здесь нельзя: это и есть «единый источник правды», из-за
///     нарушения которого чек раньше спорил сам с собой.
class ReceiptView {
  const ReceiptView._();

  /// Показывает чек по данным `receipt-data`.
  ///
  /// `fallback` — карточка документа, если `receipt-data` недоступна
  /// (у кассира это локальные данные документа). У жильца экран без
  /// данных чека смысла не имеет, поэтому он передаёт только
  /// `receiptData`.
  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic>? receiptData,
    Map<String, dynamic> fallback = const {},
  }) async {
    final d = fallback;
    final services =
        (receiptData?['services'] ?? d['services']) as List? ?? [];
    final totalPaid = (receiptData?['total_paid'] as num?)?.toDouble() ??
        services.fold<double>(
            0, (sum, s) => sum + ((s['paid'] as num?)?.toDouble() ?? 0));
    final totalDebt = (receiptData?['total_debt'] as num?)?.toDouble() ??
        services.fold<double>(
            0, (sum, s) => sum + ((s['debt_end'] as num?)?.toDouble() ?? 0));
    final qrString = receiptData?['qr_string'] as String?;
    // Почему QR не сформирован — текстом. Локальный fallback убран: он
    // собирал строку без получателя (Name/PersonalAcc/BankName/BIC/
    // CorrespAcc по ГОСТ Р 56042-2014), жилец её сканировал, и оплата
    // не проходила. Лучше честно сказать, что не заполнены реквизиты.
    final qrError = receiptData?['qr_error'] as String? ??
        (receiptData == null
            ? 'Данные чека недоступны — QR-код не сформирован'
            : null);
    // Период оплаты считает бэкенд (_build_payment_period_lines) —
    // единственный источник правды. Раньше надпись собиралась в трёх
    // местах, каждое по-своему, и периоды расходились.
    final periodLines = (receiptData?['payment_period_lines'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    // Списание перерасчётом — отдельным блоком: оно бывает и БЕЗ
    // оплаты, а тогда periodLines пусты. Без этой строки долг
    // «уменьшается сам собой».
    final recalcLines = (receiptData?['recalc_lines'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final debtPeriodLabel =
        receiptData?['debt_period_label'] as String? ?? '';
    final overpayment =
        (receiptData?['overpayment'] as num?)?.toDouble() ?? 0;
    final org = receiptData?['org'] as Map<String, dynamic>? ?? {};
    final periodLabel = receiptData?['period_label'] as String? ??
        _formatPeriod(d['period_date'] as String?);

    final cardDebt = (d['totals'] as Map?)?['debt_end'] as num? ?? 0;
    final effectiveDebt = receiptData != null
        ? totalDebt
        : (cardDebt > 0.01 ? cardDebt.toDouble() : 0.0);
    // Сумма в QR — та же, что в строке «Остаток долга»: иначе чек
    // спорит сам с собой. Раньше QR показывался по totalDebt, а текст
    // по effectiveDebt, и при расхождении QR исчезал при наличии долга.
    final qrAmount =
        (receiptData?['qr_amount'] as num?)?.toDouble() ?? effectiveDebt;

    final hasData =
        totalPaid > 0.01 || effectiveDebt > 0.01 || overpayment > 0.01;

    if (!hasData) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет данных для формирования чека')),
        );
      }
      return;
    }

    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 380,
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.receipt_long, size: 40, color: Colors.indigo),
                const SizedBox(height: 8),
                const Text('ЧЕК ОБ ОПЛАТЕ',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
                Text('$dateStr  $timeStr',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                if (org['name'] != null &&
                    (org['name'] as String).isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(org['name'],
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade700),
                      textAlign: TextAlign.center),
                ],
                const SizedBox(height: 16),
                receiptDivider(),
                _receiptRow('Плательщик:',
                    receiptData?['fio'] ?? d['fio'] ?? '—'),
                _receiptRow(
                    'Лицевой счёт:',
                    receiptData?['account_number'] ??
                        d['account_number'] ??
                        '—'),
                _receiptRow('Адрес:',
                    receiptData?['address'] ?? d['address'] ?? '—'),
                if (periodLines.isNotEmpty)
                  ...periodLines.map((l) => _receiptRow(
                        l['label'] as String? ?? '',
                        l['value'] as String? ?? '',
                      ))
                else
                  // Оплаты по документу не было — печатаем период
                  // документа, иначе в чеке вообще не будет периода.
                  _receiptRow('Период:', periodLabel),
                ...recalcLines.map((l) => _receiptRow(
                      l['label'] as String? ?? '',
                      l['value'] as String? ?? '',
                    )),
                if ((receiptData?['area'] ?? d['area']) != null)
                  _receiptRow('Площадь:',
                      '${receiptData?['area'] ?? d['area']} м²'),
                receiptDivider(),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Услуги:',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.black87)),
                ),
                const SizedBox(height: 6),
                ...services
                    .where((s) =>
                        ((s['paid'] as num?)?.toDouble() ?? 0) > 0 ||
                        ((s['charged'] as num?)?.toDouble() ?? 0) > 0)
                    .map((s) {
                  final paid = (s['paid'] as num?)?.toDouble() ?? 0;
                  final charged = (s['charged'] as num?)?.toDouble() ?? 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            s['label'] ?? s['key'] ?? '',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black87),
                          ),
                        ),
                        if (paid > 0)
                          Text('${_fmt(paid)} ₽',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87))
                        else
                          Text('начисл. ${_fmt(charged)} ₽',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade600)),
                      ],
                    ),
                  );
                }),
                receiptDivider(),
                if (totalPaid > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('ИТОГО ОПЛАЧЕНО:',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87)),
                      Text('${_fmt(totalPaid)} ₽',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green)),
                    ],
                  ),
                const SizedBox(height: 4),
                // Долг ИЛИ переплата — одновременно быть не может.
                if (effectiveDebt > 0.01)
                  Column(children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Остаток долга:',
                            style: TextStyle(
                                fontSize: 12, color: Colors.red.shade700)),
                        Text('${_fmt(effectiveDebt)} ₽',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.red.shade700)),
                      ],
                    ),
                    // За КАКИЕ месяцы — сразу под суммой. Бэкенд
                    // выводит раскладку из самой суммы долга, поэтому
                    // названные месяцы складываются в неё.
                    if (debtPeriodLabel.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('за $debtPeriodLabel',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.red.shade400)),
                        ),
                      ),
                  ])
                else if (overpayment > 0.01)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Переплата:',
                          style: TextStyle(
                              fontSize: 12, color: Colors.green.shade700)),
                      Text('${_fmt(overpayment)} ₽',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade700)),
                    ],
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Задолженности нет',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade700)),
                      Text('0.00 ₽',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade700)),
                    ],
                  ),
                // QR показываем ВСЕГДА, когда есть долг. Раньше условие
                // шло по totalDebt, а сумма долга — по effectiveDebt:
                // при расхождении жилец получал чек с долгом и без QR.
                if (effectiveDebt > 0.01) ...[
                  receiptDivider(),
                  const Text('Оплата по QR-коду',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                  const SizedBox(height: 4),
                  if (qrString != null && qrString.isNotEmpty) ...[
                    Text('Отсканируйте для оплаты',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade600)),
                    const SizedBox(height: 8),
                    Center(
                      child: QrImageView(
                        data: qrString,
                        version: QrVersions.auto,
                        size: 160,
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('Сумма: ${_fmt(qrAmount)} ₽',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade700)),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        qrError ?? 'QR-код недоступен',
                        style: TextStyle(
                            fontSize: 10.5, color: Colors.orange.shade900),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
                receiptDivider(),
                if (org['bank_name'] != null &&
                    (org['bank_name'] as String).isNotEmpty) ...[
                  Text(
                    'Банк: ${org['bank_name']}  БИК: ${org['bik'] ?? ''}  р/с: ${org['account_number'] ?? ''}',
                    style:
                        TextStyle(fontSize: 9, color: Colors.grey.shade500),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                ],
                Text('Спасибо за оплату!',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontStyle: FontStyle.italic)),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Закрыть'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => generatePdf(
                          ctx,
                          receiptData ?? d,
                          services,
                          totalPaid,
                          dateStr,
                          timeStr,
                          qrString: qrString,
                          qrAmount: qrAmount,
                          qrError: qrError,
                          totalDebt: effectiveDebt,
                          overpayment: overpayment,
                          org: org,
                          // Те же строки, что в диалоге: PDF и экран
                          // обязаны показывать один и тот же период.
                          periodLines: periodLines,
                          debtPeriodLabel: debtPeriodLabel,
                          recalcLines: recalcLines,
                        ),
                        icon: const Icon(Icons.picture_as_pdf, size: 16),
                        label: const Text('PDF'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Пунктир-разделитель чека.
  static Widget receiptDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: List.generate(
          30,
          (_) => Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              height: 1,
              color: Colors.grey.shade300,
            ),
          ),
        ),
      ),
    );
  }

  static Widget _receiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            // 150, а не 110: подписи периода оплаты длиннее («В т.ч.
            // погашение долга за:») и при 110 рвались на три строки.
            width: 150,
            child: Text(label,
                style:
                    TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  static String _fmt(dynamic val) {
    if (val == null) return '0';
    final n = (val is num)
        ? val.toDouble()
        : double.tryParse(val.toString()) ?? 0;
    if (n == 0) return '0';
    return n.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
  }

  static String _formatPeriod(String? date) {
    if (date == null) return '—';
    try {
      final d = DateTime.parse(date);
      const months = [
        '', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
        'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
      ];
      return '${months[d.month]} ${d.year}';
    } catch (_) {
      return date;
    }
  }

  /// QR-код как PNG — для вставки в PDF.
  static Future<Uint8List> generateQrPng(String data,
      {double size = 200}) async {
    final qrPainter = QrPainter(
      data: data,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      gapless: true,
    );
    final imageData = await qrPainter.toImageData(size);
    return imageData!.buffer.asUint8List();
  }

  /// PDF-чек: формат A5, тот же, что печатает касса.
  static Future<void> generatePdf(
    BuildContext context,
    Map<String, dynamic> d,
    List services,
    double totalPaid,
    String date,
    String time, {
    String? qrString,
    double? qrAmount,
    String? qrError,
    double totalDebt = 0,
    double overpayment = 0,
    Map<String, dynamic>? org,
    // Период оплаты и долга приходят готовыми строками с бэкенда,
    // чтобы PDF и диалог не пересчитывали их по-разному.
    List<Map<String, dynamic>> periodLines = const [],
    List<Map<String, dynamic>> recalcLines = const [],
    String debtPeriodLabel = '',
  }) async {
    try {
      final fontData =
          await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      final ttf = pw.Font.ttf(fontData);

      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(base: ttf, bold: ttf),
      );
      final paidServices = services
          .where((s) => ((s['paid'] as num?)?.toDouble() ?? 0) > 0)
          .toList();
      // totalDebt уже посчитан по накопительному балансу (backend).
      // Fallback по sum(debt_end) недопустим: при переплате он даёт
      // ложный долг.
      final debtEnd = totalDebt;

      pw.MemoryImage? qrImage;
      if (qrString != null && qrString.isNotEmpty && debtEnd > 0.01) {
        try {
          final qrPng = await generateQrPng(qrString, size: 300);
          qrImage = pw.MemoryImage(qrPng);
        } catch (_) {}
      }
      final qrSum = qrAmount ?? debtEnd;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5,
          margin: const pw.EdgeInsets.all(24),
          theme: pw.ThemeData.withFont(base: ttf, bold: ttf),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Text('ЧЕК ОБ ОПЛАТЕ',
                      style: pw.TextStyle(
                          font: ttf,
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold)),
                ),
                pw.Center(
                  child: pw.Text('$date  $time',
                      style: pw.TextStyle(
                          font: ttf,
                          fontSize: 10,
                          color: PdfColors.grey700)),
                ),
                if (org != null && (org['name'] ?? '').toString().isNotEmpty)
                  pw.Center(
                    child: pw.Text(org['name'],
                        style: pw.TextStyle(
                            font: ttf,
                            fontSize: 9,
                            color: PdfColors.grey600)),
                  ),
                pw.SizedBox(height: 12),
                pw.Divider(thickness: 1.5),
                pw.SizedBox(height: 8),
                _pdfInfoRow('Плательщик:', d['fio'] ?? '—', ttf),
                _pdfInfoRow(
                    'Лицевой счёт:', d['account_number'] ?? '—', ttf),
                _pdfInfoRow('Адрес:', d['address'] ?? '—', ttf),
                if (periodLines.isNotEmpty)
                  ...periodLines.map((l) => _pdfInfoRow(
                        l['label'] as String? ?? '',
                        l['value'] as String? ?? '',
                        ttf,
                      ))
                else
                  _pdfInfoRow(
                      'Период:',
                      d['period_label'] ??
                          _formatPeriod(d['period_date'] as String?),
                      ttf),
                ...recalcLines.map((l) => _pdfInfoRow(
                      l['label'] as String? ?? '',
                      l['value'] as String? ?? '',
                      ttf,
                    )),
                if (d['area'] != null)
                  _pdfInfoRow('Площадь:', '${d['area']} м²', ttf),
                pw.SizedBox(height: 10),
                pw.Divider(),
                pw.SizedBox(height: 6),
                if (paidServices.isNotEmpty) ...[
                  pw.Text('Оплаченные услуги:',
                      style: pw.TextStyle(
                          font: ttf,
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Table(
                    border: pw.TableBorder.all(
                        color: PdfColors.grey400, width: 0.5),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(3),
                      1: const pw.FlexColumnWidth(1),
                    },
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(
                            color: PdfColors.grey200),
                        children: [
                          pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text('Услуга',
                                  style: pw.TextStyle(
                                      font: ttf,
                                      fontWeight: pw.FontWeight.bold,
                                      fontSize: 9))),
                          pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text('Сумма',
                                  style: pw.TextStyle(
                                      font: ttf,
                                      fontWeight: pw.FontWeight.bold,
                                      fontSize: 9),
                                  textAlign: pw.TextAlign.right)),
                        ],
                      ),
                      ...paidServices.map((s) => pw.TableRow(
                            children: [
                              pw.Padding(
                                  padding: const pw.EdgeInsets.all(5),
                                  child: pw.Text(
                                      s['label'] ?? s['key'] ?? '',
                                      style: pw.TextStyle(
                                          font: ttf, fontSize: 9))),
                              pw.Padding(
                                  padding: const pw.EdgeInsets.all(5),
                                  child: pw.Text('${_fmt(s['paid'])} р.',
                                      style: pw.TextStyle(
                                          font: ttf, fontSize: 9),
                                      textAlign: pw.TextAlign.right)),
                            ],
                          )),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                ],
                pw.Divider(thickness: 1.5),
                pw.SizedBox(height: 6),
                if (totalPaid > 0)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('ИТОГО ОПЛАЧЕНО:',
                          style: pw.TextStyle(
                              font: ttf,
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold)),
                      pw.Text('${_fmt(totalPaid)} р.',
                          style: pw.TextStyle(
                              font: ttf,
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                pw.SizedBox(height: 3),
                // Долг ИЛИ переплата — одновременно быть не может.
                if (debtEnd > 0.01)
                  pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          mainAxisAlignment:
                              pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Остаток долга:',
                                style: pw.TextStyle(
                                    font: ttf,
                                    fontSize: 9,
                                    color: PdfColors.red700)),
                            pw.Text('${_fmt(debtEnd)} р.',
                                style: pw.TextStyle(
                                    font: ttf,
                                    fontSize: 9,
                                    color: PdfColors.red700)),
                          ],
                        ),
                        if (debtPeriodLabel.isNotEmpty)
                          pw.Text('за $debtPeriodLabel',
                              style: pw.TextStyle(
                                  font: ttf,
                                  fontSize: 8,
                                  color: PdfColors.red400)),
                      ])
                else if (overpayment > 0.01)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Переплата:',
                          style: pw.TextStyle(
                              font: ttf,
                              fontSize: 9,
                              color: PdfColors.green700)),
                      pw.Text('${_fmt(overpayment)} р.',
                          style: pw.TextStyle(
                              font: ttf,
                              fontSize: 9,
                              color: PdfColors.green700)),
                    ],
                  )
                else
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Задолженности нет',
                          style: pw.TextStyle(
                              font: ttf,
                              fontSize: 9,
                              color: PdfColors.green700)),
                      pw.Text('0.00 р.',
                          style: pw.TextStyle(
                              font: ttf,
                              fontSize: 9,
                              color: PdfColors.green700)),
                    ],
                  ),
                // QR — есть долг, значит есть и чем его заплатить.
                if (debtEnd > 0.01) ...[
                  pw.SizedBox(height: 8),
                  pw.Divider(),
                  pw.SizedBox(height: 4),
                  pw.Center(
                      child: pw.Text('Оплата по QR-коду',
                          style: pw.TextStyle(
                              font: ttf,
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold))),
                  pw.SizedBox(height: 4),
                  if (qrImage != null) ...[
                    pw.Center(
                        child: pw.Image(qrImage, width: 80, height: 80)),
                    pw.SizedBox(height: 2),
                    pw.Center(
                        child: pw.Text(
                            'Отсканируйте для оплаты • ${_fmt(qrSum)} р.',
                            style: pw.TextStyle(
                                font: ttf,
                                fontSize: 8,
                                color: PdfColors.grey600))),
                  ] else
                    pw.Center(
                        child: pw.Text(
                      qrError ?? 'QR-код недоступен',
                      style: pw.TextStyle(
                          font: ttf,
                          fontSize: 8,
                          color: PdfColors.orange800),
                    )),
                ],
                pw.SizedBox(height: 10),
                pw.Divider(),
                pw.SizedBox(height: 4),
                if (org != null &&
                    (org['bank_name'] ?? '').toString().isNotEmpty)
                  pw.Center(
                    child: pw.Text(
                      'Банк: ${org['bank_name']}  БИК: ${org['bik'] ?? ''}  р/с: ${org['account_number'] ?? ''}',
                      style: pw.TextStyle(
                          font: ttf,
                          fontSize: 7,
                          color: PdfColors.grey500),
                    ),
                  ),
                pw.SizedBox(height: 4),
                pw.Center(
                  child: pw.Text('Спасибо за оплату!',
                      style: pw.TextStyle(
                          font: ttf,
                          fontSize: 10,
                          color: PdfColors.grey600)),
                ),
              ],
            );
          },
        ),
      );

      final dir = await getTemporaryDirectory();
      final fileName =
          'check_${d['account_number'] ?? 'receipt'}_${date.replaceAll('.', '')}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      if (context.mounted) {
        final savedPath = await FileExportHelper.exportFile(
          sourceFile: file,
          fileName: fileName,
          mimeType: 'application/pdf',
          subject: 'Чек об оплате — ${d['fio'] ?? ''}',
        );
        if (savedPath != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('✅ Чек сохранён: $savedPath'),
                backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('❌ Ошибка генерации PDF: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  static pw.Widget _pdfInfoRow(String label, String value, pw.Font ttf) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // 140, а не 100: длинные подписи периода не должны рваться.
          pw.SizedBox(
              width: 140,
              child: pw.Text(label,
                  style: pw.TextStyle(
                      font: ttf,
                      fontSize: 9.5,
                      color: PdfColors.grey700))),
          pw.Expanded(
              child: pw.Text(value,
                  style: pw.TextStyle(
                      font: ttf,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold))),
        ],
      ),
    );
  }
}
