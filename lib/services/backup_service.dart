import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../data/note_database.dart';

class BackupService {
  Future<bool> exportNotes(List<Note> notes) async {
    if (notes.isEmpty) return false;
    final archive = Archive();
    for (final note in notes) {
      final filename = '${_safeFilename(note.title)}-${note.id}.md';
      final bytes = Uint8List.fromList(note.body.codeUnits);
      archive.addFile(ArchiveFile(filename, bytes.length, bytes));
    }
    final zipBytes = ZipEncoder().encode(archive);
    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Export notes',
      fileName: 'lipih-backup-${DateTime.now().millisecondsSinceEpoch}.zip',
      type: FileType.custom,
      allowedExtensions: ['zip'],
      bytes: Uint8List.fromList(zipBytes),
    );
    return savedPath != null;
  }

  Future<List<ImportedNote>> importNotes() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Restore notes',
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return const [];
    final archive = ZipDecoder().decodeBytes(result.files.single.bytes!);
    return [
      for (final file in archive.files)
        if (file.isFile && p.extension(file.name).toLowerCase() == '.md')
          ImportedNote(
            title: _titleFromFilename(file.name),
            body: String.fromCharCodes(file.readBytes()!),
          ),
    ];
  }

  String _safeFilename(String title) {
    final cleaned = title.trim().replaceAll(RegExp(r'[^a-zA-Z0-9 _-]'), '');
    return cleaned.isEmpty ? 'untitled-note' : cleaned.replaceAll(' ', '-');
  }

  String _titleFromFilename(String filename) {
    final base = p.basenameWithoutExtension(filename);
    return base.replaceFirst(RegExp(r'-\d+$'), '').replaceAll('-', ' ').trim();
  }
}

class ImportedNote {
  const ImportedNote({required this.title, required this.body});

  final String title;
  final String body;
}
