import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'data/note_database.dart';
import 'services/backup_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final licenseText = await rootBundle.loadString(
      'assets/fonts/NithyaRanjana-OFL.txt',
    );
    yield LicenseEntryWithLineBreaks(['Nithya Ranjana'], licenseText);
    final phosphorLicenseText = await rootBundle.loadString(
      'assets/PHOSPHOR-LICENSE.txt',
    );
    yield LicenseEntryWithLineBreaks(['Phosphor Icons'], phosphorLicenseText);
  });
  runApp(const LipihApp());
}

class LipihApp extends StatefulWidget {
  const LipihApp({super.key});

  @override
  State<LipihApp> createState() => _LipihAppState();
}

class _LipihAppState extends State<LipihApp> {
  ThemeMode themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final preferences = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        themeMode = preferences.getBool('dark_mode') == false
            ? ThemeMode.light
            : ThemeMode.dark;
      });
    }
  }

  Future<void> _toggleTheme() async {
    final isDark = themeMode == ThemeMode.dark;
    setState(() => themeMode = isDark ? ThemeMode.light : ThemeMode.dark);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('dark_mode', !isDark);
  }

  @override
  Widget build(BuildContext context) {
    final lightScheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xff1c1c1c),
          brightness: Brightness.light,
          surface: const Color(0xffded9cc),
        ).copyWith(
          primary: const Color(0xff1c1c1c),
          onPrimary: const Color(0xffffffff),
          onSurface: const Color(0xff161616),
          onSurfaceVariant: const Color(0xff5f5d59),
          outline: const Color(0xffc5c0b5),
          outlineVariant: const Color(0xffc5c0b5),
          surfaceContainerLowest: const Color(0xffded9cc),
          surfaceContainerLow: const Color(0xffded9cc),
          surfaceContainer: const Color(0xffded9cc),
          surfaceContainerHigh: const Color(0xffded9cc),
          surfaceContainerHighest: const Color(0xffded9cc),
        );
    final darkScheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xfff2f1ec),
          brightness: Brightness.dark,
          surface: const Color(0xff292929),
        ).copyWith(
          primary: const Color(0xfff2f1ec),
          onPrimary: const Color(0xff111111),
          onSurface: const Color(0xfff2f1ec),
          onSurfaceVariant: const Color(0xffb8b7b2),
          outline: const Color(0xff555555),
          outlineVariant: const Color(0xff555555),
          surfaceContainerLowest: const Color(0xff292929),
          surfaceContainerLow: const Color(0xff292929),
          surfaceContainer: const Color(0xff292929),
          surfaceContainerHigh: const Color(0xff292929),
          surfaceContainerHighest: const Color(0xff292929),
        );
    return MaterialApp(
      title: 'Lipih',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: _theme(lightScheme, Brightness.light),
      darkTheme: _theme(darkScheme, Brightness.dark),
      home: NotesWorkspace(onToggleTheme: _toggleTheme),
    );
  }

  ThemeData _theme(ColorScheme scheme, Brightness brightness) {
    final gotuFamily = GoogleFonts.gotu().fontFamily;
    final baseTextTheme = brightness == Brightness.light
        ? Typography.material2021().black
        : Typography.material2021().white;
    final gotuTextTheme = baseTextTheme.apply(
      fontFamily: gotuFamily,
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    return ThemeData(
      colorScheme: scheme,
      brightness: brightness,
      useMaterial3: true,
      fontFamily: gotuFamily,
      textTheme: gotuTextTheme,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: brightness == Brightness.dark
            ? const Color(0xffffa941)
            : const Color(0xff1c1c1c),
        selectionColor: scheme.primary.withValues(alpha: 0.3),
        selectionHandleColor: brightness == Brightness.dark
            ? const Color(0xffffa941)
            : const Color(0xff1c1c1c),
      ),
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xffe8e3d6)
          : const Color(0xff111111),
      dividerColor: scheme.outline,
      appBarTheme: AppBarTheme(
        backgroundColor: brightness == Brightness.light
            ? const Color(0xffe8e3d6)
            : const Color(0xff111111),
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class NotesWorkspace extends StatefulWidget {
  const NotesWorkspace({super.key, required this.onToggleTheme});

  final VoidCallback onToggleTheme;

  @override
  State<NotesWorkspace> createState() => _NotesWorkspaceState();
}

class _NotesWorkspaceState extends State<NotesWorkspace> {
  final NoteDatabase database = NoteDatabase();
  final BackupService backupService = BackupService();
  final TextEditingController titleController = TextEditingController();
  final TextEditingController bodyController = TextEditingController();
  final FocusNode titleFocusNode = FocusNode();
  final FocusNode bodyFocusNode = FocusNode();
  Timer? autosaveTimer;
  Future<void> _saveQueue = Future<void>.value();

  List<Note> notes = const [];
  Note? selectedNote;
  bool isLoading = true;
  Object? loadError;
  bool isSaving = false;
  int pendingSaves = 0;
  bool isPreviewVisible = false;
  bool isSidebarVisible = false;
  final Set<int> selectedForBackup = <int>{};

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  @override
  void dispose() {
    titleController.dispose();
    bodyController.dispose();
    titleFocusNode.dispose();
    bodyFocusNode.dispose();
    autosaveTimer?.cancel();
    database.close();
    super.dispose();
  }

  Future<void> _loadNotes({int? selectId}) async {
    try {
      final loadedNotes = await database.listNotes();
      if (!mounted) return;
      setState(() {
        notes = loadedNotes;
        isLoading = false;
        loadError = null;
      });
      if (loadedNotes.isNotEmpty) {
        final nextNote = loadedNotes.firstWhere(
          (note) => note.id == selectId,
          orElse: () =>
              selectedNote != null &&
                  loadedNotes.any((note) => note.id == selectedNote!.id)
              ? loadedNotes.firstWhere((note) => note.id == selectedNote!.id)
              : loadedNotes.first,
        );
        _selectNote(nextNote);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        loadError = error;
      });
    }
  }

  Future<void> _retryLoadingNotes() async {
    setState(() {
      isLoading = true;
      loadError = null;
    });
    await _loadNotes();
  }

  void _selectNote(Note note) {
    final previousNote = selectedNote;
    if (previousNote?.id == note.id) return;
    autosaveTimer?.cancel();
    if (previousNote != null) {
      final title = titleController.text.trim();
      if (title != previousNote.title ||
          bodyController.text != previousNote.body) {
        unawaited(
          _saveNote(
            noteToSave: previousNote,
            titleToSave: title,
            bodyToSave: bodyController.text,
          ),
        );
      }
    }
    setState(() => selectedNote = note);
    titleController.value = TextEditingValue(text: note.title);
    bodyController.value = TextEditingValue(text: note.body);
  }

  Future<void> _createNote() async {
    final note = await database.createNote();
    await _loadNotes(selectId: note.id);
    bodyFocusNode.requestFocus();
  }

  Future<void> _saveNote({
    Note? noteToSave,
    String? titleToSave,
    String? bodyToSave,
  }) async {
    final note = noteToSave ?? selectedNote;
    if (note == null) return;
    final title = (titleToSave ?? titleController.text).trim();
    final body = bodyToSave ?? bodyController.text;
    if (mounted) {
      setState(() {
        pendingSaves++;
        isSaving = true;
      });
    }
    final save = _saveQueue.then(
      (_) => database.updateNote(note.id, title, body),
    );
    _saveQueue = save.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    try {
      await save;
      final updatedAt = DateTime.now();
      if (!mounted) return;
      setState(() {
        notes = [
          Note(id: note.id, title: title, body: body, updatedAt: updatedAt),
          ...notes.where((item) => item.id != note.id),
        ];
        if (selectedNote?.id == note.id) {
          selectedNote = Note(
            id: note.id,
            title: title,
            body: body,
            updatedAt: updatedAt,
          );
        }
      });
      final currentTitle = titleController.text.trim();
      if (selectedNote?.id == note.id &&
          (currentTitle != title || bodyController.text != body)) {
        _scheduleAutosave();
      }
    } catch (error) {
      if (mounted) {
        _showMessage('Unable to save note: $error');
      }
    } finally {
      if (mounted) {
        setState(() {
          pendingSaves--;
          isSaving = pendingSaves > 0;
        });
      }
    }
  }

  void _scheduleAutosave() {
    autosaveTimer?.cancel();
    autosaveTimer = Timer(const Duration(milliseconds: 500), _saveNote);
  }

  void _handleNoteChanged({bool refreshPreview = false}) {
    _scheduleAutosave();
    if (isSidebarVisible || refreshPreview) {
      setState(() => isSidebarVisible = false);
    }
  }

  void _toggleSidebar() {
    if (!isSidebarVisible) {
      titleFocusNode.unfocus();
      bodyFocusNode.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
    }
    setState(() => isSidebarVisible = !isSidebarVisible);
  }

  Future<void> _shareSelectedNote() async {
    final note = selectedNote;
    if (note == null) return;
    await SharePlus.instance.share(
      ShareParams(
        title: titleController.text.trim().isEmpty
            ? note.title
            : titleController.text.trim(),
        subject: titleController.text.trim().isEmpty
            ? note.title
            : titleController.text.trim(),
        text: bodyController.text,
      ),
    );
  }

  Future<void> _deleteNote(Note note) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete note?'),
        content: Text(
          '“${note.title.isEmpty ? 'Untitled note' : note.title}” will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;
    autosaveTimer?.cancel();
    await _saveQueue;
    await database.deleteNote(note.id);
    if (!mounted) return;
    selectedForBackup.remove(note.id);
    if (selectedNote?.id == note.id) {
      selectedNote = null;
      titleController.clear();
      bodyController.clear();
      FocusScope.of(context).unfocus();
    }
    await _loadNotes();
  }

  Future<void> _exportSelected() async {
    final exportNotes = notes
        .where((note) => selectedForBackup.contains(note.id))
        .toList();
    if (exportNotes.isEmpty && selectedNote != null) {
      exportNotes.add(selectedNote!);
    }
    final exported = await backupService.exportNotes(exportNotes);
    if (mounted && exported) _showMessage('Backup exported successfully');
  }

  Future<void> _restoreNotes() async {
    final importedNotes = await backupService.importNotes();
    for (final importedNote in importedNotes) {
      await database.createNote(importedNote.title, importedNote.body);
    }
    if (importedNotes.isNotEmpty) {
      await _loadNotes();
      if (mounted) _showMessage('${importedNotes.length} notes restored');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showAbout() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lipih'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(packageInfo.version),
            const SizedBox(height: 20),
            const Text('A focused markdown notes workspace.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).push(
                MaterialPageRoute<void>(
                  builder: (_) => const _OpenSourceLicensesPage(),
                ),
              );
            },
            child: const Text('View licenses'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _insertMarkdown(String prefix, [String suffix = '']) {
    final value = bodyController.value;
    final start = value.selection.start < 0
        ? value.text.length
        : value.selection.start;
    final end = value.selection.end < 0 ? start : value.selection.end;
    final selectedText = value.text.substring(start, end);
    final replacement = '$prefix$selectedText$suffix';
    final newText = value.text.replaceRange(start, end, replacement);
    bodyController.value = value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    bodyFocusNode.requestFocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBackground = Theme.of(context).scaffoldBackgroundColor;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: scaffoldBackground,
        systemNavigationBarDividerColor: scaffoldBackground,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        body: SafeArea(
          maintainBottomViewPadding: true,
          child: SizedBox.expand(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : loadError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Unable to load notes.'),
                          const SizedBox(height: 8),
                          Text('$loadError', textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _retryLoadingNotes,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 960;
                      final keyboardVisible =
                          MediaQuery.viewInsetsOf(context).bottom > 0;
                      final isAndroid =
                          defaultTargetPlatform == TargetPlatform.android;
                      final showPreview =
                          isPreviewVisible &&
                          (isAndroid || isWide) &&
                          !keyboardVisible;
                      final isSideBySide = isAndroid
                          ? MediaQuery.orientationOf(context) ==
                                Orientation.landscape
                          : isWide;
                      final sidebarWidth = isSidebarVisible
                          ? (isWide ? 310.0 : 260.0)
                          : 0.0;
                      final editorLeft = isWide ? sidebarWidth : 0.0;
                      return Stack(
                        children: [
                          Positioned.fill(
                            left: editorLeft,
                            child: ClipRect(
                              child: ColoredBox(
                                color: Theme.of(context)
                                    .scaffoldBackgroundColor,
                                child: _buildEditorArea(
                                  showPreview,
                                  isSideBySide,
                                ),
                              ),
                            ),
                          ),
                          if (isSidebarVisible)
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: isWide
                                  ? sidebarWidth
                                  : sidebarWidth.clamp(
                                      0.0,
                                      constraints.maxWidth * 0.85,
                                    ),
                              child: _buildSidebar(isWide),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(bool isWide) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 460;
        return Container(
          width: isWide ? 310 : 260,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            border: Border(
              right: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: compact
              ? SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildSidebarHeader(compact: true),
                      _buildNewNoteButton(compact: true),
                      const SizedBox(height: 8),
                      _buildNotesHeader(),
                      const SizedBox(height: 4),
                      for (final note in notes) _buildNoteTile(note),
                      _buildSidebarFooter(compact: true),
                    ],
                  ),
                )
              : Column(
                  children: [
                    _buildSidebarHeader(),
                    _buildNewNoteButton(),
                    const SizedBox(height: 18),
                    _buildNotesHeader(),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        itemCount: notes.length,
                        itemBuilder: (context, index) =>
                            _buildNoteTile(notes[index]),
                      ),
                    ),
                    _buildSidebarFooter(),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildSidebarHeader({bool compact = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(22, compact ? 4 : 20, 14, compact ? 0 : 12),
      child: Row(
        children: [
          SvgPicture.asset('assets/pen-nib-fill.svg', width: 26, height: 26),
          Text(
            'लिपि:',
            style: const TextStyle(
              fontFamily: 'NithyaRanjana',
              fontSize: 28,
              color: Color(0xffff9933),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _showAbout,
            tooltip: 'Help and about',
            icon: const Icon(LucideIcons.circleHelp),
          ),
          IconButton(
            onPressed: widget.onToggleTheme,
            tooltip: 'Toggle light and dark mode',
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? LucideIcons.sun
                  : LucideIcons.moon,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewNoteButton({bool compact = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: FilledButton.icon(
        onPressed: _createNote,
        icon: const Icon(LucideIcons.plus),
        label: const Text('New note'),
        style: FilledButton.styleFrom(
          minimumSize: Size.fromHeight(compact ? 36 : 44),
        ),
      ),
    );
  }

  Widget _buildNotesHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          Text(
            'NOTES',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(letterSpacing: 1.5, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(
            '${notes.length}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarFooter({bool compact = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        Padding(
          padding: EdgeInsets.fromLTRB(
            14,
            compact ? 4 : 10,
            14,
            compact ? 4 : 14,
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exportSelected,
                  icon: const Icon(LucideIcons.archive, size: 18),
                  label: const Text('Backup'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _restoreNotes,
                tooltip: 'Restore notes from ZIP',
                icon: const Icon(LucideIcons.archiveRestore),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNoteTile(Note note) {
    final isSelected = selectedNote?.id == note.id;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          selected: isSelected,
          selectedTileColor: Theme.of(context).colorScheme.primary
              .withValues(alpha: 0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          onTap: () => _selectNote(note),
          onLongPress: () => _deleteNote(note),
          leading: Checkbox(
            value: selectedForBackup.contains(note.id),
            onChanged: (value) => setState(
              () => value == true
                  ? selectedForBackup.add(note.id)
                  : selectedForBackup.remove(note.id),
            ),
          ),
          title: Text(
            note.title.isEmpty ? 'Untitled note' : note.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(_relativeDate(note.updatedAt), maxLines: 1),
        ),
      ),
    );
  }

  String _relativeDate(DateTime date) {
    final difference = DateTime.now().difference(date);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    if (difference.inDays == 1) return 'Yesterday';
    return '${date.month}/${date.day}/${date.year}';
  }

  Widget _buildEditorArea(bool hasPreview, bool isSideBySide) {
    if (selectedNote == null) {
      return Center(
        child: Text(
          'Select a note to begin',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopBar(isSideBySide),
        Expanded(
          child: hasPreview && isPreviewVisible
              ? isSideBySide
                    ? LayoutBuilder(
                        builder: (context, constraints) {
                          final paneWidth = constraints.maxWidth / 2;
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: paneWidth, child: _buildEditor()),
                              SizedBox(
                                width: paneWidth,
                                child: _buildPreview(
                                  isSideBySide: isSideBySide,
                                ),
                              ),
                            ],
                          );
                        },
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 3, child: _buildEditor()),
                          Expanded(
                            flex: 2,
                            child: _buildPreview(isSideBySide: false),
                          ),
                        ],
                      )
              : _buildEditor(),
        ),
      ],
    );
  }

  Widget _buildTopBar(bool isWide) {
    return SizedBox(
      height: 78,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 12, 22, 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: titleController,
                focusNode: titleFocusNode,
                cursorColor: Theme.of(context).textSelectionTheme.cursorColor,
                showCursor: true,
                onChanged: (_) => _handleNoteChanged(),
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
                decoration: const InputDecoration(
                  hintText: 'Untitled note',
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (isSaving)
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            IconButton(
              onPressed: _shareSelectedNote,
              tooltip: 'Share note',
              icon: const Icon(LucideIcons.share),
            ),
            IconButton(
              onPressed: () =>
                  setState(() => isPreviewVisible = !isPreviewVisible),
              tooltip: 'Toggle preview',
              icon: Icon(
                isPreviewVisible ? LucideIcons.eye : LucideIcons.eyeOff,
              ),
            ),
            IconButton(
              onPressed: _toggleSidebar,
              tooltip: isSidebarVisible ? 'Hide notes pane' : 'Show notes pane',
              icon: const Icon(LucideIcons.panelLeft),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor() {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(28, 8, 18, keyboardVisible ? 0 : 24),
      child: Column(
        children: [
          _buildMarkdownToolbar(),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: bodyController,
              focusNode: bodyFocusNode,
              cursorColor: Theme.of(context).textSelectionTheme.cursorColor,
              showCursor: true,
              expands: true,
              maxLines: null,
              minLines: null,
              style: GoogleFonts.gotu(
                fontSize: 16,
                height: 1.65,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onChanged: (_) {
                _handleNoteChanged(refreshPreview: true);
              },
              decoration: const InputDecoration(
                hintText: 'Start writing in Markdown...',
                filled: false,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarkdownToolbar() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 2,
        children: [
          _toolbarButton(
            'Bold',
            LucideIcons.bold,
            () => _insertMarkdown('**', '**'),
          ),
          _toolbarButton(
            'Italic',
            LucideIcons.italic,
            () => _insertMarkdown('*', '*'),
          ),
          _toolbarButton(
            'Heading',
            LucideIcons.heading,
            () => _insertMarkdown('# '),
          ),
          _toolbarButton(
            'Link',
            LucideIcons.link,
            () => _insertMarkdown('[', '](https://)'),
          ),
          _toolbarButton(
            'Bulleted list',
            LucideIcons.list,
            () => _insertMarkdown('- '),
          ),
          _toolbarButton(
            'Numbered list',
            LucideIcons.listOrdered,
            () => _insertMarkdown('1. '),
          ),
          _toolbarButton(
            'Quote',
            LucideIcons.quote,
            () => _insertMarkdown('> '),
          ),
          _toolbarButton(
            'Code',
            LucideIcons.code,
            () => _insertMarkdown('`', '`'),
          ),
        ],
      ),
    );
  }

  Widget _toolbarButton(
    String tooltip,
    IconData icon,
    VoidCallback onPressed,
  ) => IconButton(
    onPressed: onPressed,
    tooltip: tooltip,
    icon: Icon(icon, size: 19),
  );

  Widget _buildPreview({required bool isSideBySide}) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: isSideBySide
            ? Border(left: BorderSide(color: theme.dividerColor))
            : Border(top: BorderSide(color: theme.dividerColor)),
        color: theme.colorScheme.surface,
      ),
      padding: const EdgeInsets.fromLTRB(34, 28, 34, 24),
      child: SingleChildScrollView(
        child: MarkdownBody(
          data: bodyController.text.isEmpty
              ? '_Nothing to preview yet._'
              : bodyController.text,
          selectable: true,
          styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
            p: GoogleFonts.gotu(fontSize: 16, height: 1.65),
            h1: GoogleFonts.gotu(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              height: 1.25,
            ),
            h2: GoogleFonts.gotu(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
            h3: GoogleFonts.gotu(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              height: 1.35,
            ),
            code: GoogleFonts.gotu(color: theme.colorScheme.primary),
          ),
        ),
      ),
    );
  }
}

class _LicenseDocument {
  const _LicenseDocument({required this.package, required this.text});

  final String package;
  final String text;
}

class _OpenSourceLicensesPage extends StatefulWidget {
  const _OpenSourceLicensesPage();

  @override
  State<_OpenSourceLicensesPage> createState() =>
      _OpenSourceLicensesPageState();
}

class _OpenSourceLicensesPageState extends State<_OpenSourceLicensesPage> {
  late final Future<List<_LicenseDocument>> licensesFuture;
  String selectedPackage = 'Nithya Ranjana';

  @override
  void initState() {
    super.initState();
    licensesFuture = _loadLicenses();
  }

  Future<List<_LicenseDocument>> _loadLicenses() async {
    final groupedLicenses = <String, List<String>>{};
    await for (final license in LicenseRegistry.licenses) {
      final text = license.paragraphs
          .map((paragraph) => paragraph.text)
          .join('\n');
      for (final package in license.packages) {
        groupedLicenses.putIfAbsent(package, () => []).add(text);
      }
    }

    final documents = groupedLicenses.entries
        .map(
          (entry) => _LicenseDocument(
            package: entry.key,
            text: entry.value.join('\n\n'),
          ),
        )
        .toList();
    documents.sort((left, right) {
      final leftIsFont = left.package == 'Nithya Ranjana';
      final rightIsFont = right.package == 'Nithya Ranjana';
      if (leftIsFont != rightIsFont) return leftIsFont ? -1 : 1;
      return left.package.toLowerCase().compareTo(right.package.toLowerCase());
    });
    return documents;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBackground = Theme.of(context).scaffoldBackgroundColor;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: scaffoldBackground,
        systemNavigationBarDividerColor: scaffoldBackground,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: SafeArea(
        child: Scaffold(
          appBar: AppBar(title: const Text('Open Source Licenses')),
          body: FutureBuilder<List<_LicenseDocument>>(
            future: licensesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text('Unable to load licenses: ${snapshot.error}'),
                );
              }
              final documents = snapshot.data ?? const <_LicenseDocument>[];
              if (documents.isEmpty) {
                return const Center(child: Text('No licenses available.'));
              }
              final selected = documents.firstWhere(
                (document) => document.package == selectedPackage,
                orElse: () => documents.first,
              );
              return LayoutBuilder(
                builder: (context, constraints) {
                  final isWide =
                      constraints.maxWidth >= 760 &&
                      constraints.maxHeight >= 500;
                  final compactPadding = constraints.maxHeight < 500
                      ? 8.0
                      : 24.0;
                  final packageList = _buildPackageList(documents);
                  final licenseDetails = _buildLicenseDetails(selected);
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1280),
                      child: Padding(
                        padding: EdgeInsets.all(compactPadding),
                        child: isWide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(width: 300, child: packageList),
                                  VerticalDivider(
                                    width: 1,
                                    color: Theme.of(context).dividerColor,
                                  ),
                                  Expanded(child: licenseDetails),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(
                                      bottom: compactPadding / 2,
                                    ),
                                    child: Row(
                                      children: [
                                        const Padding(
                                          padding: EdgeInsets.only(right: 12),
                                          child: Text('License package'),
                                        ),
                                        Expanded(
                                          child:
                                              DropdownButtonFormField<String>(
                                                initialValue: selected.package,
                                                isExpanded: true,
                                                isDense: true,
                                                decoration:
                                                    const InputDecoration(
                                                      contentPadding:
                                                          EdgeInsets.symmetric(
                                                            horizontal: 12,
                                                            vertical: 8,
                                                          ),
                                                    ),
                                                items: [
                                                  for (final document
                                                      in documents)
                                                    DropdownMenuItem(
                                                      value: document.package,
                                                      child: Text(
                                                        document.package,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                ],
                                                onChanged: (package) {
                                                  if (package != null) {
                                                    setState(
                                                      () => selectedPackage =
                                                          package,
                                                    );
                                                  }
                                                },
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(child: licenseDetails),
                                ],
                              ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPackageList(List<_LicenseDocument> documents) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text('Packages', style: theme.textTheme.titleSmall),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: documents.length,
            itemBuilder: (context, index) {
              final document = documents[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                selected: document.package == selectedPackage,
                selectedTileColor: theme.colorScheme.surfaceContainerHigh,
                title: Text(document.package),
                subtitle: Text(
                  document.text.split('\n').first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => setState(() => selectedPackage = document.package),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLicenseDetails(_LicenseDocument document) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 16, 12),
          child: Text(document.package, style: theme.textTheme.titleSmall),
        ),
        Divider(height: 1, color: theme.dividerColor),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: SelectableText(
              document.text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
