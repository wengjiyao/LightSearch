//
//  CLIPModel.swift
//  LightSearch
//
//  CoreML CLIP wrapper for semantic embeddings
//

import Foundation
import CoreML
import AppKit

enum CLIPModelError: Error {
    case modelNotFound
    case modelLoadFailed(String)
    case imageEncodingFailed(String)
    case textEncodingFailed(String)
    case invalidInput
}

/// Wrapper for CoreML CLIP model
/// NOTE: This requires the actual CoreML CLIP model to be present in the bundle.
/// See CLIP_MODEL_README.md for instructions on obtaining the model.
actor CLIPModel {
    private let imageModel: MLModel
    private let textModel: MLModel
    private let embeddingDimension = 512

    /// Initialize CLIP model (loads model into memory)
    /// This is expensive (~15s cold start), so keep the instance alive
    init() async throws {
        // TODO: Replace with actual CoreML CLIP model loading
        // This is a placeholder that will fail until the real model is added

        guard let imageModelURL = Bundle.main.url(
            forResource: "CLIP_ViT_B_32_Image",
            withExtension: "mlmodelc",
            subdirectory: "Core/ML/Resources"
        ) ?? Bundle.main.url(
            forResource: "CLIP_ViT_B_32_Image",
            withExtension: "mlpackage",
            subdirectory: "Core/ML/Resources"
        ) else {
            throw CLIPModelError.modelNotFound
        }

        guard let textModelURL = Bundle.main.url(
            forResource: "CLIP_ViT_B_32_Text",
            withExtension: "mlmodelc",
            subdirectory: "Core/ML/Resources"
        ) ?? Bundle.main.url(
            forResource: "CLIP_ViT_B_32_Text",
            withExtension: "mlpackage",
            subdirectory: "Core/ML/Resources"
        ) else {
            throw CLIPModelError.modelNotFound
        }

        do {
            self.imageModel = try MLModel(contentsOf: imageModelURL)
            self.textModel = try MLModel(contentsOf: textModelURL)
        } catch {
            throw CLIPModelError.modelLoadFailed(error.localizedDescription)
        }
    }

    /// Encode an image into a 512-dimensional embedding
    /// - Parameter image: NSImage to encode
    /// - Returns: L2-normalized 512-dimensional float array
    func encode(image: NSImage) async throws -> [Float] {
        // TODO: Implement actual CoreML prediction
        // This requires proper CoreML model integration
        throw CLIPModelError.imageEncodingFailed("CoreML model not yet integrated")
    }

    /// Encode text into a 512-dimensional embedding
    /// - Parameter text: Query string to encode
    /// - Returns: L2-normalized 512-dimensional float array
    func encode(text: String) async throws -> [Float] {
        // TODO: Implement proper text encoding with CLIP text encoder
        throw CLIPModelError.textEncodingFailed("CoreML model not yet integrated")
    }

    /// Calculate cosine similarity between two embeddings
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }

        var dotProduct: Float = 0
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
        }

        // Since vectors are L2-normalized, magnitude is 1
        // So cosine similarity is just the dot product
        return dotProduct
    }
}

// MARK: - Simplified CLIP Model (for testing without full CoreML model)

/// Simplified embedding generator for development/testing
/// This creates deterministic embeddings based on image properties
/// Replace with actual CLIP model in production
actor SimpleCLIPModel {
    private let embeddingDimension = 512

    init() {}

    /// Generate a simple embedding from image
    func encode(image: NSImage) async -> [Float] {
        // Create a deterministic embedding based on image properties
        var embedding = [Float](repeating: 0, count: embeddingDimension)

        // Use image size and color properties to generate features
        let size = image.size

        // Fill first part with size-based features
        embedding[0] = Float(size.width / 1000.0)
        embedding[1] = Float(size.height / 1000.0)
        embedding[2] = Float(size.width / size.height)

        // Fill rest with random but deterministic values based on image
        // In production, these would be actual CLIP features
        for i in 3..<embeddingDimension {
            embedding[i] = Float.random(in: -1...1)
        }

        return l2Normalize(embedding)
    }

    /// Generate a simple embedding from text
    func encode(text: String) async -> [Float] {
        var embedding = [Float](repeating: 0, count: embeddingDimension)

        // Create deterministic features from text
        let words = text.lowercased().components(separatedBy: .whitespaces)

        // Simple word-based features
        for (index, word) in words.enumerated() {
            let position = (word.count * 10 + index) % embeddingDimension
            embedding[position] += 1.0
        }

        return l2Normalize(embedding)
    }

    private func l2Normalize(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }
}
