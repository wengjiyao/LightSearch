//
//  IndexDatabase.swift
//  LightSearch
//
//  Manages the LightSearch index database with sqlite-vec extension
//

import Foundation
import SQLite

/// Asset metadata stored in the index
struct Asset {
    let id: String
    let filePath: String
    let capturedAt: Date?
    let cameraMake: String?
    let cameraModel: String?
    let lens: String?
    let focalMm: Double?
    let aperture: Double?
    let shutterS: Double?
    let iso: Int?
    let lat: Double?
    let lng: Double?
    let width: Int?
    let height: Int?
    let rating: Int?
    let indexedAt: Date
}

enum IndexDatabaseError: Error {
    case extensionLoadFailed(String)
    case connectionFailed(String)
    case schemaCreationFailed(String)
    case insertFailed(String)
}

/// Manages the LightSearch index database
actor IndexDatabase {
    private let connection: Connection
    private let dbPath: String
    private var extensionLoaded = false

    /// Get the default database path
    nonisolated static func databasePath() -> String {
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LightSearch")
            .appendingPathComponent("index.db")
            .path
    }

    /// Initialize database connection
    /// - Parameter path: Path to database file (default: ~/Library/Application Support/LightSearch/index.db)
    init(path: String? = nil) throws {
        // Use default path if not specified
        self.dbPath = path ?? Self.databasePath()

        // Create directory if needed
        let directory = URL(fileURLWithPath: self.dbPath).deletingLastPathComponent().path
        try? FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )

        // Open database connection
        do {
            self.connection = try Connection(self.dbPath)
        } catch {
            throw IndexDatabaseError.connectionFailed(error.localizedDescription)
        }

        // Load extension and create schema in a nonisolated context
        try Self.loadExtension(connection: connection)
        extensionLoaded = true

        try Self.createSchema(connection: connection)
    }

    /// Load the sqlite-vec extension
    private nonisolated static func loadExtension(connection: Connection) throws {
        // Find the extension in the app bundle (directly in Resources)
        guard let extensionPath = Bundle.main.path(
            forResource: "libsqlite_vec",
            ofType: "dylib"
        ) else {
            throw IndexDatabaseError.extensionLoadFailed("Extension not found in bundle")
        }

        do {
            // Load the extension using raw SQL with proper binding
            let stmt = try connection.prepare("SELECT load_extension(?)")
            try stmt.run(extensionPath)

            // Verify extension loaded by checking version
            let version = try connection.scalar("SELECT vec_version()") as? String
            print("sqlite-vec extension loaded successfully. Version: \(version ?? "unknown")")
        } catch {
            throw IndexDatabaseError.extensionLoadFailed(error.localizedDescription)
        }
    }

    /// Create database schema
    private nonisolated static func createSchema(connection: Connection) throws {
        do {
            for statement in Schema.createStatements {
                try connection.execute(statement)
            }
        } catch {
            throw IndexDatabaseError.schemaCreationFailed(error.localizedDescription)
        }
    }

    /// Insert or update an asset in the database
    func insertAsset(_ asset: Asset) throws {
        let table = Table("assets")

        // Convert dates to Unix timestamps
        let capturedAtTimestamp = asset.capturedAt.map { Int($0.timeIntervalSince1970) }
        let indexedAtTimestamp = Int(asset.indexedAt.timeIntervalSince1970)

        let insert = table.insert(
            or: .replace,
            Schema.Assets.id <- asset.id,
            Schema.Assets.filePath <- asset.filePath,
            Schema.Assets.capturedAt <- capturedAtTimestamp,
            Schema.Assets.cameraMake <- asset.cameraMake,
            Schema.Assets.cameraModel <- asset.cameraModel,
            Schema.Assets.lens <- asset.lens,
            Schema.Assets.focalMm <- asset.focalMm,
            Schema.Assets.aperture <- asset.aperture,
            Schema.Assets.shutterS <- asset.shutterS,
            Schema.Assets.iso <- asset.iso,
            Schema.Assets.lat <- asset.lat,
            Schema.Assets.lng <- asset.lng,
            Schema.Assets.width <- asset.width,
            Schema.Assets.height <- asset.height,
            Schema.Assets.rating <- asset.rating,
            Schema.Assets.indexedAt <- indexedAtTimestamp
        )

        do {
            try connection.run(insert)
        } catch {
            throw IndexDatabaseError.insertFailed(error.localizedDescription)
        }
    }

    /// Insert a vector embedding for an asset
    func insertVector(assetId: String, embedding: [Float]) throws {
        // Ensure embedding is 512 dimensions
        guard embedding.count == 512 else {
            throw IndexDatabaseError.insertFailed("Embedding must be 512 dimensions")
        }

        // Convert to binary format expected by sqlite-vec
        let data = embedding.withUnsafeBytes { Data($0) }

        // Insert into virtual table using raw SQL with proper binding
        let stmt = try connection.prepare("""
            INSERT OR REPLACE INTO asset_vectors (id, embedding)
            VALUES (?, ?)
            """)

        do {
            try stmt.run(assetId, data.withUnsafeBytes { Blob(bytes: $0.baseAddress!, length: data.count) })
        } catch {
            throw IndexDatabaseError.insertFailed(error.localizedDescription)
        }
    }

    /// Get the total number of indexed assets
    func countAssets() throws -> Int {
        let table = Table("assets")
        return try connection.scalar(table.count)
    }

    /// Get the total number of vectors
    func countVectors() throws -> Int {
        // Use raw SQL for virtual table
        let count = try connection.scalar("SELECT COUNT(*) FROM asset_vectors") as! Int64
        return Int(count)
    }

    /// Delete all data from the database
    func clearAll() throws {
        try connection.run("DELETE FROM assets")
        try connection.run("DELETE FROM asset_vectors")
    }

    /// Get database file path
    func getDatabasePath() -> String {
        return dbPath
    }

    // MARK: - Batch Operations

    /// Begin a transaction for batch operations
    func beginTransaction() throws {
        try connection.run("BEGIN TRANSACTION")
    }

    /// Commit the current transaction
    func commitTransaction() throws {
        try connection.run("COMMIT")
    }

    /// Rollback the current transaction
    func rollbackTransaction() throws {
        try connection.run("ROLLBACK")
    }

    /// Insert multiple assets in a batch
    /// More efficient than individual inserts when inserting many records
    func insertAssetBatch(_ assets: [Asset]) throws {
        for asset in assets {
            try insertAsset(asset)
        }
    }

    /// Insert multiple vectors in a batch
    func insertVectorBatch(_ vectors: [(assetId: String, embedding: [Float])]) throws {
        for vector in vectors {
            try insertVector(assetId: vector.assetId, embedding: vector.embedding)
        }
    }

    // MARK: - Incremental Indexing

    /// Check if an asset exists in the database
    func assetExists(id: String) throws -> Bool {
        let table = Table("assets")
        let count = try connection.scalar(
            table.filter(Schema.Assets.id == id).count
        )
        return count > 0
    }

    /// Get the last indexed timestamp for an asset
    func getAssetIndexedTime(id: String) throws -> Date? {
        let table = Table("assets")
        let query = table
            .select(Schema.Assets.indexedAt)
            .filter(Schema.Assets.id == id)

        guard let row = try connection.pluck(query) else {
            return nil
        }

        let timestamp = row[Schema.Assets.indexedAt]
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    /// Delete an asset and its vector
    func deleteAsset(id: String) throws {
        let table = Table("assets")
        try connection.run(table.filter(Schema.Assets.id == id).delete())
        try connection.run("DELETE FROM asset_vectors WHERE id = ?", id)
    }

    /// Get all asset IDs in the database
    func getAllAssetIds() throws -> Set<String> {
        let table = Table("assets")
        let query = table.select(Schema.Assets.id)

        var ids = Set<String>()
        for row in try connection.prepare(query) {
            ids.insert(row[Schema.Assets.id])
        }
        return ids
    }

    // MARK: - Search Support

    /// Execute a vector similarity search query
    func executeVectorQuery(sql: String, embedding: Data, k: Int) throws -> [SearchResult] {
        var results: [SearchResult] = []

        let stmt = try connection.prepare(sql)
        let blob = embedding.withUnsafeBytes { Blob(bytes: $0.baseAddress!, length: embedding.count) }

        for row in try stmt.run(blob, k) {
            let id = row[0] as! String
            let filePath = row[1] as! String

            // Captured at (may be null)
            var capturedAt: Date?
            if let timestamp = row[2] as? Int64 {
                capturedAt = Date(timeIntervalSince1970: TimeInterval(timestamp))
            }

            // Optional fields
            let cameraMake = row[3] as? String
            let cameraModel = row[4] as? String
            let lens = row[5] as? String
            let focalMm = row[6] as? Double
            let aperture = row[7] as? Double
            let shutterS = row[8] as? Double
            let iso = row[9] as? Int64
            let lat = row[10] as? Double
            let lng = row[11] as? Double
            let width = row[12] as? Int64
            let height = row[13] as? Int64
            let rating = row[14] as? Int64
            let indexedAt = Date(timeIntervalSince1970: TimeInterval(row[15] as! Int64))

            // Distance from vector search
            let distance = Float(row[16] as! Double)

            let asset = Asset(
                id: id,
                filePath: filePath,
                capturedAt: capturedAt,
                cameraMake: cameraMake,
                cameraModel: cameraModel,
                lens: lens,
                focalMm: focalMm,
                aperture: aperture,
                shutterS: shutterS,
                iso: iso.map { Int($0) },
                lat: lat,
                lng: lng,
                width: width.map { Int($0) },
                height: height.map { Int($0) },
                rating: rating.map { Int($0) },
                indexedAt: indexedAt
            )

            let result = SearchResult(
                id: id,
                filePath: filePath,
                distance: distance,
                asset: asset
            )

            results.append(result)
        }

        return results
    }

    /// Get distinct camera models from indexed assets
    func getDistinctCameras() throws -> [String] {
        let sql = """
            SELECT DISTINCT camera_model
            FROM assets
            WHERE camera_model IS NOT NULL
            ORDER BY camera_model
            """

        var cameras: [String] = []
        for row in try connection.prepare(sql) {
            if let camera = row[0] as? String {
                cameras.append(camera)
            }
        }
        return cameras
    }

    /// Get distinct lenses from indexed assets
    func getDistinctLenses() throws -> [String] {
        let sql = """
            SELECT DISTINCT lens
            FROM assets
            WHERE lens IS NOT NULL
            ORDER BY lens
            """

        var lenses: [String] = []
        for row in try connection.prepare(sql) {
            if let lens = row[0] as? String {
                lenses.append(lens)
            }
        }
        return lenses
    }
}
