//
//  ResultsGridView.swift
//  LightSearch
//
//  Grid display for search results
//

import SwiftUI

struct ResultsGridView: View {
    let results: [SearchResult]
    let isSearching: Bool
    let query: String
    let totalResults: Int
    let searchDuration: TimeInterval

    @State private var selectedResult: SearchResult?
    @State private var showingDetail = false

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            if results.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    // Results header
                    resultsHeader

                    // Results grid
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(results) { result in
                            ResultCardView(result: result)
                                .onTapGesture {
                                    selectedResult = result
                                    showingDetail = true
                                }
                        }
                    }
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingDetail) {
            if let selectedResult = selectedResult {
                DetailView(
                    result: selectedResult,
                    allResults: results,
                    isPresented: $showingDetail
                )
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            if isSearching {
                // Searching state
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)

                    Text("Searching...")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            } else if query.isEmpty {
                // No query state
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 60))
                        .foregroundStyle(.tertiary)

                    Text("Search your photos")
                        .font(.title2)
                        .fontWeight(.medium)

                    Text("Try: \"golden hour sunset\", \"portrait\", or \"mountain landscape\"")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                // No results state
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 60))
                        .foregroundStyle(.tertiary)

                    Text("No results found")
                        .font(.title2)
                        .fontWeight(.medium)

                    Text("No photos match \"\(query)\" above the relevance threshold")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text("Try different search terms or check if your catalog is indexed")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private var resultsHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(totalResults) \(totalResults == 1 ? "result" : "results")")
                    .font(.headline)

                if searchDuration > 0 {
                    Text("Found in \(String(format: "%.2f", searchDuration))s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }
}

#Preview {
    let mockAsset = Asset(
        id: "1",
        filePath: "/path/to/photo.jpg",
        capturedAt: Date(),
        cameraMake: "Sony",
        cameraModel: "ILCE-7M4",
        lens: "FE 24-70mm F2.8 GM II",
        focalMm: 50.0,
        aperture: 2.8,
        shutterS: 1.0/200.0,
        iso: 400,
        lat: nil,
        lng: nil,
        width: 6000,
        height: 4000,
        rating: 5,
        indexedAt: Date()
    )

    let mockResults = (1...12).map { i in
        SearchResult(
            id: "\(i)",
            filePath: "/path/to/photo\(i).jpg",
            distance: Float(i) * 0.05,
            asset: mockAsset
        )
    }

    return VStack {
        // With results
        ResultsGridView(
            results: mockResults,
            isSearching: false,
            query: "golden hour",
            totalResults: 12,
            searchDuration: 0.15
        )
    }
}
