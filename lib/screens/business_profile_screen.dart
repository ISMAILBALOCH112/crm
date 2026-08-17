import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/chat_service.dart';
import '../theme/app_theme.dart';

Future<void> openBusinessProfileScreen(BuildContext context, String tenantId) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => BusinessProfileScreen(tenantId: tenantId)),
  );
}

class BusinessProfileScreen extends StatefulWidget {
  final String tenantId;

  const BusinessProfileScreen({super.key, required this.tenantId});

  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ChatService().fetchWhatsappProfile(widget.tenantId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WhatsApp business profile'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_data['connected'] != true)
                      const Card(
                        child: ListTile(
                          leading: Icon(Icons.warning_amber_rounded, color: Colors.orange),
                          title: Text('WhatsApp not connected'),
                          subtitle: Text('Connect under Settings → WhatsApp first.'),
                        ),
                      )
                    else ...[
                      _row('Verified name', '${_data['verifiedName'] ?? '—'}'),
                      _row('Display number', '${_data['displayPhone'] ?? '—'}'),
                      _row('CRM business name', '${_data['businessName'] ?? '—'}'),
                      _row('Quality rating', '${_data['qualityRating'] ?? '—'}'),
                      _row('Code verification', '${_data['codeVerificationStatus'] ?? '—'}'),
                      _row('WABA ID', '${_data['wabaId'] ?? '—'}'),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      _data['editHint']?.toString() ??
                          'Hours, address, website, and Meta Commerce catalog are edited in Meta Business Suite.',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse('https://business.facebook.com/wa/manage/home/'),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open WhatsApp Manager'),
                    ),
                  ],
                ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        ],
      ),
    );
  }
}
