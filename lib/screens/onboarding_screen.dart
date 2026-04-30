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

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  TimeOfDay? _selectedTime;
  final List<String> _selectedGoals = [];
  bool _saving = false;

  static const int _totalPages = 4;

  // the full list of goals the user can pick from on page 2
  static const List<Map<String, dynamic>> _allGoals = [
    {'id': 'sleep', 'label': 'Better sleep & earlier bedtimes','icon': Icons.bedtime_outlined},
    {'id': 'phone', 'label': 'Less late-night phone use', 'icon': Icons.phone_android_outlined},
    {'id': 'stress', 'label': 'Reduce stress before bed', 'icon': Icons.self_improvement_outlined},
    {'id': 'routine', 'label': 'Build a wind-down routine', 'icon': Icons.loop_outlined},
    {'id': 'control', 'label': 'Feel more in control of my evenings', 'icon': Icons.tune_outlined},
    {'id': 'procrastination','label': 'Stop staying up without meaning to', 'icon': Icons.nights_stay_outlined},
    {'id': 'exhaustion', 'label': 'Wake up less exhausted', 'icon': Icons.wb_sunny_outlined},
  ];

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  // caps at 2 selections 
  void _toggleGoal(String id) {
    setState(() {
      if (_selectedGoals.contains(id)) {
        _selectedGoals.remove(id);
      } else if (_selectedGoals.length < 2) {
        _selectedGoals.add(id);
      }
    });
  }

  Future<void> _pickTime() async {
    // defaults to 10:30 PM as a sensible starting point for most people
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 22, minute: 30),
      helpText: 'When should we check in?',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _accent,
            surface: _surface,
            onSurface: _textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => _selectedTime = picked);
  }

  // saves everything and schedules the nightly notification, then hands off to the app
  Future<void> _finish() async {
    if (_selectedTime == null) return;
    setState(() => _saving = true);

    await AppPrefs.setGoals(_selectedGoals);
    await AppPrefs.setPromptTime(
        hour: _selectedTime!.hour, minute: _selectedTime!.minute);
    await NotificationService.instance.schedulePrimaryAndBackup(
        hour: _selectedTime!.hour, minute: _selectedTime!.minute);
    await AppPrefs.setOnboardingComplete();

    if (!mounted) return;
    widget.onComplete();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),

            // progress dots at the top — the active one stretches wider
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_totalPages, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == i ? 24 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _currentPage == i ? _accent : _cardBorder,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),

            Expanded(
              child: PageView(
                controller: _pageController,
                // swiping between pages is disabled — the buttons drive navigation
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _PageWelcome(onNext: _nextPage),
                  _PageGoals(
                    allGoals: _allGoals,
                    selected: _selectedGoals,
                    onToggle: _toggleGoal,
                    // Next button is locked until they pick at least one goal
                    onNext: _selectedGoals.isEmpty ? null : _nextPage,
                  ),
                  _PageTime(
                    selectedTime: _selectedTime,
                    onPickTime: _pickTime,
                    // Next button is locked until they pick a time
                    onNext: _selectedTime == null ? null : _nextPage,
                  ),
                  _PageConfirm(
                    selectedTime: _selectedTime,
                    selectedGoals: _selectedGoals,
                    allGoals: _allGoals,
                    saving: _saving,
                    onFinish: (_selectedTime == null || _saving) ? null : _finish,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Page 1: Welcome 

class _PageWelcome extends StatelessWidget {
  final VoidCallback onNext;
  const _PageWelcome({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Icon(Icons.bedtime, size: 72, color: _accent),
          ),
          const SizedBox(height: 32),
          const Text(
            'Better nights start\nwith a gentle nudge.',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'A short story sent to your phone each evening — to help you reflect on your bedtime habits. No judgement, no blocking.',
            style: TextStyle(color: _textSecondary, fontSize: 15, height: 1.6),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          // three quick feature callouts to give the user a sense of what they're signing up for
          _FeatureRow(icon: Icons.auto_stories_outlined,
              text: 'Story-style prompts to make you think, not feel guilty'),
          const SizedBox(height: 14),
          _FeatureRow(icon: Icons.shield_outlined,
              text: 'No tracking, no data sold — just you and your goals'),
          const SizedBox(height: 14),
          _FeatureRow(icon: Icons.my_location,
              text: 'Linked to the goals you choose'),
          const SizedBox(height: 48),
          ElevatedButton(
            onPressed: onNext,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Get started',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _cardBorder, width: 1),
          ),
          child: Icon(icon, size: 20, color: _accent),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  color: _textSecondary, fontSize: 13, height: 1.4)),
        ),
      ],
    );
  }
}

// Page 2: Goals

class _PageGoals extends StatelessWidget {
  final List<Map<String, dynamic>> allGoals;
  final List<String> selected;
  final void Function(String) onToggle;
  final VoidCallback? onNext;

  const _PageGoals({
    required this.allGoals,
    required this.selected,
    required this.onToggle,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'What matters most\nto you right now?',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pick up to 2. Your prompts will be tailored to these.',
            style: TextStyle(color: _textSecondary, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),

          Expanded(
            child: ListView.separated(
              itemCount: allGoals.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final goal = allGoals[i];
                final id = goal['id'] as String;
                final isSelected = selected.contains(id);
                // once 2 are picked, everything else goes grey and stops responding to taps
                final isDisabled = !isSelected && selected.length >= 2;

                return GestureDetector(
                  onTap: isDisabled ? null : () => onToggle(id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _accent.withOpacity(0.12)
                          : _surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? _accent : _cardBorder,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          goal['icon'] as IconData,
                          size: 22,
                          color: isSelected
                              ? _accent
                              : isDisabled
                                  ? _cardBorder
                                  : _textSecondary,
                        ),
                        const SizedBox(width: 14),
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
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle_rounded,
                              color: _accent, size: 20),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onNext,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              disabledBackgroundColor: _surface,
              disabledForegroundColor: _textSecondary,
            ),
            child: const Text('Next',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          // small comment below the button so it's obvious why it's disabled
          if (selected.isEmpty) ...[
            const SizedBox(height: 8),
            const Text('Choose at least one to continue',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textSecondary, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

// Page 3: Time

class _PageTime extends StatelessWidget {
  final TimeOfDay? selectedTime;
  final VoidCallback onPickTime;
  final VoidCallback? onNext;

  const _PageTime({
    required this.selectedTime,
    required this.onPickTime,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.schedule_outlined, size: 64, color: _accent),
          const SizedBox(height: 32),
          const Text(
            'When should we\ncheck in with you?',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Pick the time you usually start thinking about winding down — not when you want to be asleep.',
            style: TextStyle(color: _textSecondary, fontSize: 14, height: 1.6),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),

          // tapping this opens the system time picker
          // border turns purple once a time has been chosen
          GestureDetector(
            onTap: onPickTime,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selectedTime != null ? _accent : _cardBorder,
                  width: selectedTime != null ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.access_time_rounded,
                      color: selectedTime != null ? _accent : _textSecondary),
                  const SizedBox(width: 12),
                  Text(
                    selectedTime == null
                        ? 'Tap to choose a time'
                        : selectedTime!.format(context),
                    style: TextStyle(
                      color: selectedTime != null ? _textPrimary : _textSecondary,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: onNext,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              disabledBackgroundColor: _surface,
              disabledForegroundColor: _textSecondary,
            ),
            child: const Text('Next',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          if (selectedTime == null) ...[
            const SizedBox(height: 8),
            const Text('Choose a time to continue',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textSecondary, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

// Page 4: Confirm 

class _PageConfirm extends StatelessWidget {
  final TimeOfDay? selectedTime;
  final List<String> selectedGoals;
  final List<Map<String, dynamic>> allGoals;
  final bool saving;
  final VoidCallback? onFinish;

  const _PageConfirm({
    required this.selectedTime,
    required this.selectedGoals,
    required this.allGoals,
    required this.saving,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    // look up the full label for each selected goal id so we can display it nicely
    final goalLabels = selectedGoals.map((id) {
      final match = allGoals.firstWhere((g) => g['id'] == id,
          orElse: () => {'label': id});
      return match['label'] as String;
    }).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.check_circle_outline_rounded,
              size: 72, color: _accent),
          const SizedBox(height: 32),
          const Text(
            "You're all set.",
            style: TextStyle(
              color: _textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // summary card showing back what the user just chose
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _cardBorder, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SummaryRow(
                  icon: Icons.schedule_outlined,
                  label: 'Prompt time',
                  value: selectedTime?.format(context) ?? '—',
                ),
                const SizedBox(height: 14),
                _SummaryRow(
                  icon: Icons.flag_outlined,
                  label: 'Your goals',
                  value: goalLabels.join(' · '),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Text(
            'You can change these any time in Settings.',
            style: TextStyle(color: _textSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),

          ElevatedButton(
            onPressed: saving ? null : onFinish,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            // spinner while we save prefs and schedule the notification
            child: saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text("Let's go",
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// reusable row for the confirm summary card — icon, label above, value below
class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _SummaryRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: _accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: _textSecondary, fontSize: 12)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }
}