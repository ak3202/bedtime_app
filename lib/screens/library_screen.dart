import 'package:flutter/material.dart';
import '../storage/prompt_history_store.dart';
import 'journal_screen.dart';
import '../storage/journal_store.dart';

// same palette as the rest of the app
const _navy = Color(0xFF0D0F1C);
const _surface = Color(0xFF161829);
const _accent = Color(0xFF7B82E8);
const _cardBorder = Color(0xFF2E3156);
const _textPrimary = Color(0xFFE8E9F3);
const _textSecondary = Color(0xFF8B8FA8);

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Map<String, dynamic>> _all = []; // every prompt the user has ever completed
  List<Map<String, dynamic>> _filtered = []; // what's currently visible based on the active filter
  bool _loading = true;
  String _activeFilter = 'all';

  // the filter chips at the top of the screen — order here is the order they appear
  static const _filters = [
    {'id': 'all', 'label': 'All'},
    {'id': 'narrative', 'label': 'Story'},
    {'id': 'offloading', 'label': 'Wind-down'},
    {'id': 'imagery', 'label': 'Visualisation'},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await PromptHistoryStore.load();
    if (mounted) {
      setState(() {
        _all = items;
        _loading = false;
      });
      _applyFilter(_activeFilter);
    }
  }

  // called whenever the user taps a filter chip
  void _applyFilter(String filterId) {
    setState(() {
      _activeFilter = filterId;
      if (filterId == 'all') {
        _filtered = List.from(_all);
      } else {
        // only show prompts that match the selected type
        _filtered = _all
            .where((p) => (p['type'] as String? ?? '') == filterId)
            .toList();
      }
    });
  }

  // same date formatting as the journal screen — "Today", "Yesterday", or "Jan 5"
  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(local.year, local.month, local.day);
    final diffDays = today.difference(date).inDays;

    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    final time = '$hour:$minute $ampm';

    if (diffDays == 0) return 'Today, $time';
    if (diffDays == 1) return 'Yesterday, $time';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[local.month - 1]} ${local.day}, $time';
  }

  // the little badge text shown on each card, e.g. "✦  Story"
  String _typeLabel(String type) {
    switch (type) {
      case 'narrative': return '✦  Story';
      case 'offloading': return '✎  Wind-down';
      case 'imagery': return '◎  Visualisation';
      default: return '';
    }
  }

  // each prompt type gets its own colour so they're easy to tell apart at a glance
  Color _typeColor(String type) {
    switch (type) {
      case 'narrative': return const Color(0xFF9FA4F0); // blue-purple
      case 'offloading': return const Color(0xFF6FC8B0); // teal
      case 'imagery': return const Color(0xFFB48EE8); // soft purple
      default: return _textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: _navy,
        elevation: 0,
        title: const Text(
          'Library',
          style: TextStyle(
            color: _textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // horizontally scrollable filter chips — All/Story/Wind-down/Visualisation
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                    itemCount: _filters.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final f = _filters[i];
                      final id = f['id']!;
                      final label = f['label']!;
                      final isSelected = _activeFilter == id;

                      // the little number badge next to the label, e.g. "Story  3"
                      final count = id == 'all'
                          ? _all.length
                          : _all
                              .where((p) =>
                                  (p['type'] as String? ?? '') == id)
                              .length;

                      return GestureDetector(
                        onTap: () => _applyFilter(id),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? _accent.withOpacity(0.18)
                                : _surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? _accent : _cardBorder,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                label,
                                style: TextStyle(
                                  color: isSelected
                                      ? _accent
                                      : _textSecondary,
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                              // only show the count badge if there's actually something to count
                              if (count > 0) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? _accent.withOpacity(0.25)
                                        : _cardBorder.withOpacity(0.5),
                                    borderRadius:
                                        BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$count',
                                    style: TextStyle(
                                      color: isSelected
                                          ? _accent
                                          : _textSecondary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 4),

                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.book_outlined,
                                  size: 48, color: _textSecondary),
                              const SizedBox(height: 16),
                              Text(
                                // slightly different message depending on whether
                                // they have prompts but filtered them all out or genuinely have none
                                _activeFilter == 'all'
                                    ? 'No past prompts yet.'
                                    : _activeFilter == 'narrative'
                                        ? 'No Story prompts yet.'
                                        : _activeFilter == 'offloading'
                                            ? 'No Wind-down prompts yet.'
                                            : 'No Visualisation prompts yet.',
                                style: const TextStyle(
                                    color: _textSecondary, fontSize: 15),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _activeFilter == 'all'
                                    ? 'Complete tonight\'s prompt to see it here.'
                                    : _activeFilter == 'narrative'
                                        ? 'Story prompts you\'ve completed will appear here.'
                                        : _activeFilter == 'offloading'
                                            ? 'Wind-down prompts you\'ve completed will appear here.'
                                            : 'Visualisation prompts you\'ve completed will appear here.',
                                style: const TextStyle(
                                    color: _textSecondary, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding:
                              const EdgeInsets.fromLTRB(16, 8, 16, 32),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final p = _filtered[i];
                            final title = (p['title'] ?? 'Prompt') as String;
                            final body = (p['body'] ?? '') as String;
                            final type = (p['type'] ?? '') as String;
                            final rawDate = p['savedAt'] as String?;
                            // savedAt comes back as a string from storage, so parse it
                            final savedAt = rawDate == null
                                ? null
                                : DateTime.tryParse(rawDate);

                            return GestureDetector(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => PromptDetailScreen(
                                    title: title,
                                    body: body,
                                    promptId: p['id'] as String?,
                                  ),
                                ),
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: _surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: _cardBorder, width: 1),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (type.isNotEmpty) ...[
                                            Container(
                                              margin: const EdgeInsets
                                                  .only(bottom: 6),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3),
                                              decoration: BoxDecoration(
                                                color: _typeColor(type)
                                                    .withOpacity(0.12),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                    color: _typeColor(type)
                                                        .withOpacity(0.3),
                                                    width: 1),
                                              ),
                                              child: Text(
                                                _typeLabel(type),
                                                style: TextStyle(
                                                  color: _typeColor(type),
                                                  fontSize: 10,
                                                  fontWeight:
                                                      FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                          Text(
                                            title,
                                            style: const TextStyle(
                                              color: _textPrimary,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (savedAt != null) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              _formatDate(savedAt),
                                              style: const TextStyle(
                                                color: _textSecondary,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right,
                                        color: _textSecondary, size: 20),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}


class PromptDetailScreen extends StatefulWidget {
  final String title;
  final String body;
  final String? promptId;

  const PromptDetailScreen({
    super.key,
    required this.title,
    required this.body,
    this.promptId,
  });

  @override
  State<PromptDetailScreen> createState() => _PromptDetailScreenState();
}

class _PromptDetailScreenState extends State<PromptDetailScreen> {
  // if the user already wrote a journal entry for this prompt, we show it below
  JournalEntry? _journalEntry;

  @override
  void initState() {
    super.initState();
    _loadJournalEntry();
  }

  Future<void> _loadJournalEntry() async {
    if (widget.promptId == null) return;
    final entry = await JournalStore.getForPrompt(widget.promptId!);
    if (mounted) setState(() => _journalEntry = entry);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: _navy,
        elevation: 0,
        iconTheme: const IconThemeData(color: _textPrimary),
        title: Text(
          widget.title,
          style: const TextStyle(
              color: _textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // the full prompt text
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _cardBorder, width: 1),
              ),
              child: Text(
                widget.body,
                style: const TextStyle(
                  color: Color(0xFFCCCEE4),
                  fontSize: 15,
                  height: 1.75,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // if there's a journal entry linked to this prompt, show it so the user can read or edit it — otherwise show a button to write one
            if (_journalEntry != null) ...[
              const Text(
                'YOUR JOURNAL ENTRY',
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 10,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => JournalEditorScreen(
                      existing: _journalEntry,
                      // reload after they save so the updated text shows immediately
                      onSaved: _loadJournalEntry,
                    ),
                  ));
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: _accent.withOpacity(0.2), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _journalEntry!.body,
                        style: const TextStyle(
                          color: Color(0xFFCCCEE4),
                          fontSize: 14,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Tap to edit',
                        style: TextStyle(
                            color: _accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // no journal entry yet — invite them to write one
              OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => JournalEditorScreen(
                      linkedPromptId: widget.promptId,
                      linkedPromptTitle: widget.title,
                      onSaved: _loadJournalEntry,
                    ),
                  ));
                },
                icon: const Icon(Icons.edit_note_outlined, color: _accent),
                label: const Text('Add a journal entry'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: const BorderSide(color: _cardBorder, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}