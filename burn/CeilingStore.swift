//
//  CeilingStore.swift
//  burn
//
//  Persists per-job Ceiling releases as JSON in Application Support.
//


import Foundation

struct CeilingRecord: Codable {
    var popStart: Date?
    var popEnd: Date?
    var releases: [CeilingRelease]
}

struct CeilingStore {
    // Directory name inside Application Support
    private static let subdirectory = "ceiling"

    // MARK: - Public API

    /// Load full ceiling record (PoP + releases) with migration support.
    static func loadRecord(jobId: Int) throws -> CeilingRecord {
        let url = try fileURL(for: jobId)
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return CeilingRecord(popStart: nil, popEnd: nil, releases: [])
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Try decoding new schema first
        if let record = try? decoder.decode(CeilingRecord.self, from: data) {
            return CeilingRecord(popStart: record.popStart, popEnd: record.popEnd, releases: record.releases.sorted { $0.date < $1.date })
        }
        // Fallback: legacy schema was an array of releases
        let releases = try decoder.decode([CeilingRelease].self, from: data).sorted { $0.date < $1.date }
        return CeilingRecord(popStart: nil, popEnd: nil, releases: releases)
    }

    /// Save ceiling releases for a given job id (overwrites).
    /// Releases are sorted by date ascending before writing.
    static func save(jobId: Int, releases: [CeilingRelease]) throws {
        var sorted = releases
        sorted.sort { $0.date < $1.date }
        // Preserve existing PoP data if any
        var record = (try? loadRecord(jobId: jobId)) ?? CeilingRecord(popStart: nil, popEnd: nil, releases: [])
        record.releases = sorted
        try saveRecord(jobId: jobId, record: record)
    }

    /// Save full ceiling record (PoP + releases) for a given job id.
    static func saveRecord(jobId: Int, record: CeilingRecord) throws {
        var rec = record
        rec.releases.sort { $0.date < $1.date }
        let url = try fileURL(for: jobId)
        try ensureDirectoryExists(url.deletingLastPathComponent())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(rec)
        try data.write(to: url, options: [.atomic])
    }

    // MARK: - Validation
    static func isValidPoP(_ start: Date?, _ end: Date?) -> Bool {
        guard let s = start, let e = end else { return false }
        return s <= e
    }

    // MARK: - Paths

    private static func appSupportDirectory() throws -> URL {
        let fm = FileManager.default
        #if os(macOS)
        if let bundleID = Bundle.main.bundleIdentifier {
            let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return base.appendingPathComponent(bundleID, isDirectory: true)
        } else {
            // Fallback to app name if bundle id is missing
            let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return base.appendingPathComponent("burn", isDirectory: true)
        }
        #else
        // Other platforms: use documents as a fallback
        return try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        #endif
    }

    private static func fileURL(for jobId: Int) throws -> URL {
        let root = try appSupportDirectory()
        return root
            .appendingPathComponent(subdirectory, isDirectory: true)
            .appendingPathComponent("job_\(jobId).json", conformingTo: .json)
    }

    private static func ensureDirectoryExists(_ dir: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
