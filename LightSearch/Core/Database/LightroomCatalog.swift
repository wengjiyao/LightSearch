//
//  LightroomCatalog.swift
//  LightSearch
//
//  Reads Lightroom Classic catalog files (.lrcat)
//

import Foundation
import SQLite

/// Represents a photo from Lightroom catalog
struct LightroomPhoto {
    let id: String
    let filename: String
    let folderPath: String
    let captureTime: Date?
    let rating: Int?
    let fileExtension: String

    /// Construct absolute file path
    func absolutePath(catalogPath: String) -> String {
        let catalogDir = URL(fileURLWithPath: catalogPath).deletingLastPathComponent().path
        let fullPath = catalogDir + folderPath + "/" + filename
        return fullPath
    }
}

enum LightroomCatalogError: Error {
    case invalidCatalogPath
    case connectionFailed(String)
    case queryFailed(String)
    case catalogNotAccessible
}

/// Reads Lightroom Classic SQLite catalog
actor LightroomCatalog {
    private let catalogPath: String
    private let connection: Connection

    /// Initialize with path to .lrcat file
    init(catalogPath: String) throws {
        guard FileManager.default.fileExists(atPath: catalogPath) else {
            throw LightroomCatalogError.invalidCatalogPath
        }

        self.catalogPath = catalogPath

        // Open catalog read-only
        do {
            self.connection = try Connection(catalogPath, readonly: true)
        } catch {
            throw LightroomCatalogError.connectionFailed(error.localizedDescription)
        }
    }

    /// Read all photos from the catalog
    /// - Returns: Array of LightroomPhoto objects
    func readPhotos() throws -> [LightroomPhoto] {
        // SQL to join AgLibraryFile, AgLibraryFolder, and Adobe_images tables
        // This reconstructs the file structure from Lightroom's catalog
        let sql = """
            SELECT
                f.id_local AS id,
                f.baseName AS base_name,
                f.extension AS extension,
                fo.pathFromRoot AS folder_path,
                img.captureTime AS capture_time,
                img.rating AS rating
            FROM AgLibraryFile f
            JOIN AgLibraryFolder fo ON fo.id_local = f.folder
            LEFT JOIN Adobe_images img ON img.rootFile = f.id_local
            WHERE f.extension IN ('jpg', 'jpeg', 'JPG', 'JPEG',
                                 'arw', 'ARW',
                                 'cr3', 'CR3',
                                 'nef', 'NEF',
                                 'dng', 'DNG',
                                 'mov', 'MOV',
                                 'mp4', 'MP4')
            ORDER BY f.id_local
            """

        var photos: [LightroomPhoto] = []

        do {
            for row in try connection.prepare(sql) {
                // Extract values from row
                let id = String(row[0] as! Int64)
                let baseName = row[1] as! String
                let ext = row[2] as! String
                let folderPath = row[3] as! String

                // Capture time (may be null)
                var captureTime: Date? = nil
                if let timestamp = row[4] as? Double {
                    // Lightroom stores timestamps as seconds since 2001-01-01
                    // (Core Data / Cocoa reference date)
                    let referenceDate = Date(timeIntervalSinceReferenceDate: 0)
                    captureTime = Date(timeInterval: timestamp, since: referenceDate)
                }

                // Rating (may be null)
                let rating = row[5] as? Int64
                let ratingInt = rating.map { Int($0) }

                let filename = "\(baseName).\(ext)"

                let photo = LightroomPhoto(
                    id: id,
                    filename: filename,
                    folderPath: folderPath,
                    captureTime: captureTime,
                    rating: ratingInt,
                    fileExtension: ext.lowercased()
                )

                photos.append(photo)
            }
        } catch {
            throw LightroomCatalogError.queryFailed(error.localizedDescription)
        }

        return photos
    }

    /// Get catalog path
    func getCatalogPath() -> String {
        return catalogPath
    }

    /// Get count of photos in catalog
    func countPhotos() throws -> Int {
        let sql = """
            SELECT COUNT(*)
            FROM AgLibraryFile f
            WHERE f.extension IN ('jpg', 'jpeg', 'JPG', 'JPEG',
                                 'arw', 'ARW',
                                 'cr3', 'CR3',
                                 'nef', 'NEF',
                                 'dng', 'DNG',
                                 'mov', 'MOV',
                                 'mp4', 'MP4')
            """

        do {
            let count = try connection.scalar(sql) as! Int64
            return Int(count)
        } catch {
            throw LightroomCatalogError.queryFailed(error.localizedDescription)
        }
    }
}
