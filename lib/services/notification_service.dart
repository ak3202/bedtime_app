import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../constants.dart';

class NotificationService {
  // one instance shared across the app
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  // fixed IDs so we can cancel or replace specific notifications without accidentally stacking up duplicates
  static const int idPrimary = 1001; // the main nightly prompt notification
  static const int idBackup = 1002; // a follow-up sent if the user ignores the first
  static const int idRemindLater = 1003; // fires when the user taps a snooze chip
  static const int idTestNow = 9999; // only used from the debug/test button in settings

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // shared channel config — all notifications in the app use this
  static const _androidChannel = AndroidNotificationDetails(
    'bedtime_prompts',
    'Bedtime Prompts',
    channelDescription: 'Gentle bedtime reminders',
    importance: Importance.high,
    priority: Priority.high,
    color: Color(0xFF7B82E8),
  );

  static const _notifDetails = NotificationDetails(
    android: _androidChannel,
    iOS: DarwinNotificationDetails(),
  );

  Future<void> init() async {
    tz.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(initSettings);
  }

  // called during onboarding — prompts the OS permission dialog on both platforms
  Future<void> requestAndroidPermissionIfNeeded() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final impl = _plugin.resolvePlatformSpecificImplementation
          AndroidFlutterLocalNotificationsPlugin>();
      await impl?.requestNotificationsPermission();
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final impl = _plugin.resolvePlatformSpecificImplementation
          IOSFlutterLocalNotificationsPlugin>();
      await impl?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  // fires immediately so the user can confirm notifications are actually working
  Future<void> showTestNow() async {
    await _plugin.show(
      idTestNow,
      'Test notification',
      'If you see this, notifications are working.',
      _notifDetails,
    );
  }

  // sets up the normal schedule: a daily repeating notification at the chosen time, plus a one-shot backup for tonight in case the first gets dismissed
  Future<void> schedulePrimaryAndBackup({
    required int hour,
    required int minute,
  }) async {
    await _plugin.cancel(idPrimary);
    await _plugin.cancel(idBackup);

    print('Scheduling primary at $hour:$minute');

    // matchDateTimeComponents: time makes this repeat every day at the same time
    await _plugin.zonedSchedule(
      idPrimary,
      'Tonight',
      'Your nightly prompt is ready.',
      _nextInstanceOf(hour, minute),
      _notifDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    await _scheduleOneShotBackup(hour, minute);
  }

  // schedules just tonight's backup — used when we want to add the backup without touching the existing repeating primary
  Future<void> scheduleBackupForTonight({
    required int hour,
    required int minute,
  }) async {
    await _plugin.cancel(idBackup);
    await _scheduleOneShotBackup(hour, minute);
  }

  Future<void> _scheduleOneShotBackup(int hour, int minute) async {
    // fires a fixed number of minutes after the primary (set in constants.dart)
    int backupMinute = minute + backupReminderMinutes;
    int backupHour = hour + (backupMinute ~/ 60);
    backupMinute = backupMinute % 60;
    backupHour = backupHour % 24;

    print('Scheduling one-shot backup at $backupHour:$backupMinute');

    // no matchDateTimeComponents here — that's what makes it fire once and not repeat
    await _plugin.zonedSchedule(
      idBackup,
      'Still up?',
      'Quick reminder to wind down.',
      _nextInstanceOf(backupHour, backupMinute),
      _notifDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  // called when the user opens the prompt early by tapping "Get tonight's prompt now"
  // cancel the scheduled notifications and replace the backup with one that fires in backupReminderMinutes from right now
  Future<void> onManualOpen() async {
    await _plugin.cancel(idPrimary);
    await _plugin.cancel(idBackup);
    await _plugin.cancel(idRemindLater);

    final fireAt = tz.TZDateTime.now(tz.local)
        .add(Duration(minutes: backupReminderMinutes));

    print('Manual open — backup rescheduled for ${fireAt.hour}:${fireAt.minute}');

    await _plugin.zonedSchedule(
      idBackup,
      'Still up?',
      'Quick reminder to wind down.',
      fireAt,
      _notifDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  // when the user pauses prompts, we cancel everything and schedule a single one-shot notification for the first prompt time after the pause ends — the app will restore the repeating schedule once that fires
  Future<void> schedulePostPauseNotification({
    required DateTime pauseUntil,
    required int hour,
    required int minute,
  }) async {
    await _plugin.cancel(idPrimary);
    await _plugin.cancel(idBackup);
    await _plugin.cancel(idRemindLater);

    // find the first occurrence of hour:minute on or after the resume date
    var resumeDate = DateTime(
      pauseUntil.year,
      pauseUntil.month,
      pauseUntil.day,
      hour,
      minute,
    );

    // if that time has already passed today, push it to the next day
    if (resumeDate.isBefore(DateTime.now())) {
      resumeDate = resumeDate.add(const Duration(days: 1));
    }

    final fireAt = tz.TZDateTime.from(resumeDate, tz.local);

    print('Pause active — one-shot scheduled for resume at $fireAt');

    // no matchDateTimeComponents → fires once, doesn't repeat
    await _plugin.zonedSchedule(
      idPrimary,
      'Tonight',
      'Your nightly prompt is ready.',
      fireAt,
      _notifDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  // fires when the user taps a snooze chip on the tonight screen (15m/30m/1hr/2hr)
  Future<void> scheduleRemindLater(int minutes) async {
    await _plugin.cancel(idRemindLater);

    final fireAt =
        tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes));
    print('Scheduling remind-later at ${fireAt.hour}:${fireAt.minute}');

    await _plugin.zonedSchedule(
      idRemindLater,
      'Reminder',
      'Want to check the prompt now?',
      fireAt,
      _notifDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  // called when the user marks themselves done — no more pings tonight
  Future<void> cancelBackupAndRemindLater() async {
    await _plugin.cancel(idBackup);
    await _plugin.cancel(idRemindLater);
  }

  // wipes everything, used when pausing prompts
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  // returns the next future DateTime for a given hour:minute in local time — if that time has already passed today, it returns tomorrow's occurrence
  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}