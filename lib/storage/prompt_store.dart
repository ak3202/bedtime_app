import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/prompt.dart';

class PromptStore {
  static const _key = 'prompt_history';

  static Future<List<Prompt>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw
        .map((s) => Prompt.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList()
        .reversed
        .toList(); // newest first
  }

  static Future<void> add(Prompt prompt) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.add(jsonEncode(prompt.toJson()));
    await prefs.setStringList(_key, raw);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}