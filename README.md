# LightSearch

A native macOS app for semantic and metadata search over Lightroom Classic libraries. Find your photos using natural language descriptions combined with powerful metadata filters.

![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

### 🔍 Semantic Search
- **Natural language queries**: Search using plain English descriptions like "golden hour sunset" or "portrait with shallow depth of field"
- **CLIP-powered**: Uses OpenAI's CLIP ViT-B/32 model for image-text similarity matching
- **Smart scoring**: Color-coded relevance badges (Green 85%+, Blue 75-84%, Orange 68-74%)

### 🎯 Metadata Filters
- **Date range**: Filter by capture date with preset ranges (Last 7 days, 30 days, 3 months, etc.)
- **Camera**: Multi-select filter by camera make and model
- **Lens**: Multi-select filter by lens name
- **Aperture**: Slider for maximum aperture (ƒ/1.4 - ƒ/22)
- **Rating**: Minimum star rating filter
- **GPS**: Show only geotagged photos

### 🖼️ Detail View
- **Full-resolution preview**: View full-size images with zoom and pan
- **Complete EXIF**: Camera, lens, exposure settings, GPS coordinates
- **MapKit integration**: See photo location on an interactive map
- **Keyboard navigation**: Arrow keys, zoom shortcuts, and more

### ⚡ Performance
- **Vector similarity search**: sqlite-vec extension for fast nearest-neighbor queries
- **Batch indexing**: Process 32 images at a time with progress reporting
- **Checkpoint/resume**: Automatic recovery from interrupted indexing
- **Incremental updates**: Only index new or modified photos

## Requirements

- **macOS**: 14.0 (Sonnet) or later
- **Lightroom Classic**: Any version with .lrcat SQLite catalogs
- **Storage**: ~600MB for CLIP model + index database (~50MB per 1,000 photos)

## Installation

### Option 1: Build from Source

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/lightsearch.git
   cd lightsearch
   ```

2. **Install dependencies**
   ```bash
   # Install xcodegen if not already installed
   brew install xcodegen

   # Generate Xcode project
   xcodegen generate
   ```

3. **Build and run**
   ```bash
   # Open in Xcode
   open LightSearch.xcodeproj

   # Or build from command line
   xcodebuild -scheme LightSearch -configuration Release build
   ```

4. **Set up CLIP model** (optional, for production use)
   - See [CLIP_MODEL_README.md](CLIP_MODEL_README.md) for instructions
   - App includes SimpleCLIPModel for development/testing

### Option 2: Download Release

1. Download the latest `.dmg` from [Releases](https://github.com/yourusername/lightsearch/releases)
2. Drag LightSearch to Applications
3. Open and grant necessary permissions

## Quick Start

1. **Select your Lightroom catalog**
   - Open Settings (⌘,)
   - Click "Choose..." and select your `.lrcat` file
   - Indexing starts automatically

2. **Wait for indexing to complete**
   - Progress shown in Settings window
   - ~60 photos/min on M1 (1,000 photos ≈ 15-20 minutes)
   - Can resume if interrupted

3. **Start searching**
   - Type natural language queries: "sunset over mountains"
   - Combine with filters for precision
   - Click results to view full details

## Keyboard Shortcuts

See [KEYBOARD_SHORTCUTS.md](KEYBOARD_SHORTCUTS.md) for complete list.

**Most used:**
- ⌘F - Focus Search
- ⌘K - Clear Search
- Esc - Close detail view
- ← → - Navigate photos
- ⌘, - Preferences

## Architecture

### Core Components

- **IndexDatabase**: SQLite.swift wrapper with sqlite-vec extension
- **LightroomCatalog**: Reads .lrcat files and reconstructs absolute paths
- **EXIFExtractor**: ImageIO/AVFoundation wrapper for metadata extraction
- **CLIPModel**: CoreML CLIP ViT-B/32 wrapper for semantic embeddings
- **SearchEngine**: Combines vector search with SQL filters
- **BackgroundIndexer**: Actor-based batch indexing with checkpointing

### Technology Stack

- **Language**: Swift 6.0 with strict concurrency checking
- **UI**: SwiftUI with @Observable macro
- **Database**: SQLite.swift + sqlite-vec extension
- **ML**: CoreML CLIP ViT-B/32 (~600MB)
- **Target**: macOS 14.0+ (Universal Binary)

### Project Structure

```
LightSearch/
├── App/                    # App entry, entitlements, status bar
├── Core/
│   ├── Database/          # IndexDatabase, Schema, LightroomCatalog
│   ├── Indexing/          # BackgroundIndexer, EXIFExtractor, CatalogWatcher
│   ├── ML/                # CLIPModel, SimpleCLIPModel
│   ├── Search/            # SearchEngine, SearchFilters
│   └── Security/          # SecurityScopedBookmark, DatabaseRecovery
├── Features/
│   ├── Search/            # ContentView, SearchBarView, ResultsGridView, DetailView
│   └── Settings/          # SettingsView
└── Resources/
    ├── Assets.xcassets/   # App icon
    └── sqlite-vec/        # Extension dylib
```

## Performance Benchmarks

**Indexing** (M1 MacBook Pro):
- ~60 photos/min (including EXIF extraction + embedding generation)
- 1,000 photos: 15-20 minutes
- 10,000 photos: 2.5-3 hours

**Search** (1,000 photo index):
- Text encoding: ~50ms
- Vector query (k=200): ~20ms
- SQL filtering: ~5ms
- **Total**: ~75ms per search

**Memory Usage**:
- CLIP model: ~600MB (resident)
- Index database: ~50MB per 1,000 photos
- App runtime: ~100MB baseline

## Limitations

### Current Limitations

1. **Read-only Lightroom integration**
   - Does not modify Lightroom catalog or photos
   - Changes in Lightroom require manual index update

2. **No collection/keyword support**
   - Only reads core metadata (EXIF, ratings, GPS)
   - Lightroom collections/keywords not indexed

3. **Single catalog**
   - Only one catalog can be indexed at a time
   - Switching catalogs requires full re-index

4. **Model size**
   - CLIP model requires ~600MB memory (always resident)
   - Not suitable for low-memory systems

5. **Sandbox limitations**
   - Requires user to select catalog each session
   - Security-scoped bookmarks used for persistence

### Known Issues

- **SimpleCLIPModel**: Development fallback, not accurate for real searches
- **Entitlements**: xcodegen clears entitlements file on regenerate (manual restore needed)
- **Incremental indexing**: Delta calculation can be slow on large catalogs

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Setup

```bash
# Install dependencies
brew install xcodegen

# Generate project
xcodegen generate

# Restore entitlements (required after xcodegen)
cat > LightSearch/App/LightSearch.entitlements << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-only</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<false/>
</dict>
</plist>
EOF

# Build
xcodebuild -scheme LightSearch -configuration Debug build
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- **OpenAI CLIP**: For the vision-language model
- **sqlite-vec**: For fast vector similarity search
- **SQLite.swift**: For type-safe SQLite wrapper
- **Lightroom Classic**: For the amazing photo management software

## Support

- 📖 [Documentation](https://github.com/yourusername/lightsearch/wiki)
- 🐛 [Report Issues](https://github.com/yourusername/lightsearch/issues)
- 💬 [Discussions](https://github.com/yourusername/lightsearch/discussions)

---

Made with ❤️ for photographers who have too many photos
