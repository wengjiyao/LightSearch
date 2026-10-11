//
//  CatalogWatcher.swift
//  LightSearch
//
//  Monitors Lightroom catalog file for changes using kqueue
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.lightsearch.LightSearch", category: "CatalogWatcher")

/// Events that can occur to a catalog file
enum CatalogEvent {
    case modified
    case deleted
    case moved
}

/// Monitors a Lightroom catalog file for changes
actor CatalogWatcher {
    private let catalogPath: String
    private var fileDescriptor: Int32 = -1
    private var kqueueDescriptor: Int32 = -1
    private var watchTask: Task<Void, Never>?
    private var onEvent: ((CatalogEvent) -> Void)?

    /// Initialize watcher for a catalog file
    /// - Parameter catalogPath: Path to .lrcat file to monitor
    init(catalogPath: String) {
        self.catalogPath = catalogPath
    }

    /// Start watching the catalog file
    /// - Parameter onEvent: Callback invoked when catalog changes
    func startWatching(onEvent: @escaping (CatalogEvent) -> Void) throws {
        guard watchTask == nil else {
            logger.warning("Already watching catalog")
            return
        }

        self.onEvent = onEvent

        // Open the file to get a file descriptor
        fileDescriptor = open(catalogPath, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            throw NSError(
                domain: "CatalogWatcher",
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Failed to open catalog file"]
            )
        }

        // Create kqueue
        kqueueDescriptor = kqueue()
        guard kqueueDescriptor >= 0 else {
            close(fileDescriptor)
            fileDescriptor = -1
            throw NSError(
                domain: "CatalogWatcher",
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Failed to create kqueue"]
            )
        }

        // Register for file events
        var event = kevent()
        event.ident = UInt(fileDescriptor)
        event.filter = Int16(EVFILT_VNODE)
        event.flags = UInt16(EV_ADD | EV_CLEAR)
        event.fflags = UInt32(NOTE_WRITE | NOTE_DELETE | NOTE_RENAME)
        event.data = 0
        event.udata = nil

        let result = kevent(kqueueDescriptor, &event, 1, nil, 0, nil)
        guard result >= 0 else {
            cleanup()
            throw NSError(
                domain: "CatalogWatcher",
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Failed to register kevent"]
            )
        }

        logger.info("Started watching catalog: \(self.catalogPath)")

        // Start monitoring in background task
        watchTask = Task {
            await monitorEvents()
        }
    }

    /// Stop watching the catalog file
    func stopWatching() {
        logger.info("Stopping catalog watch")
        watchTask?.cancel()
        watchTask = nil
        cleanup()
    }

    /// Monitor kqueue events
    private func monitorEvents() async {
        var event = kevent()

        while !Task.isCancelled {
            // Wait for events (with 1 second timeout)
            var timeout = timespec(tv_sec: 1, tv_nsec: 0)
            let result = kevent(kqueueDescriptor, nil, 0, &event, 1, &timeout)

            if result < 0 {
                if errno == EINTR {
                    // Interrupted, continue
                    continue
                }
                logger.error("kevent error: \(errno)")
                break
            }

            if result == 0 {
                // Timeout, continue
                continue
            }

            // Process event
            let fflags = event.fflags

            if fflags & UInt32(NOTE_DELETE) != 0 {
                logger.info("Catalog deleted")
                onEvent?(.deleted)
                break
            } else if fflags & UInt32(NOTE_RENAME) != 0 {
                logger.info("Catalog moved/renamed")
                onEvent?(.moved)
                break
            } else if fflags & UInt32(NOTE_WRITE) != 0 {
                logger.info("Catalog modified")
                onEvent?(.modified)
            }
        }

        cleanup()
    }

    /// Clean up file descriptors
    private func cleanup() {
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }

        if kqueueDescriptor >= 0 {
            close(kqueueDescriptor)
            kqueueDescriptor = -1
        }
    }

    deinit {
        if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
        if kqueueDescriptor >= 0 {
            close(kqueueDescriptor)
        }
    }
}
