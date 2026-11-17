import BatteriCore
import SwiftUI

/// The window that drops down from the menu bar item.
struct PanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: BatteryStore

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(width: 320)
        .task {
            // Opening the menu is a good moment to make sure the numbers are fresh.
            if store.isStale(after: 60) { await model.refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading:
            message(symbol: nil, title: "Looking for your devices…", detail: nil) {
                ProgressView().controlSize(.small)
            }
        case .needsLogin:
            message(
                symbol: "person.crop.circle.badge.questionmark",
                title: "Sign in to see your devices",
                detail: "Batteri uses your iCloud account to read the same battery levels as Find My."
            ) {
                Button("Sign In…") { model.showSignIn() }
                    .keyboardShortcut(.defaultAction)
            }
        case .engineMissing:
            message(
                symbol: "exclamationmark.triangle",
                title: "Batteri is incomplete",
                detail: "The part that talks to iCloud is missing. Download Batteri again, or install the batteri command-line tool."
            ) { EmptyView() }
        case .ready:
            if store.devices.isEmpty {
                message(
                    symbol: "battery.0percent",
                    title: store.lastError == nil ? "No devices found" : "Couldn’t load your devices",
                    detail: store.lastError == nil
                        ? "Make sure Find My is turned on for your devices."
                        : "Check your internet connection and try again."
                ) { EmptyView() }
            } else {
                deviceList
            }
        }
    }

    private var deviceList: some View {
        let own = store.devices.filter { !$0.family }
        let family = store.devices.filter(\.family)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(own) { DeviceRow(device: $0) }
                if !family.isEmpty {
                    Text("Family")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(family) { DeviceRow(device: $0) }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if store.lastError != nil, !store.devices.isEmpty {
                Label("Couldn’t update", systemImage: "exclamationmark.triangle")
                    .help(store.lastError ?? "")
            } else if let updatedAt = store.updatedAt {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(Presentation.updatedText(since: updatedAt, now: context.date))
                }
            }
            Spacer()
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
                .accessibilityLabel("Refresh")
                .keyboardShortcut("r")
                .disabled(store.phase == .engineMissing)
            }
            Menu {
                Button("Settings…") { model.showSettings() }
                    .keyboardShortcut(",")
                Divider()
                Button("Quit Batteri") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func message<Accessory: View>(
        symbol: String?, title: String, detail: String?,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        VStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(title).font(.headline)
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            accessory()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
    }
}

/// One device: what it is, what it is called, and how much charge is left.
struct DeviceRow: View {
    let device: Device

    var body: some View {
        let status = Presentation.statusText(for: device)
        let dimmed = device.percent == nil || device.source == .bluetoothLastKnown
        HStack(spacing: 10) {
            Image(systemName: Presentation.deviceSymbol(for: device))
                .font(.system(size: 17))
                .frame(width: 26)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(Presentation.percentText(device))
                .monospacedDigit()
                .foregroundStyle(dimmed ? .secondary : .primary)
            Image(systemName: Presentation.batterySymbol(percent: device.percent, charging: device.charging))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(batteryColor)
                .font(.system(size: 17))
                .frame(width: 30)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .help(Presentation.detailText(for: device))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Presentation.accessibilityLabel(for: device))
    }

    private var batteryColor: Color {
        if device.percent == nil { return .secondary.opacity(0.5) }
        if device.source == .bluetoothLastKnown { return .secondary }
        if Presentation.isLow(device) { return .red }
        if device.charging { return .green }
        return .primary
    }
}
