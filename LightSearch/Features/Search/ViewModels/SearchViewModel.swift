//
//  SearchViewModel.swift
//  LightSearch
//
//  ViewModel for search interface
//

import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.lightsearch.LightSearch", category: "SearchViewModel")

/// ViewModel managing search state and execution
@MainActor
@Observable
class SearchViewModel {
    // Search state
    var query: String = "" {
        didSet {
            // Trigger debounced search when query changes
            debouncedSearch()
        }
    }

    var results: [SearchResult] = []
    var isSearching = false
    var error: Error?

    // Filter state
    var filters = SearchFilters()

    // Statistics
    var totalResults = 0
    var searchDuration: TimeInterval = 0

    // Internal state
    private var searchEngine: SearchEngine?
    private var debounceTask: Task<Void, Never>?
    private let debounceDelay: TimeInterval = 0.3  // 300ms

    init() {
        Task {
            await initializeSearchEngine()
        }
    }

    /// Initialize the search engine
    private func initializeSearchEngine() async {
        do {
            searchEngine = try await SearchEngine()
            logger.info("Search engine initialized")
        } catch {
            logger.error("Failed to initialize search engine: \(error.localizedDescription)")
            self.error = error
        }
    }

    /// Execute search with debouncing
    private func debouncedSearch() {
        // Cancel previous debounce task
        debounceTask?.cancel()

        // Don't search if query is empty
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            totalResults = 0
            return
        }

        // Create new debounce task
        debounceTask = Task {
            // Wait for debounce delay
            try? await Task.sleep(for: .milliseconds(300))

            // Check if cancelled during sleep
            guard !Task.isCancelled else { return }

            // Execute search
            await executeSearch()
        }
    }

    /// Execute the search immediately
    func executeSearch() async {
        guard let searchEngine = searchEngine else {
            logger.warning("Search engine not initialized")
            return
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty else {
            results = []
            totalResults = 0
            return
        }

        isSearching = true
        error = nil

        let startTime = Date()

        do {
            logger.info("Executing search: \"\(trimmedQuery)\"")

            let searchResults = try await searchEngine.search(
                query: trimmedQuery,
                filters: filters,
                limit: 50
            )

            searchDuration = Date().timeIntervalSince(startTime)

            results = searchResults
            totalResults = searchResults.count

            logger.info("Search completed in \(String(format: "%.2f", self.searchDuration))s, found \(self.totalResults) results")

        } catch {
            logger.error("Search failed: \(error.localizedDescription)")
            self.error = error
            results = []
            totalResults = 0
        }

        isSearching = false
    }

    /// Clear search results
    func clearSearch() {
        query = ""
        results = []
        totalResults = 0
        error = nil
        debounceTask?.cancel()
    }

    /// Apply filters and re-search
    func applyFilters(_ newFilters: SearchFilters) async {
        filters = newFilters
        await executeSearch()
    }

    /// Get available filter options
    func getFilterOptions() async -> (cameras: [String], lenses: [String]) {
        guard let searchEngine = searchEngine else {
            return ([], [])
        }

        do {
            return try await searchEngine.getFilterOptions()
        } catch {
            logger.error("Failed to get filter options: \(error.localizedDescription)")
            return ([], [])
        }
    }
}
