//
//  SecurityScopedBookmark.swift
//  LightSearch
//
//  Security-scoped bookmarks for sandboxed file access
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.lightsearch.LightSearch", category: "Security")

enum BookmarkError: Error {
    case creationFailed(String)
    case resolutionFailed(String)
    case accessDenied(String)
}

@MainActor
class SecurityScopedBookmark {
    /// Save a security-scoped bookmark for a URL
    /// - Parameters:
    ///   - url: The URL to bookmark
    ///   - key: UserDefaults key for storage
    /// - Throws: BookmarkError if creation fails
    static func saveBookmark(for url: URL, key: String) throws {
        do {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            UserDefaults.standard.set(bookmarkData, forKey: key)
            logger.info("Saved security-scoped bookmark for: \(url.path)")
        } catch {
            logger.error("Failed to create bookmark: \(error.localizedDescription)")
            throw BookmarkError.creationFailed(error.localizedDescription)
        }
    }

    /// Resolve a security-scoped bookmark and start accessing the resource
    /// - Parameter key: UserDefaults key where bookmark is stored
    /// - Returns: The resolved URL if successful
    /// - Throws: BookmarkError if resolution fails
    static func resolveBookmark(forKey key: String) throws -> URL {
        guard let bookmarkData = UserDefaults.standard.data(forKey: key) else {
            throw BookmarkError.resolutionFailed("No bookmark found for key: \(key)")
        }

        var isStale = false
        let url: URL

        do {
            url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            logger.error("Failed to resolve bookmark: \(error.localizedDescription)")
            throw BookmarkError.resolutionFailed(error.localizedDescription)
        }

        // If bookmark is stale, recreate it
        if isStale {
            logger.warning("Bookmark is stale, recreating...")
            try saveBookmark(for: url, key: key)
        }

        // Start accessing the security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            logger.error("Failed to access security-scoped resource: \(url.path)")
            throw BookmarkError.accessDenied("Cannot access file at \(url.path)")
        }

        logger.info("Resolved and accessing: \(url.path)")
        return url
    }

    /// Stop accessing a security-scoped resource
    /// - Parameter url: The URL to stop accessing
    static func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
        logger.info("Stopped accessing: \(url.path)")
    }

    /// Check if a bookmark exists for a key
    /// - Parameter key: UserDefaults key to check
    /// - Returns: true if bookmark exists
    static func hasBookmark(forKey key: String) -> Bool {
        return UserDefaults.standard.data(forKey: key) != nil
    }

    /// Remove a bookmark
    /// - Parameter key: UserDefaults key to remove
    static func removeBookmark(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: key)
        logger.info("Removed bookmark for key: \(key)")
    }
}
