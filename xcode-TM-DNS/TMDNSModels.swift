import Foundation

struct DashboardResponse: Decodable {
    let dashboard: DashboardSummary
    let dns: DNSRuntime
    let system: SystemStats?
}

struct DashboardSummary: Decodable {
    let queriesToday: Int
    let blockedToday: Int
    let uniqueHosts: Int
    let recent: [QueryEvent]
    let blocked: [QueryEvent]
    let topHosts: [TopHost]
    let topDomains: [TopRow]
    let ruleHits: [TopRow]

    enum CodingKeys: String, CodingKey {
        case queriesToday = "queries_today"
        case blockedToday = "blocked_today"
        case uniqueHosts = "unique_hosts"
        case recent
        case blocked
        case topHosts = "top_hosts"
        case topDomains = "top_domains"
        case ruleHits = "rule_hits"
    }
}

struct DNSRuntime: Decodable {
    let dnsAddr: String?
    let queries: Int?
    let blocked: Int?
    let droppedEvents: Int?

    enum CodingKeys: String, CodingKey {
        case dnsAddr = "dns_addr"
        case queries
        case blocked
        case droppedEvents = "dropped_events"
    }
}

struct SystemStats: Decodable {
    let cpuPercent: Double?
    let residentMB: Double?
    let appStorageMB: Double?
    let diskUsedPercent: Double?

    enum CodingKeys: String, CodingKey {
        case cpuPercent = "cpu_percent"
        case residentMB = "resident_mb"
        case appStorageMB = "app_storage_mb"
        case diskUsedPercent = "disk_used_percent"
    }
}

struct QueryEvent: Decodable, Identifiable {
    var id: String { "\(timestamp)-\(sourceIP)-\(queryName)-\(queryType)" }
    let timestamp: Date
    let sourceIP: String
    let hostLabel: String
    let queryName: String
    let queryType: String
    let action: String
    let matchedSource: String
    let responseCode: String
    let latencyMS: Int
    let answerSummary: String

    enum CodingKeys: String, CodingKey {
        case timestamp
        case sourceIP = "source_ip"
        case hostLabel = "host_label"
        case queryName = "query_name"
        case queryType = "query_type"
        case action
        case matchedSource = "matched_source"
        case responseCode = "response_code"
        case latencyMS = "latency_ms"
        case answerSummary = "answer_summary"
    }
}

struct TopRow: Decodable, Identifiable {
    var id: String { key }
    let key: String
    let count: Int
}

struct TopHost: Decodable, Identifiable {
    let id: Int
    let key: String
    let sourceIP: String
    let label: String
    let hostname: String
    let count: Int

    enum CodingKeys: String, CodingKey {
        case id
        case key
        case sourceIP = "source_ip"
        case label
        case hostname
        case count
    }
}

struct Host: Decodable, Identifiable {
    let id: Int
    let sourceIP: String
    let label: String
    let hostname: String
    let mac: String
    let vendor: String
    let identityConfidence: String
    let queryCount: Int
    let blockCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case sourceIP = "source_ip"
        case label
        case hostname
        case mac
        case vendor
        case identityConfidence = "identity_confidence"
        case queryCount = "query_count"
        case blockCount = "block_count"
    }
}

struct HostDetail: Decodable {
    let host: Host
    let recent: [QueryEvent]
    let blocked: [QueryEvent]
    let topDomains: [TopRow]

    enum CodingKeys: String, CodingKey {
        case host
        case recent
        case blocked
        case topDomains = "top_domains"
    }
}

struct RuleCreateRequest: Encodable {
    let target: String
    let note: String
}

struct BlocklistPreset: Decodable, Identifiable {
    let id: String
    let name: String
    let tier: String
    let description: String
    let homeURL: String
    let sourceURL: String
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case tier
        case description
        case homeURL = "home_url"
        case sourceURL = "source_url"
        case enabled
    }
}

struct BlocklistSource: Decodable, Identifiable {
    let id: Int
    let name: String
    let url: String
    let format: String
    let enabled: Bool
    let lastStatus: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case url
        case format
        case enabled
        case lastStatus = "last_status"
    }
}

struct BlocklistSourceCreateRequest: Encodable {
    let name: String
    let url: String
    let format: String
}

struct BlocklistRefreshResult: Decodable, Identifiable {
    var id: String { "\(sourceName)-\(url)" }
    let sourceName: String
    let url: String
    let status: String
    let entries: Int
    let error: String?

    enum CodingKeys: String, CodingKey {
        case sourceName = "source_name"
        case url
        case status
        case entries
        case error
    }
}

struct AuditEvent: Decodable, Identifiable {
    let id: Int
    let timestamp: String
    let action: String
    let target: String
    let detail: String
}

extension JSONDecoder {
    static var tmdns: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        return decoder
    }
}

extension JSONDecoder.DateDecodingStrategy {
    static let iso8601WithFractionalSeconds = custom { decoder in
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let date = ISO8601DateFormatter.tmdns.date(from: value) {
            return date
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(value)")
    }
}

extension ISO8601DateFormatter {
    static let tmdns: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
