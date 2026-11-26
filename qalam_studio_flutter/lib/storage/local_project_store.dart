import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/design_project.dart';

class LocalProjectStore {
  LocalProjectStore._();
  static final LocalProjectStore instance = LocalProjectStore._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docsDir.path, 'qalamix_offline_projects.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE projects (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            payload TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  Future<void> saveProject(DesignProject project) async {
    final db = await database;
    await db.insert(
      'projects',
      {
        'id': project.id,
        'name': project.name,
        'updated_at': project.updatedAt,
        'payload': project.encode(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<DesignProject>> loadAllProjects() async {
    final db = await database;
    final rows = await db.query('projects', orderBy: 'updated_at DESC');
    // One corrupt saved project must not hide the whole library: decode
    // each row on its own and drop only the rows that fail to decode.
    final projects = <DesignProject>[];
    for (final row in rows) {
      try {
        projects.add(DesignProject.decode(row['payload'] as String));
      } catch (_) {
        try {
          await db.delete(
            'projects',
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        } catch (_) {}
      }
    }
    return projects;
  }

  Future<void> deleteProject(String id) async {
    final db = await database;
    await db.delete('projects', where: 'id = ?', whereArgs: [id]);
  }
}
