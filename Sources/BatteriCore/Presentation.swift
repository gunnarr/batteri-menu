import Foundation

/// Turns a `Device` into the words and symbols shown in the menu.
public enum Presentation {
    /// At or below this level a device that is not charging counts as low.
    public static let lowThreshold = 20

    /// SF Symbol for the kind of device.
    public static func deviceSymbol(for device: Device) -> String {
        let cls = device.deviceClass
        switch cls {
        case "iPhone", "iPod": return "iphone"
        case "iPad": return "ipad"
        case "Watch": return "applewatch"
        case "Keyboard": return "keyboard"
        case "Mouse": return "magicmouse"
        case "Trackpad": return "rectangle.and.hand.point.up.left"
        case "Headphones": return "headphones"
        case "AppleTV": return "appletv"
        case "iMac": return "desktopcomputer"
        case "Macmini": return "macmini"
        case "MacStudio": return "macstudio"
        case "MacPro": return "macpro.gen3"
        default: break
        }
        if cls.hasPrefix("MacBook") { return "laptopcomputer" }
        if cls.hasPrefix("Mac") { return "desktopcomputer" }
        let model = device.model + " " + device.name
        if model.localizedCaseInsensitiveContains("AirPods Max") { return "airpodsmax" }
        if model.localizedCaseInsensitiveContains("AirPods Pro") { return "airpodspro" }
        if model.localizedCaseInsensitiveContains("AirPods") { return "airpods" }
        if model.localizedCaseInsensitiveContains("Beats") { return "beats.headphones" }
        return "questionmark.circle"
    }

    /// SF Symbol for a battery at the given level.
    public static func batterySymbol(percent: Int?, charging: Bool) -> String {
        guard let percent else { return "battery.0percent" }
        if charging { return "battery.100percent.bolt" }
        switch percent {
        case 88...: return "battery.100percent"
        case 63...: return "battery.75percent"
        case 38...: return "battery.50percent"
        case 13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    public static func isLow(_ device: Device) -> Bool {
        guard let percent = device.percent, !device.charging else { return false }
        return percent <= lowThreshold
    }

    public static func percentText(_ device: Device) -> String {
        device.percent.map { "\($0)%" } ?? "–"
    }

    /// The secondary line under the device name. Empty when there is nothing to add.
    public static func statusText(for device: Device) -> String {
        guard let percent = device.percent else {
            return device.online ? "No battery information" : "Offline"
        }
        var parts: [String] = []
        if device.charging {
            parts.append(percent >= 100 ? "Fully charged" : "Charging")
        }
        if device.lowPower {
            parts.append("Low Power Mode")
        }
        switch device.source {
        case .bluetoothLastKnown:
            parts.append("Last known level")
        case .bluetooth, .findMy:
            if !device.online { parts.append("Offline") }
        }
        // Only spell out the earbuds when they differ; "L 100% · R 100%" next to "100%" is noise.
        if let left = device.left, let right = device.right, left != right {
            parts.append("L \(left)% · R \(right)%")
        }
        return parts.joined(separator: " · ")
    }

    /// Everything known about the device, for the tooltip.
    public static func detailText(for device: Device) -> String {
        var lines: [String] = []
        if !device.model.isEmpty, device.source == .findMy || device.left != nil { lines.append(device.model) }
        var levels: [String] = []
        if let left = device.left { levels.append("Left \(left)%") }
        if let right = device.right { levels.append("Right \(right)%") }
        if let caseLevel = device.caseLevel { levels.append("Case \(caseLevel)%") }
        if !levels.isEmpty { lines.append(levels.joined(separator: ", ")) }
        switch device.source {
        case .findMy: break
        case .bluetooth: lines.append("Read from this Mac’s Bluetooth connection.")
        case .bluetoothLastKnown:
            lines.append("The level this Mac saw the last time the device was connected. It may be out of date.")
        }
        return lines.joined(separator: "\n")
    }

    /// What VoiceOver reads for a row.
    public static func accessibilityLabel(for device: Device) -> String {
        var parts = [device.name]
        if let percent = device.percent {
            parts.append("\(percent) percent")
        }
        let status = statusText(for: device)
        if !status.isEmpty { parts.append(status) }
        return parts.joined(separator: ", ")
    }

    /// The device that most needs attention: the lowest level among devices that are
    /// reachable right now. Stale readings and family devices are left out.
    public static func lowest(in devices: [Device]) -> Device? {
        devices
            .filter { $0.percent != nil && $0.online && !$0.family && $0.source != .bluetoothLastKnown }
            .min { ($0.percent ?? 0) < ($1.percent ?? 0) }
    }

    /// "Updated just now", "Updated 5 min ago" …
    public static func updatedText(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "Updated just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "Updated \(minutes) min ago" }
        let hours = minutes / 60
        return hours == 1 ? "Updated 1 hour ago" : "Updated \(hours) hours ago"
    }
}
