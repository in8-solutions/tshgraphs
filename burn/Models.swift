import Foundation

// Config
struct Config: Codable {
    let API_URL: String
    let API_TOKEN: String
}

// API responses
struct JobCodesResponse: Codable {
    let results: JobCodesResults
    struct JobCodesResults: Codable {
        let jobcodes: [String: JobCode]   // keyed by string ids in the API
    }
}

struct TimesheetsResponse: Codable {
    let results: TimesheetsResults
    struct TimesheetsResults: Codable {
        let timesheets: [String: TimesheetEntry]
    }
}

// Entities
struct JobCode: Codable, Hashable {
    let id: Int
    let name: String
    let parent_id: Int?
    let active: Bool?
}

struct TimesheetEntry: Codable, Hashable {
    let id: Int
    let user_id: Int
    let jobcode_id: Int
    let duration: Double // seconds, as returned by API
}

// Tree node used by the UI
struct JobNode: Hashable {
    let id: Int
    let name: String
    let children: [JobNode]
}

// Users
struct User: Codable, Hashable {
    let id: Int
    let first_name: String?
    let last_name: String?
    let name: String?
}


struct UsersResponse: Codable {
    let results: UsersResults
    struct UsersResults: Codable {
        let users: [String: User]
    }
}

// Ceiling (replaces former Max Hours concept)
struct CeilingRelease: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var hours: Double      // additive; can be negative; fractional allowed
    var note: String? = nil
}
