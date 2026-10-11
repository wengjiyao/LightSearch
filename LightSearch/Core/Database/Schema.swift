//
//  Schema.swift
//  LightSearch
//
//  SQLite database schema definitions
//

import Foundation
import SQLite

struct Schema {
    /// SQL statements to create the database schema
    static let createStatements = [
        """
        CREATE TABLE IF NOT EXISTS assets (
            id TEXT PRIMARY KEY,
            file_path TEXT NOT NULL,
            captured_at INTEGER,
            camera_make TEXT,
            camera_model TEXT,
            lens TEXT,
            focal_mm REAL,
            aperture REAL,
            shutter_s REAL,
            iso INTEGER,
            lat REAL,
            lng REAL,
            width INTEGER,
            height INTEGER,
            rating INTEGER,
            indexed_at INTEGER NOT NULL
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_captured_at ON assets(captured_at)",
        "CREATE INDEX IF NOT EXISTS idx_camera_model ON assets(camera_model)",
        "CREATE INDEX IF NOT EXISTS idx_lens ON assets(lens)",
        "CREATE INDEX IF NOT EXISTS idx_rating ON assets(rating)",
        """
        CREATE VIRTUAL TABLE IF NOT EXISTS asset_vectors USING vec0(
            id TEXT PRIMARY KEY,
            embedding FLOAT[512]
        )
        """
    ]

    /// Asset table column definitions
    struct Assets {
        static let id = Expression<String>("id")
        static let filePath = Expression<String>("file_path")
        static let capturedAt = Expression<Int?>("captured_at")
        static let cameraMake = Expression<String?>("camera_make")
        static let cameraModel = Expression<String?>("camera_model")
        static let lens = Expression<String?>("lens")
        static let focalMm = Expression<Double?>("focal_mm")
        static let aperture = Expression<Double?>("aperture")
        static let shutterS = Expression<Double?>("shutter_s")
        static let iso = Expression<Int?>("iso")
        static let lat = Expression<Double?>("lat")
        static let lng = Expression<Double?>("lng")
        static let width = Expression<Int?>("width")
        static let height = Expression<Int?>("height")
        static let rating = Expression<Int?>("rating")
        static let indexedAt = Expression<Int>("indexed_at")
    }
}
