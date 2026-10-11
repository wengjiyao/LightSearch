//
//  SearchEngine.swift
//  LightSearch
//
//  Executes semantic search queries using sqlite-vec
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.lightsearch.LightSearch", category: "Search")

/// A single search result
struct SearchResult: Identifiable {
    let id: String
    let filePath: String
    let score: Float  // Cosine similarity (0-1, higher is better)
    let asset: Asset

    /// Distance from sqlite-vec (lower is better)
    /// Converted to score for consistency
    init(id: String, filePath: String, distance: Float, asset: Asset) {
        self.id = id
        self.filePath = filePath
        // Convert L2 distance to cosine similarity
        // For normalized vectors: similarity = 1 - (distance^2 / 2)
        self.score = 1.0 - (distance * distance / 2.0)
        self.asset = asset
    }
}

/// Search filters for metadata
struct SearchFilters {
    var dateRange: ClosedRange<Date>?
    var cameras: Set<String>?
    var lenses: Set<String>?
    var maxAperture: Double?
    var minRating: Int?
    var hasGPS: Bool?

    /// Convert filters to SQL WHERE clause
    func toSQL() -> String {
        var clauses: [String] = []

        if let dateRange = dateRange {
            let start = Int(dateRange.lowerBound.timeIntervalSince1970)
            let end = Int(dateRange.upperBound.timeIntervalSince1970)
            clauses.append("a.captured_at BETWEEN \(start) AND \(end)")
        }

        if let cameras = cameras, !cameras.isEmpty {
            let quoted = cameras.map { "'\($0)'" }.joined(separator: ", ")
            clauses.append("a.camera_model IN (\(quoted))")
        }

        if let lenses = lenses, !lenses.isEmpty {
            let quoted = lenses.map { "'\($0)'" }.joined(separator: ", ")
            clauses.append("a.lens IN (\(quoted))")
        }

        if let maxAperture = maxAperture {
            clauses.append("a.aperture <= \(maxAperture)")
        }

        if let minRating = minRating {
            clauses.append("a.rating >= \(minRating)")
        }

        if let hasGPS = hasGPS, hasGPS {
            clauses.append("a.lat IS NOT NULL AND a.lng IS NOT NULL")
        }

        if clauses.isEmpty {
            return ""
        } else {
            return "AND " + clauses.joined(separator: " AND ")
        }
    }
}

enum SearchError: Error {
    case noEmbeddings
    case queryFailed(String)
    case modelNotAvailable
}

/// Search engine for semantic queries
actor SearchEngine {
    private let database: IndexDatabase
    private let clipModel: SimpleCLIPModel

    /// Minimum similarity score for text-to-image matches
    /// Based on embedding experiments: text-to-image scores ~8pp lower than text-to-text
    private let textToImageThreshold: Float = 0.68

    /// Over-fetch factor for filtering
    /// We fetch more results than needed, then filter by metadata and threshold
    private let overFetchMultiplier = 4

    init() async throws {
        self.database = try IndexDatabase()
        self.clipModel = SimpleCLIPModel()
    }

    /// Execute a semantic search query
    /// - Parameters:
    ///   - query: Natural language search query
    ///   - filters: Optional metadata filters
    ///   - limit: Maximum number of results to return
    /// - Returns: Array of SearchResult, sorted by relevance
    func search(query: String, filters: SearchFilters = SearchFilters(), limit: Int = 50) async throws -> [SearchResult] {
        guard !query.isEmpty else {
            return []
        }

        logger.info("Searching for: \"\(query)\"")

        // Check if we have any vectors
        let vectorCount = try await database.countVectors()
        guard vectorCount > 0 else {
            throw SearchError.noEmbeddings
        }

        // Encode query text to embedding
        let queryEmbedding = await clipModel.encode(text: query)

        // Over-fetch to account for filtering
        let kValue = limit * overFetchMultiplier

        // Execute vector search with sqlite-vec
        let results = try await executeVectorSearch(
            queryEmbedding: queryEmbedding,
            filters: filters,
            k: kValue
        )

        // Filter by score threshold
        let filtered = results.filter { $0.score >= textToImageThreshold }

        logger.info("Found \(filtered.count) results above threshold (searched \(results.count))")

        // Return top results
        return Array(filtered.prefix(limit))
    }

    /// Execute vector similarity search using sqlite-vec
    private func executeVectorSearch(
        queryEmbedding: [Float],
        filters: SearchFilters,
        k: Int
    ) async throws -> [SearchResult] {
        // Convert embedding to binary format
        let embeddingData = queryEmbedding.withUnsafeBytes { Data($0) }

        // Build SQL query with vector search and filters
        let filterSQL = filters.toSQL()

        let sql = """
            SELECT
                a.id,
                a.file_path,
                a.captured_at,
                a.camera_make,
                a.camera_model,
                a.lens,
                a.focal_mm,
                a.aperture,
                a.shutter_s,
                a.iso,
                a.lat,
                a.lng,
                a.width,
                a.height,
                a.rating,
                a.indexed_at,
                v.distance
            FROM asset_vectors v
            JOIN assets a ON a.id = v.id
            WHERE v.embedding MATCH ? AND k = ?
            \(filterSQL)
            ORDER BY v.distance
            """

        do {
            // Execute query via IndexDatabase
            let results = try await database.executeVectorQuery(
                sql: sql,
                embedding: embeddingData,
                k: k
            )

            return results
        } catch {
            logger.error("Vector search failed: \(error.localizedDescription)")
            throw SearchError.queryFailed(error.localizedDescription)
        }
    }

    /// Get available filter options from indexed assets
    func getFilterOptions() async throws -> (cameras: [String], lenses: [String]) {
        let cameras = try await database.getDistinctCameras()
        let lenses = try await database.getDistinctLenses()
        return (cameras, lenses)
    }
}
