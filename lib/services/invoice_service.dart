import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'chat_service.dart';
import 'invoice_branding.dart';
import 'media_upload_service.dart';
import 'order_notify_service.dart';
import 'order_service.dart';

class InvoiceService {
  final _chat = ChatService();
  final _media = MediaUploadService();

  String fileName(CrmOrder order) {
    final code = order.displayId.replaceAll(RegExp(r'[^\w\-]+'), '-');
    return 'Invoice-$code.pdf';
  }

  Future<Uint8List> buildPdf(
    CrmOrder order, {
    String? businessName,
    InvoiceBranding branding = const InvoiceBranding(),
  }) async {
    final shop = (businessName != null && businessName.trim().isNotEmpty) ? businessName.trim() : 'Invoice';
    final money = NumberFormat('#,##0');
    final created = order.createdAt != null ? DateFormat('d MMM yyyy, h:mm a').format(order.createdAt!) : '—';
    final brand = PdfColor.fromInt(branding.brandColorInt);
    final logoBytes = await branding.loadLogoBytes();
    pw.ImageProvider? logoImage;
    if (logoBytes != null && logoBytes.isNotEmpty) {
      logoImage = pw.MemoryImage(logoBytes);
    }
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (logoImage != null) ...[
                    pw.Container(
                      width: 56,
                      height: 56,
                      margin: const pw.EdgeInsets.only(right: 12),
                      child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                    ),
                  ],
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          shop,
                          style: pw.TextStyle(
                            fontSize: 22,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromInt(0xFF2D2430),
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'INVOICE',
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: brand,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(order.displayId, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      pw.Text(order.status.label.toUpperCase(), style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      pw.Text(created, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 18),
              pw.Container(height: 2, color: brand),
              pw.SizedBox(height: 18),
              pw.Text('Bill to', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
              pw.SizedBox(height: 6),
              pw.Text(order.customerName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.Text(order.customerPhone, style: const pw.TextStyle(fontSize: 11)),
              if (order.city != null && order.city!.trim().isNotEmpty) pw.Text(order.city!, style: const pw.TextStyle(fontSize: 11)),
              if (order.address != null && order.address!.trim().isNotEmpty)
                pw.Text(order.address!, style: const pw.TextStyle(fontSize: 11)),
              pw.SizedBox(height: 20),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
                columnWidths: {
                  0: const pw.FlexColumnWidth(4),
                  1: const pw.FlexColumnWidth(1.2),
                  2: const pw.FlexColumnWidth(1.6),
                  3: const pw.FlexColumnWidth(1.8),
                },
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: brand),
                    children: [
                      _headerCell('Item'),
                      _headerCell('Qty', align: pw.TextAlign.center),
                      _headerCell('Price', align: pw.TextAlign.right),
                      _headerCell('Total', align: pw.TextAlign.right),
                    ],
                  ),
                  for (final item in order.items)
                    pw.TableRow(
                      children: [
                        _bodyCell(item.name),
                        _bodyCell('${item.qty}', align: pw.TextAlign.center),
                        _bodyCell('PKR ${money.format(item.price)}', align: pw.TextAlign.right),
                        _bodyCell('PKR ${money.format(item.lineTotal)}', align: pw.TextAlign.right),
                      ],
                    ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFEEF2FF),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Text(
                    'Total  PKR ${money.format(order.totalAmount)}',
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF2D2430)),
                  ),
                ),
              ),
              if (order.courier != null || (order.trackingNumber != null && order.trackingNumber!.trim().isNotEmpty)) ...[
                pw.SizedBox(height: 18),
                pw.Text('Shipping', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                pw.SizedBox(height: 4),
                if (order.courier != null) pw.Text('Courier: ${order.courier}', style: const pw.TextStyle(fontSize: 11)),
                if (order.trackingNumber != null && order.trackingNumber!.trim().isNotEmpty)
                  pw.Text('Tracking: ${order.trackingNumber}', style: const pw.TextStyle(fontSize: 11)),
              ],
              if (order.notes != null && order.notes!.trim().isNotEmpty) ...[
                pw.SizedBox(height: 14),
                pw.Text('Notes', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                pw.SizedBox(height: 4),
                pw.Text(order.notes!, style: const pw.TextStyle(fontSize: 11)),
              ],
              pw.Spacer(),
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 6),
              pw.Text(
                'Thank you for your order.',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                textAlign: pw.TextAlign.center,
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  Future<File> saveTemp(
    CrmOrder order, {
    String? businessName,
    InvoiceBranding branding = const InvoiceBranding(),
  }) async {
    final bytes = await buildPdf(order, businessName: businessName, branding: branding);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${fileName(order)}');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> share(
    CrmOrder order, {
    String? businessName,
    InvoiceBranding branding = const InvoiceBranding(),
  }) async {
    final file = await saveTemp(order, businessName: businessName, branding: branding);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf', name: fileName(order))],
        subject: 'Invoice ${order.displayId}',
        text: 'Invoice ${order.displayId}',
        title: 'Invoice ${order.displayId}',
      ),
    );
  }

  Future<void> sendWhatsApp({
    required String tenantId,
    required CrmOrder order,
    String? businessName,
    InvoiceBranding branding = const InvoiceBranding(),
  }) async {
    final file = await saveTemp(order, businessName: businessName, branding: branding);
    final url = await _media.uploadRawFile(file.path, folder: 'invoices');
    final phone = OrderNotifyService.normalizePhone(order.customerPhone);
    if (phone.length < 10) throw Exception('Customer phone is not a valid WhatsApp number.');
    await _chat.ensureContact(tenantId: tenantId, phone: phone, name: order.customerName);
    await _chat.sendDocument(
      tenantId: tenantId,
      to: phone,
      documentUrl: url,
      filename: fileName(order),
      caption: 'Invoice ${order.displayId} — PKR ${order.totalAmount.toStringAsFixed(0)}',
    );
  }

  pw.Widget _headerCell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(color: PdfColors.white, fontSize: 10, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _bodyCell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: pw.Text(text, textAlign: align, style: const pw.TextStyle(fontSize: 10)),
    );
  }
}
