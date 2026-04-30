import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../storage/app_prefs.dart';
import '../services/time_rules.dart';
import '../services/notification_service.dart';
import '../services/prompt_service.dart';
import '../storage/tonight_prompt_store.dart';
import '../storage/prompt_history_store.dart';
import 'journal_screen.dart';

// the three states the tonight screen can be in:
// waiting = before prompt time, active = prompt is showing, done = user tapped "I'm done"
enum TonightPhase { waiting, active, done }

// tracks what the text-to-speech is doing so the audio controls render correctly
enum AudioState { idle, playing, paused, finished }

// same palette as the rest of the app
const _navy = Color(0xFF0D0F1C);
const _surface = Color(0xFF161829);
const _accent = Color(0xFF7B82E8);
const _cardBorder = Color(0xFF2E3156);
const _textPrimary = Color(0xFFE8E9F3);
const _textSecondary = Color(0xFF8B8FA8);
const _imageryColor = Color(0xFFB48EE8); 

class TonightScreen extends StatefulWidget {
  final VoidCallback goToSettings;
  final VoidCallback goToLibrary;

  const TonightScreen({
    super.key,
    required this.goToSettings,
    required this.goToLibrary,
  });

  @override
  State<TonightScreen> createState() => TonightScreenState();
}

class TonightScreenState extends State<TonightScreen>
    with WidgetsBindingObserver {
  TonightPhase phase = TonightPhase.waiting;
  TimeOfDay? promptTime;
  bool paused = false;
  bool loading = true;

  PromptItem? currentPrompt;

  Timer? _phaseTimer; // fires when it's time to flip from waiting → active
  Timer? _pollTimer; // polls every 5s as a safety net in case the timer drifts

  final FlutterTts _tts = FlutterTts();
  AudioState _audioState = AudioState.idle;
  bool _imageryStarted = false; // tracks whether the user has tapped Begin on the imagery intro screen

  // helpers

  // "tonight" runs from 6am today until 6am tomorrow, so we need to know which 6am is the start of the current night
  DateTime _nightStart(DateTime now) {
    final todayAt6am = DateTime(now.year, now.month, now.day, 6, 0);
    return now.isBefore(todayAt6am)
        ? todayAt6am.subtract(const Duration(days: 1))
        : todayAt6am;
  }

  // works out the exact DateTime of tonight's prompt, handling times past midnight (e.g. a 1am prompt time should land on the next calendar day)
  DateTime _promptDateTime(DateTime nightStart, TimeOfDay t) {
    var dt = DateTime(
        nightStart.year, nightStart.month, nightStart.day, t.hour, t.minute);
    if (t.hour < 6) dt = dt.add(const Duration(days: 1));
    return dt;
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-GB');
    await _tts.setSpeechRate(0.38); 
    await _tts.setVolume(0.9);
    await _tts.setPitch(0.9);

    _tts.setStartHandler(() {
      if (mounted) setState(() => _audioState = AudioState.playing);
      // hide the status bar while audio is playing so it feels more immersive
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: [SystemUiOverlay.bottom]);
    });

    _tts.setCompletionHandler(() async {
      if (mounted) setState(() => _audioState = AudioState.finished);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      // automatically mark as done when the audio finishes playing
      await _doneForTonight(fromAudio: true);
    });

    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _audioState = AudioState.idle);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    });

    _tts.setCancelHandler(() {
      if (mounted) setState(() => _audioState = AudioState.idle);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    });
  }

  Future<void> _startListening() async {
    final p = currentPrompt;
    if (p == null) return;
    setState(() => _audioState = AudioState.playing);
    // read the title first, then a pause, then the body
    await _tts.speak('${p.title}.\n\n${p.body}');
  }

  Future<void> _pauseListening() async {
    await _tts.pause();
    if (mounted) setState(() => _audioState = AudioState.paused);
  }

  Future<void> _resumeListening() async {
    // TTS doesn't support true resume, so we restart from the body only
    await _tts.speak(currentPrompt?.body ?? '');
    if (mounted) setState(() => _audioState = AudioState.playing);
  }

  Future<void> _stopListening() async {
    await _tts.stop();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) setState(() => _audioState = AudioState.idle);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initTts();

    // poll every 5 seconds as a fallback — handles edge cases where the one-shot timer fires slightly early or the clock changes
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshPhaseFromPrefs();
    });

    _loadInitial();
  }

  @override
  void dispose() {
    _tts.stop();
    _phaseTimer?.cancel();
    _pollTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // called by AppShell when the user taps back to this tab
  void refresh() => _refreshPhaseFromPrefs();

  // re-check state whenever the app comes back to the foreground (the user might have changed settings or the prompt time might have passed)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPhaseFromPrefs();
  }

  // data loading

  Future<void> _loadInitial() async {
    final prompt = await _loadOrPickTonightPrompt();
    if (!mounted) return;
    setState(() {
      currentPrompt = prompt;
      loading = false;
    });
    await _maybeScheduleBackupTonight();
    await _refreshPhaseFromPrefs();
  }

  Future<void> _refreshPhaseFromPrefs() async {
    final t = await AppPrefs.getPromptTime();
    final p = await AppPrefs.isPaused();
    final done = await AppPrefs.isDoneForTonight(DateTime.now());
    final manualActive = await AppPrefs.isManuallyActivatedTonight(DateTime.now());

    final now = DateTime.now();
    final TimeOfDay? savedTime =
        t == null ? null : TimeOfDay(hour: t.$1, minute: t.$2);

    // check whether the prompt time has passed and we should auto-activate
    bool shouldAutoActive = false;
    if (!p && !done && savedTime != null) {
      final nightStart = _nightStart(now);
      final promptDT = _promptDateTime(nightStart, savedTime);
      shouldAutoActive = now.isAfter(promptDT);
    }

    // if a pause just expired, restore the normal repeating notification schedule
    if (!p && t != null) {
      final backupAlreadyScheduled = await AppPrefs.isBackupScheduledTonight(now);
      if (!backupAlreadyScheduled) {
        await NotificationService.instance.schedulePrimaryAndBackup(
          hour: t.$1,
          minute: t.$2,
        );
      }
    }

    if (!mounted) return;

    setState(() {
      promptTime = savedTime;
      paused = p;

      if (done) {
        phase = TonightPhase.done;
      } else if (shouldAutoActive || manualActive) {
        phase = TonightPhase.active;
      } else {
        phase = TonightPhase.waiting;
      }
    });

    // if still paused, make sure no OS notifications are queued up
    if (p) {
      await NotificationService.instance.cancelAll();
      await AppPrefs.clearBackupScheduledTonight();
    }

    _scheduleAutoSwitchIfNeeded();
    await _maybeScheduleBackupTonight();
  }

  // sets a one-shot timer to flip to active at exactly the right moment so the screen updates even if the user is already in the app
  void _scheduleAutoSwitchIfNeeded() {
    _phaseTimer?.cancel();

    if (!mounted) return;
    if (paused) return;
    if (promptTime == null) return;
    if (phase != TonightPhase.waiting) return;

    final now = DateTime.now();
    final target = _promptDateTime(_nightStart(now), promptTime!);

    if (!target.isAfter(now)) {
      // already past the time — just refresh immediately
      _refreshPhaseFromPrefs();
      return;
    }

    _phaseTimer = Timer(target.difference(now), () async {
      await _refreshPhaseFromPrefs();
    });
  }

  // backup notification scheduling

  // schedules a one-shot backup notification for tonight if we haven't already, this catches users who dismiss the primary notification without opening the app
  Future<void> _maybeScheduleBackupTonight() async {
    final now = DateTime.now();
    final done = await AppPrefs.isDoneForTonight(now);
    if (done) return;

    final alreadyScheduled = await AppPrefs.isBackupScheduledTonight(now);
    if (alreadyScheduled) return;

    final t = await AppPrefs.getPromptTime();
    if (t == null) return;

    final p = await AppPrefs.isPaused();
    if (p) return;

    await NotificationService.instance.scheduleBackupForTonight(
      hour: t.$1,
      minute: t.$2,
    );
    await AppPrefs.setBackupScheduledTonight(now);
    print('One-shot backup scheduled for tonight');
  }

  // prompt loading

  Future<PromptItem?> _loadOrPickTonightPrompt() async {
    // if we already picked one for tonight, use that — keeps it consistent
    // even if the user closes and reopens the app
    final saved = await TonightPromptStore.loadForTonight();
    if (saved != null) return PromptItem.fromJson(saved);

    // nothing saved yet — pick one, preferring prompts that match the user's goals
    final prompts = await PromptService.loadPrompts();
    if (prompts.isEmpty) return null;

    final userGoals = await AppPrefs.getGoals();
    List<PromptItem> pool = prompts;

    if (userGoals.isNotEmpty) {
      final matched = prompts
          .where((p) =>
              p.goals != null &&
              p.goals!.any((g) => userGoals.contains(g)))
          .toList();
      // only narrow the pool if we actually found matches — otherwise use everything
      if (matched.isNotEmpty) pool = matched;
    }

    final picked = pool[Random().nextInt(pool.length)];
    await TonightPromptStore.saveForTonight({
      'id': picked.id,
      'title': picked.title,
      'body': picked.body,
      'type': picked.type ?? '',
    });
    return picked;
  }

  String _fmt(TimeOfDay? t) => t == null ? 'Not set' : t.format(context);

  // user tapped "Get tonight's prompt now" before the scheduled time
  Future<void> _goActive() async {
    if (currentPrompt == null) {
      final prompt = await _loadOrPickTonightPrompt();
      if (!mounted) return;
      setState(() => currentPrompt = prompt);
    }
    await AppPrefs.setManuallyActivatedTonight(DateTime.now());
    await NotificationService.instance.onManualOpen();
    _phaseTimer?.cancel();
    setState(() {
      phase = TonightPhase.active;
      _imageryStarted = false;
    });
  }

  // marks the night as done, saves the prompt to history, and cancels any remaining notifications for tonight
  Future<void> _doneForTonight({bool fromAudio = false}) async {
    await _stopListening();
    await AppPrefs.setDoneForTonight(DateTime.now(), true);
    await AppPrefs.clearManuallyActivatedTonight(DateTime.now());
    await NotificationService.instance.cancelBackupAndRemindLater();
    _phaseTimer?.cancel();

    // save the prompt to the library — guard against saving it twice 
    final p = currentPrompt;
    if (p != null) {
      final alreadySaved = await AppPrefs.hasSavedPromptTonight(DateTime.now());
      if (!alreadySaved) {
        await PromptHistoryStore.add({
          'id': p.id,
          'title': p.title,
          'body': p.body,
          'type': p.type ?? '',
        });
        await AppPrefs.markPromptSavedTonight(DateTime.now());
      }
    }

    if (!mounted) return;
    setState(() => phase = TonightPhase.done);
  }

  // lets the user step back from the done screen in case they tapped it by mistake
  Future<void> _undoDone() async {
    await AppPrefs.setDoneForTonight(DateTime.now(), false);
    if (!mounted) return;
    _phaseTimer?.cancel();
    setState(() {
      phase = TonightPhase.active;
      _audioState = AudioState.idle;
      _imageryStarted = false;
    });
  }

  // schedules a reminder notification and shows a snackbar confirming it
  // clamps the time so we don't send notifications in the early hours of the morning
  void _remindLater(int requestedMinutes) {
    final now = DateTime.now();
    final minutes = clampRemindMinutes(now, requestedMinutes);

    if (minutes <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("It's too close to morning. No more reminders tonight.")),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Okay — I'll remind you in $minutes min.")),
    );

    NotificationService.instance.cancelBackupAndRemindLater();
    NotificationService.instance.scheduleRemindLater(minutes);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: _navy,
        body: Center(child: CircularProgressIndicator(color: _accent)),
      );
    }

    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: _navy,
        elevation: 0,
        title: const Text(
          'Tonight',
          style: TextStyle(
            color: _textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        // paused takes priority over everything else 
        child: paused ? _buildPaused() : _buildPhase(),
      ),
    );
  }

  // shown when the user has paused prompts from settings
  Widget _buildPaused() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.pause_circle_outline, size: 56, color: _textSecondary),
          const SizedBox(height: 20),
          const Text(
            'Prompts are paused.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Re-enable them in Settings whenever you\'re ready.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 32),
          OutlinedButton(
            onPressed: widget.goToSettings,
            style: OutlinedButton.styleFrom(
              foregroundColor: _accent,
              side: const BorderSide(color: _cardBorder, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Go to Settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildPhase() {
    switch (phase) {
      case TonightPhase.waiting:
        return _buildWaiting();
      case TonightPhase.active:
        // imagery prompts get a special intro screen before the text is shown
        if (currentPrompt?.type == 'imagery' && !_imageryStarted) {
          return _buildImageryReady();
        }
        return _buildActive();
      case TonightPhase.done:
        return _buildDone();
    }
  }

  // the "waiting" screen — shown before the prompt time has arrived
  Widget _buildWaiting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 40),
        Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _surface,
              border: Border.all(color: _cardBorder, width: 1.5),
            ),
            child: const Icon(Icons.bedtime, size: 44, color: _accent),
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          "TONIGHT'S PROMPT",
          textAlign: TextAlign.center,
          style: TextStyle(color: _textSecondary, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.6),
        ),
        const SizedBox(height: 8),
        Text(
          promptTime == null ? 'No time set' : 'arrives at ${_fmt(promptTime)}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _textPrimary, fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 48),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            // if no time is set, the button stays disabled until they go to settings
            onPressed: promptTime == null ? null : _goActive,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            child: const Text("Get tonight's prompt now"),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: widget.goToSettings,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: const BorderSide(color: _cardBorder, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                child: const Text('Change time'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: widget.goToSettings,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: const BorderSide(color: _cardBorder, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                child: const Text('Pause'),
              ),
            ),
          ],
        ),
        if (promptTime == null) ...[
          const SizedBox(height: 24),
          const Text(
            'Set a prompt time in Settings to begin.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _textSecondary, fontSize: 13),
          ),
        ],
      ],
    );
  }

  // special intro screen for visualisation prompts — tells the user to get comfy before the audio starts
  Widget _buildImageryReady() {
    final p = currentPrompt;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _imageryColor.withOpacity(0.1),
              border: Border.all(color: _imageryColor.withOpacity(0.3), width: 1.5),
            ),
            child: const Icon(Icons.nights_stay_outlined, size: 46, color: _imageryColor),
          ),
        ),
        const SizedBox(height: 28),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: _imageryColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _imageryColor.withOpacity(0.3), width: 1),
            ),
            child: const Text(
              '◎  Visualisation',
              style: TextStyle(color: _imageryColor, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          p?.title ?? 'Tonight\'s visualisation',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _textPrimary, fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _cardBorder, width: 1),
          ),
          child: const Column(
            children: [
              Text('This is a guided visualisation.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
              SizedBox(height: 8),
              Text(
                'Find a comfortable position, put your headphones in if you have them, and get ready to close your eyes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textSecondary, fontSize: 13, height: 1.6),
              ),
              SizedBox(height: 8),
              Text('The audio will begin when you tap Begin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _textSecondary, fontSize: 13, height: 1.6)),
            ],
          ),
        ),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: () async {
            setState(() => _imageryStarted = true);
            // small delay so the screen transition finishes before the audio kicks in
            await Future.delayed(const Duration(milliseconds: 300));
            await _startListening();
          },
          icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
          label: const Text('Begin'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _imageryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 12),
        // for users who'd rather read than listen
        TextButton(
          onPressed: () => setState(() => _imageryStarted = true),
          style: TextButton.styleFrom(foregroundColor: _textSecondary),
          child: const Text('Read instead'),
        ),
      ],
    );
  }

  // the main prompt view — shows the text, audio controls, journal button (for wind-down prompts), the done button, and snooze chips at the bottom
  Widget _buildActive() {
    final p = currentPrompt;
    final isPlaying = _audioState == AudioState.playing;
    final isPaused = _audioState == AudioState.paused;
    final isAudioActive = isPlaying || isPaused;
    final isOffloading = p?.type == 'offloading'; // wind-down prompts get a journal button
    final isImagery = p?.type == 'imagery'; // imagery prompts use purple audio controls

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 16, bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // prompt card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _cardBorder, width: 1),
            ),
            child: p == null
                ? const Center(child: CircularProgressIndicator(color: _accent))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // type badge (Story/Wind-down/Visualisation)
                          if (p.type != null && p.type!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _typeColor(p.type!).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: _typeColor(p.type!).withOpacity(0.3), width: 1),
                              ),
                              child: Text(
                                _typeLabel(p.type!),
                                style: TextStyle(fontSize: 11, color: _typeColor(p.type!), fontWeight: FontWeight.w600, letterSpacing: 0.6),
                              ),
                            ),
                          const Spacer(),
                          // audio controls — hidden for imagery when nothing is playing (they start audio from the Begin button on the intro screen instead)
                          if (!isImagery) ...[
                            if (!isAudioActive)
                              GestureDetector(
                                onTap: _startListening,
                                child: Container(
                                  width: 34, height: 34,
                                  decoration: BoxDecoration(
                                    color: _accent.withOpacity(0.12),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: _accent.withOpacity(0.3), width: 1),
                                  ),
                                  child: const Icon(Icons.record_voice_over_outlined, size: 16, color: _accent),
                                ),
                              )
                            else ...[
                              // pause/resume toggle
                              GestureDetector(
                                onTap: isPlaying ? _pauseListening : _resumeListening,
                                child: Container(
                                  width: 34, height: 34,
                                  decoration: BoxDecoration(
                                    color: _accent.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: _accent, width: 1),
                                  ),
                                  child: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 16, color: _accent),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // stop button
                              GestureDetector(
                                onTap: _stopListening,
                                child: Container(
                                  width: 34, height: 34,
                                  decoration: BoxDecoration(
                                    color: _surface,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: _cardBorder, width: 1),
                                  ),
                                  child: const Icon(Icons.stop_rounded, size: 16, color: _textSecondary),
                                ),
                              ),
                            ],
                          ],
                          // imagery audio controls use purple instead of the default accent
                          if (isImagery && isAudioActive) ...[
                            GestureDetector(
                              onTap: isPlaying ? _pauseListening : _resumeListening,
                              child: Container(
                                width: 34, height: 34,
                                decoration: BoxDecoration(
                                  color: _imageryColor.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: _imageryColor, width: 1),
                                ),
                                child: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 16, color: _imageryColor),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _stopListening,
                              child: Container(
                                width: 34, height: 34,
                                decoration: BoxDecoration(
                                  color: _surface,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: _cardBorder, width: 1),
                                ),
                                child: const Icon(Icons.stop_rounded, size: 16, color: _textSecondary),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(p.title, style: const TextStyle(color: _textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      Text(p.body, style: const TextStyle(color: Color(0xFFCCCEE4), fontSize: 15, height: 1.75)),
                    ],
                  ),
          ),

          // reassure the user their screen can go dark without stopping the audio
          if (isPlaying) ...[
            const SizedBox(height: 10),
            const Text(
              '🔊  Screen can dim or lock — audio will keep playing.',
              style: TextStyle(fontSize: 12, color: _textSecondary),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 16),

          // wind-down prompts get a shortcut to the journal
          if (isOffloading && p != null) ...[
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => JournalEditorScreen(
                    linkedPromptId: p.id,
                    linkedPromptTitle: p.title,
                  ),
                ));
              },
              icon: const Icon(Icons.edit_note_outlined, color: _accent, size: 20),
              label: const Text('Write in journal'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                side: const BorderSide(color: _cardBorder, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // hide the done button while audio is playing — it'll auto-complete when finished
          if (!isPlaying)
            ElevatedButton(
              onPressed: () => _doneForTonight(),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              child: const Text("I'm done for tonight"),
            ),

          const SizedBox(height: 20),

          // snooze chips — remind me in 15m, 30m, 1hr, 2hr
          const Text(
            'SNOOZE',
            style: TextStyle(color: _textSecondary, fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _remindChip(15),
              _remindChip(30),
              _remindChip(60),
              _remindChip(120),
            ],
          ),
        ],
      ),
    );
  }

  Widget _remindChip(int minutes) {
    final label = minutes >= 60 ? '${minutes ~/ 60}hr' : '${minutes}m';
    return GestureDetector(
      onTap: () => _remindLater(minutes),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _cardBorder, width: 1),
        ),
        child: Text(label, style: const TextStyle(color: _textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
      ),
    );
  }

  // shown after the user taps "I'm done for tonight"
  Widget _buildDone() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 96, height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _surface,
              border: Border.all(color: _cardBorder, width: 1.5),
            ),
            child: const Icon(Icons.check_rounded, size: 48, color: _accent),
          ),
        ),
        const SizedBox(height: 28),
        const Text('Done for tonight.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _textPrimary, fontSize: 22, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text('Sleep well.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _textSecondary, fontSize: 16, fontStyle: FontStyle.italic)),
        const SizedBox(height: 40),
        OutlinedButton(
          onPressed: _undoDone,
          style: OutlinedButton.styleFrom(
            foregroundColor: _accent,
            side: const BorderSide(color: _cardBorder, width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('Undo'),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: widget.goToLibrary,
          style: TextButton.styleFrom(foregroundColor: _accent),
          child: const Text('See past prompts'),
        ),
      ],
    );
  }

  // same label/colour helpers as the library screen
  String _typeLabel(String type) {
    switch (type) {
      case 'narrative': return '✦  Story';
      case 'offloading': return '✎  Wind-down';
      case 'imagery': return '◎  Visualisation';
      default: return type;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'narrative': return const Color(0xFF9FA4F0);
      case 'offloading': return const Color(0xFF6FC8B0);
      case 'imagery': return _imageryColor;
      default: return _textSecondary;
    }
  }
}