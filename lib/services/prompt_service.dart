import 'package:flutter/services.dart';
import 'dart:convert';

class PromptItem {
  final String id;
  final String title;
  final String body;
  final String? type; // 'narrative', 'offloading' or 'imagery'
  final List<String>? goals; // which user goals this prompt is relevant to

  PromptItem({
    required this.id,
    required this.title,
    required this.body,
    this.type,
    this.goals,
  });

  factory PromptItem.fromJson(Map<String, dynamic> json) => PromptItem(
        id:    json['id']    as String,
        title: json['title'] as String,
        body:  json['body']  as String,
        type:  json['type']  as String?,
        // goals is an optional array in the JSON, so handle the null case
        goals: (json['goals'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
      );
}

class PromptService {
  // loads and parses the full prompt list from the bundled JSON asset
  static Future<List<PromptItem>> loadPrompts() async {
    final raw = await rootBundle.loadString('assets/prompts.json');
    final list = json.decode(raw) as List;
    return list
        .map((e) => PromptItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}