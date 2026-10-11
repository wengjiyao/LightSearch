//
//  EXIFExtractor.swift
//  LightSearch
//
//  Extracts EXIF metadata from images and videos using ImageIO and AVFoundation
//

import Foundation
import ImageIO
import AVFoundation
import CoreLocation

/// EXIF metadata extracted from a photo or video
struct EXIFMetadata {
    // Camera information
    var cameraMake: String?
    var cameraModel: String?
    var lens: String?

    // Exposure settings
    var focalMm: Double?
    var aperture: Double?
    var shutterS: Double?
    var iso: Int?

    // GPS coordinates
    var lat: Double?
    var lng: Double?

    // Image dimensions
    var width: Int?
    var height: Int?

    // Capture date/time
    var capturedAt: Date?
}

enum EXIFExtractorError: Error {
    case fileNotFound
    case unsupportedFormat
    case extractionFailed(String)
}

/// Extracts EXIF metadata from photos and videos
struct EXIFExtractor {

    /// Extract metadata from a file
    /// - Parameter path: Absolute path to the file
    /// - Returns: EXIFMetadata object
    static func extract(from path: String) throws -> EXIFMetadata {
        let url = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            throw EXIFExtractorError.fileNotFound
        }

        let ext = url.pathExtension.lowercased()

        // Determine file type and extract accordingly
        switch ext {
        case "jpg", "jpeg", "arw", "cr3", "nef", "dng":
            // Images (including RAW) use ImageIO
            return try extractFromImage(url: url)

        case "mov", "mp4":
            // Videos use AVFoundation
            return try extractFromVideo(url: url)

        default:
            throw EXIFExtractorError.unsupportedFormat
        }
    }

    /// Extract metadata from image files (JPEG, RAW)
    private static func extractFromImage(url: URL) throws -> EXIFMetadata {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw EXIFExtractorError.extractionFailed("Could not create image source")
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
            throw EXIFExtractorError.extractionFailed("Could not read image properties")
        }

        var metadata = EXIFMetadata()

        // Extract TIFF data (camera make/model)
        if let tiffDict = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            metadata.cameraMake = tiffDict[kCGImagePropertyTIFFMake as String] as? String
            metadata.cameraModel = tiffDict[kCGImagePropertyTIFFModel as String] as? String
        }

        // Extract EXIF data (exposure settings, lens, date)
        if let exifDict = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            // Lens
            metadata.lens = exifDict[kCGImagePropertyExifLensModel as String] as? String

            // Focal length
            if let focalLength = exifDict[kCGImagePropertyExifFocalLength as String] as? Double {
                metadata.focalMm = focalLength
            }

            // Aperture (f-number)
            if let fNumber = exifDict[kCGImagePropertyExifFNumber as String] as? Double {
                metadata.aperture = fNumber
            }

            // Shutter speed (exposure time in seconds)
            if let exposureTime = exifDict[kCGImagePropertyExifExposureTime as String] as? Double {
                metadata.shutterS = exposureTime
            }

            // ISO
            if let isoArray = exifDict[kCGImagePropertyExifISOSpeedRatings as String] as? [Int],
               let iso = isoArray.first {
                metadata.iso = iso
            }

            // Capture date
            if let dateString = exifDict[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                metadata.capturedAt = parseEXIFDate(dateString)
            }
        }

        // Extract GPS data
        if let gpsDict = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            if let lat = gpsDict[kCGImagePropertyGPSLatitude as String] as? Double,
               let latRef = gpsDict[kCGImagePropertyGPSLatitudeRef as String] as? String,
               let lng = gpsDict[kCGImagePropertyGPSLongitude as String] as? Double,
               let lngRef = gpsDict[kCGImagePropertyGPSLongitudeRef as String] as? String {

                // Apply hemisphere reference (N/S, E/W)
                metadata.lat = latRef == "S" ? -lat : lat
                metadata.lng = lngRef == "W" ? -lng : lng
            }
        }

        // Extract dimensions
        if let width = properties[kCGImagePropertyPixelWidth as String] as? Int {
            metadata.width = width
        }
        if let height = properties[kCGImagePropertyPixelHeight as String] as? Int {
            metadata.height = height
        }

        return metadata
    }

    /// Extract metadata from video files
    private static func extractFromVideo(url: URL) throws -> EXIFMetadata {
        let asset = AVAsset(url: url)
        var metadata = EXIFMetadata()

        // Extract dimensions from video tracks
        if let videoTrack = asset.tracks(withMediaType: .video).first {
            let size = videoTrack.naturalSize
            metadata.width = Int(size.width)
            metadata.height = Int(size.height)
        }

        // Extract metadata from AVMetadataItem
        let metadataItems = asset.metadata

        for item in metadataItems {
            guard let key = item.commonKey?.rawValue else { continue }

            switch key {
            case AVMetadataKey.commonKeyCreationDate.rawValue:
                // Try to parse creation date
                if let dateString = item.stringValue {
                    metadata.capturedAt = parseISO8601Date(dateString)
                } else if let date = item.dateValue {
                    metadata.capturedAt = date
                }

            case AVMetadataKey.commonKeyMake.rawValue:
                metadata.cameraMake = item.stringValue

            case AVMetadataKey.commonKeyModel.rawValue:
                metadata.cameraModel = item.stringValue

            case AVMetadataKey.commonKeyLocation.rawValue:
                // Parse location string if available
                if let locationString = item.stringValue {
                    if let location = parseLocationString(locationString) {
                        metadata.lat = location.latitude
                        metadata.lng = location.longitude
                    }
                }

            default:
                break
            }
        }

        // Try to extract GPS from QuickTime metadata (used by iPhones, drones)
        for format in asset.availableMetadataFormats {
            let items = asset.metadata(forFormat: format)

            for item in items {
                if let key = item.key as? String {
                    if key.contains("GPS") || key.contains("location") {
                        // Try to extract GPS coordinates
                        if key.contains("latitude"), let lat = item.numberValue?.doubleValue {
                            metadata.lat = lat
                        }
                        if key.contains("longitude"), let lng = item.numberValue?.doubleValue {
                            metadata.lng = lng
                        }
                    }
                }
            }
        }

        return metadata
    }

    /// Parse EXIF date string (format: "YYYY:MM:DD HH:MM:SS")
    private static func parseEXIFDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateString)
    }

    /// Parse ISO 8601 date string (used by videos)
    private static func parseISO8601Date(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
    }

    /// Parse location string (format varies by device)
    private static func parseLocationString(_ locationString: String) -> CLLocationCoordinate2D? {
        // Try to parse location strings like "+37.3317-122.0302/" or similar formats
        let pattern = "([+-]?\\d+\\.\\d+)([+-]?\\d+\\.\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let nsString = locationString as NSString
        guard let match = regex.firstMatch(in: locationString, range: NSRange(location: 0, length: nsString.length)) else {
            return nil
        }

        if match.numberOfRanges == 3 {
            let latString = nsString.substring(with: match.range(at: 1))
            let lngString = nsString.substring(with: match.range(at: 2))

            if let lat = Double(latString), let lng = Double(lngString) {
                return CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }
        }

        return nil
    }
}
