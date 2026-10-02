import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../platform/database_platform.dart';

class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
  });

  final int id;
  final String title;
  final String body;
  final DateTime updatedAt;

  factory Note.fromMap(Map<String, Object?> map) => Note(
    id: map['id'] as int,
    title: map['title'] as String,
    body: map['body'] as String,
    updatedAt: DateTime.parse(map['updated_at'] as String),
  );
}

class NoteDatabase {
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    configureDatabase();
    final databasePath = await getDatabasesPath();
    _database = await openDatabase(
      p.join(databasePath, 'lipih.db'),
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await database.insert('notes', {
          'title': 'Welcome to Lipih',
          'body': '# A quieter place for ideas\n\nWrite in **Markdown**, keep the useful bits, and let Lipih stay out of the way.\n\n- Select a note to edit\n- Use the preview to check your formatting\n- Export selected notes whenever you need a backup',
          'updated_at': DateTime.now().toIso8601String(),
        });
      },
    );
    return _database!;
  }

  Future<List<Note>> listNotes() async {
    final db = await database;
    final rows = await db.query('notes', orderBy: 'updated_at DESC');
    return rows.map(Note.fromMap).toList();
  }

  Future<Note> createNote([String title = '', String body = '']) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('notes', {
      'title': title,
      'body': body,
      'updated_at': now,
    });
    return Note(
      id: id,
      title: title,
      body: body,
      updatedAt: DateTime.parse(now),
    );
  }

  Future<void> updateNote(int id, String title, String body) async {
    final db = await database;
    await db.update(
      'notes',
      {
        'title': title,
        'body': body,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteNote(int id) async {
    final db = await database;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
