//
//  BackgroundIndexer.swift
//  LightSearch
//
//  Background actor for indexing Lightroom catalogs
//

import Foundation
import AppKit
import os.log

private let logger = Logger(subsystem: "com.lightsearch.LightSearch", category: "Indexing")

/// Progress information for indexing
struct IndexProgress {
    let current: Int
    let total: Int
    let currentFile: String?

    var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
}

enum IndexerError: Error {
    case catalogReadFailed(String)
    case databaseError(String)
    case cancelled
    case checkpointLoadFailed(String)
}

/// Indexing checkpoint for resuming interrupted indexing
struct IndexCheckpoint: Codable {
    let catalogPath: String
    let lastProcessedId: String
    let timestamp: Date
}

/// Background actor for indexing photos
@MainActor
@Observable
class BackgroundIndexer {
    // Observable state
    var isIndexing = false
    var progress: IndexProgress?
    var error: Error?

    // Internal state
    private var indexDatabase: IndexDatabase?
    private var clipModel: SimpleCLIPModel?
    private var isCancelled = false
    private var enableEmbeddings = true  // Set to false to skip embedding generation

    // Batch processing configuration
    private let batchSize = 32  // Process 32 images at a time
    private let commitInterval = 500  // Commit every 500 rows

    // Checkpoint keys
    private let checkpointKey = "LightSearch.IndexCheckpoint"

    init() {}

    // MARK: - Checkpoint Management

    /// Save checkpoint to UserDefaults
    private func saveCheckpoint(catalogPath: String, lastProcessedId: String) {
        let checkpoint = IndexCheckpoint(
            catalogPath: catalogPath,
            lastProcessedId: lastProcessedId,
            timestamp: Date()
        )

        if let encoded = try? JSONEncoder().encode(checkpoint) {
            UserDefaults.standard.set(encoded, forKey: checkpointKey)
            logger.info("Checkpoint saved: \(lastProcessedId)")
        }
    }

    /// Load checkpoint from UserDefaults
    private func loadCheckpoint(for catalogPath: String) -> IndexCheckpoint? {
        guard let data = UserDefaults.standard.data(forKey: checkpointKey),
              let checkpoint = try? JSONDecoder().decode(IndexCheckpoint.self, from: data) else {
            return nil
        }

        // Only use checkpoint if it's for the same catalog
        guard checkpoint.catalogPath == catalogPath else {
            logger.info("Checkpoint is for different catalog, ignoring")
            return nil
        }

        logger.info("Checkpoint found: resuming from \(checkpoint.lastProcessedId)")
        return checkpoint
    }

    /// Clear checkpoint
    private func clearCheckpoint() {
        UserDefaults.standard.removeObject(forKey: checkpointKey)
        logger.info("Checkpoint cleared")
    }

    /// Start indexing a catalog
    /// - Parameter catalogPath: Path to .lrcat file
    func startIndexing(catalogPath: String) async {
        // Reset state
        isIndexing = true
        progress = nil
        error = nil
        isCancelled = false

        // Notify status bar
        NotificationCenter.default.post(name: .indexingDidStart, object: nil)

        do {
            // Initialize database connection
            let db = try IndexDatabase()
            indexDatabase = db

            // Initialize CLIP model if embeddings are enabled
            if enableEmbeddings {
                logger.info("Initializing CLIP model...")
                clipModel = SimpleCLIPModel()
                logger.info("CLIP model ready")
            }

            logger.info("Starting indexing of catalog: \(catalogPath)")

            // Open catalog
            let catalog = try LightroomCatalog(catalogPath: catalogPath)

            // Get total count
            let totalPhotos = try await catalog.countPhotos()
            logger.info("Found \(totalPhotos) photos in catalog")

            progress = IndexProgress(current: 0, total: totalPhotos, currentFile: nil)

            // Read all photos
            var photos = try await catalog.readPhotos()

            // Check for checkpoint and resume if available
            let checkpoint = loadCheckpoint(for: catalogPath)
            var startIndex = 0

            if let checkpoint = checkpoint {
                // Find the index of the last processed photo
                if let index = photos.firstIndex(where: { $0.id == checkpoint.lastProcessedId }) {
                    startIndex = index + 1  // Start from the next photo
                    logger.info("Resuming from checkpoint: skipping \(startIndex) photos")
                }
            }

            // Slice photos from start index
            let photosToProcess = Array(photos[startIndex...])

            // Process photos in batches
            var indexed = startIndex
            var batchAssets: [Asset] = []
            var batchVectors: [(assetId: String, embedding: [Float])] = []

            try await db.beginTransaction()

            for photo in photosToProcess {
                // Check for cancellation
                if isCancelled {
                    try await db.rollbackTransaction()
                    saveCheckpoint(catalogPath: catalogPath, lastProcessedId: photo.id)
                    throw IndexerError.cancelled
                }

                // Update progress
                progress = IndexProgress(
                    current: indexed,
                    total: totalPhotos,
                    currentFile: photo.filename
                )

                // Notify status bar of progress (every 10 photos to avoid spam)
                if indexed % 10 == 0 {
                    NotificationCenter.default.post(
                        name: .indexingDidUpdate,
                        object: nil,
                        userInfo: ["progress": progress!.percentage]
                    )
                }

                // Get absolute path
                let absolutePath = photo.absolutePath(catalogPath: catalogPath)

                // Extract EXIF metadata
                var exif: EXIFMetadata
                do {
                    exif = try EXIFExtractor.extract(from: absolutePath)
                } catch {
                    // Log error but continue processing
                    logger.warning("Failed to extract EXIF from \(photo.filename): \(error.localizedDescription)")
                    exif = EXIFMetadata()
                }

                // Use Lightroom's capture time if EXIF doesn't have it
                let capturedAt = exif.capturedAt ?? photo.captureTime

                // Create asset record
                let asset = Asset(
                    id: photo.id,
                    filePath: absolutePath,
                    capturedAt: capturedAt,
                    cameraMake: exif.cameraMake,
                    cameraModel: exif.cameraModel,
                    lens: exif.lens,
                    focalMm: exif.focalMm,
                    aperture: exif.aperture,
                    shutterS: exif.shutterS,
                    iso: exif.iso,
                    lat: exif.lat,
                    lng: exif.lng,
                    width: exif.width,
                    height: exif.height,
                    rating: photo.rating,
                    indexedAt: Date()
                )

                // Add to batch
                batchAssets.append(asset)

                // Generate embedding if enabled
                if enableEmbeddings, let clipModel = clipModel {
                    do {
                        if let thumbnail = loadImageThumbnail(from: absolutePath) {
                            let embedding = await clipModel.encode(image: thumbnail)
                            batchVectors.append((assetId: photo.id, embedding: embedding))
                        } else {
                            logger.warning("Could not load thumbnail for \(photo.filename)")
                        }
                    } catch {
                        logger.warning("Failed to generate embedding for \(photo.filename): \(error.localizedDescription)")
                    }
                }

                indexed += 1

                // Process batch when full or at commit interval
                if batchAssets.count >= batchSize || indexed % commitInterval == 0 {
                    // Insert batch
                    try await db.insertAssetBatch(batchAssets)
                    if !batchVectors.isEmpty {
                        try await db.insertVectorBatch(batchVectors)
                    }

                    // Clear batches
                    batchAssets.removeAll(keepingCapacity: true)
                    batchVectors.removeAll(keepingCapacity: true)

                    // Commit every commitInterval rows
                    if indexed % commitInterval == 0 {
                        try await db.commitTransaction()
                        saveCheckpoint(catalogPath: catalogPath, lastProcessedId: photo.id)
                        try await db.beginTransaction()

                        let vectorCount = (try? await db.countVectors()) ?? 0
                        logger.info("Progress: \(indexed)/\(totalPhotos) photos (\(vectorCount) embeddings) - checkpoint saved")
                    }
                }
            }

            // Process remaining items in batch
            if !batchAssets.isEmpty {
                try await db.insertAssetBatch(batchAssets)
                if !batchVectors.isEmpty {
                    try await db.insertVectorBatch(batchVectors)
                }
            }

            // Final commit
            try await db.commitTransaction()

            // Final progress update
            progress = IndexProgress(
                current: indexed,
                total: totalPhotos,
                currentFile: nil
            )

            // Clear checkpoint on successful completion
            clearCheckpoint()

            logger.info("Indexing complete! Indexed \(indexed) photos")

        } catch {
            logger.error("Indexing failed: \(error.localizedDescription)")
            self.error = error

            // Keep checkpoint on error so we can resume
        }

        // Mark as complete
        isIndexing = false

        // Notify status bar of completion
        NotificationCenter.default.post(name: .indexingDidComplete, object: nil)
    }

    /// Cancel ongoing indexing
    func cancel() {
        isCancelled = true
    }

    /// Get current database
    func getDatabase() -> IndexDatabase? {
        return indexDatabase
    }

    /// Check if there's a checkpoint for a catalog
    func hasCheckpoint(for catalogPath: String) -> Bool {
        guard let checkpoint = loadCheckpoint(for: catalogPath) else {
            return false
        }
        return checkpoint.catalogPath == catalogPath
    }

    /// Get checkpoint info if available
    func getCheckpointInfo(for catalogPath: String) -> String? {
        guard let checkpoint = loadCheckpoint(for: catalogPath) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        return "Resume from \(formatter.string(from: checkpoint.timestamp))"
    }

    // MARK: - Incremental Indexing

    /// Perform incremental indexing (only new/modified photos)
    /// - Parameter catalogPath: Path to .lrcat file
    func incrementalIndexing(catalogPath: String) async {
        // Reset state
        isIndexing = true
        progress = nil
        error = nil
        isCancelled = false

        do {
            // Initialize database connection
            let db = try IndexDatabase()
            indexDatabase = db

            // Initialize CLIP model if embeddings are enabled
            if enableEmbeddings {
                logger.info("Initializing CLIP model...")
                clipModel = SimpleCLIPModel()
            }

            logger.info("Starting incremental indexing of catalog: \(catalogPath)")

            // Open catalog
            let catalog = try LightroomCatalog(catalogPath: catalogPath)

            // Get all photos from catalog
            let catalogPhotos = try await catalog.readPhotos()
            logger.info("Found \(catalogPhotos.count) photos in catalog")

            // Get existing asset IDs from database
            let existingIds = try await db.getAllAssetIds()
            logger.info("Found \(existingIds.count) photos in index")

            // Find new photos (in catalog but not in database)
            let catalogIds = Set(catalogPhotos.map { $0.id })
            let newPhotoIds = catalogIds.subtracting(existingIds)

            // Find deleted photos (in database but not in catalog)
            let deletedPhotoIds = existingIds.subtracting(catalogIds)

            logger.info("Changes: \(newPhotoIds.count) new, \(deletedPhotoIds.count) deleted")

            // Delete removed photos
            if !deletedPhotoIds.isEmpty {
                try await db.beginTransaction()
                for photoId in deletedPhotoIds {
                    try await db.deleteAsset(id: photoId)
                }
                try await db.commitTransaction()
                logger.info("Deleted \(deletedPhotoIds.count) removed photos")
            }

            // Index new photos
            if !newPhotoIds.isEmpty {
                let newPhotos = catalogPhotos.filter { newPhotoIds.contains($0.id) }

                progress = IndexProgress(current: 0, total: newPhotos.count, currentFile: nil)

                var indexed = 0
                var batchAssets: [Asset] = []
                var batchVectors: [(assetId: String, embedding: [Float])] = []

                try await db.beginTransaction()

                for photo in newPhotos {
                    if isCancelled {
                        try await db.rollbackTransaction()
                        throw IndexerError.cancelled
                    }

                    progress = IndexProgress(
                        current: indexed,
                        total: newPhotos.count,
                        currentFile: photo.filename
                    )

                    let absolutePath = photo.absolutePath(catalogPath: catalogPath)

                    var exif: EXIFMetadata
                    do {
                        exif = try EXIFExtractor.extract(from: absolutePath)
                    } catch {
                        logger.warning("Failed to extract EXIF from \(photo.filename): \(error.localizedDescription)")
                        exif = EXIFMetadata()
                    }

                    let capturedAt = exif.capturedAt ?? photo.captureTime

                    let asset = Asset(
                        id: photo.id,
                        filePath: absolutePath,
                        capturedAt: capturedAt,
                        cameraMake: exif.cameraMake,
                        cameraModel: exif.cameraModel,
                        lens: exif.lens,
                        focalMm: exif.focalMm,
                        aperture: exif.aperture,
                        shutterS: exif.shutterS,
                        iso: exif.iso,
                        lat: exif.lat,
                        lng: exif.lng,
                        width: exif.width,
                        height: exif.height,
                        rating: photo.rating,
                        indexedAt: Date()
                    )

                    batchAssets.append(asset)

                    // Generate embedding if enabled
                    if enableEmbeddings, let clipModel = clipModel {
                        do {
                            if let thumbnail = loadImageThumbnail(from: absolutePath) {
                                let embedding = await clipModel.encode(image: thumbnail)
                                batchVectors.append((assetId: photo.id, embedding: embedding))
                            }
                        } catch {
                            logger.warning("Failed to generate embedding for \(photo.filename): \(error.localizedDescription)")
                        }
                    }

                    indexed += 1

                    // Process batch
                    if batchAssets.count >= batchSize || indexed % commitInterval == 0 {
                        try await db.insertAssetBatch(batchAssets)
                        if !batchVectors.isEmpty {
                            try await db.insertVectorBatch(batchVectors)
                        }

                        batchAssets.removeAll(keepingCapacity: true)
                        batchVectors.removeAll(keepingCapacity: true)

                        if indexed % commitInterval == 0 {
                            try await db.commitTransaction()
                            try await db.beginTransaction()
                            logger.info("Progress: \(indexed)/\(newPhotos.count) new photos indexed")
                        }
                    }
                }

                // Process remaining
                if !batchAssets.isEmpty {
                    try await db.insertAssetBatch(batchAssets)
                    if !batchVectors.isEmpty {
                        try await db.insertVectorBatch(batchVectors)
                    }
                }

                try await db.commitTransaction()

                logger.info("Incremental indexing complete! Added \(indexed) new photos")
            } else {
                logger.info("No new photos to index")
            }

            progress = IndexProgress(
                current: newPhotoIds.count,
                total: newPhotoIds.count,
                currentFile: nil
            )

        } catch {
            logger.error("Incremental indexing failed: \(error.localizedDescription)")
            self.error = error
        }

        isIndexing = false
    }

    /// Load image thumbnail at 224x224 (CLIP input size)
    private nonisolated func loadImageThumbnail(from path: String) -> NSImage? {
        guard let image = NSImage(contentsOfFile: path) else {
            return nil
        }

        // Resize to 224x224
        let targetSize = NSSize(width: 224, height: 224)
        let thumbnail = NSImage(size: targetSize)

        thumbnail.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        thumbnail.unlockFocus()

        return thumbnail
    }
}
