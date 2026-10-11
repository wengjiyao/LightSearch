//
//  SettingsView.swift
//  LightSearch
//
//  Settings interface for catalog selection and configuration
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @State private var catalogPath: String = UserDefaults.standard.string(forKey: "catalogPath") ?? "No catalog selected"
    @State private var catalogAccessible = true
    @State private var indexer = BackgroundIndexer()
    @State private var indexedCount: Int = 0
    @State private var vectorCount: Int = 0
    @State private var checkpointInfo: String?

    var body: some View {
        Form {
            Section("Lightroom Catalog") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(catalogPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if !catalogAccessible && catalogPath != "No catalog selected" {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Catalog not accessible - file may have been moved or deleted")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    Spacer()

                    Button("Choose...") {
                        selectCatalog()
                    }
                    .disabled(indexer.isIndexing)
                }
            }

            Section("Index") {
                HStack {
                    Text("Photos indexed:")
                    Spacer()
                    Text("\(indexedCount)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Embeddings:")
                    Spacer()
                    Text("\(vectorCount)")
                        .foregroundStyle(.secondary)
                }

                if let checkpointInfo = checkpointInfo {
                    HStack {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundStyle(.orange)
                        Text(checkpointInfo)
                            .font(.caption)
                    }
                }

                if indexer.isIndexing {
                    if let progress = indexer.progress {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: progress.percentage) {
                                Text("Indexing: \(progress.current) / \(progress.total)")
                                    .font(.caption)
                            }

                            if let currentFile = progress.currentFile {
                                Text(currentFile)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }

                        Button("Cancel") {
                            indexer.cancel()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    } else {
                        ProgressView("Starting indexing...")
                    }
                } else {
                    HStack {
                        Button("Full Rebuild") {
                            startIndexing()
                        }
                        .disabled(catalogPath == "No catalog selected")

                        Button("Update Index") {
                            startIncrementalIndexing()
                        }
                        .disabled(catalogPath == "No catalog selected" || indexedCount == 0)
                    }
                }

                if let error = indexer.error {
                    Text("Error: \(error.localizedDescription)")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 550, height: 350)
        .task {
            // Load indexed count on appear
            await updateIndexedCount()
            await updateCheckpointInfo()
            checkCatalogAccessibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rebuildIndex)) { _ in
            startIndexing()
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateIndex)) { _ in
            startIncrementalIndexing()
        }
    }

    private func selectCatalog() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "lrcat")!]
        panel.message = "Select your Lightroom Classic catalog"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                catalogPath = url.path
                UserDefaults.standard.set(catalogPath, forKey: "catalogPath")

                // Save security-scoped bookmark
                do {
                    try SecurityScopedBookmark.saveBookmark(for: url, key: "catalogBookmark")
                } catch {
                    indexer.error = error
                    return
                }

                // Automatically start indexing
                startIndexing()
            }
        }
    }

    private func startIndexing() {
        guard catalogPath != "No catalog selected" else { return }

        Task {
            await indexer.startIndexing(catalogPath: catalogPath)
            await updateIndexedCount()
            await updateCheckpointInfo()
        }
    }

    private func startIncrementalIndexing() {
        guard catalogPath != "No catalog selected" else { return }

        Task {
            await indexer.incrementalIndexing(catalogPath: catalogPath)
            await updateIndexedCount()
        }
    }

    private func updateIndexedCount() async {
        do {
            let db = try IndexDatabase()
            indexedCount = try await db.countAssets()
            vectorCount = try await db.countVectors()
        } catch {
            print("Failed to get indexed count: \(error)")
        }
    }

    private func updateCheckpointInfo() async {
        checkpointInfo = await indexer.getCheckpointInfo(for: catalogPath)
    }

    private func checkCatalogAccessibility() {
        guard catalogPath != "No catalog selected" else {
            catalogAccessible = true
            return
        }

        // Try to resolve bookmark if available
        if SecurityScopedBookmark.hasBookmark(forKey: "catalogBookmark") {
            do {
                let url = try SecurityScopedBookmark.resolveBookmark(forKey: "catalogBookmark")
                catalogAccessible = FileManager.default.fileExists(atPath: url.path)
                SecurityScopedBookmark.stopAccessing(url)
            } catch {
                catalogAccessible = false
            }
        } else {
            // Fall back to direct file check
            catalogAccessible = FileManager.default.fileExists(atPath: catalogPath)
        }
    }
}

#Preview {
    SettingsView()
}
