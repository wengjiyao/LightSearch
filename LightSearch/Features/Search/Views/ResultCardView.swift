//
//  ResultCardView.swift
//  LightSearch
//
//  Individual search result card with thumbnail and metadata
//

import SwiftUI
import AppKit

struct ResultCardView: View {
    let result: SearchResult

    @State private var thumbnail: NSImage?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Thumbnail
            ZStack(alignment: .topTrailing) {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 200)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    Rectangle()
                        .fill(Color(nsColor: .quaternaryLabelColor))
                        .frame(height: 200)
                        .cornerRadius(8)
                        .overlay(
                            Group {
                                if isLoading {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                } else {
                                    Image(systemName: "photo")
                                        .font(.largeTitle)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        )
                }

                // Score badge
                ScoreBadge(score: result.score)
                    .padding(8)
            }

            // Metadata
            VStack(alignment: .leading, spacing: 2) {
                // Filename
                Text(URL(fileURLWithPath: result.filePath).lastPathComponent)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Camera info
                if let camera = result.asset.cameraModel {
                    Text(camera)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Exposure info
                if let aperture = result.asset.aperture,
                   let shutter = result.asset.shutterS,
                   let iso = result.asset.iso {
                    Text("ƒ/\(String(format: "%.1f", aperture)) • \(formatShutter(shutter)) • ISO \(iso)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
        }
        .onAppear {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        Task {
            // Load thumbnail asynchronously
            if let image = NSImage(contentsOfFile: result.filePath) {
                // Resize to thumbnail
                let thumbnailSize = NSSize(width: 400, height: 400)
                let thumbnail = NSImage(size: thumbnailSize)

                thumbnail.lockFocus()
                image.draw(
                    in: NSRect(origin: .zero, size: thumbnailSize),
                    from: NSRect(origin: .zero, size: image.size),
                    operation: .copy,
                    fraction: 1.0
                )
                thumbnail.unlockFocus()

                await MainActor.run {
                    self.thumbnail = thumbnail
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }

    private func formatShutter(_ seconds: Double) -> String {
        if seconds >= 1 {
            return "\(Int(seconds))s"
        } else {
            let denominator = Int(1 / seconds)
            return "1/\(denominator)"
        }
    }
}

/// Score badge showing similarity score
struct ScoreBadge: View {
    let score: Float

    var badgeColor: Color {
        switch score {
        case 0.85...:
            return .green
        case 0.75..<0.85:
            return .blue
        case 0.68..<0.75:
            return .orange
        default:
            return .gray
        }
    }

    var body: some View {
        Text("\(Int(score * 100))%")
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(badgeColor)
            .cornerRadius(4)
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
        lat: 37.7749,
        lng: -122.4194,
        width: 6000,
        height: 4000,
        rating: 5,
        indexedAt: Date()
    )

    let mockResult = SearchResult(
        id: "1",
        filePath: "/path/to/photo.jpg",
        distance: 0.2,
        asset: mockAsset
    )

    return ResultCardView(result: mockResult)
        .frame(width: 250)
        .padding()
}
