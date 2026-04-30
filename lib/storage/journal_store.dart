import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// a single journal entry
class JournalEntry {
  final String id;
  final DateTime date;
  final String body;
  final String? promptId; // set if the entry was written from a specific prompt
  final String? promptTitle; 

  JournalEntry({
    required this.id,
    required this.date,
    required this.body,
    this.promptId,
    this.promptTitle,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'body': body,
        'promptId': promptId,
        'promptTitle': promptTitle,
      };

  factory JournalEntry.fromJson(Map<String, dynamic> json) => JournalEntry(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        body: json['body'] as String,
        promptId: json['promptId'] as String?,
        promptTitle: json['promptTitle'] as String?,
      );
}

class JournalStore {
  static const _key = 'journal_entries';

  // newest first
  static Future<List<JournalEntry>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = json.decode(raw) as List;
    return list
        .map((e) => JournalEntry.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  // looks up whether the user wrote a journal entry for a specific prompt
  static Future<JournalEntry?> getForPrompt(String promptId) async {
    final all = await getAll();
    try {
      return all.firstWhere((e) => e.promptId == promptId);
    } catch (_) {
      return null;
    }
  }

  // handles both new entries and edits 
  static Future<void> save(JournalEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await getAll();

    final idx = all.indexWhere((e) => e.id == entry.id);
    if (idx >= 0) {
      all[idx] = entry;
    } else {
      all.insert(0, entry);
    }

    await prefs.setString(
        _key, json.encode(all.map((e) => e.toJson()).toList()));
  }

  static Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await getAll();
    all.removeWhere((e) => e.id == id);
    await prefs.setString(
        _key, json.encode(all.map((e) => e.toJson()).toList()));
  }
}