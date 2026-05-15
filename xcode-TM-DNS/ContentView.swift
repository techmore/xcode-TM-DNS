import AppKit
import Foundation
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
    @State private var selectedHostID: Int?
    @State private var hostWindowHours = 24

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
                    HostsView { hostID in
                        openHostDetail(hostID, hours: 24)
                    }
                case .hostDetail:
                    DedicatedHostDetailView(
                        selectedHostID: selectedHostID,
                        windowHours: $hostWindowHours,
                        onBack: {
                            service.clearSelectedHost()
                            selectedHostID = nil
                            selection = .hosts
                        },
                        onWindowChange: { hours in
                            guard let selectedHostID else { return }
                            openHostDetail(selectedHostID, hours: hours)
                        }
                    )
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

    private func openHostDetail(_ hostID: Int, hours: Int) {
        selectedHostID = hostID
        hostWindowHours = hours
        service.clearSelectedHost()
        selection = .hostDetail
        Task {
            await service.selectHost(hostID, hours: hours)
        }
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case setup
    case overview
    case activity
    case hosts
    case hostDetail
    case domains
    case lists
    case audit
    case web
    case settings

    static var allCases: [AppSection] {
        [.setup, .overview, .activity, .hosts, .domains, .lists, .audit, .web, .settings]
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .setup: "Setup"
        case .overview: "Overview"
        case .activity: "Realtime"
        case .hosts: "Hosts"
        case .hostDetail: "Host Detail"
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
        case .hostDetail: "desktopcomputer.and.arrow.down"
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

    private var detectedLANIP: String {
        service.detectedLANIP ?? "LAN IP not detected"
    }

    private var lanDigCommand: String {
        guard let ip = service.detectedLANIP else {
            return "route get default | grep interface\nipconfig getifaddr <interface>"
        }
        return "dig @\(ip) example.com"
    }

    private var liveCommand: String {
        """
        sudo TMDNS_DNS_ADDR=auto:53 \\
          TMDNS_HTTP_ADDR=auto:8080 \\
          TMDNS_DB_PATH="/Library/Application Support/TM-DNS/tm-dns.db" \\
          TMDNS_LOG_LEVEL=info \\
          "/Library/Application Support/TM-DNS/tmdns"
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
                    Text("Use these confirmation and troubleshooting checks after install. Verify the local service first, then validate LAN clients only when you are ready to point DNS at this Mac.")
                        .foregroundStyle(TMDNSTheme.stone500)
                }
                .padding(20)
                .foregroundStyle(TMDNSTheme.stone900)
                .background(TMDNSTheme.olive200, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(TMDNSTheme.olive400, lineWidth: 1))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SetupStepCard(
                        number: "1",
                        title: "Verify the app API",
                        detail: service.isHealthy ? "The native app can reach the local TM-DNS admin API." : "The native app cannot reach the admin API yet. Start TM-DNS, then refresh.",
                        command: "curl http://127.0.0.1:8080/api/dashboard"
                    ) {
                        Button("Refresh") {
                            Task { await service.refresh() }
                        }
                        .buttonStyle(.bordered)
                        .tint(TMDNSTheme.olive700)
                    }

                    SetupStepCard(
                        number: "2",
                        title: "Test DNS locally",
                        detail: "Before touching router settings, make sure this Mac can answer a DNS query directly.",
                        command: digCommand
                    )

                    SetupStepCard(
                        number: "3",
                        title: "Test LAN DNS address",
                        detail: "From the Mac or another machine on the same network, query this Mac's detected LAN DNS address: \(detectedLANIP).",
                        command: lanDigCommand
                    )

                    SetupStepCard(
                        number: "4",
                        title: "Confirm router DNS settings",
                        detail: "In UniFi, keep DHCP Mode set to DHCP Server. Set DNS Server to the Mac's static LAN IP. Do not use DHCP Relay for this.",
                        command: service.detectedLANIP.map { "DNS Server: \($0)" } ?? "DNS Server: <detected LAN IP>"
                    )

                    SetupStepCard(
                        number: "5",
                        title: "Watch requests",
                        detail: "After a client renews DHCP or manually points DNS here, requests should appear in Realtime and Top Hosts.",
                        command: "sudo tcpdump -ni any port 53"
                    )

                    SetupStepCard(
                        number: "6",
                        title: "Manual daemon troubleshooting",
                        detail: "Only use this when the launchd service is offline and you need to see foreground logs.",
                        command: liveCommand
                    )
                }
            }
            .padding(20)
        }
        .background(TMDNSTheme.olive300)
        .foregroundStyle(TMDNSTheme.stone900)
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
                .foregroundStyle(TMDNSTheme.stone900)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(TMDNSTheme.olive100.opacity(0.18), in: Capsule())
        .foregroundStyle(TMDNSTheme.stone900)
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
        .foregroundStyle(TMDNSTheme.stone900)
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
                HAPairingOverviewCard()
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

struct HAPairingOverviewCard: View {
    @EnvironmentObject private var service: TMDNSService

    private var pendingRequests: [HAJoinRequest] {
        service.haJoinRequests.filter { $0.status == "pending" }
    }

    private var detectedNode: HADiscoveredNode? {
        guard service.dashboard?.ha?.configured != true else { return nil }
        return service.haDiscoveredNodes.first
    }

    var body: some View {
        if !pendingRequests.isEmpty || detectedNode != nil {
            VStack(alignment: .leading, spacing: 10) {
                if !pendingRequests.isEmpty {
                    HStack {
                        Label("Secondary join request", systemImage: "link.badge.plus")
                            .font(.system(size: 17, weight: .semibold, design: .serif))
                        Spacer()
                        Text("\(pendingRequests.count) pending")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(TMDNSTheme.olive700)
                    }
                    ForEach(pendingRequests) { request in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(request.nodeHostname.isEmpty ? request.nodeName : request.nodeHostname)
                                    .font(.body.weight(.bold))
                                Text([request.nodeIP, request.nodeMAC, request.nodeURL].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(TMDNSTheme.stone500)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("Accept") {
                                Task { await service.acceptHAJoinRequest(request.id) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(TMDNSTheme.olive700)
                        }
                    }
                } else if let node = detectedNode {
                    HStack(spacing: 12) {
                        Label("Other TM-DNS detected", systemImage: "network")
                            .font(.system(size: 17, weight: .semibold, design: .serif))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.hostname.isEmpty ? node.name : node.hostname)
                                .font(.caption.weight(.bold))
                            Text([node.ip, node.mac, node.url].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption.monospaced())
                                .foregroundStyle(TMDNSTheme.stone500)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Request Join") {
                            Task { await service.requestHAJoin(to: node) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(TMDNSTheme.olive700)
                    }
                }
            }
            .padding(14)
            .foregroundStyle(TMDNSTheme.stone900)
            .background(TMDNSTheme.olive200, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(TMDNSTheme.olive400, lineWidth: 1))
        }
    }
}

struct HeaderRedundancyStatus: View {
    @EnvironmentObject private var service: TMDNSService
    @State private var showsGuidance = false

    private var roleText: String {
        guard let role = service.dashboard?.ha?.role.lowercased(), !role.isEmpty else {
            return "Role unknown"
        }
        return role == "secondary" ? "Secondary DNS" : "Primary DNS"
    }

    private var shouldWarn: Bool {
        guard let ha = service.dashboard?.ha else {
            return true
        }
        return !ha.enabled || !ha.configured || ha.stale
    }

    private var detail: String {
        guard let ha = service.dashboard?.ha else {
            return "TM-DNS cannot confirm secondary DNS health yet. A single DNS server can take the network offline if this Mac is restarted, asleep, disconnected, or updating."
        }
        let isSecondary = ha.role.lowercased() == "secondary"
        if !ha.enabled {
            return isSecondary
                ? "This node is marked Secondary, but redundancy is disabled. Accept pairing from the Primary or enable HA before using it as backup DNS."
                : "Secondary DNS is not enabled. Put a second onsite TM-DNS server in DHCP as backup DNS before relying on this for production."
        }
        if !ha.configured {
            return isSecondary
                ? "This Secondary is not paired to a Primary yet. Request join from this Mac, then accept it on the Primary dashboard."
                : "Primary DNS is enabled but no Secondary peer is paired yet. Accept a secondary join request, then run Heartbeat and Push Sync."
        }
        if ha.stale {
            return isSecondary
                ? "Primary DNS heartbeat is stale. Check the primary Mac, network path, admin token, and firewall access before relying on failover."
                : "Secondary DNS heartbeat is stale. Check the peer Mac, network path, admin token, and firewall access before making network-wide DNS changes."
        }
        return ""
    }

    private var warningText: String {
        guard let ha = service.dashboard?.ha else { return "HA unknown" }
        if ha.role.lowercased() == "secondary" {
            if !ha.enabled || !ha.configured { return "Secondary not paired" }
            if ha.stale { return "Primary stale" }
            return "Secondary healthy"
        }
        if !ha.enabled || !ha.configured { return "No secondary DNS" }
        if ha.stale { return "Secondary stale" }
        return "Secondary healthy"
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(roleText)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(TMDNSTheme.stone900)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(TMDNSTheme.olive100, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(TMDNSTheme.olive400, lineWidth: 1))
            if shouldWarn {
                warningChip
            }
        }
    }

    private var warningChip: some View {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TMDNSTheme.red)
                Text(warningText)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TMDNSTheme.stone900)
                Button {
                    showsGuidance.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(TMDNSTheme.olive700)
                .popover(isPresented: $showsGuidance, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Redundant DNS")
                            .font(.headline)
                            .foregroundStyle(TMDNSTheme.stone900)
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(TMDNSTheme.stone900)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Recommendation")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(TMDNSTheme.stone900)
                        Text("Use two wired Macs with static IPs or DHCP reservations. Configure one as Primary, one as Secondary, run Heartbeat, Push Sync from the Primary, then advertise both IPs as DNS servers in DHCP.")
                            .font(.caption)
                            .foregroundStyle(TMDNSTheme.stone500)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(width: 340, alignment: .leading)
                    .background(TMDNSTheme.olive100)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(red: 0.93, green: 0.86, blue: 0.72), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.69, green: 0.49, blue: 0.17), lineWidth: 1))
    }
}

struct HeaderCard: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("DNS")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(TMDNSTheme.olive950)
                        .frame(width: 34, height: 28)
                        .background(TMDNSTheme.olive100, in: RoundedRectangle(cornerRadius: 7))
                    Label("TM-DNS", systemImage: service.isHealthy ? "shield.checkered" : "shield.slash")
                        .font(.system(size: 27, weight: .semibold, design: .serif))
                }
                Text("All your queries are belong to us")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TMDNSTheme.stone500)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 10) {
                    Text(service.statusText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(service.isHealthy ? TMDNSTheme.olive700 : TMDNSTheme.red)
                    Text(service.installedVersionText)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(TMDNSTheme.stone500)
                    HeaderRedundancyStatus()
                }
                HeaderSystemStats(system: service.dashboard?.system)
                HeaderUpdateControls()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .foregroundStyle(TMDNSTheme.stone900)
        .background(TMDNSTheme.olive200, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(TMDNSTheme.olive400, lineWidth: 1))
    }
}

struct HeaderUpdateControls: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(service.updateStatus.message)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TMDNSTheme.stone500)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 220, alignment: .trailing)
            if let release = service.availableUpdate {
                Link("Notes", destination: release.htmlURL)
                    .font(.system(size: 11, weight: .semibold))
            }
            Button(service.updateStatus.canInstall ? "Update" : "Check") {
                Task {
                    if service.updateStatus.canInstall {
                        await service.installAvailableUpdate()
                    } else {
                        await service.checkForUpdates(userInitiated: true)
                    }
                }
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .tint(service.updateStatus.canInstall ? TMDNSTheme.green : TMDNSTheme.olive700)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(TMDNSTheme.olive100, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(TMDNSTheme.olive400, lineWidth: 1))
    }

    private var iconName: String {
        switch service.updateStatus {
        case .available: "arrow.down.circle.fill"
        case .downloading, .verifying, .installing: "clock.arrow.circlepath"
        case .failed: "exclamationmark.triangle.fill"
        case .current, .readyToInstall: "checkmark.seal.fill"
        case .idle, .checking: "arrow.triangle.2.circlepath"
        }
    }

    private var iconColor: Color {
        switch service.updateStatus {
        case .available: TMDNSTheme.green
        case .failed: TMDNSTheme.red
        default: TMDNSTheme.olive700
        }
    }
}

struct HeaderSystemStats: View {
    let system: SystemStats?

    var body: some View {
        HStack(spacing: 6) {
            HeaderStatChip(title: "CPU", value: percent(system?.cpuPercent))
            HeaderStatChip(title: "MEM", value: mb(system?.residentMB))
            HeaderStatChip(title: "APP", value: mb(system?.appStorageMB))
            HeaderStatChip(title: "DISK", value: percent(system?.diskUsedPercent))
        }
    }
}

struct HeaderStatChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundStyle(TMDNSTheme.stone500)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .serif))
                .foregroundStyle(TMDNSTheme.stone900)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(width: 60, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(TMDNSTheme.olive100, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(TMDNSTheme.olive400, lineWidth: 1))
    }
}

struct UpdateCard: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 34, height: 34)
                .background(TMDNSTheme.olive100, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 3) {
                Text("Software Update")
                    .font(.headline)
                    .foregroundStyle(TMDNSTheme.stone900)
                Text(service.updateStatus.message)
                    .font(.caption)
                    .foregroundStyle(TMDNSTheme.stone500)
            }
            Spacer()
            if let release = service.availableUpdate {
                Link("Release Notes", destination: release.htmlURL)
                    .font(.caption.weight(.semibold))
            }
            Button(service.updateStatus.canInstall ? "Update" : "Check") {
                Task {
                    if service.updateStatus.canInstall {
                        await service.installAvailableUpdate()
                    } else {
                        await service.checkForUpdates(userInitiated: true)
                    }
                }
            }
            .buttonStyle(.bordered)
            .tint(service.updateStatus.canInstall ? TMDNSTheme.green : TMDNSTheme.olive700)
        }
        .padding(14)
        .foregroundStyle(TMDNSTheme.stone900)
        .background(TMDNSTheme.olive200, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(TMDNSTheme.olive400, lineWidth: 1))
    }

    private var iconName: String {
        switch service.updateStatus {
        case .available: "arrow.down.circle.fill"
        case .downloading, .verifying, .installing: "clock.arrow.circlepath"
        case .failed: "exclamationmark.triangle.fill"
        case .current, .readyToInstall: "checkmark.seal.fill"
        case .idle, .checking: "arrow.triangle.2.circlepath"
        }
    }

    private var iconColor: Color {
        switch service.updateStatus {
        case .available: TMDNSTheme.green
        case .failed: TMDNSTheme.red
        default: TMDNSTheme.olive700
        }
    }
}

struct MetricGrid: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        let dashboard = service.dashboard?.dashboard
        let dns = service.dashboard?.dns
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            MetricCard(title: "Queries Today", value: "\(dashboard?.queriesToday ?? 0)")
            MetricCard(title: "Blocked Today", value: "\(dashboard?.blockedToday ?? 0)")
            MetricCard(title: "Unique Hosts", value: "\(dashboard?.uniqueHosts ?? 0)")
            MetricCard(title: "Runtime Queries", value: "\(dns?.queries ?? 0)")
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
            Text("Last 48 hours")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TMDNSTheme.stone500)
            TopDomainsList(rows: rows)
        }
        .frame(width: 360, alignment: .topLeading)
        .padding(14)
        .background(TMDNSTheme.olive200, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(TMDNSTheme.olive400, lineWidth: 1))
        .foregroundStyle(TMDNSTheme.stone900)
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
        .foregroundStyle(TMDNSTheme.stone900)
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
    @State private var selectedHostID: Int?
    @State private var loadingHostID: Int?
    let onOpenHost: (Int) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(service.dashboard?.dashboard.topHosts ?? []) { host in
                    HostListRow(
                        host: host,
                        isLoading: loadingHostID == host.id,
                        isSelected: selectedHostID == host.id
                    ) {
                        openHost(host.id)
                    }
                }
            }
            .padding(16)
        }
        .background(TMDNSTheme.olive300)
    }

    private func openHost(_ id: Int) {
        selectedHostID = id
        loadingHostID = id
        onOpenHost(id)
        loadingHostID = nil
    }
}

struct DedicatedHostDetailView: View {
    @EnvironmentObject private var service: TMDNSService
    let selectedHostID: Int?
    @Binding var windowHours: Int
    let onBack: () -> Void
    let onWindowChange: (Int) -> Void

    var body: some View {
        Group {
            if let detail = service.selectedHostDetail {
                HostDetailPage(
                    detail: detail,
                    windowHours: $windowHours,
                    onBack: onBack,
                    onWindowChange: onWindowChange
                )
            } else {
                VStack(spacing: 14) {
                    ProgressView()
                    Text(selectedHostID == nil ? "Select a host to view details." : "Loading host detail...")
                        .font(.headline)
                        .foregroundStyle(TMDNSTheme.stone900)
                    if let error = service.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(TMDNSTheme.red)
                    }
                    Button {
                        onBack()
                    } label: {
                        Label("Back to Hosts", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(TMDNSTheme.olive300)
            }
        }
    }
}

struct HostListRow: View {
    let host: TopHost
    let isLoading: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(displayName)
                        .font(.headline)
                        .foregroundStyle(TMDNSTheme.stone900)
                    Text(host.hostname.isEmpty ? "hostname not learned yet" : host.hostname)
                        .font(.caption)
                        .foregroundStyle(TMDNSTheme.stone500)
                    Text(host.sourceIP)
                        .font(.caption.monospaced())
                        .foregroundStyle(TMDNSTheme.stone500)
                }
                Spacer()
                Text("\(host.count)")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(TMDNSTheme.olive700)
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(TMDNSTheme.stone500)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? TMDNSTheme.olive200 : TMDNSTheme.olive100, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(TMDNSTheme.olive400, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var displayName: String {
        if !host.label.isEmpty { return host.label }
        if !host.hostname.isEmpty { return host.hostname }
        return host.sourceIP
    }
}

struct HostDetailPage: View {
    @EnvironmentObject private var service: TMDNSService
    let detail: HostDetail
    @Binding var windowHours: Int
    let onBack: () -> Void
    let onWindowChange: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Button {
                        onBack()
                    } label: {
                        Label("Hosts", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName(detail.host))
                            .font(.system(size: 34, weight: .semibold, design: .serif))
                        Text("\(detail.host.sourceIP) · DNS \(detail.host.hostname.isEmpty ? "not learned" : detail.host.hostname)")
                            .font(.caption.monospaced())
                            .foregroundStyle(TMDNSTheme.stone500)
                    }
                    Spacer()
                    Picker("Window", selection: Binding(
                        get: { windowHours },
                        set: { value in
                            windowHours = value
                            onWindowChange(value)
                        }
                    )) {
                        Text("24 hours").tag(24)
                        Text("48 hours").tag(48)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
                .padding(20)
                .background(TMDNSTheme.olive200, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(TMDNSTheme.olive400, lineWidth: 1))

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    MetricCard(title: "\(detail.windowHours)h Hits", value: "\(detail.totalQueries)")
                    MetricCard(title: "Blocked", value: "\(detail.totalBlocked)")
                    MetricCard(title: "Unique Sites", value: "\(detail.uniqueDomains)")
                    MetricCard(title: "Identity", value: detail.host.identityConfidence.isEmpty ? "unknown" : detail.host.identityConfidence)
                }

                HStack(alignment: .top, spacing: 16) {
                    HostInfoCard(host: detail.host)
                    BreakdownCard(title: "Request Breakdown", rows: detail.topDomains, total: detail.totalQueries, allowBlocking: true)
                    BreakdownCard(title: "Actions", rows: detail.topActions, total: detail.totalQueries, allowBlocking: false)
                }

                ListPanel(title: "Timeline") {
                    if detail.recent.isEmpty {
                        Text("No DNS requests recorded in this window.")
                            .foregroundStyle(TMDNSTheme.stone500)
                    }
                    ForEach(detail.recent) { event in
                        EventRow(event: event)
                    }
                }
            }
            .padding(20)
        }
        .background(TMDNSTheme.olive300)
    }

    private func displayName(_ host: Host) -> String {
        if !host.label.isEmpty { return host.label }
        if !host.hostname.isEmpty { return host.hostname }
        return host.sourceIP
    }
}

struct HostInfoCard: View {
    let host: Host

    var body: some View {
        ListPanel(title: "Host Info") {
            InfoLine(label: "IP", value: host.sourceIP)
            InfoLine(label: "Hostname", value: host.hostname.isEmpty ? "not learned" : host.hostname)
            InfoLine(label: "MAC", value: host.mac.isEmpty ? "not learned" : host.mac)
            InfoLine(label: "Vendor", value: host.vendor.isEmpty ? "not learned" : host.vendor)
        }
    }
}

struct BreakdownCard: View {
    @EnvironmentObject private var service: TMDNSService
    let title: String
    let rows: [TopRow]
    let total: Int
    let allowBlocking: Bool

    var body: some View {
        ListPanel(title: title) {
            if rows.isEmpty {
                Text("No activity in this window.")
                    .foregroundStyle(TMDNSTheme.stone500)
            }
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.key)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(TMDNSTheme.stone900)
                            .lineLimit(1)
                        ProgressView(value: percentage(row.count), total: 100)
                            .tint(TMDNSTheme.olive700)
                    }
                    Spacer()
                    Text("\(row.count)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(TMDNSTheme.stone500)
                    Text(percentLabel(row.count))
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(TMDNSTheme.olive700)
                        .frame(width: 58, alignment: .trailing)
                    if allowBlocking {
                        Button("Block") {
                            Task { await service.block(domain: row.key) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(TMDNSTheme.red)
                    }
                }
                .padding(8)
                .background(TMDNSTheme.olive100, in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    private func percentage(_ count: Int) -> Double {
        guard total > 0 else { return 0 }
        return (Double(count) / Double(total)) * 100
    }

    private func percentLabel(_ count: Int) -> String {
        "\(Int(percentage(count).rounded()))%"
    }
}

struct InfoLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(TMDNSTheme.stone500)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(TMDNSTheme.stone900)
                .textSelection(.enabled)
        }
        .padding(8)
        .background(TMDNSTheme.olive100, in: RoundedRectangle(cornerRadius: 7))
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
                    if let percent = row.percent {
                        Text(percentLabel(percent))
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(TMDNSTheme.olive700)
                            .frame(width: 58, alignment: .trailing)
                    }
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

    private func percentLabel(_ percent: Double) -> String {
        "\(Int(percent.rounded()))%"
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
        .foregroundStyle(TMDNSTheme.stone900)
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
                        .buttonStyle(.bordered)
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
                        .buttonStyle(.bordered)
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
        .foregroundStyle(TMDNSTheme.stone900)
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
        .foregroundStyle(TMDNSTheme.stone900)
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
        .foregroundStyle(TMDNSTheme.stone900)
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
        .foregroundStyle(TMDNSTheme.stone900)
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
    @State private var haEnabled = false
    @State private var haRole = "primary"
    @State private var haPeerName = ""
    @State private var haPeerURL = ""
    @State private var haPeerToken = ""
    @State private var joinPrimaryURL = ""
    @State private var joinLocalURL = ""
    @State private var joinNodeName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ListPanel(title: "Connection") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Local API URL", text: $service.baseURLString)
                            .textFieldStyle(.roundedBorder)
                        SecureField("Admin token for LAN access", text: $service.adminToken)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Refresh Connection") {
                                Task { await service.refresh() }
                            }
                            .buttonStyle(.bordered)
                            .tint(TMDNSTheme.olive700)
                            Button("Open Web Dashboard") {
                                service.openWebDashboard()
                            }
                            .buttonStyle(.bordered)
                            .tint(TMDNSTheme.olive700)
                        }
                        Text("The native app and localhost web dashboard can use loopback without a login. LAN browsers still need the admin token from admin-token.txt next to the database unless TMDNS_ADMIN_TOKEN is configured.")
                            .font(.caption)
                            .foregroundStyle(TMDNSTheme.stone500)
                    }
                }

                UpdateCard()

                ListPanel(title: "Operational Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoLine(label: "API URL", value: service.baseURLString)
                        InfoLine(label: "Detected LAN IP", value: service.detectedLANIP ?? "not detected")
                        InfoLine(label: "DNS Listener", value: service.dashboard?.dns.dnsAddr ?? "service offline")
                        InfoLine(label: "Upstream", value: service.dashboard?.dns.upstream ?? "service offline")
                        InfoLine(label: "Database", value: service.dashboard?.system?.dataDir ?? "service offline")
                    }
                }

                ListPanel(title: "Appliance Checks") {
                    VStack(alignment: .leading, spacing: 8) {
                        let power = service.dashboard?.system?.power
                        InfoLine(label: "Sleep", value: power?.detail ?? "power state unavailable")
                        InfoLine(label: "Dropped Events", value: "\(service.dashboard?.dns.droppedEvents ?? 0)")
                        InfoLine(label: "Event Queue", value: "\(service.dashboard?.dns.eventQueueDepth ?? 0)")
                        CommandBox(command: "curl http://127.0.0.1:8080/api/diagnostics")
                    }
                }

                ListPanel(title: "Onsite Secondary DNS") {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Pairing")
                                .font(.headline)
                            Text("Install TM-DNS on the second Mac, set it to Secondary, then send a join request to the Primary. The Primary must accept before sync is trusted.")
                                .font(.caption)
                                .foregroundStyle(TMDNSTheme.stone500)
                            HStack {
                                TextField("Primary API URL, e.g. http://192.168.222.8:8080", text: $joinPrimaryURL)
                                    .textFieldStyle(.roundedBorder)
                                TextField("This Mac API URL", text: $joinLocalURL)
                                    .textFieldStyle(.roundedBorder)
                            }
                            TextField("This node name", text: $joinNodeName)
                                .textFieldStyle(.roundedBorder)
                            HStack {
                                Button("Find Local Nodes") {
                                    Task { await service.discoverHANodes() }
                                }
                                .buttonStyle(.bordered)
                                .tint(TMDNSTheme.olive700)
                                Button("Request Join") {
                                    Task {
                                        await service.requestHAJoin(primaryURL: joinPrimaryURL, localURL: joinLocalURL, nodeName: joinNodeName)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .tint(TMDNSTheme.olive700)
                                Button("Refresh Pending Requests") {
                                    Task { await service.refreshHAJoinRequests() }
                                }
                                .buttonStyle(.bordered)
                                .tint(TMDNSTheme.olive700)
                            }
                            if !service.haDiscoveredNodes.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Discovered TM-DNS Nodes")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(TMDNSTheme.stone900)
                                    ForEach(service.haDiscoveredNodes) { node in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(node.name)
                                                    .font(.caption.weight(.semibold))
                                                Text("\(node.url) · \(node.role)")
                                                    .font(.caption.monospaced())
                                                    .foregroundStyle(TMDNSTheme.stone500)
                                            }
                                            Spacer()
                                            Button("Use as Primary") {
                                                joinPrimaryURL = node.url
                                            }
                                            .buttonStyle(.bordered)
                                            .tint(TMDNSTheme.olive700)
                                        }
                                        .padding(8)
                                        .background(TMDNSTheme.olive100, in: RoundedRectangle(cornerRadius: 7))
                                    }
                                }
                            }
                            if !service.haJoinRequests.filter({ $0.status == "pending" }).isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Pending Join Requests")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(TMDNSTheme.stone900)
                                    ForEach(service.haJoinRequests.filter { $0.status == "pending" }) { request in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(request.nodeName)
                                                    .font(.caption.weight(.semibold))
                                                Text(request.nodeURL)
                                                    .font(.caption.monospaced())
                                                    .foregroundStyle(TMDNSTheme.stone500)
                                            }
                                            Spacer()
                                            Button("Accept") {
                                                Task { await service.acceptHAJoinRequest(request.id) }
                                            }
                                            .buttonStyle(.bordered)
                                            .tint(TMDNSTheme.green)
                                        }
                                        .padding(8)
                                        .background(TMDNSTheme.olive100, in: RoundedRectangle(cornerRadius: 7))
                                    }
                                }
                            }
                        }
                        Divider()
                        Toggle("Enable peer heartbeat and sync", isOn: $haEnabled)
                            .toggleStyle(.switch)
                        Picker("Role", selection: $haRole) {
                            Text("Primary").tag("primary")
                            Text("Secondary").tag("secondary")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 260)
                        TextField("Peer name", text: $haPeerName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Peer API URL, e.g. https://tm-dns-secondary.example.edu:8080", text: $haPeerURL)
                            .textFieldStyle(.roundedBorder)
                        SecureField(service.haSettings.hasPeerToken ? "Peer admin token saved - leave blank to keep" : "Peer admin token", text: $haPeerToken)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Save Peer") {
                                Task { await saveHASettings() }
                            }
                            .buttonStyle(.bordered)
                            .tint(TMDNSTheme.olive700)
                            Button("Heartbeat") {
                                Task { await service.testHAPeer() }
                            }
                            .buttonStyle(.bordered)
                            .tint(TMDNSTheme.olive700)
                            Button("Push Sync") {
                                Task { await service.syncHAPeer() }
                            }
                            .buttonStyle(.bordered)
                            .tint(TMDNSTheme.olive700)
                        }
                        Text("Recommended deployment: two onsite Macs with static IPs. Put both IPs into DHCP DNS servers. Use HTTPS or a trusted management VLAN for peer sync, then Push Sync after policy changes.")
                            .font(.caption)
                            .foregroundStyle(TMDNSTheme.stone500)
                        InfoLine(label: "Peer Status", value: service.haStatus?.error ?? service.haStatus?.status ?? service.haSettings.lastStatus.ifEmpty("not checked"))
                        InfoLine(label: "Last Heartbeat", value: service.haSettings.lastHeartbeat.ifEmpty("never"))
                        InfoLine(label: "Last Sync", value: service.haSettings.lastSync.ifEmpty("never"))
                        if let result = service.haSyncResult {
                            InfoLine(label: "Last Push", value: "\(result.status): \(result.rules) rules, \(result.staticRecords) records, \(result.blocklistSources) custom lists")
                        }
                        if let health = service.dashboard?.ha, health.enabled {
                            InfoLine(label: "Automatic Heartbeat", value: health.stale ? "stale" : health.status)
                            InfoLine(label: "Automatic Sync", value: health.role == "primary" ? "primary pushes every 5 minutes" : "secondary receives sync")
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(TMDNSTheme.olive300)
        .foregroundStyle(TMDNSTheme.stone900)
        .task {
            await service.refreshHASettings()
            await service.refreshHAJoinRequests()
            loadHASettings()
            loadJoinDefaults()
        }
        .onChange(of: service.haSettings) { _, _ in
            loadHASettings()
        }
    }

    private func loadHASettings() {
        haEnabled = service.haSettings.enabled
        haRole = service.haSettings.role.isEmpty ? "primary" : service.haSettings.role
        haPeerName = service.haSettings.peerName
        haPeerURL = service.haSettings.peerURL
        haPeerToken = ""
    }

    private func loadJoinDefaults() {
        if joinLocalURL.isEmpty, let lanIP = service.detectedLANIP {
            joinLocalURL = "http://\(lanIP):8080"
        }
        if joinNodeName.isEmpty {
            joinNodeName = ProcessInfo.processInfo.hostName
        }
    }

    private func saveHASettings() async {
        await service.saveHASettings(HASettings(
            enabled: haEnabled,
            role: haRole,
            peerName: haPeerName,
            peerURL: haPeerURL,
            peerToken: haPeerToken,
            hasPeerToken: service.haSettings.hasPeerToken,
            lastHeartbeat: service.haSettings.lastHeartbeat,
            lastSync: service.haSettings.lastSync,
            lastStatus: service.haSettings.lastStatus
        ))
        loadHASettings()
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
            Text(service.installedVersionText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(TMDNSTheme.stone500)
            Divider()
            Button("Open Dashboard") {
                service.openWebDashboard()
            }
            Button("Refresh") {
                Task { await service.refresh() }
            }
            if service.updateStatus.canInstall {
                Button("Update") {
                    Task { await service.installAvailableUpdate() }
                }
            } else {
                Button("Check for Updates") {
                    Task { await service.checkForUpdates(userInitiated: true) }
                }
            }
            Text(service.updateStatus.message)
                .font(.caption)
                .foregroundStyle(TMDNSTheme.stone500)
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

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}

#Preview {
    ContentView()
        .environmentObject(TMDNSService())
}
