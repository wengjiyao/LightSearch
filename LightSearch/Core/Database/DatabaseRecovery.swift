//
//  DatabaseRecovery.swift
//  LightSearch
//
//  Database corruption detection and recovery
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.lightsearch.LightSearch", category: "DatabaseRecovery")

enum RecoveryError: Error {
    case corruptionDetected(String)
    case recoveryFailed(String)
    case backupFailed(String)
}

@MainActor
class DatabaseRecovery {
    private static let dbPath = IndexDatabase.databasePath()
    private static let backupSuffix = ".backup"

    /// Check if database is corrupted
    static func isCorrupted() -> Bool {
        guard FileManager.default.fileExists(atPath: dbPath) else {
            return false
        }

        // Try to open database and perform integrity check
        do {
            let db = try IndexDatabase()
            return !(try checkIntegrity(db: db))
        } catch {
            logger.error("Database corruption detected: \(error.localizedDescription)")
            return true
        }
    }

    /// Perform SQLite PRAGMA integrity_check
    private static func checkIntegrity(db: IndexDatabase) throws -> Bool {
        // This would need to be implemented in IndexDatabase
        // For now, assume database is OK if we can connect
        return true
    }

    /// Create a backup of the database
    static func createBackup() throws {
        let backupPath = dbPath + backupSuffix

        do {
            // Remove old backup if exists
            if FileManager.default.fileExists(atPath: backupPath) {
                try FileManager.default.removeItem(atPath: backupPath)
            }

            // Copy current database to backup
            try FileManager.default.copyItem(atPath: dbPath, toPath: backupPath)
            logger.info("Database backup created: \(backupPath)")
        } catch {
            logger.error("Failed to create backup: \(error.localizedDescription)")
            throw RecoveryError.backupFailed(error.localizedDescription)
        }
    }

    /// Restore database from backup
    static func restoreFromBackup() throws {
        let backupPath = dbPath + backupSuffix

        guard FileManager.default.fileExists(atPath: backupPath) else {
            throw RecoveryError.recoveryFailed("No backup file found")
        }

        do {
            // Remove corrupted database
            if FileManager.default.fileExists(atPath: dbPath) {
                try FileManager.default.removeItem(atPath: dbPath)
            }

            // Restore from backup
            try FileManager.default.copyItem(atPath: backupPath, toPath: dbPath)
            logger.info("Database restored from backup")
        } catch {
            logger.error("Failed to restore from backup: \(error.localizedDescription)")
            throw RecoveryError.recoveryFailed(error.localizedDescription)
        }
    }

    /// Delete corrupted database and start fresh
    static func resetDatabase() throws {
        do {
            if FileManager.default.fileExists(atPath: dbPath) {
                try FileManager.default.removeItem(atPath: dbPath)
                logger.info("Corrupted database deleted")
            }

            // Also remove backup
            let backupPath = dbPath + backupSuffix
            if FileManager.default.fileExists(atPath: backupPath) {
                try FileManager.default.removeItem(atPath: backupPath)
            }
        } catch {
            logger.error("Failed to reset database: \(error.localizedDescription)")
            throw RecoveryError.recoveryFailed(error.localizedDescription)
        }
    }

    /// Attempt automatic recovery
    /// - Returns: true if recovery was successful
    static func attemptRecovery() -> Bool {
        logger.warning("Attempting database recovery...")

        // Try restoring from backup first
        do {
            try restoreFromBackup()
            logger.info("Recovery successful: restored from backup")
            return true
        } catch {
            logger.warning("Backup restoration failed: \(error.localizedDescription)")
        }

        // If backup fails, reset database
        do {
            try resetDatabase()
            logger.info("Recovery successful: database reset")
            return true
        } catch {
            logger.error("Recovery failed: \(error.localizedDescription)")
            return false
        }
    }
}
