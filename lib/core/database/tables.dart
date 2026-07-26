import 'package:drift/drift.dart';

enum ReadingStatus { toRead, reading, done, dropped }

class Papers extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// arXiv identifier including version, e.g. `2103.00020v1`.
  TextColumn get arxivId => text().unique()();
  TextColumn get title => text()();

  /// Author names joined by `; `. Never queried individually, so a table would
  /// only add joins.
  TextColumn get authors => text()();
  TextColumn get abstractText => text()();

  /// arXiv categories joined by `; `, e.g. `cs.CV; cs.LG`.
  TextColumn get categories => text().withDefault(const Constant(''))();
  DateTimeColumn get publishedAt => dateTime().nullable()();
  TextColumn get pdfUrl => text()();

  /// Path under the documents directory, e.g. `CLIP/2103.00020 - Learning....pdf`.
  /// Null means the PDF has not been downloaded. Relative because iOS moves the
  /// app container on every update.
  TextColumn get relativePath => text().nullable()();

  TextColumn get status =>
      textEnum<ReadingStatus>().withDefault(const Constant('toRead'))();

  /// Where you stopped, in prose. "stuck on the proof of Lemma 3" beats "62%".
  TextColumn get progressNote => text().withDefault(const Constant(''))();

  DateTimeColumn get addedAt => dateTime()();
  DateTimeColumn get lastOpenedAt => dateTime().nullable()();

  /// Page the reader was last on, so reopening a paper resumes rather than
  /// restarting. Null until the paper has been opened in the reader.
  IntColumn get lastPage => integer().nullable()();
}

/// A highlight in a paper, with an optional note attached.
///
/// Deliberately stored here rather than written into the PDF file. Annotations
/// in the file would be invisible to search, lost on re-download, and unusable
/// by any future export. Kept in the database they sit alongside progress notes
/// as one body of thinking about the paper — which is the entire point of the app.
class Annotations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get paperId =>
      integer().references(Papers, #id, onDelete: KeyAction.cascade)();

  /// 1-based, matching how PDF readers and papers themselves count pages.
  IntColumn get pageNumber => integer()();

  /// The highlighted text itself. Searchable, and what shows in a list of
  /// highlights without having to open the PDF.
  TextColumn get quotedText => text()();

  /// Highlight geometry as `[[left,top,right,bottom], ...]` in PDF page
  /// coordinates — origin bottom-left, y increasing upward. One rect per line
  /// of the selection, so a highlight spanning three lines does not paint one
  /// fat box over the paragraph. Page coordinates rather than screen ones, so
  /// they survive zoom, rotation, and a different device.
  TextColumn get rectsJson => text()();

  IntColumn get colorValue => integer()();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
}

class Projects extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();

  /// Directory name under the documents directory. Sanitised at creation time
  /// and then frozen, so renaming a project never orphans downloaded files.
  TextColumn get folderName => text()();
  IntColumn get colorValue => integer()();
  DateTimeColumn get createdAt => dateTime()();
}

class PaperProjects extends Table {
  IntColumn get paperId =>
      integer().references(Papers, #id, onDelete: KeyAction.cascade)();
  IntColumn get projectId =>
      integer().references(Projects, #id, onDelete: KeyAction.cascade)();

  /// Why this paper belongs to this project — "baseline we compare against",
  /// "where the trick comes from".
  TextColumn get note => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {paperId, projectId};
}

class PaperRelations extends Table {
  // Both columns point at Papers, so drift needs distinct names for the
  // back-references or it generates neither.
  @ReferenceName('outgoingRelations')
  IntColumn get fromId =>
      integer().references(Papers, #id, onDelete: KeyAction.cascade)();
  @ReferenceName('incomingRelations')
  IntColumn get toId =>
      integer().references(Papers, #id, onDelete: KeyAction.cascade)();

  /// Why these two are connected. A link without a stated reason is barely
  /// worth more than no link at all.
  TextColumn get note => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {fromId, toId};
}
