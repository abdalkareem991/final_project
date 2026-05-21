import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_text.dart';
import '../core/app_theme.dart';

class LocalNote {
  final String id;
  final String title;
  final String body;
  final DateTime updatedAt;

  const LocalNote({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory LocalNote.fromJson(Map<String, dynamic> json) {
    return LocalNote(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      updatedAt:
          DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  static const String _storageKey = 'finmind_local_notes';

  List<LocalNote> _notes = [];
  bool _isLoading = true;

  AppThemeColors get _colors => context.themeColors;
  Color get _bgColor => _colors.background;
  Color get _cardColor => _colors.surface;
  Color get _fieldColor => _colors.field;
  Color get _accentGreen => _colors.primary;
  Color get _textColor => _colors.textPrimary;
  Color get _secondaryTextColor => _colors.textSecondary;
  Color get _mutedTextColor => _colors.textMuted;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final rawItems = prefs.getStringList(_storageKey) ?? [];
    final notes =
        rawItems
            .map((raw) {
              try {
                return LocalNote.fromJson(
                  jsonDecode(raw) as Map<String, dynamic>,
                );
              } catch (_) {
                return null;
              }
            })
            .whereType<LocalNote>()
            .where((note) => note.id.isNotEmpty)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (!mounted) return;
    setState(() {
      _notes = notes;
      _isLoading = false;
    });
  }

  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _storageKey,
      _notes.map((note) => jsonEncode(note.toJson())).toList(),
    );
  }

  Future<void> _upsertNote({LocalNote? existing}) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final bodyController = TextEditingController(text: existing?.body ?? '');

    final savedNote = await showModalBottomSheet<LocalNote?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _mutedTextColor.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                existing == null
                    ? context.t("New Note", "ملاحظة جديدة")
                    : context.t("Edit Note", "تعديل الملاحظة"),
                style: TextStyle(
                  color: _textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                style: TextStyle(color: _textColor),
                decoration: _inputDecoration(
                  context.t("Title", "العنوان"),
                  Icons.title,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bodyController,
                minLines: 5,
                maxLines: 8,
                style: TextStyle(color: _textColor),
                decoration: _inputDecoration(
                  context.t("Write your note", "اكتب ملاحظتك"),
                  Icons.notes,
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () {
                  final title = titleController.text.trim();
                  final body = bodyController.text.trim();
                  if (title.isEmpty && body.isEmpty) {
                    Navigator.pop(sheetContext, null);
                    return;
                  }

                  final note = LocalNote(
                    id:
                        existing?.id ??
                        DateTime.now().microsecondsSinceEpoch.toString(),
                    title: title.isEmpty
                        ? context.t("Untitled Note", "ملاحظة بدون عنوان")
                        : title,
                    body: body,
                    updatedAt: DateTime.now(),
                  );

                  Navigator.pop(sheetContext, note);
                },
                icon: Icon(Icons.save_outlined, color: _colors.onPrimary),
                label: Text(
                  context.t("Save Note", "حفظ الملاحظة"),
                  style: TextStyle(
                    color: _colors.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentGreen,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    titleController.dispose();
    bodyController.dispose();

    if (savedNote != null) {
      if (!mounted) return;

      setState(() {
        final index = _notes.indexWhere((item) => item.id == savedNote.id);
        if (index == -1) {
          _notes.insert(0, savedNote);
        } else {
          _notes[index] = savedNote;
        }
        _notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      });

      try {
        await _saveNotes();
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.t(
                "Could not save the note locally.",
                "تعذر حفظ الملاحظة على الجهاز.",
              ),
            ),
            backgroundColor: _colors.expense,
          ),
        );
      }
    }
  }

  Future<void> _deleteNote(LocalNote note) async {
    final previous = List<LocalNote>.from(_notes);
    setState(() {
      _notes.removeWhere((item) => item.id == note.id);
    });

    try {
      await _saveNotes();
    } catch (_) {
      if (!mounted) return;
      setState(() => _notes = previous);
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: _mutedTextColor),
      prefixIcon: Icon(icon, color: _accentGreen),
      filled: true,
      fillColor: _fieldColor,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _colors.subtleBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _accentGreen),
      ),
    );
  }

  String _formatUpdatedAt(DateTime date) {
    final local = date.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return "${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hour:$minute $period";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        title: Text(
          context.t("Notes", "الملاحظات"),
          style: TextStyle(color: _textColor, fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _accentGreen))
          : _notes.isEmpty
          ? _buildEmptyState()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
              itemBuilder: (context, index) => _buildNoteCard(_notes[index]),
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemCount: _notes.length,
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'notes_add_btn',
        backgroundColor: _accentGreen,
        onPressed: () => _upsertNote(),
        child: Icon(Icons.add, color: _colors.onPrimary),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.note_alt_outlined, color: _accentGreen, size: 46),
            const SizedBox(height: 12),
            Text(
              context.t("No notes yet", "لا توجد ملاحظات بعد"),
              style: TextStyle(
                color: _textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.t(
                "Your notes stay on this device only.",
                "ملاحظاتك تبقى محفوظة على هذا الجهاز فقط.",
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: _mutedTextColor, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteCard(LocalNote note) {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _colors.subtleBorder),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        onTap: () => _upsertNote(existing: note),
        title: Text(
          note.title,
          style: TextStyle(
            color: _textColor,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (note.body.isNotEmpty)
                Text(
                  note.body,
                  style: TextStyle(color: _secondaryTextColor, fontSize: 13),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 6),
              Text(
                _formatUpdatedAt(note.updatedAt),
                style: TextStyle(color: _mutedTextColor, fontSize: 11),
              ),
            ],
          ),
        ),
        trailing: IconButton(
          tooltip: context.t("Delete", "حذف"),
          onPressed: () => _deleteNote(note),
          icon: Icon(Icons.delete_outline, color: _colors.expense),
        ),
      ),
    );
  }
}
