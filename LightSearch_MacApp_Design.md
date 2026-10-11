# LightSearch — Mac App Design Doc

2026-10-10 · jiyao weng

Semantic and metadata search over your Lightroom library, built natively for macOS in Swift.

---

## 1. Goals

LightSearch is a macOS app that lets you find photos and videos in your Lightroom library by describing what you're looking for in plain language, or by combining semantic queries with structured filters (date, camera, lens, GPS area, aperture, ISO).

**Who it's for:** photographers who manage large Lightroom catalogs (10k–500k assets) and find keyword search too rigid.

**Core capabilities:**
- Type "golden hour portrait, shallow depth of field" and get the 20 most visually similar shots
- Filter by date range, GPS bounding box, camera body, or lens alongside any semantic query
- Index runs silently in the background; first index of 50k photos completes overnight
- Fully local — no cloud, no API keys, embeddings computed on-device via Neural Engine

---

## 2. Architecture Overview

```
INDEXING (background, on catalog change)
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  [Lightroom .lrcat] → [Background Indexer] → [sqlite-vec]   │
│                        CoreML CLIP                    ↑      │
│                        ImageIO EXIF              shared store│
└──────────────────────────────────────────────────────────────┘
                                                       │
QUERY (on each search)                                 ▼
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  [SwiftUI] → [CoreML CLIP] → [Search Engine] → [Results]    │
│  search+chips  encode query   cosine+SQL filters  photo grid │
└──────────────────────────────────────────────────────────────┘
```

The indexing pipeline runs in the background whenever the Lightroom catalog changes. Every search reads from sqlite-vec: the query text is encoded by CoreML CLIP, then the Search Engine does a cosine similarity scan with optional SQL filters on the EXIF metadata columns.

---

## 3. Lightroom Catalog Integration

Lightroom Classic stores its catalog as a plain SQLite file at `~/Pictures/Lightroom/Lightroom Catalog.lrcat` (user-configurable). Open it read-only with `SQLite.swift`; no Lightroom SDK or plugin needed.

**Key tables:**

| Table | What it holds |
| --- | --- |
| `AgLibraryFile` | Filename, folder ref, extension |
| `AgLibraryFolder` | Folder paths (join to reconstruct absolute path) |
| `Adobe_imageDevelopSettings` | Develop settings; tells you if a RAW was processed |
| `AgHarvestedExifMetadata` | Camera make/model, focal length, ISO, shutter, aperture |
| `AgHarvestedIptcMetadata` | Caption, keywords, copyright |
| `AgLibraryKeyword` | Keyword tree |
| `AgLibraryKeywordImage` | Keyword-to-image assignments |
| `Adobe_images` | Master record per asset; `fileFormat`, `captureTime`, `rating`, `colorLabels` |

**Absolute path reconstruction:**
```sql
SELECT f.baseName || '.' || f.extension AS filename,
       fo.pathFromRoot AS folder
FROM AgLibraryFile f
JOIN AgLibraryFolder fo ON fo.id_local = f.folder
```
Prepend the catalog's parent directory to `pathFromRoot` to get the full disk path.

**Watch for changes:** use `kqueue` (via `DispatchSource.makeFileSystemObjectSource`) on the `.lrcat` file to detect when Lightroom writes. Re-query only rows with `captureTime` or `id_local` newer than the last indexed timestamp.

---

## 4. Embedding Model

**Recommendation: CoreML CLIP (ViT-B/32)**

OpenAI CLIP converted to CoreML runs on the Apple Neural Engine (ANE) at ~50ms per image on M1. It gives a single 512-dim shared embedding space for both text and images, enabling text-to-image queries like "misty mountain at sunrise".

| Option | Pros | Cons |
| --- | --- | --- |
| CoreML CLIP ViT-B/32 | Runs on ANE, Apache 2 weights, 600MB, well-tested | 512 dims (vs 768 for larger models) |
| CoreML CLIP ViT-L/14 | Higher quality, 768 dims | 1.7GB, slower on older hardware |
| Apple Vision `VNFeaturePrintObservation` | Zero setup, built-in OS | Image-to-image only — no text queries |
| EmbeddingGemma 2 (Python) | Proven in EmbeddingExperiment, 768-dim, text+audio+video | Requires Python server, ~3GB VRAM |

**Getting the CoreML model:**
```bash
pip install git+https://github.com/apple/ml-ane-transformers
python -c "import clip; clip.load('ViT-B/32'); ..."  # export to .mlpackage
```
Or download the pre-converted model from [apple/coreml-examples](https://github.com/apple/coreml-examples).

**Embedding dimensions:** 512 (ViT-B/32). All vectors stored as FLOAT32 blobs in sqlite-vec.

**Fallback:** if the user is on Intel Mac or the ANE is unavailable, CoreML falls back to CPU automatically — no code change needed.

---

## 5. Metadata Extraction (EXIF)

Use `ImageIO` framework — no third-party dependency. Load via `CGImageSourceCreateWithURL` and read the `kCGImagePropertyExifDictionary` and `kCGImagePropertyGPSDictionary` dictionaries.

**Fields to index:**

| Field | Source dict | SQLite column | Notes |
| --- | --- | --- | --- |
| Capture date | `{Exif}DateTimeOriginal` | `captured_at INTEGER` | Store as Unix timestamp for range queries |
| Camera make | `{TIFF}Make` | `camera_make TEXT` | e.g. "Sony", "Canon" |
| Camera model | `{TIFF}Model` | `camera_model TEXT` | e.g. "ILCE-7M4" |
| Lens model | `{Exif}LensModel` | `lens TEXT` | e.g. "FE 24-70mm F2.8 GM" |
| Focal length | `{Exif}FocalLength` | `focal_mm REAL` | mm, effective |
| Aperture | `{Exif}FNumber` | `aperture REAL` | f-number |
| Shutter speed | `{Exif}ExposureTime` | `shutter_s REAL` | seconds (0.001 = 1/1000) |
| ISO | `{Exif}ISOSpeedRatings[0]` | `iso INTEGER` | |
| GPS latitude | `{GPS}Latitude` + `LatitudeRef` | `lat REAL` | Signed decimal degrees |
| GPS longitude | `{GPS}Longitude` + `LongitudeRef` | `lng REAL` | Signed decimal degrees |
| Width / height | `{Exif}PixelXDimension` | `width INTEGER` | |
| Flash | `{Exif}Flash` | `flash INTEGER` | Bitmask; `& 0x1 = 1` means fired |

**For RAW files** (ARW, CR3, NEF): `ImageIO` reads embedded EXIF from the raw container — same API, no special handling.

**For videos** (MOV, MP4): use `AVAsset` + `AVMetadataItem` for capture date and GPS. Codec, frame rate, and duration come from `AVAssetTrack`.

---

## 6. Index & Storage

Use **sqlite-vec** (Alex Garcia, MIT license) — a SQLite extension that adds `vec0` virtual tables for approximate nearest-neighbor search. Ships as a single `.dylib`; load at runtime via `sqlite3_load_extension`.

**Schema:**
```sql
-- Scalar metadata (fast SQL filters)
CREATE TABLE assets (
  id          TEXT PRIMARY KEY,   -- Lightroom id_local
  file_path   TEXT NOT NULL,
  captured_at INTEGER,            -- Unix timestamp
  camera_make TEXT,
  camera_model TEXT,
  lens        TEXT,
  focal_mm    REAL,
  aperture    REAL,
  shutter_s   REAL,
  iso         INTEGER,
  lat         REAL,
  lng         REAL,
  width       INTEGER,
  height      INTEGER,
  rating      INTEGER,            -- 0-5 (Lightroom star rating)
  indexed_at  INTEGER NOT NULL    -- Unix timestamp; used for incremental updates
);

-- Vector index (cosine similarity)
CREATE VIRTUAL TABLE asset_vectors USING vec0(
  id          TEXT PRIMARY KEY,
  embedding   FLOAT[512]          -- change to 768 if using ViT-L/14
);
```

**Query pattern (semantic + filters combined):**
```sql
SELECT a.id, a.file_path, a.camera_model, a.captured_at,
       v.distance
FROM asset_vectors v
JOIN assets a ON a.id = v.id
WHERE v.embedding MATCH ?           -- query vector blob
  AND k = 200                       -- over-fetch for post-filtering
  AND a.aperture <= 2.8
  AND a.captured_at BETWEEN ? AND ?
ORDER BY v.distance
LIMIT 20;
```
Fetch `k=200` from the vector index, then SQL filters on `assets` narrow the result. This avoids re-running CLIP for filtering.

**Index file location:** `~/Library/Application Support/LightSearch/index.db`

---

## 7. Search Pipeline

Each search runs in under 200ms on an M1 (excluding cold model load).

**Steps:**
1. User types query text in SwiftUI — debounce 300ms
2. `SearchEngine.encode(text:)` — pass to CoreML CLIP text encoder, returns Float32[512]
3. L2-normalize the query vector
4. Run the sqlite-vec SQL query (over-fetch k=200, apply SQL filters)
5. Re-rank: sort by cosine distance, take top N
6. Apply minimum score threshold to drop irrelevant results (key lesson from EmbeddingExperiment)
7. Return `[SearchResult]` to SwiftUI

**Score thresholds (empirical from EmbeddingExperiment, tune after testing):**

| Asset type | Min cosine similarity | Rationale |
| --- | --- | --- |
| Image | 0.68 | Cross-modal gap: text-to-image scores ~8pp lower |
| Video | 0.71 | Less gap than image |
| Text / caption | 0.76 | Same modality as query |

If no results pass the threshold, return empty rather than low-confidence noise — this was the key fix from EmbeddingExperiment (a query for "china" with no China assets returned Singapore results without this guard).

**Filter types exposed in UI:**
- Date range (calendar picker)
- Camera body (multi-select, populated from index)
- Lens (multi-select)
- Aperture max (slider: f/1.4 to f/22)
- GPS bounding box (map picker, optional)
- Star rating minimum
- Asset type: photo / video / both

---

## 8. SwiftUI App Structure

**Main views:**
```
LightSearchApp
+-- ContentView
    +-- SearchBarView          (text field + filter chips)
    +-- FilterPanelView        (collapsible: date, camera, lens, aperture, GPS, rating)
    +-- ResultsGridView        (LazyVGrid of ResultCardView)
    |   +-- ResultCardView     (thumbnail, score badge, metadata line)
    +-- DetailView             (full-size preview + all EXIF, on click)
```

**Data flow (ObservableObject):**
```swift
@Observable class SearchViewModel {
    var query: String = ""
    var filters: SearchFilters = .init()
    var results: [SearchResult] = []
    var isIndexing: Bool = false
    var indexProgress: Double = 0

    func search() async { ... }    // debounced, calls SearchEngine
    func triggerReindex() { ... }  // kicks off BackgroundIndexer
}
```

**Thumbnail loading:** use `NSImage(contentsOf:)` inside a `Task` per card; cache with `NSCache<NSURL, NSImage>`. For RAW files, load the embedded JPEG preview via `CGImageSourceCreateThumbnailAtIndex` (fast — does not decode the full RAW).

**Menu bar:** add an `NSStatusItem` showing index progress and a "Re-index" action. Useful while the app is in the background.

**Settings window:** catalog path picker, index location, CoreML model variant (B/32 vs L/14), max results count.

---

## 9. Indexing Pipeline

The `BackgroundIndexer` actor runs on a low-priority `Task`. It never blocks the UI.

**First run (full index):**
1. Open catalog SQLite read-only
2. SELECT all asset rows not yet in `assets` table
3. For each asset (batched in groups of 32):
   a. Reconstruct absolute file path
   b. Read EXIF via `ImageIO` / `AVAsset`
   c. Load image thumbnail (max 224×224 — CLIP's input size)
   d. Run `CLIPModel.encode(image:)` on ANE
   e. INSERT into `assets` and `asset_vectors`
4. Commit every 500 rows

**Incremental updates:**
- `kqueue` watcher fires on `.lrcat` write
- Re-query rows with `id_local` not in `assets` OR `indexed_at < catalog_modified_at`
- Same per-asset steps above; UPDATE existing rows

**Performance targets:**

| Catalog size | First index time | Incremental (50 new photos) |
| --- | --- | --- |
| 10k photos | ~30 min (M1) | ~90 sec |
| 50k photos | ~2.5 hr (M1) | ~90 sec |
| 150k photos | ~7.5 hr (M1) | ~90 sec |

Index runs at ~60 images/min on M1 ANE. Let it run overnight for large catalogs.

**Interruption handling:** write a `checkpoint` row after each commit. On next launch, resume from the last checkpoint — no re-embedding already-indexed assets.

**Sandboxing note:** request `com.apple.security.files.user-selected.read-only` entitlement. Ask the user to grant access to their Pictures folder on first launch via `NSOpenPanel`.

---

## 10. Key APIs & Dependencies

| Dependency | Purpose | Notes |
| --- | --- | --- |
| `CoreML` (Apple) | Run CLIP model on ANE | Built-in, zero config |
| `ImageIO` (Apple) | Read EXIF from any image format | Built-in; handles RAW via `CGImageSource` |
| `AVFoundation` (Apple) | EXIF + metadata from video files | Built-in |
| `SQLite.swift` | Type-safe SQLite wrapper | SPM: `stephencelis/SQLite.swift` |
| `sqlite-vec` | Vector similarity search extension | `.dylib` bundled in app; github.com/asg017/sqlite-vec |
| CoreML CLIP model | `.mlpackage` file | Pre-converted ViT-B/32; ~600MB; bundle or download on first launch |

**Swift Package dependencies (Package.swift):**
```swift
dependencies: [
    .package(url: "https://github.com/stephencelis/SQLite.swift", from: "0.15.0"),
]
```

**Entitlements needed:**
- `com.apple.security.files.user-selected.read-only` — read Photos/Lightroom catalog
- `com.apple.security.app-sandbox` — required for Mac App Store distribution

**macOS deployment target:** 14.0 (Sonoma) minimum — required for the `@Observable` macro used in the view model.

---

## 11. Lessons from EmbeddingExperiment

The Ubuntu prototype (`/home/jiyao/AI/EmbeddingExperiment`) validated the core ideas and produced several findings that carry directly into this app.

**What transfers:**

| Finding | How it applies |
| --- | --- |
| Text-to-image cosine scores are ~8pp lower than text-to-text | Use separate min-score thresholds per type (Section 7) — don't use a single global cutoff |
| Without a min-score threshold, irrelevant results appear confidently ("china" query returned Singapore) | Always filter by threshold before returning results |
| Modality-bucketing: guarantee N results per type when no type filter is active | Useful if you want to show both image and video results even when one modality scores lower |
| L2-normalize all vectors at index time, not at query time | Pre-normalize on INSERT into `asset_vectors`; search becomes a plain dot product |
| Over-fetching (k=200) then SQL-filtering is faster than filtering inside the vector scan | Use the `k=200` pattern in sqlite-vec queries |
| The model loads in ~15s cold; keep it resident | Load `CLIPModel` at app startup and keep in memory — don't reload per query |

**What does NOT transfer (Python-specific):**
- The Flask server, conda environment, PyTorch code
- The pre-computed `.npz` embeddings (different dataset)
- The `AutoProcessor` API (Hugging Face) — replaced by CoreML model loading

**Key reference files:**
- `scripts/search.py` — the search ranking logic (threshold, bucketing, normalization)
- `scripts/search_server.py` — the `_search()` function logic
- `results/metadata.json` — the metadata schema design

---

## 12. Milestones

| Phase | Deliverable | Done when |
| --- | --- | --- |
| M1: Skeleton | Xcode project, SwiftUI shell, SQLite.swift + sqlite-vec wired up | App launches, empty results grid shows |
| M2: Catalog reader | Read `.lrcat`, list all assets with absolute paths, EXIF extraction | `assets` table populates for a real catalog |
| M3: Embedding | CoreML CLIP loads, embeds one test image and one test text query, cosine similarity matches | Smoke test: "golden hour" query returns a sunset photo |
| M4: Full index | `BackgroundIndexer` indexes entire catalog, progress shown in menu bar | 1k-photo catalog fully indexed |
| M5: Search UI | Search bar, filter chips, results grid, thumbnail loading, score badge | End-to-end search works for text queries |
| M6: Filters | Date range, camera, lens, aperture, GPS, rating filters wired to SQL | Filtered queries return correct subsets |
| M7: Detail view | Click a result to see full-size preview + all EXIF metadata | Detail view shows all fields |
| M8: Polish | Incremental index on catalog change, Settings window, empty-state UI, error handling | App handles catalog moves, missing files gracefully |

**Suggested start:** M1 + M2 together (no ML yet) — validates the Lightroom catalog reading which is the most uncertain part.
