import 'package:flutter/material.dart';
import 'tonight_screen.dart';
import 'library_screen.dart';
import 'journal_screen.dart';
import 'settings_screen.dart';

// core app colors defined here
const _navy = Color(0xFF0D0F1C);
const _surface = Color(0xFF161829); // slightly lighter than navy for surfaces
const _accent = Color(0xFF7B82E8); // purple-ish, used for selected nav items
const _textSecondary = Color(0xFF8B8FA8);

class AppShell extends StatefulWidget {
  final void Function(String size)? onTextSizeChanged;
  final String textSize;

  const AppShell({
    super.key,
    this.onTextSizeChanged,
    this.textSize = 'medium',
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  // we need a key for TonightScreen so we can call refresh() on it directly
  final GlobalKey<TonightScreenState> _tonightKey =
      GlobalKey<TonightScreenState>();

  // shortcuts passed down to child screens that need to trigger navigation
  void _goToSettings() => setState(() => _currentIndex = 3);
  void _goToLibrary() => setState(() => _currentIndex = 1);

  // tells tonight screen to re-check the schedule (called after settings change or when the user taps back to the tonight tab)
  void _refreshTonight() {
    // addPostFrameCallback so the key's state is guaranteed to exist by the time it is called
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tonightKey.currentState?.refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    // keeping pages inside build so settings props stay in sync
    // (if this becomes a perf issue we can memoize, but it's fine for now)
    final pages = [
      TonightScreen(
        key: _tonightKey,
        goToSettings: _goToSettings,
        goToLibrary: _goToLibrary,
      ),
      const LibraryScreen(),
      const JournalScreen(),
      SettingsScreen(
        onScheduleChanged: _refreshTonight,
        onTextSizeChanged: widget.onTextSizeChanged,
        textSize: widget.textSize,
      ),
    ];

    return Scaffold(
      backgroundColor: _navy,
      body: pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        backgroundColor: _surface,
        indicatorColor: _accent.withOpacity(0.2),
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          setState(() => _currentIndex = i);
          // refresh tonight data whenever we land back on that tab
          if (i == 0) _refreshTonight();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bedtime_outlined, color: _textSecondary),
            selectedIcon: Icon(Icons.bedtime, color: _accent),
            label: 'Tonight',
          ),
          NavigationDestination(
            icon: Icon(Icons.book_outlined, color: _textSecondary),
            selectedIcon: Icon(Icons.book, color: _accent),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_note_outlined, color: _textSecondary),
            selectedIcon: Icon(Icons.edit_note, color: _accent),
            label: 'Journal',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined, color: _textSecondary),
            selectedIcon: Icon(Icons.settings, color: _accent),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}