import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../theme/app_theme.dart';
import 'tabs/chat_conversation_screen.dart';

/// Normalizes a local phone into WhatsApp digits (Pakistan-friendly).
String normalizeWhatsAppPhone(String raw, {String defaultCountry = '92'}) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  if (digits.startsWith('00')) digits = digits.substring(2);
  // Local PK: 03xxxxxxxxx → 923xxxxxxxxx
  if (digits.startsWith('0') && digits.length >= 10) {
    digits = '$defaultCountry${digits.substring(1)}';
  } else if (digits.length == 10 && digits.startsWith('3')) {
    // Common PK mobile without leading 0: 3xxxxxxxxx
    digits = '$defaultCountry$digits';
  }
  return digits;
}

Future<void> openPhoneContactsPicker(BuildContext context, {required String tenantId}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => PhoneContactsScreen(tenantId: tenantId)),
  );
}

class PhoneContactsScreen extends StatefulWidget {
  final String tenantId;

  const PhoneContactsScreen({super.key, required this.tenantId});

  @override
  State<PhoneContactsScreen> createState() => _PhoneContactsScreenState();
}

class _PhoneContactsScreenState extends State<PhoneContactsScreen> {
  final _search = TextEditingController();
  List<_DeviceContact> _all = [];
  bool _loading = true;
  String? _error;
  bool _denied = false;
  int _rawCount = 0;
  int _noPhoneCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _denied = false;
      _rawCount = 0;
      _noPhoneCount = 0;
    });

    try {
      final status = await FlutterContacts.permissions.request(PermissionType.readWrite);
      if (status != PermissionStatus.granted && status != PermissionStatus.limited) {
        setState(() {
          _loading = false;
          _denied = true;
        });
        return;
      }

      var contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.name, ContactProperty.phone},
      );

      final phoneCount = contacts.fold<int>(0, (n, c) => n + c.phones.length);
      if (contacts.isNotEmpty && phoneCount == 0) {
        contacts = await FlutterContacts.getAll(properties: ContactProperties.allProperties);
      }

      _rawCount = contacts.length;
      final mapped = <_DeviceContact>[];
      for (final c in contacts) {
        final name = (c.displayName ?? '').trim();
        if (c.phones.isEmpty) {
          _noPhoneCount++;
          continue;
        }
        for (final p in c.phones) {
          final source = (p.normalizedNumber != null && p.normalizedNumber!.trim().isNotEmpty)
              ? p.normalizedNumber!.trim()
              : p.number.trim();
          if (source.isEmpty) continue;

          var normalized = normalizeWhatsAppPhone(source);
          if (normalized.length < 7) {
            normalized = source.replaceAll(RegExp(r'\D'), '');
          }
          if (normalized.length < 7) continue;

          mapped.add(
            _DeviceContact(
              name: name.isEmpty ? normalized : name,
              phone: normalized,
              rawPhone: source,
            ),
          );
        }
      }

      try {
        final simContacts = await FlutterContacts.sim.get();
        for (final c in simContacts) {
          final name = (c.displayName ?? '').trim();
          for (final p in c.phones) {
            final source = p.number.trim();
            if (source.isEmpty) continue;
            var normalized = normalizeWhatsAppPhone(source);
            if (normalized.length < 7) {
              normalized = source.replaceAll(RegExp(r'\D'), '');
            }
            if (normalized.length < 7) continue;
            mapped.add(
              _DeviceContact(
                name: name.isEmpty ? normalized : name,
                phone: normalized,
                rawPhone: source,
              ),
            );
          }
        }
      } catch (_) {}

      mapped.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      final seen = <String>{};
      final unique = <_DeviceContact>[];
      for (final c in mapped) {
        if (seen.add(c.phone)) unique.add(c);
      }

      if (!mounted) return;
      setState(() {
        _all = unique;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _openChat(_DeviceContact c) {
    // Replace contacts screen so back goes to chat tab, not the picker.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ChatConversationScreen(
          tenantId: widget.tenantId,
          phone: c.phone,
          contactName: c.name,
        ),
      ),
    );
  }

  List<_DeviceContact> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all
        .where((c) => c.name.toLowerCase().contains(q) || c.phone.contains(q) || c.rawPhone.contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text(
          'Select contact',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search name or number',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: AppColors.surfaceSolid,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.surfaceBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.surfaceBorder),
                ),
              ),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_denied) {
      return _Message(
        icon: Icons.contacts_outlined,
        title: 'Contacts permission needed',
        body: 'Allow contacts access in the system dialog, or open settings and enable Contacts for WaTech.',
        actionLabel: 'Open settings',
        onAction: () => FlutterContacts.permissions.openSettings(),
        secondaryLabel: 'Try again',
        onSecondary: _load,
      );
    }
    if (_error != null) {
      return _Message(
        icon: Icons.error_outline,
        title: 'Could not load contacts',
        body: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    final list = _filtered;
    if (list.isEmpty) {
      final detail = _rawCount == 0
          ? 'Phone book empty lag raha hai. Settings → Apps → WaTech → Permissions → Contacts = Allow, phir Retry.'
          : '$_rawCount contacts mile, lekin $_noPhoneCount ke paas number nahi / invalid.';
      return _Message(
        icon: Icons.person_search_outlined,
        title: 'No usable contacts',
        body: detail,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72, color: AppColors.surfaceBorder),
      itemBuilder: (context, index) {
        final c = list[index];
        final letter = c.name.isNotEmpty ? c.name[0].toUpperCase() : '?';
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: Text(letter, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
          title: Text(
            c.name,
            style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          subtitle: Text(c.phone, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          onTap: () => _openChat(c),
        );
      },
    );
  }
}

class _DeviceContact {
  final String name;
  final String phone;
  final String rawPhone;

  const _DeviceContact({required this.name, required this.phone, required this.rawPhone});
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: AppColors.textSecondary),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, height: 1.35),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: Text(actionLabel!),
              ),
            ],
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
