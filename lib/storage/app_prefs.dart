import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';

// all persistent app state lives here
class AppPrefs {
  static const _keyHour = 'prompt_hour';
  static const _keyMinute = 'prompt_minute';
  static const _keyPauseFrom = 'pause_from';
  static const _keyPauseUntil = 'pause_until';
  static const _keyDoneNight = 'done_night';
  static const _keySavedPromptNight  = 'saved_prompt_night';
  static const _keyManualActive = 'manual_active_night';
  static const _keyOnboarding = 'onboarding_complete';
  static const _keyGoals = 'user_goals';
  static const _keyTextSize = 'text_size';
  static const _keyBackupScheduled = 'backup_scheduled_night';

  // "tonight" runs from 6am to 6am, so we need a stable key that represents the current night rather than the current calendar day.
  // e.g. 2am on Jan 6 → night key is "2025-01-05" (still last night)
  static String _nightKey(DateTime now) {
    final reset = DateTime(now.year, now.month, now.day, nightResetHour);
    final nightDate = now.isBefore(reset)
        ? now.subtract(const Duration(days: 1))
        : now;
    final y = nightDate.year.toString().padLeft(4, '0');
    final m = nightDate.month.toString().padLeft(2, '0');
    final d = nightDate.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  // Prompt time
  static Future<void> setPromptTime(
      {required int hour, required int minute}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyHour, hour);
    await prefs.setInt(_keyMinute, minute);
  }

  // returns null if the user hasn't set a time yet
  static Future<(int hour, int minute)?> getPromptTime() async {
    final prefs = await SharedPreferences.getInstance();
    final h = prefs.getInt(_keyHour);
    final m = prefs.getInt(_keyMinute);
    if (h == null || m == null) return null;
    return (h, m);
  }

  // Pause schedule
  // saves both the start and end of a pause window — "from" can be in the future for scheduled pauses like "this weekend"
  static Future<void> setPauseSchedule({
    required DateTime from,
    required DateTime until,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPauseFrom,  from.toIso8601String());
    await prefs.setString(_keyPauseUntil, until.toIso8601String());
  }

  // passing null clears the pause entirely
  static Future<void> setPausedUntil(DateTime? until) async {
    final prefs = await SharedPreferences.getInstance();
    if (until == null) {
      await prefs.remove(_keyPauseFrom);
      await prefs.remove(_keyPauseUntil);
    } else {
      await prefs.setString(_keyPauseFrom,  DateTime.now().toIso8601String());
      await prefs.setString(_keyPauseUntil, until.toIso8601String());
    }
  }

  // returns true only if we're currently within an active pause window 
  static Future<bool> isPaused() async {
    final prefs = await SharedPreferences.getInstance();
    final rawFrom  = prefs.getString(_keyPauseFrom);
    final rawUntil = prefs.getString(_keyPauseUntil);
    if (rawFrom == null || rawUntil == null) return false;

    final from  = DateTime.tryParse(rawFrom);
    final until = DateTime.tryParse(rawUntil);
    if (from == null || until == null) return false;

    final now = DateTime.now();

    // pause has expired
    if (now.isAfter(until)) {
      await prefs.remove(_keyPauseFrom);
      await prefs.remove(_keyPauseUntil);
      return false;
    }

    // pause is scheduled but hasn't started yet
    if (now.isBefore(from)) return false;

    return true;
  }

  // returns null if there's no pause or it's already expired
  static Future<DateTime?> getPauseUntil() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyPauseUntil);
    if (raw == null) return null;
    final until = DateTime.tryParse(raw);
    if (until == null) return null;
    // auto-clean expired pause while we're here
    if (DateTime.now().isAfter(until)) {
      await prefs.remove(_keyPauseFrom);
      await prefs.remove(_keyPauseUntil);
      return null;
    }
    return until;
  }

  static Future<DateTime?> getPauseFrom() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyPauseFrom);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  // Done for tonight
  // stores tonight's night key so we know the user has already completed their prompt 
  static Future<void> setDoneForTonight(DateTime now, bool done) async {
    final prefs = await SharedPreferences.getInstance();
    if (!done) {
      await prefs.remove(_keyDoneNight);
      return;
    }
    await prefs.setString(_keyDoneNight, _nightKey(now));
  }

  static Future<bool> isDoneForTonight(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keyDoneNight);
    return saved == _nightKey(now);
  }

  // set when the user taps "Get tonight's prompt now" before the scheduled time
  static Future<void> setManuallyActivatedTonight(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyManualActive, _nightKey(now));
  }

  static Future<bool> isManuallyActivatedTonight(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyManualActive) == _nightKey(now);
  }

  static Future<void> clearManuallyActivatedTonight(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyManualActive);
  }

  // prevents the same prompt being added to the library twice 
  static Future<bool> hasSavedPromptTonight(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySavedPromptNight) == _nightKey(now);
  }

  static Future<void> markPromptSavedTonight(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySavedPromptNight, _nightKey(now));
  }

  // Backup notification guard

  // tracks whether we've already scheduled tonight's one-shot backup notification so we don't stack up duplicates on every refresh
  static Future<void> setBackupScheduledTonight(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBackupScheduled, _nightKey(now));
  }

  static Future<bool> isBackupScheduledTonight(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBackupScheduled) == _nightKey(now);
  }

  static Future<void> clearBackupScheduledTonight() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyBackupScheduled);
  }

  static Future<bool> isOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOnboarding) ?? false;
  }

  static Future<void> setOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboarding, true);
  }

  static Future<List<String>> getGoals() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyGoals) ?? [];
  }

  static Future<void> setGoals(List<String> goals) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyGoals, goals);
  }

  static Future<String> getTextSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyTextSize) ?? 'medium';
  }

  static Future<void> setTextSize(String size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTextSize, size);
  }

  // wipes everything (for testing)
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyHour);
    await prefs.remove(_keyMinute);
    await prefs.remove(_keyPauseFrom);
    await prefs.remove(_keyPauseUntil);
    await prefs.remove(_keyDoneNight);
    await prefs.remove(_keySavedPromptNight);
    await prefs.remove(_keyManualActive);
    await prefs.remove(_keyOnboarding);
    await prefs.remove(_keyGoals);
    await prefs.remove(_keyTextSize);
    await prefs.remove(_keyBackupScheduled);
  }
}