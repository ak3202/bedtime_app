import 'package:flutter/material.dart';
import '../storage/app_prefs.dart';
import '../services/notification_service.dart';

// same palette as the rest of the app
const _navy = Color(0xFF0D0F1C);
const _surface = Color(0xFF161829);
const _accent = Color(0xFF7B82E8);
const _cardBorder = Color(0xFF2E3156);
const _textPrimary = Color(0xFFE8E9F3);
const _textSecondary = Color(0xFF8B8FA8);

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onScheduleChanged;
  final void Function(String size)? onTextSizeChanged;
  final String textSize;

  const SettingsScreen({
    super.key,
    this.onScheduleChanged,
    this.onTextSizeChanged,
    this.textSize = 'medium',
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  TimeOfDay? time;
  DateTime? pauseUntil;
  DateTime? pauseFrom;
  bool loading = true;
  late String _textSize;
  List<String> _goals = [];

  @override
  void initState() {
    super.initState();
    _textSize = widget.textSize;
    _load();
  }

  Future<void> _load() async {
    final t = await AppPrefs.getPromptTime();
    final until = await AppPrefs.getPauseUntil();
    final from = await AppPrefs.getPauseFrom();
    final goals = await AppPrefs.getGoals();
    setState(() {
      time = t == null ? null : TimeOfDay(hour: t.$1, minute: t.$2);
      pauseUntil = until;
      pauseFrom = from;
      _goals = goals;
      loading = false;
    });
  }

  // saves the new time, reschedules the notification, and shows a snackbar confirmation
  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: time ?? const TimeOfDay(hour: 22, minute: 30),
    );
    if (picked == null) return;

    await AppPrefs.setPromptTime(hour: picked.hour, minute: picked.minute);
    await NotificationService.instance.schedulePrimaryAndBackup(
      hour: picked.hour,
      minute: picked.minute,
    );

    setState(() => time = picked);
    widget.onScheduleChanged?.call();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved prompt time: ${picked.format(context)}')),
      );
    }
  }

  // opens the bottom sheet where the user picks how long to pause for
  Future<void> _openPausePicker() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PausePicker(
        onChanged: (from, until) async {
          await AppPrefs.setPauseSchedule(from: from, until: until);

          // cancel any existing notifications and replace with a single one that fires when the pause ends
          await AppPrefs.clearBackupScheduledTonight();
          await NotificationService.instance.cancelAll();

          final t = await AppPrefs.getPromptTime();
          if (t != null) {
            await NotificationService.instance.schedulePostPauseNotification(
              pauseUntil: until,
              hour: t.$1,
              minute: t.$2,
            );
          }

          final updatedUntil = await AppPrefs.getPauseUntil();
          final updatedFrom = await AppPrefs.getPauseFrom();
          if (mounted) setState(() {
            pauseUntil = updatedUntil;
            pauseFrom = updatedFrom;
          });
          widget.onScheduleChanged?.call();
        },
      ),
    );
  }

  // clears the pause and immediately restores the normal nightly notification
  Future<void> _resumeNow() async {
    await AppPrefs.setPausedUntil(null);
    await AppPrefs.clearBackupScheduledTonight();

    final t = await AppPrefs.getPromptTime();
    if (t != null) {
      await NotificationService.instance.schedulePrimaryAndBackup(
        hour: t.$1,
        minute: t.$2,
      );
    }

    if (mounted) setState(() { pauseUntil = null; pauseFrom = null; });
    widget.onScheduleChanged?.call();
  }

  // persists the size and tells the app shell to update so the change is instant
  Future<void> _setTextSize(String size) async {
    await AppPrefs.setTextSize(size);
    setState(() => _textSize = size);
    widget.onTextSizeChanged?.call(size);
  }

  // opens the goal picker sheet, then refreshes the subtitle once they close it
  Future<void> _openGoalPicker() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _GoalPicker(),
    );
    final updated = await AppPrefs.getGoals();
    if (mounted) setState(() => _goals = updated);
  }

  // reusable bottom sheet for the "How to use" and "What is Drift?" info pages
  void _showInfoSheet(BuildContext context, String title, List<_InfoItem> items) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            // drag handle
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: _cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(title,
                style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(item.icon, color: _accent, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title,
                            style: const TextStyle(
                                color: _textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(item.body,
                            style: const TextStyle(
                                color: _textSecondary,
                                fontSize: 13,
                                height: 1.5)),
                      ],
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  String _fmt(TimeOfDay? t) => t == null ? 'Not set' : t.format(context);

  // turns the list of goal ids into a readable subtitle like "Better sleep · Reduce stress"
  String _goalsLabel() {
    if (_goals.isEmpty) return 'Not set';
    const labels = {
      'sleep': 'Better sleep',
      'phone': 'Less phone use',
      'stress': 'Reduce stress',
      'routine': 'Wind-down routine',
      'control': 'Control evenings',
      'procrastination': 'Stop unplanned delays',
      'exhaustion': 'Wake less exhausted',
    };
    return _goals.map((g) => labels[g] ?? g).join(' · ');
  }

  // the subtitle under "Pause prompts" — changes depending on whether a pause is active, scheduled for the future, or off entirely
  String _pauseStatusLabel() {
    if (pauseUntil == null) return 'Prompts are active';

    final now = DateTime.now();
    final isScheduled = pauseFrom != null && now.isBefore(pauseFrom!);

    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    final resumeStr = '${months[pauseUntil!.month - 1]} ${pauseUntil!.day}';

    if (isScheduled) {
      final startStr = '${months[pauseFrom!.month - 1]} ${pauseFrom!.day}';
      return 'Scheduled: $startStr → resumes $resumeStr';
    }
    return 'Paused until $resumeStr';
  }

  bool get _hasPause => pauseUntil != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: _navy,
        elevation: 0,
        title: const Text('Settings',
            style: TextStyle(
                color: _textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [

                _sectionHeader('Prompts'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('Prompt time'),
                        subtitle: Text(_fmt(time)),
                        trailing: FilledButton.tonal(
                          onPressed: _pickTime,
                          child: const Text('Change'),
                        ),
                      ),
                      const Divider(height: 1),

                      ListTile(
                        title: const Text('Pause prompts'),
                        subtitle: Text(
                          _pauseStatusLabel(),
                          style: TextStyle(
                            // orange-ish tint when paused 
                            color: _hasPause
                                ? const Color(0xFFE8A87C)
                                : _textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        // when paused, show a Resume button instead of the chevron
                        trailing: _hasPause
                            ? GestureDetector(
                                onTap: _resumeNow,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: Colors.redAccent.withOpacity(0.3),
                                        width: 1),
                                  ),
                                  child: const Text(
                                    'Resume',
                                    style: TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              )
                            : const Icon(Icons.chevron_right, size: 20),
                        // tapping is disabled while paused — use the Resume button instead
                        onTap: _hasPause ? null : _openPausePicker,
                      ),

                      const Divider(height: 1),
                      ListTile(
                        title: const Text('Your goals'),
                        subtitle: Text(_goalsLabel()),
                        trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: _openGoalPicker,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                _sectionHeader('Display'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Text size',
                            style: TextStyle(
                                color: _textPrimary,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        const Text(
                          'Adjusts text size across the whole app',
                          style: TextStyle(fontSize: 12, color: _textSecondary),
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'small',
                              label: Text('Small'),
                              icon: Icon(Icons.text_fields, size: 14),
                            ),
                            ButtonSegment(
                              value: 'medium',
                              label: Text('Medium'),
                              icon: Icon(Icons.text_fields, size: 18),
                            ),
                            ButtonSegment(
                              value: 'large',
                              label: Text('Large'),
                              icon: Icon(Icons.text_fields, size: 22),
                            ),
                          ],
                          selected: {_textSize},
                          onSelectionChanged: (s) => _setTextSize(s.first),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                _sectionHeader('About'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('How to use Drift'),
                        trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: () => _showInfoSheet(context, 'How to use Drift', [
                          _InfoItem(Icons.schedule_outlined, 'Set your prompt time',
                              'Go to Settings and pick the time you usually wind down — somewhere between 9 pm and midnight works well. You\'ll get a gentle notification when your prompt is ready.'),
                          _InfoItem(Icons.notifications_outlined, 'Wait for your prompt',
                              'Each evening at your chosen time, you\'ll get a notification. Open the app to read tonight\'s prompt — it takes under two minutes.'),
                          _InfoItem(Icons.check_circle_outline, 'Mark yourself done',
                              'Once you\'ve read the prompt, tap "I\'m done for tonight" to let the app know. No more notifications will be sent that night.'),
                          _InfoItem(Icons.snooze_outlined, 'Not ready yet? Snooze it',
                              'If you\'re not ready to wind down, hit a snooze option (15m, 30m, 1hr, 2hr) and you\'ll get a reminder later instead.'),
                          _InfoItem(Icons.pause_circle_outline, 'Need a break?',
                              'You can pause prompts for tonight, a few days, or the weekend — just go to Pause prompts in Settings. They\'ll restart automatically.'),
                        ]),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('What is Drift?'),
                        trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: () => _showInfoSheet(context, 'What is Drift?', [
                          _InfoItem(Icons.bedtime_outlined, 'A gentle bedtime companion',
                              'Drift is designed to help you reflect on your night-time phone habits. It doesn\'t block anything or tell you what to do — it just nudges you to pause and think.'),
                          _InfoItem(Icons.menu_book_outlined, 'Story-style prompts',
                              'Each night you get a short prompt — a story, a wind-down reflection, or a guided visualisation. They\'re designed to be easy to read and relevant to student life.'),
                          _InfoItem(Icons.psychology_outlined, 'Built around your goals',
                              'Set up to two personal goals (like better sleep or less stress) and prompts will be chosen to match what matters to you.'),
                          _InfoItem(Icons.auto_awesome_outlined, 'No pressure, no tracking',
                              'Drift doesn\'t monitor your screen time or judge your habits. It\'s here to support you — not control you. You\'re always free to ignore it.'),
                          _InfoItem(Icons.library_books_outlined, 'Your library',
                              'Every prompt you complete gets saved to your Library so you can revisit it whenever you like.'),
                        ]),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: _textSecondary,
        ),
      ),
    );
  }
}


// Info item data class 

class _InfoItem {
  final IconData icon;
  final String title;
  final String body;
  const _InfoItem(this.icon, this.title, this.body);
}


// Pause picker

class _PausePicker extends StatelessWidget {
  final void Function(DateTime from, DateTime until) onChanged;

  const _PausePicker({required this.onChanged});

  // all pause options resume at 6am so notifications don't fire in the middle of the night
  DateTime _at6am(DateTime date) =>
      DateTime(date.year, date.month, date.day, 6, 0);

  DateTime _daysFromNow(int days) =>
      _at6am(DateTime.now().add(Duration(days: days)));

  // finds the next Saturday, or the one after if today is already Saturday
  DateTime _thisSaturday() {
    final now = DateTime.now();
    int daysUntilSat = (DateTime.saturday - now.weekday + 7) % 7;
    if (daysUntilSat == 0) daysUntilSat = 7;
    return _at6am(now.add(Duration(days: daysUntilSat)));
  }

  DateTime _nextMonday() {
    final now = DateTime.now();
    int daysUntilMon = (DateTime.monday - now.weekday + 7) % 7;
    if (daysUntilMon == 0) daysUntilMon = 7;
    return _at6am(now.add(Duration(days: daysUntilMon)));
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // each option has a from and until date — "scheduled: true" means the pause doesn't start immediately (e.g. weekend starts on Saturday)
    final options = [
      {
        'label': 'Tonight only',
        'subtitle': 'Pauses now — resumes tomorrow morning',
        'from': now,
        'until': _daysFromNow(1),
        'icon': Icons.bedtime_outlined,
        'scheduled': false,
      },
      {
        'label': '2 days',
        'subtitle': 'Pauses now — resumes in 2 days',
        'from': now,
        'until': _daysFromNow(2),
        'icon': Icons.calendar_today_outlined,
        'scheduled': false,
      },
      {
        'label': '3 days',
        'subtitle': 'Pauses now — resumes in 3 days',
        'from': now,
        'until': _daysFromNow(3),
        'icon': Icons.calendar_month_outlined,
        'scheduled': false,
      },
      {
        'label': 'This weekend',
        'subtitle': 'Pauses Saturday — resumes Monday morning',
        'from': _thisSaturday(),
        'until': _nextMonday(),
        'icon': Icons.weekend_outlined,
        'scheduled': true,
      },
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: _cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          const Text(
            'Pause prompts',
            style: TextStyle(
                color: _textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            'Prompts will automatically resume on the date shown.',
            style: TextStyle(color: _textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 20),

          ...options.map((opt) {
            final isScheduled = opt['scheduled'] as bool;

            return GestureDetector(
              onTap: () {
                onChanged(
                  opt['from'] as DateTime,
                  opt['until'] as DateTime,
                );
                Navigator.pop(context);
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: _navy,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _cardBorder, width: 1),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: _accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(opt['icon'] as IconData,
                          color: _accent, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                opt['label'] as String,
                                style: const TextStyle(
                                    color: _textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600),
                              ),
                              // "Scheduled" badge for options that don't start immediately
                              if (isScheduled) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _accent.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Scheduled',
                                    style: TextStyle(
                                        color: _accent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            opt['subtitle'] as String,
                            style: const TextStyle(
                                color: _textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: _textSecondary, size: 18),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}


// Goal picker

class _GoalPicker extends StatefulWidget {
  const _GoalPicker();

  @override
  State<_GoalPicker> createState() => _GoalPickerState();
}

class _GoalPickerState extends State<_GoalPicker> {
  List<String> _selected = [];
  bool _loaded = false;

  // same goal list as onboarding
  static const List<Map<String, dynamic>> _allGoals = [
    {'id': 'sleep', 'label': 'Better sleep & earlier bedtimes', 'icon': Icons.bedtime_outlined},
    {'id': 'phone', 'label': 'Less late-night phone use', 'icon': Icons.phone_android_outlined},
    {'id': 'stress', 'label': 'Reduce stress before bed', 'icon': Icons.self_improvement_outlined},
    {'id': 'routine', 'label': 'Build a wind-down routine', 'icon': Icons.loop_outlined},
    {'id': 'control', 'label': 'Feel more in control of my evenings', 'icon': Icons.tune_outlined},
    {'id': 'procrastination', 'label': 'Stop staying up without meaning to', 'icon': Icons.nights_stay_outlined},
    {'id': 'exhaustion', 'label': 'Wake up less exhausted', 'icon': Icons.wb_sunny_outlined},
  ];

  @override
  void initState() {
    super.initState();
    // pre-tick whatever goals they already have saved
    AppPrefs.getGoals().then((g) {
      if (mounted) setState(() { _selected = List.from(g); _loaded = true; });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: _cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          const Text('Your goals',
              style: TextStyle(
                  color: _textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Pick up to 2 — prompts will be tailored to these.',
              style: TextStyle(color: _textSecondary, fontSize: 13)),
          const SizedBox(height: 16),

          if (!_loaded)
            const Center(child: CircularProgressIndicator())
          else
            ..._allGoals.map((goal) {
              final id = goal['id'] as String;
              final isSelected = _selected.contains(id);
              // once 2 are picked, everything else goes grey and stops responding to taps
              final isDisabled = !isSelected && _selected.length >= 2;

              return GestureDetector(
                onTap: isDisabled
                    ? null
                    : () => setState(() {
                          if (isSelected)
                            _selected.remove(id);
                          else
                            _selected.add(id);
                        }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? _accent.withOpacity(0.12) : _navy,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? _accent : _cardBorder,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        goal['icon'] as IconData,
                        size: 20,
                        color: isSelected
                            ? _accent
                            : isDisabled
                                ? _cardBorder
                                : _textSecondary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          goal['label'] as String,
                          style: TextStyle(
                            color: isSelected
                                ? _textPrimary
                                : isDisabled
                                    ? _cardBorder
                                    : _textSecondary,
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (isSelected)
                        const Icon(Icons.check_circle_rounded,
                            color: _accent, size: 18),
                    ],
                  ),
                ),
              );
            }),

          const SizedBox(height: 8),

          ElevatedButton(
            onPressed: _selected.isEmpty
                ? null
                : () async {
                    await AppPrefs.setGoals(_selected);
                    if (mounted) Navigator.pop(context);
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _cardBorder.withOpacity(0.3),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Save',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}