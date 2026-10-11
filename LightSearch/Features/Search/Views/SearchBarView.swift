//
//  SearchBarView.swift
//  LightSearch
//
//  Search input with debouncing and loading indicator
//

import SwiftUI

struct SearchBarView: View {
    @Binding var query: String
    var isSearching: Bool
    var onClear: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            // Text field
            TextField("Search your photos...", text: $query)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .font(.system(size: 16))

            // Loading indicator or clear button
            if isSearching {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            } else if !query.isEmpty {
                Button(action: {
                    query = ""
                    onClear()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onAppear {
            // Auto-focus on appear
            isFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            isFocused = true
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SearchBarView(
            query: .constant(""),
            isSearching: false,
            onClear: {}
        )

        SearchBarView(
            query: .constant("golden hour sunset"),
            isSearching: false,
            onClear: {}
        )

        SearchBarView(
            query: .constant("searching..."),
            isSearching: true,
            onClear: {}
        )
    }
    .padding()
    .frame(width: 400)
}
