//
//  ChartSaver.swift
//  burn
//
//

import SwiftUI
import Photos
import AppKit

struct ChartSaver {
    /// Renders a ChartCard offscreen (dark appearance) and saves it to Photos.
    /// Returns (success, message)
    @MainActor
    static func saveChartToPhotos(
        title: String,
        employees: [String],
        series: [(month: String, value: Double)],
        start: Date,
        end: Date,
        projectedStartIndex: Int?,
        ceilingSeries: [Double]? = nil,
        ceiling75Series: [Double]? = nil,
        monthlySeries: [(month: String, value: Double)]? = nil,
        cumulativeActualSeries: [(month: String, value: Double)]? = nil
    ) async -> (Bool, String) {
        // Build the view we want to render
        let chart = ChartCard(
            title: title,
            employees: employees,
            series: series,
            start: start,
            end: end,
            projectedStartIndex: projectedStartIndex,
            ceilingSeries: ceilingSeries,
            ceiling75Series: ceiling75Series,
            monthlySeries: monthlySeries,
            cumulativeActualSeries: cumulativeActualSeries
        )
        .frame(width: 1200, height: 800)
        .padding()
        .preferredColorScheme(.dark)
        .background(Color(nsColor: NSColor.windowBackgroundColor))

        #if os(macOS)
        // Render using SwiftUI ImageRenderer at Retina scale
        let renderer = ImageRenderer(content: chart.environment(\.colorScheme, .dark))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        guard let nsImage = renderer.nsImage else {
            return (false, "Failed to render chart image.")
        }
        let result = await saveNSImageToPhotos(nsImage)
        return result
        #else
        // iOS / other platforms fallback (not used for this macOS app)
        return (false, "Saving charts is only implemented for macOS in this build.")
        #endif
    }

    @MainActor
    private static func saveNSImageToPhotos(_ image: NSImage) async -> (Bool, String) {
        let granted = await requestPhotosAccess()
        guard granted else {
            return (false, "Photos access was denied. Enable it in System Settings → Privacy & Security → Photos.")
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            return (false, "Could not encode image as PNG.")
        }
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("BurnChart-\(timestamp).png")
        do { try pngData.write(to: tmpURL) } catch {
            return (false, "Failed to write temp image: \(error.localizedDescription)")
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: tmpURL)
            }
            return (true, "Chart saved to Photos.")
        } catch {
            return (false, "Failed to save to Photos: \(error.localizedDescription)")
        }
    }

    private static func requestPhotosAccess() async -> Bool {
        await withCheckedContinuation { cont in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                cont.resume(returning: status == .authorized || status == .limited)
            }
        }
    }
}
