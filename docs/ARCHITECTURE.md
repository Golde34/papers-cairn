# Cairn — Architecture

> A cairn is a stack of stones marking a trail, so whoever comes next knows where they
> are on the path. That is what this app does for papers you are reading.

## What the app does

Catalogue, downloader, and reader for arXiv papers.

1. You share an arXiv link from the browser; the app fetches metadata.
2. You check the paper is the right one, then save it.
3. You file it under a project, saying *why* it belongs there.
4. You tap Download, then read the PDF in the app, highlighting as you go.
5. You record where you stopped, in prose, and how this paper relates to others.

The value is in the metadata, the relations, the highlights, and the progress notes.

### Why there is a reader after all

The first design had no PDF reader: existing readers are better at rendering than anything
worth building here, so papers were handed off to whichever one the user had.

That was wrong, for a reason that only became obvious in use. Reading a paper produces
highlights and marginal notes, and those are the most valuable thing the app could hold —
but in a foreign reader they are invisible to Cairn's search, unlinked from the paper's
progress note, lost when the PDF is re-downloaded, and unexportable. The handoff gave away
exactly the material the app exists to keep.

So rendering is delegated to `pdfrx` (PDFium, open source), while **annotations belong to
Cairn** and live in its database rather than being written into the PDF file. Highlights
are searchable alongside notes, and a paper's page shows everything thought about it in one
place. `syncfusion_flutter_pdfviewer` would have supplied a finished annotation UI in a
fraction of the time, but it stores annotations in the file — the one thing worth not
doing — and carries a commercial licence besides.

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
               relativePath, status, progressNote, addedAt, lastOpenedAt, lastPage
Project        id, name, folderName, color, createdAt
PaperProject   paperId, projectId, note        -- why this paper is in this project
PaperRelation  fromId, toId, note              -- why these two papers are connected
Annotation     id, paperId, pageNumber, quotedText, rectsJson, colorValue,
               note, createdAt                 -- a highlight, and why it matters
Board          id, title, projectId, createdAt, updatedAt
Stroke         id, boardId, pointsJson, colorValue, width, createdAt
BoardItem      id, boardId, kind, x, y, width, body, paperId, colorValue,
               createdAt                      -- a note, or a paper pinned on
```

Both join tables carry a free-text `note`. That is the point of the app: a link with no
stated reason is barely worth more than no link. `progressNote` is prose ("stuck on the
proof of Lemma 3") rather than a percentage, because prose is what actually helps when you
come back three weeks later.

A **board** is an unbounded surface to think on — sketch the argument, draw the arrows,
scribble the question you cannot yet phrase. It is deliberately not a project: a project is
a tidy list of what you are reading, while a board is the working-out a list cannot hold. A
board may belong to a project or float free.

A pinned paper is a **reference, not a copy**: `BoardItem` stores only `paperId`, so the
card always shows the paper's current title and opens the real one. Deleting a paper from
the library cascades to its cards rather than leaving them pointing at nothing.
`BoardItem.body` is spelled that way because a column called `text` collides with drift's
own `Table.text()` builder.

Board items store a width but no height: a note should grow as it is written rather than
scroll inside a fixed box. Their gestures are deliberately split — tap opens, long-press
then drag moves — because a plain drag would be ambiguous with panning the board, and the
two would fight in the gesture arena. While a drawing tool is selected the items are
wrapped in `IgnorePointer`, so ink goes straight across them.

`Stroke.pointsJson` holds `[[x,y], ...]` in **board coordinates**, so a line drawn zoomed
right in stays put when you zoom back out. Coordinates are rounded to a tenth of a unit —
a finger does not carry the precision the touchscreen reports, and the full doubles triple
the stored size for no visible gain. The surface is a very large finite square with the
view starting at its centre, which behaves like an infinite plane unless somebody draws for
several kilometres.

`Annotation.rectsJson` holds `[[left,top,right,bottom], ...]` in **PDF page coordinates**:
origin bottom-left, y increasing upward, so `top` is numerically above `bottom`. Page
coordinates rather than screen ones, so a highlight lands in the same place at a different
zoom, orientation, or device. One rect per line of the selection rather than one for the
whole thing — otherwise a highlight running across three lines paints a single box over the
entire paragraph.

## Storage

Files live under `getApplicationDocumentsDirectory()/<project>/`, identical code on both
platforms. iOS sandboxing has no equivalent of Android's Storage Access Framework, so the
app owns one directory rather than writing into a folder the user picks.

**That directory is user-visible on iOS and private on Android**, which is worth stating
plainly because it is asymmetric. `UIFileSharingEnabled` and
`LSSupportsOpeningDocumentsInPlace` put it in the iOS Files app. On Android the same call
returns `/data/data/<package>/app_flutter`, which no file manager can browse and no other
app can read by path — PDFs reach a reader through a `FileProvider` content URI, and are
invisible outside Cairn. Making them browsable on Android means either app-specific
external storage or MediaStore, and neither has an iOS counterpart, so the asymmetry stays
until there is a reason to pay for it.

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
- **Cairn's own arxiv.org intent filter can swallow its own outgoing links.** Handing a
  `https://arxiv.org/pdf/...` URL to the intent system resolves Cairn ahead of the browser,
  so "open this elsewhere" reopens Cairn. The filter is scoped to `/abs`, and outgoing PDF
  links use `LaunchMode.inAppBrowserView`, which always lands in a browser.
- **`file_picker` cannot be used on Flutter 3.44.** Version 11 applies the Kotlin Gradle
  Plugin itself, which the built-in Kotlin pipeline rejects: the build dies on
  `GeneratedPluginRegistrant.java` failing to see `FilePickerPlugin`. `flutter clean` does
  not help. Importing therefore goes through the share sheet — an `application/pdf` intent
  filter — which needs no picker plugin at all.
- **An imported PDF is a copy; the original stays put.** Android hands a shared file over
  as a temporary copy and grants no authority over the original, so "move into Cairn" is
  not something the app can honour without `MANAGE_EXTERNAL_STORAGE` or a MediaStore
  delete request written against a platform channel.
- **A device may have no PDF viewer at all.** `OpenFilex.open` returns a result rather than
  throwing, so an unchecked call leaves a button that silently does nothing. Check the
  result and fall back to the copy on arXiv in a browser.
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
