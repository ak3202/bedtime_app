import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class TonightPromptStore {
  static const _key = 'tonight_prompt_json';
  static const _keyNight = 'tonight_prompt_night';

  static String _nightKey(DateTime now) {
    // Resets at 6am
    final reset = DateTime(now.year, now.month, now.day, 6);
    final nightDate = now.isBefore(reset) ? now.subtract(const Duration(days: 1)) : now;
    final y = nightDate.year.toString().padLeft(4, '0');
    final m = nightDate.month.toString().padLeft(2, '0');
    final d = nightDate.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static Future<Map<String, dynamic>?> loadForTonight() async {
    final prefs = await SharedPreferences.getInstance();
    final savedNight = prefs.getString(_keyNight);
    final tonight = _nightKey(DateTime.now());
    if (savedNight != tonight) return null;

    final raw = prefs.getString(_key);
    if (raw == null) return null;

    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<void> saveForTonight(Map<String, dynamic> promptJson) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNight, _nightKey(DateTime.now()));
    await prefs.setString(_key, jsonEncode(promptJson));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyNight);
    await prefs.remove(_key);
  }
}