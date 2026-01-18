import Foundation

enum APIClientError: LocalizedError {
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid API_URL in config.json: \(url)"
        }
    }
}

final class APIClient {
    private let baseURL: URL
    private let token: String

    init(config: Config) throws {
        let trimmed = config.API_URL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: trimmed) else {
            throw APIClientError.invalidURL(config.API_URL)
        }
        self.baseURL = base
        self.token = config.API_TOKEN
    }

    private func request(_ path: String, query: [URLQueryItem]? = nil) throws -> URLRequest {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var comps = URLComponents(
            url: baseURL.appendingPathComponent(cleanPath, isDirectory: false),
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }
        if let query = query { comps.queryItems = query }
        guard let url = comps.url else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.addValue("application/json", forHTTPHeaderField: "Accept")
        #if DEBUG
        print("Request URL:", url.absoluteString)
        #endif
        return req
    }

    func fetchJobCodes() async throws -> [Int: JobCode] {
        let req = try request("jobcodes")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(JobCodesResponse.self, from: data)
        // API returns keyed by string IDs; convert to [Int: JobCode]
        var byId: [Int: JobCode] = [:]
        for (_, jc) in decoded.results.jobcodes { byId[jc.id] = jc }
        return byId
    }

    func fetchTimesheets(start: Date, end: Date, jobcodeIDs: [Int]? = nil) async throws -> [TimesheetEntry] {
        var items = [
            URLQueryItem(name: "start_date", value: DateFormatters.yearMonthDay.string(from: start)),
            URLQueryItem(name: "end_date", value: DateFormatters.yearMonthDay.string(from: end))
        ]
        if let ids = jobcodeIDs, !ids.isEmpty {
            let csv = ids.map(String.init).joined(separator: ",")
            items.append(URLQueryItem(name: "jobcode_ids", value: csv))
        }
        let req = try request("timesheets", query: items)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(TimesheetsResponse.self, from: data)
        return Array(decoded.results.timesheets.values)
    }
    
    func fetchUsers() async throws -> [Int: User] {
        let req = try request("users")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(UsersResponse.self, from: data)
        var byId: [Int: User] = [:]
        for (_, u) in decoded.results.users { byId[u.id] = u }
        return byId
    }
}
