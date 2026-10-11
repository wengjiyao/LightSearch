//
//  FilterPanelView.swift
//  LightSearch
//
//  Advanced filter panel for metadata filtering
//

import SwiftUI

struct FilterPanelView: View {
    @Binding var filters: SearchFilters
    var onApply: () -> Void

    @State private var hasChanges = false
    @State private var availableCameras: [String] = []
    @State private var availableLenses: [String] = []

    // Date range state
    @State private var useDateRange = false
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()

    // Camera selection state
    @State private var selectedCameras: Set<String> = []

    // Lens selection state
    @State private var selectedLenses: Set<String> = []

    // Aperture state
    @State private var useMaxAperture = false
    @State private var maxAperture: Double = 5.6

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                Text("Filters")
                    .font(.title2)
                    .fontWeight(.bold)

                // Date Range Filter
                dateRangeSection

                Divider()

                // Camera Filter
                cameraSection

                Divider()

                // Lens Filter
                lensSection

                Divider()

                // Aperture Filter
                apertureSection

                Divider()

                // Rating Filter
                ratingSection

                Divider()

                // GPS Filter
                gpsSection

                Spacer()

                // Action Buttons
                actionButtons
            }
            .padding()
        }
        .task {
            // Load available options on appear
            // TODO: Load from SearchViewModel
        }
    }

    // MARK: - Date Range Section

    @ViewBuilder
    private var dateRangeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Date Range", isOn: $useDateRange)
                .fontWeight(.medium)
                .onChange(of: useDateRange) {
                    hasChanges = true
                    if useDateRange {
                        filters.dateRange = startDate...endDate
                    } else {
                        filters.dateRange = nil
                    }
                }

            if useDateRange {
                VStack(alignment: .leading, spacing: 8) {
                    // Preset ranges
                    Menu("Presets") {
                        Button("Last 7 Days") {
                            setDateRange(days: 7)
                        }
                        Button("Last 30 Days") {
                            setDateRange(days: 30)
                        }
                        Button("Last 3 Months") {
                            setDateRange(months: 3)
                        }
                        Button("Last 6 Months") {
                            setDateRange(months: 6)
                        }
                        Button("Last Year") {
                            setDateRange(years: 1)
                        }
                    }
                    .menuStyle(.borderlessButton)

                    // Start date
                    DatePicker("From", selection: $startDate, displayedComponents: [.date])
                        .onChange(of: startDate) {
                            hasChanges = true
                            filters.dateRange = startDate...endDate
                        }

                    // End date
                    DatePicker("To", selection: $endDate, displayedComponents: [.date])
                        .onChange(of: endDate) {
                            hasChanges = true
                            filters.dateRange = startDate...endDate
                        }
                }
                .padding(.leading)
            }
        }
    }

    private func setDateRange(days: Int? = nil, months: Int? = nil, years: Int? = nil) {
        let calendar = Calendar.current
        endDate = Date()

        if let days = days {
            startDate = calendar.date(byAdding: .day, value: -days, to: endDate) ?? endDate
        } else if let months = months {
            startDate = calendar.date(byAdding: .month, value: -months, to: endDate) ?? endDate
        } else if let years = years {
            startDate = calendar.date(byAdding: .year, value: -years, to: endDate) ?? endDate
        }

        hasChanges = true
        filters.dateRange = startDate...endDate
    }

    // MARK: - Camera Section

    @ViewBuilder
    private var cameraSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Camera")
                    .fontWeight(.medium)

                Spacer()

                if !selectedCameras.isEmpty {
                    Text("\(selectedCameras.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if availableCameras.isEmpty {
                Text("No cameras in index")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    // Select All / Clear
                    HStack {
                        Button(selectedCameras.count == availableCameras.count ? "Clear All" : "Select All") {
                            if selectedCameras.count == availableCameras.count {
                                selectedCameras.removeAll()
                            } else {
                                selectedCameras = Set(availableCameras)
                            }
                            hasChanges = true
                            filters.cameras = selectedCameras.isEmpty ? nil : selectedCameras
                        }
                        .font(.caption)
                    }

                    // Camera list
                    ForEach(availableCameras, id: \.self) { camera in
                        Toggle(camera, isOn: Binding(
                            get: { selectedCameras.contains(camera) },
                            set: { isSelected in
                                if isSelected {
                                    selectedCameras.insert(camera)
                                } else {
                                    selectedCameras.remove(camera)
                                }
                                hasChanges = true
                                filters.cameras = selectedCameras.isEmpty ? nil : selectedCameras
                            }
                        ))
                        .font(.caption)
                    }
                }
                .padding(.leading)
            }
        }
    }

    // MARK: - Lens Section

    @ViewBuilder
    private var lensSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Lens")
                    .fontWeight(.medium)

                Spacer()

                if !selectedLenses.isEmpty {
                    Text("\(selectedLenses.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if availableLenses.isEmpty {
                Text("No lenses in index")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    // Select All / Clear
                    HStack {
                        Button(selectedLenses.count == availableLenses.count ? "Clear All" : "Select All") {
                            if selectedLenses.count == availableLenses.count {
                                selectedLenses.removeAll()
                            } else {
                                selectedLenses = Set(availableLenses)
                            }
                            hasChanges = true
                            filters.lenses = selectedLenses.isEmpty ? nil : selectedLenses
                        }
                        .font(.caption)
                    }

                    // Lens list (scrollable if many)
                    ForEach(availableLenses.prefix(10), id: \.self) { lens in
                        Toggle(lens, isOn: Binding(
                            get: { selectedLenses.contains(lens) },
                            set: { isSelected in
                                if isSelected {
                                    selectedLenses.insert(lens)
                                } else {
                                    selectedLenses.remove(lens)
                                }
                                hasChanges = true
                                filters.lenses = selectedLenses.isEmpty ? nil : selectedLenses
                            }
                        ))
                        .font(.caption)
                    }

                    if availableLenses.count > 10 {
                        Text("+ \(availableLenses.count - 10) more...")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.leading)
                    }
                }
                .padding(.leading)
            }
        }
    }

    // MARK: - Aperture Section

    @ViewBuilder
    private var apertureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Maximum Aperture", isOn: $useMaxAperture)
                .fontWeight(.medium)
                .onChange(of: useMaxAperture) {
                    hasChanges = true
                    filters.maxAperture = useMaxAperture ? maxAperture : nil
                }

            if useMaxAperture {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("ƒ/\(String(format: "%.1f", maxAperture))")
                            .font(.caption)
                            .monospacedDigit()

                        Spacer()

                        Text(apertureDescription)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // Aperture slider with common f-stops
                    Slider(value: $maxAperture, in: 1.4...22.0, step: 0.1)
                        .onChange(of: maxAperture) {
                            hasChanges = true
                            filters.maxAperture = maxAperture
                        }

                    // Common f-stop presets
                    HStack(spacing: 4) {
                        ForEach([1.4, 2.0, 2.8, 4.0, 5.6, 8.0], id: \.self) { stop in
                            Button("ƒ/\(String(format: "%.1f", stop))") {
                                maxAperture = stop
                                hasChanges = true
                                filters.maxAperture = stop
                            }
                            .font(.caption2)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }
                .padding(.leading)
            }
        }
    }

    private var apertureDescription: String {
        switch maxAperture {
        case ...2.0:
            return "Very shallow DOF"
        case 2.1...4.0:
            return "Shallow DOF"
        case 4.1...8.0:
            return "Moderate DOF"
        default:
            return "Deep DOF"
        }
    }

    // MARK: - Rating Section

    @ViewBuilder
    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Minimum Rating")
                .fontWeight(.medium)

            Picker("", selection: $filters.minRating) {
                Text("Any").tag(nil as Int?)
                ForEach(1...5, id: \.self) { rating in
                    HStack {
                        Text(String(repeating: "⭐", count: rating))
                        Text("(\(rating)+)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(rating as Int?)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: filters.minRating) {
                hasChanges = true
            }
        }
    }

    // MARK: - GPS Section

    @ViewBuilder
    private var gpsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Only Geotagged Photos", isOn: Binding(
                get: { filters.hasGPS ?? false },
                set: { filters.hasGPS = $0 ? true : nil }
            ))
            .fontWeight(.medium)
            .onChange(of: filters.hasGPS) {
                hasChanges = true
            }

            if filters.hasGPS == true {
                Text("Shows only photos with GPS coordinates")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading)
            }
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 8) {
            if hasChanges {
                Button("Apply Filters") {
                    onApply()
                    hasChanges = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }

            if filtersActive {
                Button("Clear All Filters") {
                    clearAllFilters()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var filtersActive: Bool {
        filters.dateRange != nil ||
        filters.cameras != nil ||
        filters.lenses != nil ||
        filters.maxAperture != nil ||
        filters.minRating != nil ||
        filters.hasGPS != nil
    }

    private func clearAllFilters() {
        filters = SearchFilters()
        useDateRange = false
        selectedCameras.removeAll()
        selectedLenses.removeAll()
        useMaxAperture = false
        hasChanges = true
        onApply()
    }

    /// Load available filter options
    func loadFilterOptions(cameras: [String], lenses: [String]) {
        availableCameras = cameras
        availableLenses = lenses
    }
}

#Preview {
    FilterPanelView(
        filters: .constant(SearchFilters()),
        onApply: {}
    )
    .frame(width: 300, height: 800)
}
