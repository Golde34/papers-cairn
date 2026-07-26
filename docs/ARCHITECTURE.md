# Cairn — Architecture

> A cairn is a stack of stones marking a trail, so whoever comes next knows where they
> are on the path. That is what this app does for papers you are reading.

## What the app does

Catalog + downloader for arXiv papers. It does **not** read, render, or parse PDFs.

1. You share an arXiv link from the browser; the app fetches metadata.
2. You file the paper under a project, saying *why* it belongs there.
3. You tap Download; the PDF lands in `Documents/<project>/` and opens in whatever PDF
   app you already use.
4. You record where you stopped, in prose, and how this paper relates to others.

The value is in the metadata, the relations, and the progress notes. Not in the PDF.

## Architecture: feature-first, three layers, Riverpod

```
Widget  ──ref.read──▶  Controller  ──▶  Repository  ──▶  Dao / Api  ──▶  SQLite / network
Widget  ◀─ref.watch──  StreamProvider ◀── Stream<List<T>> ◀── drift .watch()
```

Data flows one way. drift returns `Stream`s, so writing to the database re-renders every
screen watching it. There is no manual refresh and no `setState` for app data.

### Deliberate omissions

This is *not* textbook Clean Architecture. Two layers were cut on purpose, because the
author is new to Flutter and working solo:

**No UseCase classes.** Controllers call repositories directly. The textbook version wants
one class per action (`AddPaperUseCase`, `DownloadPaperUseCase`, …). That turns one button
into six files and buys nothing until multiple callers share the same action.

**No separate domain entity.** drift's generated row classes *are* the models. The
textbook version defines a domain entity, a data model, and mapping code both directions.
That is real value when the DB schema and the domain diverge — which is not true here and
may never be.

**No DAO classes either.** Repositories query drift directly. A DAO layer between them
would be a second seam doing the same job as the first.

The thing worth keeping from Clean Architecture is kept: **the UI knows nothing about
SQLite or HTTP.** Every widget talks to a Repository. If drift or dio is ever swapped out,
the blast radius stops at `data/`. Adding the omitted layers later is mechanical, because
the seam is already there.

## Layout

```
lib/
  main.dart
  app.dart                       MaterialApp.router + theme
  core/
    database/
      database.dart              AppDatabase (drift)
      tables.dart                Papers, Projects, PaperProjects, PaperRelations
    network/
      arxiv_api.dart             dio + Atom XML parsing
      arxiv_id.dart              extract an arXiv id from a URL or pasted string
    storage/
      file_service.dart          download, delete, existence check
    share/
      share_receiver.dart        inbound links from the OS share sheet
    router/app_router.dart       go_router
    theme/app_theme.dart
    providers.dart               database, api and file service singletons
  features/
    home/presentation/           bottom nav: Reading, Inbox, Projects
    papers/
      data/paper_repository.dart
      presentation/              detail, search, add sheet, shared widgets
    projects/
      data/project_repository.dart
      presentation/
```

The inbox is not a feature of its own — it is a query for papers belonging to no project,
which keeps "unfiled" from becoming a state that can disagree with the join table.

`core/` is infrastructure with no feature knowledge. `features/` may depend on `core/`.
Features do not import each other's `presentation/`; if two features need the same data,
they share a repository.

## Data model

```
Paper          id, arxivId, title, authors, abstract, publishedAt, pdfUrl,
               relativePath, status, progressNote, addedAt, lastOpenedAt
Project        id, name, folderName, color, createdAt
PaperProject   paperId, projectId, note        -- why this paper is in this project
PaperRelation  fromId, toId, note              -- why these two papers are connected
```

Both join tables carry a free-text `note`. That is the point of the app: a link with no
stated reason is barely worth more than no link. `progressNote` is prose ("stuck on the
proof of Lemma 3") rather than a percentage, because prose is what actually helps when you
come back three weeks later.

## Storage

Files live under `getApplicationDocumentsDirectory()/<project>/`, identical code on both
platforms. iOS sandboxing has no equivalent of Android's Storage Access Framework, so the
app owns one directory rather than writing into a folder the user picks. On iOS,
`UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` in `Info.plist` expose that
directory in the Files app.

**Store paths relative to the documents directory, never absolute.** iOS changes the app
container path on every update; an absolute path saved today is a dead path tomorrow.

## Known traps

- **arXiv redirects plain HTTP to HTTPS** (301). Always call
  `https://export.arxiv.org/api/query`.
- **The PDF URL comes from `<link title="pdf">`**, e.g.
  `https://arxiv.org/pdf/2103.00020v1` — note the absence of a `.pdf` suffix. Read it from
  the response; do not build it by string concatenation.
- **`title` and `summary` contain real newlines and indentation** in the Atom response.
  Collapse whitespace before storing, or every list row renders broken.
- **arXiv asks for one request per three seconds.** Throttle, or expect to be blocked.
- **A file deleted from outside the app leaves the database lying.** Check existence before
  opening; on a miss, clear `relativePath` and show the Download button again.
- **The Android build needs `platforms;android-37.0`, not `android-37`.** Flutter 3.44
  defaults `compileSdk` to 36, but `receive_sharing_intent` compiles against 37 and its AAR
  metadata forces consumers to match, so `android/app/build.gradle.kts` pins 37 explicitly.
  From API 36 onwards Google ships minor-versioned platforms, so the SDK directory is
  `android-37.0`; installing plain `android-37` is not an option and AGP resolves the minor
  version on its own once it is present. Gradle failing with `Failed to find target with
  hash string 'android-37'` means the platform is simply not installed.

## Not now

In-app PDF reader and highlights, citation graph, Semantic Scholar auto-suggested
relations, BibTeX and Obsidian export, cloud sync, home screen widget. Every one of these
is easier to add once papers, projects, and relations exist. None of them is worth
blocking the first working build.
