# Box Sets Artwork (box-sets branch)

This page describes how the `box-sets` branch chooses artwork for multi-disc albums and what you (as a user) need to do to benefit from it.

It covers two related behaviors:

1. **Disc-specific artwork in a shared folder**
2. **Album-level artwork from a common parent folder** (lets a box set have one overall album cover while each disc can still have its own cover)

!!! note
    This logic is implemented in the `box-sets` branch and relies on the database schema change that adds `albums.cover` (schema_27).

---

## What LMS stores (important)

- `tracks.coverid` / `tracks.cover` represent per-track artwork.
  - `tracks.coverid` is an 8-hex ID.
  - `tracks.cover` is either a filesystem path (standalone image) or a special value indicating embedded artwork.

- `albums.artwork` is the album’s “artwork identifier” used by many queries/UI paths.
  - In normal operation it typically contains a **coverid**.

- **New in `box-sets`: `albums.cover`** stores the filesystem path to an *album-level* standalone image.
  - When `albums.cover` is set, the branch treats it as the authoritative album-level source image.

---

## Artwork selection overview

### 1) Disc-specific standalone artwork (same directory)

When scanning a track that does **not** have embedded artwork, LMS looks for standalone image files in the track’s directory.

In `box-sets`, if a disc number can be determined for that track, LMS will try **disc-specific filenames first**, then fall back to the usual names.

This solves the classic issue where:

- Disc 1 is scanned first → `folder.jpg` (or `cover.jpg`) gets cached for the directory
- Disc 2 is scanned next → LMS reuses Disc 1’s cached artwork

The `box-sets` branch introduces a disc-aware cache key so disc-specific results don’t poison the cache for other discs.

### 2) Parent directory album artwork (box set “overall cover”)

After (re)scan post-processing, `box-sets` looks for albums that:

- have local file tracks
- have **more than one distinct disc value** in the database

For those albums it:

1. collects the directories containing the album’s tracks
2. computes a common parent directory (or uses the single directory if there’s only one)
3. searches that parent directory for `cover.*`, `folder.*`, `album.*`, `thumb.*` (and possibly your configured coverArt name)
4. if found, it sets:
   - `albums.cover` = **full filesystem path** to that image
   - `albums.artwork` = **coverid** generated from that image

When the web UI requests artwork by coverid, `box-sets` will check whether any album has `albums.artwork == <coverid>` and a non-empty `albums.cover`, and if so it serves the file from `albums.cover`.

---

## What users need to do

### A) Set correct disc tags (recommended)

To fully benefit from box-set behavior (especially parent directory artwork), ensure your files have correct disc metadata:

- `DISCNUMBER`

!!! important
    The parent-directory album artwork pass only targets albums with `COUNT(DISTINCT tracks.disc) > 1` in the database.
    If all tracks have missing/zero disc tags (or all are disc 1), the parent cover won’t be set.

### B) Choose a folder layout

Two common layouts work well.

#### Layout 1: Disc subfolders + one parent cover (classic box set)

```
Box Set Album/
  folder.jpg              # overall album/box-set cover (parent)
  Disc 1/
    01 - Track.flac
    folder.jpg            # optional disc-specific cover
  Disc 2/
    01 - Track.flac
    folder.jpg            # optional disc-specific cover
```

What happens:

- `updateDiscSetArtwork()` can set the album-level cover from `Box Set Album/folder.jpg`.
- Disc folders can still have their own `folder.jpg` / disc-specific names.

#### Layout 2: Everything in one directory + disc-specific filenames

```
Box Set Album/
  01-01 - Track.flac
  02-01 - Track.flac
  cover-disc1.jpg
  cover-disc2.jpg
  folder.jpg              # recommended album-level cover (or cover.jpg)
```

What happens:

- Disc-specific filenames are preferred for tracks on that disc.
- The per-directory cache is disc-aware when disc-specific art is selected.
- The parent-directory album artwork pass uses this same directory as the “common parent”.
  If you want a stable album/box-set cover (separate from disc-specific images), include a standard name like `folder.jpg` or `cover.jpg`.
  If you omit it, the album-level cover may end up being whichever image file is found first (often a disc-specific image).

---

## Supported filename patterns

### 1) Standard standalone names (fallback)

LMS looks for (case-insensitive):

- `cover.jpg` / `cover.png` / `cover.gif`
- `folder.*`
- `album.*`
- `thumb.*`

If none of these exist, it may fall back to the first image file found in the directory.

### 2) Disc-specific names (preferred when disc is known)

If LMS can determine the disc number for a track, it will try these *before* the standard names.

Patterns (disc number can be `1` or zero-padded `01`):

- `cover-disc1.*`, `cover-disc01.*`
- `cover_disc1.*`, `cover_disc01.*`
- `coverdisc1.*`, `coverdisc01.*`
- `folder-disc1.*`, `folder-disc01.*`
- `folder_disc1.*`, `folder_disc01.*`
- `folderdisc1.*`, `folderdisc01.*`
- `disc1.*`, `disc01.*`
- `cd1.*`, `cd01.*`

Examples:

- `cover-disc2.jpg`
- `folder_disc01.png`
- `cd03.jpg`

### 3) Disc subtitle names (optional)

If your tracks have a disc subtitle (eg. “Studio”, “Live”, “Bonus”), `box-sets` also derives candidate basenames from that subtitle.

Normalization rules:

- lowercased
- whitespace trimmed
- non-alphanumeric collapsed into `-`
- also tries a “compact” version with `-` removed

Templates tried:

- `cover-<subtitle>.*`, `cover_<subtitle>.*`, `cover<subtitle>.*`
- `folder-<subtitle>.*`, `folder_<subtitle>.*`, `folder<subtitle>.*`
- `<subtitle>.*`

Examples (subtitle: `Bonus Disc`):

- `cover-bonus-disc.jpg`
- `folder_bonusdisc.png`
- `bonusdisc.jpg`

!!! tip
    Disc subtitles are purely optional. If you don’t use them, you can ignore this feature.

---

## How disc number is determined

Disc number is determined from metadata when available.

If metadata is missing, `box-sets` may also infer a disc number from the file path (heuristics), such as:

- directory basename starting with `01-...`
- directory basename like `disc 2`, `Disc2`, `CD1`, etc.

!!! note
    These heuristics help disc-specific selection in some cases, but the parent-directory album cover pass still depends on actual disc values stored in the DB.

---

## Precedence rules (practical summary)

Within a directory, when standalone artwork is needed:

1. disc-specific names (if disc known)
2. disc-subtitle names (if present)
3. standard names (`cover`, `folder`, `album`, `thumb`)
4. first image found

At the album level:

- If `albums.cover` is set, `box-sets` treats that as the album’s preferred cover source and avoids overwriting `albums.artwork` with track-derived coverids.

---

## What a user needs to run

### After upgrading to a build that includes schema_27

You do **not** need a “clear library” (wipe) for the schema change alone.

To populate `albums.cover` for existing libraries, you need a scan that runs the post-processing step:

- a standard **Rescan** is usually sufficient

!!! warning
    If your server uses SQLite and you try to run DB-updating maintenance while the server is actively scanning, you can hit locking.

---

## Troubleshooting

### “My box set still shows Disc 1 art everywhere”

- Ensure disc tags are correct.
- Use disc-specific filenames (`cover-disc1.jpg`, `cover-disc2.jpg`, etc.) when multiple discs share one folder.

### “Parent folder cover is not used”

- Ensure the album has multiple distinct disc values in the library DB.
- Ensure the parent cover file exists and is readable by the server user.
- Ensure the parent cover filename matches standard names (`folder.jpg`, `cover.jpg`, etc.).

### “I moved the cover image and now covers break”

- `albums.cover` stores a filesystem path. If you move/rename the file, run a rescan so the DB can be updated.
