# Papers Cairn

A cairn is a stack of stones marking a trail, so whoever comes next knows where they are on
the path. This app does that for the papers you are reading.

Share an arXiv link from your browser and Cairn fetches the metadata, files the paper under
a project, downloads the PDF into a folder you can see, and remembers where you stopped —
in prose, not a percentage.

You read the paper inside Cairn and highlight as you go. Those highlights are Cairn's, not
the PDF's: searchable next to your notes, still there after re-downloading the file, and
attached to the paper rather than trapped in whichever reader made them.

## Running it

```bash
flutter pub get
dart run build_runner build     # generates the drift database code
flutter run
```

Generated `*.g.dart` files are not committed, so `build_runner` has to run once after a
fresh clone or the project will not analyze.

```bash
flutter test        # unit tests, no device needed
flutter analyze
```

## What it does today

- Look a paper up from an arXiv link, id, or citation string, check it is the right one,
  then save it — or share one in from the browser
- Import a paper that is not on arXiv by sharing its PDF into Cairn from a file manager
- One library list, narrowed by reading status or by what is still unfiled
- Group papers into projects, recording why each one belongs there
- Link papers to each other, recording why they are connected
- Track reading status and a free-text note on where you stopped
- Download the PDF and read it in the app, resuming on the page you left
- Highlight text in five colours and attach a note to any highlight
- Search across titles, authors, abstracts, your notes, and your highlights
- Draw on boards: an unbounded surface for sketching how the ideas fit together,
  optionally tied to a project
- Write notes on a board and pin papers from your library onto it, then scribble
  between them

## What it does not do yet

Board items cannot be resized, and there are no connector lines between them beyond ones
you draw by hand. Beyond that: no citation graph, no BibTeX or Obsidian export, no sync
between devices, no ink on PDF pages. The iOS share sheet also needs a Share Extension
target that does not exist yet — sharing in works on Android only for now.

## Layout

`lib/core/` is infrastructure: database, arXiv client, file storage, routing. `lib/features/`
holds one directory per feature, each with a `data/` repository and a `presentation/` layer.
Widgets never touch SQLite or HTTP directly; they go through a repository.

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains the design, which layers of Clean
Architecture were deliberately left out and why, and the platform traps already found the
hard way.
