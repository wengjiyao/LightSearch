//
//  ContentView.swift
//  LightSearch
//
//  Main content view with search interface
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = SearchViewModel()
    @State private var filterPanelRef: FilterPanelView?
    @State private var availableCameras: [String] = []
    @State private var availableLenses: [String] = []

    var body: some View {
        NavigationSplitView {
            // Filter panel
            FilterPanelView(
                filters: $viewModel.filters,
                onApply: {
                    Task {
                        await viewModel.applyFilters(viewModel.filters)
                    }
                }
            )
            .frame(minWidth: 200, idealWidth: 250)
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
            .task {
                // Load filter options when view appears
                await loadFilterOptions()
            }

        } detail: {
            // Search and results
            VStack(spacing: 0) {
                // Search bar with stats
                VStack(spacing: 12) {
                    SearchBarView(
                        query: $viewModel.query,
                        isSearching: viewModel.isSearching,
                        onClear: {
                            viewModel.clearSearch()
                        }
                    )

                    if let error = viewModel.error {
                        ErrorBanner(error: error)
                    }
                }
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))

                Divider()

                // Results grid
                ResultsGridView(
                    results: viewModel.results,
                    isSearching: viewModel.isSearching,
                    query: viewModel.query,
                    totalResults: viewModel.totalResults,
                    searchDuration: viewModel.searchDuration
                )
            }
            .frame(minWidth: 600)
        }
        .navigationTitle("LightSearch")
        .onReceive(NotificationCenter.default.publisher(for: .clearSearch)) { _ in
            viewModel.clearSearch()
        }
    }

    private func loadFilterOptions() async {
        let options = await viewModel.getFilterOptions()
        availableCameras = options.cameras
        availableLenses = options.lenses
    }
}

/// Error banner for search errors
struct ErrorBanner: View {
    let error: Error

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(6)
    }

    private var errorMessage: String {
        if let searchError = error as? SearchError {
            switch searchError {
            case .noEmbeddings:
                return "No photos indexed yet. Go to Settings to index your catalog."
            case .queryFailed(let message):
                return "Search failed: \(message)"
            case .modelNotAvailable:
                return "Search model not available. Check CLIP_MODEL_README.md"
            }
        }
        return error.localizedDescription
    }
}

#Preview {
    ContentView()
}
