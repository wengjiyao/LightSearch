//
//  DetailView.swift
//  LightSearch
//
//  Full-screen detail view for a search result with image and metadata
//

import SwiftUI
import MapKit

struct DetailView: View {
    let result: SearchResult
    let allResults: [SearchResult]
    @Binding var isPresented: Bool

    @State private var currentIndex: Int
    @State private var fullImage: NSImage?
    @State private var isLoadingImage = true
    @State private var imageLoadError: String?
    @State private var imageScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero

    init(result: SearchResult, allResults: [SearchResult], isPresented: Binding<Bool>) {
        self.result = result
        self.allResults = allResults
        self._isPresented = isPresented
        self._currentIndex = State(initialValue: allResults.firstIndex(where: { $0.id == result.id }) ?? 0)
    }

    var currentResult: SearchResult {
        allResults[currentIndex]
    }

    var body: some View {
        HStack(spacing: 0) {
            // Image viewer (left/main pane)
            imageViewerPane

            Divider()

            // Metadata panel (right pane)
            metadataPane
                .frame(width: 350)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadFullImage()
        }
        .onChange(of: currentIndex) {
            loadFullImage()
            resetImageTransform()
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
        .onKeyPress(.space) {
            // Toggle between fit and 100% zoom
            if imageScale == 1.0 {
                imageScale = 2.0
            } else {
                resetImageTransform()
            }
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "+")) { keyPress in
            // Zoom in with + key
            imageScale = min(5.0, imageScale + 0.25)
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "-")) { keyPress in
            // Zoom out with - key
            imageScale = max(0.5, imageScale - 0.25)
            return .handled
        }
        .onKeyPress(keys: [KeyEquivalent("0")]) { keyPress in
            // Reset zoom with 0 key (when Command is pressed)
            if keyPress.modifiers.contains(.command) {
                resetImageTransform()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(keys: [KeyEquivalent("r")]) { keyPress in
            // Reveal in Finder with Command+R
            if keyPress.modifiers.contains(.command) {
                revealInFinder()
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Image Viewer Pane

    @ViewBuilder
    private var imageViewerPane: some View {
        ZStack {
            Color.black

            if isLoadingImage {
                ProgressView("Loading image...")
                    .progressViewStyle(.circular)
                    .tint(.white)
            } else if let error = imageLoadError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundStyle(.white.opacity(0.6))

                    Text("Failed to load image")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else if let image = fullImage {
                GeometryReader { geometry in
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(imageScale)
                        .offset(imageOffset)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    imageScale = max(0.5, min(value, 5.0))
                                }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if imageScale > 1.0 {
                                        imageOffset = value.translation
                                    }
                                }
                        )
                }
            }

            // Navigation and controls overlay
            VStack {
                // Top bar
                HStack {
                    // Navigation arrows
                    HStack(spacing: 12) {
                        Button(action: previousImage) {
                            Image(systemName: "chevron.left")
                                .font(.title2)
                        }
                        .disabled(currentIndex == 0)
                        .keyboardShortcut(.leftArrow, modifiers: [])

                        Text("\(currentIndex + 1) / \(allResults.count)")
                            .font(.caption)
                            .monospacedDigit()

                        Button(action: nextImage) {
                            Image(systemName: "chevron.right")
                                .font(.title2)
                        }
                        .disabled(currentIndex == allResults.count - 1)
                        .keyboardShortcut(.rightArrow, modifiers: [])
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.6))
                    .cornerRadius(8)

                    Spacer()

                    // Close button
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.6))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding()

                Spacer()

                // Bottom bar with zoom controls
                if fullImage != nil {
                    HStack(spacing: 16) {
                        Button(action: { imageScale = max(0.5, imageScale - 0.25) }) {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        .disabled(imageScale <= 0.5)

                        Text("\(Int(imageScale * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(minWidth: 50)

                        Button(action: { imageScale = min(5.0, imageScale + 0.25) }) {
                            Image(systemName: "plus.magnifyingglass")
                        }
                        .disabled(imageScale >= 5.0)

                        Divider()
                            .frame(height: 20)

                        Button(action: resetImageTransform) {
                            Text("Fit")
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.6))
                    .cornerRadius(8)
                    .padding()
                }
            }
        }
    }

    // MARK: - Metadata Pane

    @ViewBuilder
    private var metadataPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // File info header
                fileInfoSection

                Divider()

                // Score badge
                scoreBadgeSection

                Divider()

                // Camera section
                if currentResult.asset.cameraMake != nil || currentResult.asset.cameraModel != nil {
                    cameraSection
                    Divider()
                }

                // Lens section
                if currentResult.asset.lens != nil || currentResult.asset.focalMm != nil {
                    lensSection
                    Divider()
                }

                // Exposure section
                if hasExposureData {
                    exposureSection
                    Divider()
                }

                // Location section
                if currentResult.asset.lat != nil && currentResult.asset.lng != nil {
                    locationSection
                    Divider()
                }

                // Dimensions
                if currentResult.asset.width != nil || currentResult.asset.height != nil {
                    dimensionsSection
                    Divider()
                }

                // Rating
                if let rating = currentResult.asset.rating {
                    ratingSection(rating: rating)
                    Divider()
                }

                // Action buttons
                actionButtonsSection
            }
            .padding()
        }
    }

    @ViewBuilder
    private var fileInfoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(URL(fileURLWithPath: currentResult.filePath).lastPathComponent)
                .font(.headline)
                .lineLimit(2)

            if let date = currentResult.asset.capturedAt {
                Text(date.formatted(date: .long, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var scoreBadgeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Match Score")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                ScoreBadge(score: currentResult.score)

                Text("\(Int(currentResult.score * 100))% similarity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var cameraSection: some View {
        MetadataSection(title: "Camera") {
            if let make = currentResult.asset.cameraMake {
                MetadataRow(label: "Make", value: make)
            }
            if let model = currentResult.asset.cameraModel {
                MetadataRow(label: "Model", value: model)
            }
        }
    }

    @ViewBuilder
    private var lensSection: some View {
        MetadataSection(title: "Lens") {
            if let lens = currentResult.asset.lens {
                MetadataRow(label: "Lens", value: lens)
            }
            if let focal = currentResult.asset.focalMm {
                MetadataRow(label: "Focal Length", value: "\(Int(focal))mm")
            }
        }
    }

    private var hasExposureData: Bool {
        currentResult.asset.aperture != nil ||
        currentResult.asset.shutterS != nil ||
        currentResult.asset.iso != nil
    }

    @ViewBuilder
    private var exposureSection: some View {
        MetadataSection(title: "Exposure") {
            if let aperture = currentResult.asset.aperture {
                MetadataRow(label: "Aperture", value: "ƒ/\(String(format: "%.1f", aperture))")
            }
            if let shutter = currentResult.asset.shutterS {
                MetadataRow(label: "Shutter Speed", value: formatShutterSpeed(shutter))
            }
            if let iso = currentResult.asset.iso {
                MetadataRow(label: "ISO", value: "\(iso)")
            }
        }
    }

    @ViewBuilder
    private var locationSection: some View {
        MetadataSection(title: "Location") {
            if let lat = currentResult.asset.lat, let lng = currentResult.asset.lng {
                VStack(alignment: .leading, spacing: 8) {
                    MetadataRow(label: "Latitude", value: String(format: "%.6f", lat))
                    MetadataRow(label: "Longitude", value: String(format: "%.6f", lng))

                    // Map preview
                    MapPreview(latitude: lat, longitude: lng)
                        .frame(height: 150)
                        .cornerRadius(8)
                }
            }
        }
    }

    @ViewBuilder
    private var dimensionsSection: some View {
        MetadataSection(title: "Dimensions") {
            if let width = currentResult.asset.width, let height = currentResult.asset.height {
                MetadataRow(label: "Size", value: "\(width) × \(height)")
                MetadataRow(label: "Megapixels", value: String(format: "%.1f MP", Double(width * height) / 1_000_000))
            }
        }
    }

    @ViewBuilder
    private func ratingSection(rating: Int) -> some View {
        MetadataSection(title: "Rating") {
            HStack {
                Text(String(repeating: "⭐", count: rating))
                Text("(\(rating) stars)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var actionButtonsSection: some View {
        VStack(spacing: 8) {
            Button("Reveal in Finder") {
                revealInFinder()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)

            if currentResult.asset.lat != nil && currentResult.asset.lng != nil {
                Button("Open in Maps") {
                    openInMaps()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Helper Functions

    private func loadFullImage() {
        isLoadingImage = true
        imageLoadError = nil
        fullImage = nil

        Task {
            if let image = NSImage(contentsOfFile: currentResult.filePath) {
                await MainActor.run {
                    fullImage = image
                    isLoadingImage = false
                }
            } else {
                await MainActor.run {
                    imageLoadError = "File not found or unsupported format"
                    isLoadingImage = false
                }
            }
        }
    }

    private func resetImageTransform() {
        imageScale = 1.0
        imageOffset = .zero
    }

    private func previousImage() {
        if currentIndex > 0 {
            currentIndex -= 1
        }
    }

    private func nextImage() {
        if currentIndex < allResults.count - 1 {
            currentIndex += 1
        }
    }

    private func formatShutterSpeed(_ seconds: Double) -> String {
        if seconds >= 1 {
            return "\(Int(seconds))s"
        } else {
            let denominator = Int(1 / seconds)
            return "1/\(denominator)s"
        }
    }

    private func revealInFinder() {
        NSWorkspace.shared.selectFile(currentResult.filePath, inFileViewerRootedAtPath: "")
    }

    private func openInMaps() {
        guard let lat = currentResult.asset.lat, let lng = currentResult.asset.lng else { return }

        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = URL(fileURLWithPath: currentResult.filePath).lastPathComponent
        mapItem.openInMaps()
    }
}

// MARK: - Supporting Views

struct MetadataSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)

            content
        }
    }
}

struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

struct MapPreview: View {
    let latitude: Double
    let longitude: Double

    @State private var region: MKCoordinateRegion

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self._region = State(initialValue: MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }

    var body: some View {
        Map(position: .constant(.region(region))) {
            Marker("Photo Location", coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
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

    return DetailView(
        result: mockResult,
        allResults: [mockResult],
        isPresented: .constant(true)
    )
}
