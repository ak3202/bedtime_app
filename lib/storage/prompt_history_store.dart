import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PromptHistoryStore {
  static const _key = 'prompt_history';

  static Future<List<Map<String, dynamic>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    // newest first
    return raw.map((s) => jsonDecode(s) as Map<String, dynamic>).toList().reversed.toList();
  }

  static Future<void> add(Map<String, dynamic> promptJson) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final withTimestamp = {
      ...promptJson,
      'savedAt': DateTime.now().toIso8601String(),
    };
    raw.add(jsonEncode(withTimestamp));
    await prefs.setStringList(_key, raw);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}