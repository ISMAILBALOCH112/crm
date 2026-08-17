import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/backend_config.dart';

enum BotResponseType { text, image, audio, video }

class BotResponseItem {
  final BotResponseType type;
  final String? text;
  final String? mediaUrl;
  final String? caption;
  final bool voice;

  const BotResponseItem({
    required this.type,
    this.text,
    this.mediaUrl,
    this.caption,
    this.voice = false,
  });

  factory BotResponseItem.fromMap(Map<String, dynamic> map) {
    return BotResponseItem(
      type: BotResponseType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => BotResponseType.text,
      ),
      text: map['text'] as String?,
      mediaUrl: map['mediaUrl'] as String?,
      caption: map['caption'] as String?,
      voice: map['voice'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type.name,
        if (text != null) 'text': text,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        if (caption != null) 'caption': caption,
        if (voice) 'voice': true,
      };

  BotResponseItem copyWith({
    BotResponseType? type,
    String? text,
    String? mediaUrl,
    String? caption,
    bool? voice,
  }) {
    return BotResponseItem(
      type: type ?? this.type,
      text: text ?? this.text,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      caption: caption ?? this.caption,
      voice: voice ?? this.voice,
    );
  }
}

class BotGreetingConfig {
  final bool enabled;
  final List<BotResponseItem> responses;

  const BotGreetingConfig({this.enabled = false, this.responses = const []});

  factory BotGreetingConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return BotGreetingConfig.defaultConfig();
    final raw = map['responses'] as List<dynamic>? ?? [];
    return BotGreetingConfig(
      enabled: map['enabled'] == true,
      responses: raw.map((e) => BotResponseItem.fromMap(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }

  static BotGreetingConfig defaultConfig() => const BotGreetingConfig(
        enabled: false,
        responses: [
          BotResponseItem(
            type: BotResponseType.text,
            text: 'Assalam o Alaikum! Thanks for messaging us. How can we help you today?',
          ),
        ],
      );

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'responses': responses.map((r) => r.toMap()).toList(),
      };
}

class BotAiAgentConfig {
  final bool enabled;
  final String provider;
  final String model;
  final String systemPrompt;
  final double temperature;
  final int maxTokens;
  final List<String> handoffKeywords;

  const BotAiAgentConfig({
    this.enabled = false,
    this.provider = 'openai',
    this.model = 'gpt-4o-mini',
    this.systemPrompt =
        'You are a helpful WhatsApp sales assistant for {businessName}. Reply briefly in the same language the customer uses. Be polite and professional. If you cannot help, ask them to type "agent" to speak with a human.',
    this.temperature = 0.7,
    this.maxTokens = 500,
    this.handoffKeywords = const ['human', 'agent', 'person'],
  });

  factory BotAiAgentConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const BotAiAgentConfig();
    return BotAiAgentConfig(
      enabled: map['enabled'] == true,
      provider: map['provider'] as String? ?? 'openai',
      model: map['model'] as String? ?? 'gpt-4o-mini',
      systemPrompt: map['systemPrompt'] as String? ?? const BotAiAgentConfig().systemPrompt,
      temperature: (map['temperature'] as num?)?.toDouble() ?? 0.7,
      maxTokens: (map['maxTokens'] as num?)?.toInt() ?? 500,
      handoffKeywords: (map['handoffKeywords'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['human', 'agent', 'person'],
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'provider': provider,
        'model': model,
        'systemPrompt': systemPrompt,
        'temperature': temperature,
        'maxTokens': maxTokens,
        'handoffKeywords': handoffKeywords,
      };
}

class BotAwayConfig {
  final bool enabled;
  final bool alwaysOn;
  final String message;

  const BotAwayConfig({
    this.enabled = false,
    this.alwaysOn = false,
    this.message =
        'Shukriya message karne ka. Abhi hum available nahi — business hours mein jaldi reply karenge.',
  });

  factory BotAwayConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const BotAwayConfig();
    return BotAwayConfig(
      enabled: map['enabled'] == true,
      alwaysOn: map['alwaysOn'] == true,
      message: (map['message'] as String?)?.trim().isNotEmpty == true
          ? (map['message'] as String).trim()
          : const BotAwayConfig().message,
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'alwaysOn': alwaysOn,
        'message': message,
      };

  BotAwayConfig copyWith({bool? enabled, bool? alwaysOn, String? message}) {
    return BotAwayConfig(
      enabled: enabled ?? this.enabled,
      alwaysOn: alwaysOn ?? this.alwaysOn,
      message: message ?? this.message,
    );
  }
}

class BusinessDayHours {
  final String open;
  final String close;
  final bool closed;

  const BusinessDayHours({
    this.open = '09:00',
    this.close = '18:00',
    this.closed = false,
  });

  factory BusinessDayHours.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const BusinessDayHours();
    return BusinessDayHours(
      open: (map['open'] as String?)?.trim().isNotEmpty == true ? map['open'] as String : '09:00',
      close: (map['close'] as String?)?.trim().isNotEmpty == true ? map['close'] as String : '18:00',
      closed: map['closed'] == true,
    );
  }

  Map<String, dynamic> toMap() => {'open': open, 'close': close, 'closed': closed};

  BusinessDayHours copyWith({String? open, String? close, bool? closed}) {
    return BusinessDayHours(
      open: open ?? this.open,
      close: close ?? this.close,
      closed: closed ?? this.closed,
    );
  }
}

class BusinessHoursConfig {
  final bool enabled;
  final String timezone;
  final Map<String, BusinessDayHours> days;

  static const dayOrder = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  static const dayLabels = {
    'mon': 'Mon',
    'tue': 'Tue',
    'wed': 'Wed',
    'thu': 'Thu',
    'fri': 'Fri',
    'sat': 'Sat',
    'sun': 'Sun',
  };

  const BusinessHoursConfig({
    this.enabled = false,
    this.timezone = 'Asia/Karachi',
    this.days = const {},
  });

  factory BusinessHoursConfig.defaults() => BusinessHoursConfig(
        enabled: false,
        timezone: 'Asia/Karachi',
        days: {
          for (final d in dayOrder)
            d: d == 'sun'
                ? const BusinessDayHours(closed: true)
                : d == 'sat'
                    ? const BusinessDayHours(open: '10:00', close: '14:00')
                    : const BusinessDayHours(),
        },
      );

  factory BusinessHoursConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return BusinessHoursConfig.defaults();
    final rawDays = map['days'] as Map<String, dynamic>? ?? {};
    final defaults = BusinessHoursConfig.defaults();
    return BusinessHoursConfig(
      enabled: map['enabled'] == true,
      timezone: (map['timezone'] as String?)?.trim().isNotEmpty == true
          ? (map['timezone'] as String).trim()
          : 'Asia/Karachi',
      days: {
        for (final d in dayOrder)
          d: BusinessDayHours.fromMap(
            rawDays[d] is Map ? Map<String, dynamic>.from(rawDays[d] as Map) : defaults.days[d]?.toMap(),
          ),
      },
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'timezone': timezone,
        'days': {for (final e in days.entries) e.key: e.value.toMap()},
      };

  BusinessHoursConfig copyWith({
    bool? enabled,
    String? timezone,
    Map<String, BusinessDayHours>? days,
  }) {
    return BusinessHoursConfig(
      enabled: enabled ?? this.enabled,
      timezone: timezone ?? this.timezone,
      days: days ?? this.days,
    );
  }
}

class BotConfig {
  final bool enabled;
  final BotGreetingConfig greeting;
  final BotAwayConfig away;
  final BusinessHoursConfig businessHours;
  final BotAiAgentConfig aiAgent;

  const BotConfig({
    this.enabled = false,
    required this.greeting,
    this.away = const BotAwayConfig(),
    required this.businessHours,
    required this.aiAgent,
  });

  factory BotConfig.defaults() => BotConfig(
        enabled: false,
        greeting: BotGreetingConfig.defaultConfig(),
        away: const BotAwayConfig(),
        businessHours: BusinessHoursConfig.defaults(),
        aiAgent: const BotAiAgentConfig(),
      );

  factory BotConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return BotConfig.defaults();
    return BotConfig(
      enabled: map['enabled'] == true,
      greeting: BotGreetingConfig.fromMap(map['greeting'] as Map<String, dynamic>?),
      away: BotAwayConfig.fromMap(map['away'] as Map<String, dynamic>?),
      businessHours: BusinessHoursConfig.fromMap(map['businessHours'] as Map<String, dynamic>?),
      aiAgent: BotAiAgentConfig.fromMap(map['aiAgent'] as Map<String, dynamic>?),
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'greeting': greeting.toMap(),
        'away': away.toMap(),
        'businessHours': businessHours.toMap(),
        'aiAgent': aiAgent.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  BotConfig copyWith({
    bool? enabled,
    BotGreetingConfig? greeting,
    BotAwayConfig? away,
    BusinessHoursConfig? businessHours,
    BotAiAgentConfig? aiAgent,
  }) {
    return BotConfig(
      enabled: enabled ?? this.enabled,
      greeting: greeting ?? this.greeting,
      away: away ?? this.away,
      businessHours: businessHours ?? this.businessHours,
      aiAgent: aiAgent ?? this.aiAgent,
    );
  }
}

class BotService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  DocumentReference<Map<String, dynamic>> _configRef(String tenantId) {
    return _firestore.collection('tenants').doc(tenantId).collection('bot').doc('config');
  }

  Stream<BotConfig> watchConfig(String tenantId) {
    return _configRef(tenantId).snapshots().map((snap) => BotConfig.fromMap(snap.data()));
  }

  Future<void> saveConfig(String tenantId, BotConfig config) async {
    await _configRef(tenantId).set(config.toMap(), SetOptions(merge: true));
  }

  Future<String> _idToken() async {
    final token = await _auth.currentUser?.getIdToken();
    if (token == null) throw Exception('Not signed in.');
    return token;
  }

  Future<bool> fetchApiKeyConfigured(String tenantId) async {
    final token = await _idToken();
    final response = await http.get(
      Uri.parse('$backendBaseUrl/tenants/$tenantId/bot/api-key/status'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) return false;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['configured'] == true;
  }

  Future<void> saveApiKey(String tenantId, String openaiApiKey) async {
    final token = await _idToken();
    final response = await http.post(
      Uri.parse('$backendBaseUrl/tenants/$tenantId/bot/api-key'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'openaiApiKey': openaiApiKey}),
    );
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['error'] as String? ?? 'Could not save API key.');
    }
  }

  Future<String> testAi(String tenantId) async {
    final token = await _idToken();
    final response = await http.post(
      Uri.parse('$backendBaseUrl/tenants/$tenantId/bot/test-ai'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['error'] as String? ?? 'AI test failed.');
    }
    return body['reply'] as String? ?? 'OK';
  }
}
