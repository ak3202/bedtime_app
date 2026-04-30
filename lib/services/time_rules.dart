import '../constants.dart';

// returns the next 6am reset
DateTime nextNightReset(DateTime now) {
  final todayReset = DateTime(now.year, now.month, now.day, nightResetHour);
  if (now.isBefore(todayReset)) return todayReset;
  return todayReset.add(const Duration(days: 1));
}

// makes sure a snooze reminder doesn't fire after 6am or past the app's max allowed snooze time 
int clampRemindMinutes(DateTime now, int requestedMinutes) {
  final untilReset = nextNightReset(now).difference(now).inMinutes;
  if (untilReset <= 0) return 0;

  final cappedByReset = requestedMinutes > untilReset ? untilReset : requestedMinutes;
  final cappedByMax = cappedByReset > remindLaterMaxMinutes ? remindLaterMaxMinutes : cappedByReset;

  return cappedByMax;
}