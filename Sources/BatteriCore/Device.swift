import Foundation

/// One device as reported by the engine (`batteri --json`).
public struct Device: Codable, Identifiable, Equatable, Sendable {
    public enum Source: String, Sendable {
        /// Reported by Apple's Find My service.
        case findMy = "find_my"
        /// Read live from this Mac's Bluetooth connection.
        case bluetooth
        /// The level this Mac saw the last time the device was connected. May be old.
        case bluetoothLastKnown = "bluetooth_last_known"
    }

    public let name: String
    public let model: String
    /// `nil` when no battery level is reported for the device.
    public let percent: Int?
    public let charging: Bool
    public let lowPower: Bool
    public let online: Bool
    /// Belongs to a Family Sharing member rather than the signed-in account.
    public let family: Bool
    /// Apple's device class: iPhone, iPad, Watch, MacBookPro, Accessory, Keyboard, Mouse…
    public let deviceClass: String
    public let source: Source
    /// AirPods report each earbud and the case separately.
    public let left: Int?
    public let right: Int?
    public let caseLevel: Int?

    public var id: String { "\(family ? "family" : "own")|\(deviceClass)|\(name)" }

    enum CodingKeys: String, CodingKey {
        case name, model, percent, charging, online, family, source, left, right
        case lowPower = "low_power"
        case deviceClass = "device_class"
        case caseLevel = "case"
    }

    public init(
        name: String, model: String = "", percent: Int?, charging: Bool = false,
        lowPower: Bool = false, online: Bool = true, family: Bool = false,
        deviceClass: String = "", source: Source = .findMy,
        left: Int? = nil, right: Int? = nil, caseLevel: Int? = nil
    ) {
        self.name = name
        self.model = model
        self.percent = percent
        self.charging = charging
        self.lowPower = lowPower
        self.online = online
        self.family = family
        self.deviceClass = deviceClass
        self.source = source
        self.left = left
        self.right = right
        self.caseLevel = caseLevel
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        percent = try c.decodeIfPresent(Int.self, forKey: .percent)
        charging = try c.decodeIfPresent(Bool.self, forKey: .charging) ?? false
        lowPower = try c.decodeIfPresent(Bool.self, forKey: .lowPower) ?? false
        online = try c.decodeIfPresent(Bool.self, forKey: .online) ?? false
        family = try c.decodeIfPresent(Bool.self, forKey: .family) ?? false
        deviceClass = try c.decodeIfPresent(String.self, forKey: .deviceClass) ?? ""
        // A newer engine may add sources this app does not know yet; treat them as Find My.
        let rawSource = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        source = Source(rawValue: rawSource) ?? .findMy
        left = try c.decodeIfPresent(Int.self, forKey: .left)
        right = try c.decodeIfPresent(Int.self, forKey: .right)
        caseLevel = try c.decodeIfPresent(Int.self, forKey: .caseLevel)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(model, forKey: .model)
        try c.encodeIfPresent(percent, forKey: .percent)
        try c.encode(charging, forKey: .charging)
        try c.encode(lowPower, forKey: .lowPower)
        try c.encode(online, forKey: .online)
        try c.encode(family, forKey: .family)
        try c.encode(deviceClass, forKey: .deviceClass)
        try c.encode(source.rawValue, forKey: .source)
        try c.encodeIfPresent(left, forKey: .left)
        try c.encodeIfPresent(right, forKey: .right)
        try c.encodeIfPresent(caseLevel, forKey: .caseLevel)
    }
}
