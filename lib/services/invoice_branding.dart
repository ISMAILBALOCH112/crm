import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Tenant invoice look — logo URL + brand color (hex like #5B7FFF).
class InvoiceBranding {
  final String? logoUrl;
  final String brandColorHex;

  const InvoiceBranding({this.logoUrl, this.brandColorHex = '#5B7FFF'});

  factory InvoiceBranding.fromTenant(Map<String, dynamic>? data) {
    if (data == null) return const InvoiceBranding();
    final logo = (data['invoiceLogoUrl'] as String?)?.trim();
    final color = (data['invoiceBrandColor'] as String?)?.trim();
    return InvoiceBranding(
      logoUrl: (logo != null && logo.isNotEmpty) ? logo : null,
      brandColorHex: (color != null && color.isNotEmpty) ? color : '#5B7FFF',
    );
  }

  int get brandColorInt {
    var hex = brandColorHex.replaceFirst('#', '').trim();
    if (hex.length == 6) hex = 'FF$hex';
    return int.tryParse(hex, radix: 16) ?? 0xFF5B7FFF;
  }

  Future<Uint8List?> loadLogoBytes() async {
    final url = logoUrl;
    if (url == null || url.isEmpty) return null;
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }
}
