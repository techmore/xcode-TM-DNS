import AppKit
import SwiftUI
import WebKit

enum TMDNSTheme {
    static let olive50 = Color(red: 0.969, green: 0.973, blue: 0.957)
    static let olive100 = Color(red: 0.933, green: 0.941, blue: 0.902)
    static let olive200 = Color(red: 0.867, green: 0.882, blue: 0.816)
    static let olive300 = Color(red: 0.769, green: 0.788, blue: 0.690)
    static let olive400 = Color(red: 0.655, green: 0.682, blue: 0.545)
    static let olive700 = Color(red: 0.341, green: 0.365, blue: 0.239)
    static let olive800 = Color(red: 0.275, green: 0.290, blue: 0.204)
    static let olive950 = Color(red: 0.122, green: 0.129, blue: 0.090)
    static let stone500 = Color(red: 0.471, green: 0.443, blue: 0.424)
    static let stone900 = Color(red: 0.110, green: 0.098, blue: 0.090)
    static let red = Color(red: 0.753, green: 0.224, blue: 0.169)
    static let green = Color(red: 0.353, green: 0.541, blue: 0.369)
    static let blue = Color(red: 0.306, green: 0.553, blue: 0.639)
}

struct ContentView: View {
    @EnvironmentObject private var service: TMDNSService
    @State private var selection: AppSection = .overview

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                HStack(spacing: 8) {
                    Image(systemName: section.systemImage)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(TMDNSTheme.stone900)
                        .frame(width: 18)
                    Text(section.title)
                        .foregroundStyle(TMDNSTheme.stone900)
                }
                .listRowBackground(selection == section ? TMDNSTheme.olive300 : TMDNSTheme.olive200)
                .tag(section)
            }
            .foregroundStyle(TMDNSTheme.stone900)
            .scrollContentBackground(.hidden)
            .background(TMDNSTheme.olive200)
            .navigationTitle("TM-DNS")
            .safeAreaInset(edge: .bottom) {
                StatusFooter()
                    .padding(12)
            }
        } detail: {
            Group {
                switch selection {
                case .setup:
                    SetupView()
                case .overview:
                    OverviewView()
                case .activity:
                    ActivityView()
                case .hosts:
                    HostsView()
                case .domains:
                    DomainsView()
                case .lists:
                    ListsView()
                case .audit:
                    AuditView()
                case .web:
                    WebDashboardView(url: service.baseURL)
                case .settings:
                    SettingsView()
                }
            }
            .navigationTitle(selection.title)
            .background(TMDNSTheme.olive300)
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        Task { await service.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    Button {
                        service.openWebDashboard()
                    } label: {
                        Label("Open Web", systemImage: "safari")
                    }
                }
            }
        }
        .tint(TMDNSTheme.olive700)
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case setup
    case overview
    case activity
    case hosts
    case domains
    case lists
    case audit
    case web
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .setup: "Setup"
        case .overview: "Overview"
        case .activity: "Realtime"
        case .hosts: "Hosts"
        case .domains: "Top Domains"
        case .lists: "Block Lists"
        case .audit: "Audit"
        case .web: "Web Dashboard"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .setup: "checklist"
        case .overview: "gauge.with.dots.needle.67percent"
        case .activity: "waveform.path.ecg"
        case .hosts: "desktopcomputer"
        case .domains: "network"
        case .lists: "list.bullet.rectangle"
        case .audit: "checklist.checked"
        case .web: "globe"
        case .settings: "gearshape"
        }
    }
}

struct StatusFooter: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(service.isHealthy ? TMDNSTheme.green : TMDNSTheme.red)
                    .frame(width: 9, height: 9)
                Text(service.isHealthy ? "Online" : "Offline")
                    .font(.caption.weight(.semibold))
            }
            Text(service.statusText)
                .font(.caption)
                .foregroundStyle(TMDNSTheme.stone500)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SetupView: View {
    @EnvironmentObject private var service: TMDNSService

    private var digCommand: String {
        "dig @127.0.0.1 -p 53 example.com"
    }

    private var lanDigCommand: String {
        "dig @<detected-lan-ip> example.com"
    }

    private var liveCommand: String {
        """
        cd /Users/techmore/projects/TM-DNS
        sudo TMDNS_DNS_ADDR=auto:53 \\
          TMDNS_HTTP_ADDR=auto:8080 \\
          TMDNS_DB_PATH=/Users/techmore/projects/TM-DNS/tm-dns-dev.db \\
          TMDNS_LOG_LEVEL=debug \\
          ./tmdns
        """
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Setup")
                            .font(.system(size: 34, weight: .semibold, design: .serif))
                        Spacer()
                        StatusPill(isHealthy: service.isHealthy, text: service.isHealthy ? "API connected" : "API offline")
                    }
                    Text("Use this checklist when turning TM-DNS into the active resolver for a network. Verify the local service first, then move clients or the router to the Mac's DNS address.")
                        .foregroundStyle(TMDNSTheme.stone500)
                }
                .padding(20)
                .foregroundStyle(TMDNSTheme.stone900)
                .background(TMDNSTheme.olive200, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(TMDNSTheme.olive400, lineWidth: 1))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SetupStepCard(
                        number: "1",
                        title: "Start TM-DNS",
                        detail: "Run the resolver on the Mac that will serve DNS. Auto bind chooses the active LAN IPv4 and prefers wired Ethernet over Wi-Fi.",
                        command: liveCommand
                    )

                    SetupStepCard(
                        number: "2",
                        title: "Verify the app API",
                        detail: service.isHealthy ? "The native app can reach the local TM-DNS admin API." : "The native app cannot reach the admin API yet. Start TM-DNS, then refresh.",
                        command: "curl http://127.0.0.1:8080/api/dashboard"
                    ) {
                        Button("Refresh") {
                            Task { await service.refresh() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(TMDNSTheme.olive700)
                    }

                    SetupStepCard(
                        number: "3",
                        title: "Test DNS locally",
                        detail: "Before touching router settings, make sure this Mac can answer a DNS query directly.",
                        command: digCommand
                    )

                    SetupStepCard(
                        number: "4",
                        title: "Test LAN DNS address",
                        detail: "From the Mac or another machine on the same network, query the Mac's LAN DNS address directly.",
                        command: lanDigCommand
                    )

                    SetupStepCard(
                        number: "5",
                        title: "Point clients at TM-DNS",
                        detail: "In UniFi, keep DHCP Mode set to DHCP Server. Set DNS Server to the Mac's static LAN IP. Do not use DHCP Relay for this.",
                        command: "DNS Server: 192.168.222.8"
                    )

                    SetupStepCard(
                        number: "6",
                        title: "Watch requests",
                        detail: "After a client renews DHCP or manually points DNS here, requests should appear in Realtime and Top Hosts.",
                        command: "sudo tcpdump -ni any port 53"
                    )
                }
            }
            .padding(20)
        }
        .background(TMDNSTheme.olive300)
    }
}

struct StatusPill: View {
    let isHealthy: Bool
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isHealthy ? TMDNSTheme.green : TMDNSTheme.red)
                .frame(width: 8, height: 8)
            Text(text.uppercased())
                .font(.caption.weight(.bold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(TMDNSTheme.olive100.opacity(0.18), in: Capsule())
    }
}

struct SetupStepCard<Action: View>: View {
    let number: String
    let title: String
    let detail: String
    let command: String
    @ViewBuilder var action: Action

    init(number: String, title: String, detail: String, command: String, @ViewBuilder action: () -> Action = { EmptyView() }) {
        self.number = number
        self.title = title
        self.detail = detail
        self.command = command
        self.action = action()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(number)
                    .font(.caption.weight(.black))
                    .foregroundStyle(TMDNSTheme.olive950)
                    .frame(width: 26, height: 26)
                    .background(TMDNSTheme.olive300, in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                    Text(detail)
                        .foregroundStyle(TMDNSTheme.stone500)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            CommandBox(command: command)
            action
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(TMDNSTheme.olive200, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(TMDNSTheme.olive400, lineWidth: 1))
    }
}

struct CommandBox: View {
    let command: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(TMDNSTheme.stone900)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(TMDNSTheme.olive100, in: RoundedRectangle(cornerRadius: 7))
    }
}

struct OverviewView: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HeaderCard()
                MetricGrid()
                HStack(alignment: .top, spacing: 16) {
                    RecentActivityCard(events: Array(service.dashboard?.dashboard.recent.prefix(8) ?? []))
                    TopDomainsCard(rows: service.dashboard?.dashboard.topDomains ?? [])
                }
            }
            .padding(20)
        }
        .background(TMDNSTheme.olive300)
    }
}

struct HeaderCard: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 12) {
                    Text("DNS")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(TMDNSTheme.olive950)
                        .frame(width: 42, height: 34)
                        .background(TMDNSTheme.olive100, in: RoundedRectangle(cornerRadius: 7))
                    Label("DNS Firewall", systemImage: service.isHealthy ? "shield.checkered" : "shield.slash")
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                }
                Spacer()
                Text(service.statusText)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(service.isHealthy ? TMDNSTheme.olive700 : TMDNSTheme.red)
            }
            Text("Native control shell for the local TM-DNS resolver, policy dashboard, and school network visibility.")
                .foregroundStyle(TMDNSTheme.stone500)
        }
        .padding(20)
        .foregroundStyle(TMDNSTheme.stone900)
        .background(TMDNSTheme.olive200, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(TMDNSTheme.olive400, lineWidth: 1))
    }
}

struct MetricGrid: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        let dashboard = service.dashboard?.dashboard
        let dns = service.dashboard?.dns
        let system = service.dashboard?.system
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            MetricCard(title: "Queries Today", value: "\(dashboard?.queriesToday ?? 0)")
            MetricCard(title: "Blocked Today", value: "\(dashboard?.blockedToday ?? 0)")
            MetricCard(title: "Unique Hosts", value: "\(dashboard?.uniqueHosts ?? 0)")
            MetricCard(title: "Runtime Queries", value: "\(dns?.queries ?? 0)")
            MetricCard(title: "CPU", value: percent(system?.cpuPercent))
            MetricCard(title: "Memory", value: mb(system?.residentMB))
            MetricCard(title: "App Storage", value: mb(system?.appStorageMB))
            MetricCard(title: "Disk Used", value: percent(system?.diskUsedPercent))
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(TMDNSTheme.stone500)
            Text(value)
                .font(.system(size: 31, weight: .semibold, design: .serif))
                .foregroundStyle(TMDNSTheme.stone900)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(TMDNSTheme.olive200, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(TMDNSTheme.olive400, lineWidth: 1))
    }
}

struct RecentActivityCard: View {
    let events: [QueryEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Realtime Activity")
                .font(.system(size: 24, weight: .semibold, design: .serif))
            ForEach(events) { event in
                EventRow(event: event)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(TMDNSTheme.olive200, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(TMDNSTheme.olive400, lineWidth: 1))
    }
}

struct TopDomainsCard: View {
    let rows: [TopRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top Domains")
                .font(.system(size: 24, weight: .semibold, design: .serif))
            TopDomainsList(rows: rows)
        }
        .frame(width: 360, alignment: .topLeading)
        .padding(14)
        .background(TMDNSTheme.olive200, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(TMDNSTheme.olive400, lineWidth: 1))
    }
}

struct ActivityView: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        List(service.dashboard?.dashboard.recent ?? []) { event in
            EventRow(event: event)
                .padding(.vertical, 4)
                .listRowBackground(TMDNSTheme.olive200)
        }
        .scrollContentBackground(.hidden)
        .background(TMDNSTheme.olive300)
    }
}

struct EventRow: View {
    let event: QueryEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.queryName)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(TMDNSTheme.stone900)
                    .lineLimit(1)
                Spacer()
                Text(event.action.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(event.action == "blocked" ? TMDNSTheme.red : TMDNSTheme.green)
            }
            HStack {
                Text(event.hostLabel)
                Text(event.sourceIP)
                Text(event.queryType)
                Text("\(event.latencyMS)ms")
                Spacer()
                Text(event.answerSummary.isEmpty ? event.responseCode : event.answerSummary)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(TMDNSTheme.stone500)
        }
        .padding(8)
        .background(TMDNSTheme.olive100, in: RoundedRectangle(cornerRadius: 7))
    }
}

struct HostsView: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            List(service.dashboard?.dashboard.topHosts ?? []) { host in
                Button {
                    Task { await service.selectHost(host.id) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(host.label.isEmpty ? (host.hostname.isEmpty ? host.sourceIP : host.hostname) : host.label)
                                .font(.headline)
                            Spacer()
                            Text("\(host.count)")
                                .monospacedDigit()
                                .foregroundStyle(TMDNSTheme.olive700)
                        }
                        Text(host.hostname.isEmpty ? "hostname not learned yet" : host.hostname)
                            .font(.caption)
                            .foregroundStyle(TMDNSTheme.stone500)
                        Text(host.sourceIP)
                            .font(.caption.monospaced())
                            .foregroundStyle(TMDNSTheme.stone500)
                    }
                    .foregroundStyle(TMDNSTheme.stone900)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)
                .listRowBackground(TMDNSTheme.olive200)
            }
            .frame(minWidth: 360)
            .scrollContentBackground(.hidden)
            HostDetailPanel(detail: service.selectedHostDetail)
        }
        .padding(16)
        .background(TMDNSTheme.olive300)
    }
}

struct HostDetailPanel: View {
    @EnvironmentObject private var service: TMDNSService
    let detail: HostDetail?

    var body: some View {
        ListPanel(title: detail.map { displayName($0.host) } ?? "Host Detail") {
            if let detail {
                HStack {
                    MetricCard(title: "Queries", value: "\(detail.host.queryCount)")
                    MetricCard(title: "Blocked", value: "\(detail.host.blockCount)")
                    MetricCard(title: "Identity", value: detail.host.identityConfidence)
                }
                Text("DNS \(detail.host.hostname.isEmpty ? "not learned" : detail.host.hostname) · MAC \(detail.host.mac.isEmpty ? "not learned" : detail.host.mac)")
                    .font(.caption.monospaced())
                    .foregroundStyle(TMDNSTheme.stone500)

                Text("Top Sites")
                    .font(.headline)
                TopDomainsList(rows: detail.topDomains)

                Text("Timeline")
                    .font(.headline)
                ForEach(detail.recent.prefix(50)) { event in
                    EventRow(event: event)
                }
            } else {
                Text("Select a host to inspect destinations and request history.")
                    .foregroundStyle(TMDNSTheme.stone500)
            }
        }
    }

    private func displayName(_ host: Host) -> String {
        if !host.label.isEmpty { return host.label }
        if !host.hostname.isEmpty { return host.hostname }
        return host.sourceIP
    }
}

struct DomainsView: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        TopDomainsList(rows: service.dashboard?.dashboard.topDomains ?? [])
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(TMDNSTheme.olive300)
    }
}

struct TopDomainsList: View {
    @EnvironmentObject private var service: TMDNSService
    let rows: [TopRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                HStack {
                    Text(row.key)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(TMDNSTheme.stone900)
                        .lineLimit(1)
                    Spacer()
                    Text("\(row.count)")
                        .monospacedDigit()
                        .foregroundStyle(TMDNSTheme.stone500)
                    Button("Block") {
                        Task { await service.block(domain: row.key) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(TMDNSTheme.red)
                }
                Divider().overlay(TMDNSTheme.olive400.opacity(0.55))
            }
        }
    }
}

struct AuditView: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Audit")
                    .font(.system(size: 34, weight: .semibold, design: .serif))

                ListPanel(title: "Policy and Admin Changes") {
                    if service.auditEvents.isEmpty {
                        Text("No audit events recorded yet.")
                            .foregroundStyle(TMDNSTheme.stone500)
                    }
                    ForEach(service.auditEvents) { event in
                        HStack(alignment: .top, spacing: 12) {
                            Text(event.timestamp)
                                .font(.caption.monospaced())
                                .foregroundStyle(TMDNSTheme.stone500)
                                .frame(width: 220, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.action)
                                    .font(.headline.monospaced())
                                Text(event.target)
                                    .font(.callout.monospaced())
                                    .foregroundStyle(TMDNSTheme.stone900)
                                if !event.detail.isEmpty {
                                    Text(event.detail)
                                        .font(.caption)
                                        .foregroundStyle(TMDNSTheme.stone500)
                                }
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(TMDNSTheme.olive100, in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
            .padding(20)
        }
        .background(TMDNSTheme.olive300)
        .task {
            await service.refreshAudit()
        }
    }
}

struct ListsView: View {
    @EnvironmentObject private var service: TMDNSService
    @State private var sourceName = ""
    @State private var sourceURL = ""
    @State private var sourceFormat = "domains"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Block Lists")
                            .font(.system(size: 34, weight: .semibold, design: .serif))
                        Spacer()
                        Button("Refresh Enabled Block Lists") {
                            Task { await service.refreshEnabledBlocklists() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(TMDNSTheme.olive700)
                    }
                    Text("Enable curated block lists or add a raw GitHub/custom URL. Refresh compiles enabled sources into local DNS enforcement entries.")
                        .foregroundStyle(TMDNSTheme.stone500)
                }
                .padding(20)
                .foregroundStyle(TMDNSTheme.stone900)
                .background(TMDNSTheme.olive200, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(TMDNSTheme.olive400, lineWidth: 1))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Add Custom Source")
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                    HStack {
                        TextField("Name", text: $sourceName)
                        TextField("https://raw.githubusercontent.com/org/repo/main/domains.txt", text: $sourceURL)
                        Picker("Format", selection: $sourceFormat) {
                            Text("Domains").tag("domains")
                            Text("Hosts").tag("hosts")
                            Text("AdGuard").tag("adguard")
                        }
                        .frame(width: 130)
                        Button("Add") {
                            Task {
                                await service.addSource(name: sourceName, url: sourceURL, format: sourceFormat)
                                sourceName = ""
                                sourceURL = ""
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(TMDNSTheme.olive700)
                    }
                }
                .padding(14)
                .background(TMDNSTheme.olive200, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(TMDNSTheme.olive400, lineWidth: 1))

                HStack(alignment: .top, spacing: 16) {
                    ListPanel(title: "Curated Block Lists") {
                        ForEach(service.blocklistPresets) { preset in
                            PresetRow(preset: preset)
                        }
                    }
                    ListPanel(title: "Custom Sources") {
                        if service.blocklistSources.isEmpty {
                            Text("No custom sources yet.")
                                .foregroundStyle(TMDNSTheme.stone500)
                        }
                        ForEach(service.blocklistSources) { source in
                            SourceRow(source: source)
                        }
                    }
                }

                if !service.lastBlocklistRefresh.isEmpty {
                    ListPanel(title: "Last Refresh") {
                        ForEach(service.lastBlocklistRefresh) { result in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.sourceName)
                                        .font(.headline)
                                    Text(result.error ?? result.url)
                                        .font(.caption)
                                        .foregroundStyle(TMDNSTheme.stone500)
                                }
                                Spacer()
                                Text(result.status)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(result.status == "ok" ? TMDNSTheme.green : TMDNSTheme.red)
                                Text("\(result.entries)")
                                    .monospacedDigit()
                            }
                            .padding(10)
                            .background(TMDNSTheme.olive100, in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(TMDNSTheme.olive300)
        .task {
            await service.refreshBlocklists()
        }
    }
}

struct ListPanel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 24, weight: .semibold, design: .serif))
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(TMDNSTheme.olive200, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(TMDNSTheme.olive400, lineWidth: 1))
    }
}

struct PresetRow: View {
    @EnvironmentObject private var service: TMDNSService
    let preset: BlocklistPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.name)
                        .font(.headline)
                    Text(preset.tier)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TMDNSTheme.olive700)
                }
                Spacer()
                Toggle(preset.enabled ? "Enabled" : "Disabled", isOn: Binding(
                    get: { preset.enabled },
                    set: { enabled in Task { await service.setPreset(preset, enabled: enabled) } }
                ))
                .toggleStyle(.switch)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TMDNSTheme.stone900)
            }
            Text(preset.description)
                .font(.caption)
                .foregroundStyle(TMDNSTheme.stone500)
            HStack {
                Link("Review", destination: URL(string: preset.homeURL)!)
                Link("Source", destination: URL(string: preset.sourceURL)!)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(10)
        .background(TMDNSTheme.olive100, in: RoundedRectangle(cornerRadius: 7))
    }
}

struct SourceRow: View {
    @EnvironmentObject private var service: TMDNSService
    let source: BlocklistSource

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.name)
                        .font(.headline)
                    Text(source.format.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TMDNSTheme.olive700)
                }
                Spacer()
                Toggle(source.enabled ? "Enabled" : "Disabled", isOn: Binding(
                    get: { source.enabled },
                    set: { enabled in Task { await service.setSource(source, enabled: enabled) } }
                ))
                .toggleStyle(.switch)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TMDNSTheme.stone900)
            }
            Text(source.url)
                .font(.caption.monospaced())
                .foregroundStyle(TMDNSTheme.stone500)
                .textSelection(.enabled)
            Text(source.lastStatus)
                .font(.caption)
                .foregroundStyle(TMDNSTheme.stone500)
        }
        .padding(10)
        .background(TMDNSTheme.olive100, in: RoundedRectangle(cornerRadius: 7))
    }
}

struct WebDashboardView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if nsView.url?.absoluteString != url.absoluteString {
            nsView.load(URLRequest(url: url))
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        Form {
            TextField("Local API URL", text: $service.baseURLString)
            SecureField("Admin token", text: $service.adminToken)
            Button("Refresh Connection") {
                Task { await service.refresh() }
            }
            Divider()
            Text("The admin token is stored on the TM-DNS Mac as admin-token.txt next to the database unless TMDNS_ADMIN_TOKEN is configured.")
                .foregroundStyle(TMDNSTheme.stone500)
        }
        .padding(24)
        .scrollContentBackground(.hidden)
        .background(TMDNSTheme.olive300)
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(service.isHealthy ? "TM-DNS Online" : "TM-DNS Offline", systemImage: service.isHealthy ? "shield.checkered" : "shield.slash")
                .font(.headline)
            Text(service.statusText)
                .font(.caption)
                .foregroundStyle(TMDNSTheme.stone500)
            Divider()
            Button("Open Dashboard") {
                service.openWebDashboard()
            }
            Button("Refresh") {
                Task { await service.refresh() }
            }
            Button("Quit TM-DNS App") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 260)
        .background(TMDNSTheme.olive100)
    }
}

private func percent(_ value: Double?) -> String {
    guard let value else { return "0%" }
    return "\(Int(value.rounded()))%"
}

private func mb(_ value: Double?) -> String {
    guard let value else { return "0 MB" }
    return "\(Int(value.rounded())) MB"
}

#Preview {
    ContentView()
        .environmentObject(TMDNSService())
}
