import 'package:flutter/material.dart';
import '../storage/journal_store.dart';
import '../storage/prompt_history_store.dart';
import 'library_screen.dart';

// same palette as the rest of the app
const _navy = Color(0xFF0D0F1C);
const _surface = Color(0xFF161829);
const _accent = Color(0xFF7B82E8);
const _cardBorder = Color(0xFF2E3156);
const _textPrimary = Color(0xFFE8E9F3);
const _textSecondary = Color(0xFF8B8FA8);

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  List<JournalEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // initial load — shows spinner until we have data
  Future<void> _load() async {
    final entries = await JournalStore.getAll();
    if (mounted) setState(() { _entries = entries; _loading = false; });
  }

  // silent refresh after returning from the editor, no spinner needed
  Future<void> _reload() async {
    final entries = await JournalStore.getAll();
    if (mounted) setState(() => _entries = entries);
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(date).inDays;

    // build a readable time string like "3:04 PM"
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final time = '$hour:$minute $ampm';

    if (diffDays == 0) return 'Today, $time';
    if (diffDays == 1) return 'Yesterday, $time';

    // anything older just gets a short month + day
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, $time';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: _navy,
        elevation: 0,
        title: const Text(
          'Journal',
          style: TextStyle(
              color: _textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const JournalEditorScreen(),
                ));
                // reload once the editor pops so the list reflects any new entry
                await _reload();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: _accent.withOpacity(0.3), width: 1),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 14, color: _accent),
                    SizedBox(width: 6),
                    Text('New entry',
                        style: TextStyle(
                            color: _accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.edit_note_outlined,
                            size: 52, color: _textSecondary),
                        const SizedBox(height: 16),
                        const Text(
                          'Nothing written yet.',
                          style: TextStyle(
                              color: _textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Tap "New entry" to write freely.',
                          style: TextStyle(
                              color: _textSecondary,
                              fontSize: 13,
                              height: 1.5),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  itemCount: _entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final entry = _entries[i];
                    // truncate long entries so the card stays a reasonable height
                    final preview = entry.body.length > 80
                        ? '${entry.body.substring(0, 80)}...'
                        : entry.body;

                    return GestureDetector(
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              JournalEditorScreen(existing: entry),
                        ));
                        await _reload();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _cardBorder, width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                // only shown if the entry was linked to a prompt
                                if (entry.promptTitle != null) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: _accent.withOpacity(0.12),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      border: Border.all(
                                          color: _accent.withOpacity(0.25),
                                          width: 1),
                                    ),
                                    child: Text(
                                      entry.promptTitle!,
                                      style: const TextStyle(
                                          color: _accent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                // date pushes right when there's a badge, left otherwise
                                Expanded(
                                  child: Text(
                                    _formatDate(entry.date),
                                    style: const TextStyle(
                                        color: _textSecondary,
                                        fontSize: 11),
                                    textAlign: entry.promptTitle != null
                                        ? TextAlign.right
                                        : TextAlign.left,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              preview.isEmpty ? 'Empty entry' : preview,
                              style: TextStyle(
                                color: preview.isEmpty
                                    ? _textSecondary
                                    : const Color(0xFFCCCEE4),
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}


class JournalEditorScreen extends StatefulWidget {
  final JournalEntry? existing; // null = new entry
  final String? linkedPromptId;
  final String? linkedPromptTitle;
  final VoidCallback? onSaved;       

  const JournalEditorScreen({
    super.key,
    this.existing,
    this.linkedPromptId,
    this.linkedPromptTitle,
    this.onSaved,
  });

  @override
  State<JournalEditorScreen> createState() => _JournalEditorScreenState();
}

class _JournalEditorScreenState extends State<JournalEditorScreen> {
  late TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // pre-fill with existing text if we're editing, empty string if new
    _controller = TextEditingController(text: widget.existing?.body ?? '');
    // keeps the Save button grey when the field is empty, purple once you've typed something
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);

    // preserve the original id and date if editing — only overwrite the body
    final entry = JournalEntry(
      id: widget.existing?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      date: widget.existing?.date ?? DateTime.now(),
      body: text,
      promptId: widget.existing?.promptId ?? widget.linkedPromptId,
      promptTitle: widget.existing?.promptTitle ?? widget.linkedPromptTitle,
    );

    await JournalStore.save(entry);

    if (mounted) {
      Navigator.of(context).pop();
      widget.onSaved?.call();
    }
  }

  Future<void> _delete() async {
    if (widget.existing == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Delete entry?',
            style: TextStyle(color: _textPrimary)),
        content: const Text('This cannot be undone.',
            style: TextStyle(color: _textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: _textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await JournalStore.delete(widget.existing!.id);

    if (mounted) {
      Navigator.of(context).pop();
      widget.onSaved?.call();
    }
  }

  // tapping the linked-prompt banner navigates to its detail screen
  Future<void> _openLinkedPrompt() async {
    final promptId = widget.existing?.promptId ?? widget.linkedPromptId;
    if (promptId == null) return;

    // the linked prompt might have been deleted since — if so, do nothing
    final history = await PromptHistoryStore.load();
    final match = history.firstWhere(
      (p) => p['id'] == promptId,
      orElse: () => <String, dynamic>{},
    );

    if (!mounted) return;
    if (match.isNotEmpty) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PromptDetailScreen(
          title: match['title'] as String? ??
              (widget.existing?.promptTitle ?? widget.linkedPromptTitle ?? ''),
          body:     match['body'] as String? ?? '',
          promptId: match['id']  as String?,
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    final linkedTitle = widget.existing?.promptTitle ?? widget.linkedPromptTitle;
    // Save button stays grey until there's something worth saving
    final canSave = !_saving && _controller.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: _navy,
        elevation: 0,
        iconTheme: const IconThemeData(color: _textPrimary),
        title: Text(
          isEditing ? 'Edit entry' : 'New entry',
          style: const TextStyle(
              color: _textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600),
        ),
        actions: [
          if (isEditing)
            IconButton(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: 'Delete',
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _saving
                  ? null
                  : () async {
                      if (_controller.text.trim().isEmpty) return;
                      await _save();
                    },
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _accent))
                  : Text(
                      'Save',
                      style: TextStyle(
                        color: canSave ? _accent : _textSecondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // linked prompt banner — tappable, only rendered when relevant
            if (linkedTitle != null) ...[
              GestureDetector(
                onTap: _openLinkedPrompt,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: _accent.withOpacity(0.3), width: 1.5),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.link_outlined,
                          size: 14, color: _accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Linked to: $linkedTitle',
                          style: const TextStyle(
                              color: _accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded,
                          size: 11, color: _accent),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // the actual writing area, expands to fill remaining space
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                autofocus: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 16,
                  height: 1.7,
                ),
                decoration: const InputDecoration(
                  hintText: 'Write whatever is on your mind...',
                  hintStyle:
                      TextStyle(color: _textSecondary, fontSize: 15),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                cursorColor: _accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}