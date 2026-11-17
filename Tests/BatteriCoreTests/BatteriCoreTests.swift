import XCTest
@testable import BatteriCore

final class DeviceTests: XCTestCase {
    func testDecodesEngineOutput() throws {
        let json = """
        [{"name": "Anna’s iPhone", "model": "iPhone 16 Pro", "percent": 61, "charging": false,
          "low_power": true, "online": true, "family": false, "note": "",
          "device_class": "iPhone", "source": "find_my", "left": null, "right": null, "case": null},
         {"name": "AirPods", "model": "AirPods Pro", "percent": 70, "charging": false,
          "low_power": false, "online": false, "family": false, "note": "x",
          "device_class": "Accessory", "source": "bluetooth_last_known", "left": 70, "right": 85, "case": 100},
         {"name": "Old iPad", "percent": null, "source": "something_new"}]
        """
        let devices = try JSONDecoder().decode([Device].self, from: Data(json.utf8))
        XCTAssertEqual(devices.count, 3)
        XCTAssertEqual(devices[0].percent, 61)
        XCTAssertTrue(devices[0].lowPower)
        XCTAssertEqual(devices[0].deviceClass, "iPhone")
        XCTAssertEqual(devices[1].source, .bluetoothLastKnown)
        XCTAssertEqual([devices[1].left, devices[1].right, devices[1].caseLevel], [70, 85, 100])
        // Missing fields and unknown sources must not break decoding.
        XCTAssertNil(devices[2].percent)
        XCTAssertEqual(devices[2].source, .findMy)
        XCTAssertFalse(devices[2].online)
    }

    func testIdentifiersAreUniquePerOwnerAndName() {
        let own = Device(name: "iPhone", percent: 1, deviceClass: "iPhone")
        let family = Device(name: "iPhone", percent: 1, family: true, deviceClass: "iPhone")
        XCTAssertNotEqual(own.id, family.id)
    }
}

final class PresentationTests: XCTestCase {
    func testDeviceSymbols() {
        func symbol(_ cls: String, model: String = "") -> String {
            Presentation.deviceSymbol(for: Device(name: "x", model: model, percent: 1, deviceClass: cls))
        }
        XCTAssertEqual(symbol("iPhone"), "iphone")
        XCTAssertEqual(symbol("iPad"), "ipad")
        XCTAssertEqual(symbol("Watch"), "applewatch")
        XCTAssertEqual(symbol("MacBookPro"), "laptopcomputer")
        XCTAssertEqual(symbol("iMac"), "desktopcomputer")
        XCTAssertEqual(symbol("Keyboard"), "keyboard")
        XCTAssertEqual(symbol("Mouse"), "magicmouse")
        XCTAssertEqual(symbol("Accessory", model: "AirPods Pro (2nd generation)"), "airpodspro")
        XCTAssertEqual(symbol("Accessory", model: "AirPods Max"), "airpodsmax")
        XCTAssertEqual(symbol("Accessory", model: "AirPods"), "airpods")
        XCTAssertEqual(symbol("Accessory", model: "Mystery"), "questionmark.circle")
    }

    func testBatterySymbolSteps() {
        XCTAssertEqual(Presentation.batterySymbol(percent: nil, charging: false), "battery.0percent")
        XCTAssertEqual(Presentation.batterySymbol(percent: 100, charging: false), "battery.100percent")
        XCTAssertEqual(Presentation.batterySymbol(percent: 88, charging: false), "battery.100percent")
        XCTAssertEqual(Presentation.batterySymbol(percent: 87, charging: false), "battery.75percent")
        XCTAssertEqual(Presentation.batterySymbol(percent: 50, charging: false), "battery.50percent")
        XCTAssertEqual(Presentation.batterySymbol(percent: 20, charging: false), "battery.25percent")
        XCTAssertEqual(Presentation.batterySymbol(percent: 12, charging: false), "battery.0percent")
        XCTAssertEqual(Presentation.batterySymbol(percent: 5, charging: true), "battery.100percent.bolt")
    }

    func testLowOnlyWhenNotCharging() {
        XCTAssertTrue(Presentation.isLow(Device(name: "x", percent: 20)))
        XCTAssertFalse(Presentation.isLow(Device(name: "x", percent: 21)))
        XCTAssertFalse(Presentation.isLow(Device(name: "x", percent: 5, charging: true)))
        XCTAssertFalse(Presentation.isLow(Device(name: "x", percent: nil)))
    }

    func testStatusText() {
        XCTAssertEqual(Presentation.statusText(for: Device(name: "x", percent: 50)), "")
        XCTAssertEqual(Presentation.statusText(for: Device(name: "x", percent: 50, charging: true)), "Charging")
        XCTAssertEqual(Presentation.statusText(for: Device(name: "x", percent: 100, charging: true)), "Fully charged")
        XCTAssertEqual(
            Presentation.statusText(for: Device(name: "x", percent: 30, charging: true, lowPower: true)),
            "Charging · Low Power Mode"
        )
        XCTAssertEqual(Presentation.statusText(for: Device(name: "x", percent: 50, online: false)), "Offline")
        XCTAssertEqual(Presentation.statusText(for: Device(name: "x", percent: nil, online: false)), "Offline")
        XCTAssertEqual(Presentation.statusText(for: Device(name: "x", percent: nil)), "No battery information")
    }

    func testStatusTextForAirPods() {
        let even = Device(name: "x", percent: 100, online: false, source: .bluetoothLastKnown,
                          left: 100, right: 100, caseLevel: 100)
        XCTAssertEqual(Presentation.statusText(for: even), "Last known level")
        let uneven = Device(name: "x", percent: 70, online: false, source: .bluetoothLastKnown,
                            left: 70, right: 85, caseLevel: 100)
        XCTAssertEqual(Presentation.statusText(for: uneven), "Last known level · L 70% · R 85%")
        XCTAssertEqual(
            Presentation.detailText(for: Device(name: "x", model: "AirPods Pro", percent: 70, online: false,
                                                source: .bluetoothLastKnown, left: 70, right: 85, caseLevel: 100)),
            "AirPods Pro\nLeft 70%, Right 85%, Case 100%\nThe level this Mac saw the last time the device was connected. It may be out of date."
        )
        XCTAssertEqual(Presentation.detailText(for: Device(name: "x", model: "iPhone 16 Pro", percent: 5)), "iPhone 16 Pro")
        // Accessory models come from the engine in Swedish, so they are left out.
        XCTAssertEqual(
            Presentation.detailText(for: Device(name: "x", model: "Mus", percent: 5, source: .bluetooth)),
            "Read from this Mac’s Bluetooth connection."
        )
        let live = Device(name: "x", percent: 70, source: .bluetooth, left: 70, right: 85)
        XCTAssertEqual(Presentation.statusText(for: live), "L 70% · R 85%")
    }

    func testAccessibilityLabel() {
        let device = Device(name: "Anna’s iPhone", percent: 61, lowPower: true)
        XCTAssertEqual(Presentation.accessibilityLabel(for: device), "Anna’s iPhone, 61 percent, Low Power Mode")
        XCTAssertEqual(Presentation.accessibilityLabel(for: Device(name: "Old", percent: nil, online: false)), "Old, Offline")
    }

    func testLowestSkipsStaleOfflineAndFamilyReadings() {
        let devices = [
            Device(name: "family", percent: 1, family: true),
            Device(name: "stale", percent: 2, source: .bluetoothLastKnown),
            Device(name: "offline", percent: 3, online: false),
            Device(name: "unknown", percent: nil),
            Device(name: "mouse", percent: 44, source: .bluetooth),
            Device(name: "phone", percent: 80),
        ]
        XCTAssertEqual(Presentation.lowest(in: devices)?.name, "mouse")
        XCTAssertNil(Presentation.lowest(in: []))
    }

    func testUpdatedText() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func text(_ seconds: TimeInterval) -> String {
            Presentation.updatedText(since: now.addingTimeInterval(-seconds), now: now)
        }
        XCTAssertEqual(text(0), "Updated just now")
        XCTAssertEqual(text(59), "Updated just now")
        XCTAssertEqual(text(60), "Updated 1 min ago")
        XCTAssertEqual(text(59 * 60), "Updated 59 min ago")
        XCTAssertEqual(text(3600), "Updated 1 hour ago")
        XCTAssertEqual(text(3 * 3600), "Updated 3 hours ago")
        XCTAssertEqual(text(-30), "Updated just now")
    }
}

/// Writes a small shell script that stands in for the engine.
func makeScript(_ body: String) throws -> EngineCommand {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("batteri-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("engine")
    try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return EngineCommand(executable: url)
}

final class EngineTests: XCTestCase {
    func testReturnsDevicesAndPassesArguments() async throws {
        let command = try makeScript(#"""
        if [ "$1" = "--json" ] && [ "$2" = "--familj" ]; then
          echo '[{"name": "Family run", "percent": 5}]'
        else
          echo '[{"name": "Own run", "percent": 7}]'
        fi
        """#)
        let engine = Engine(command: command)
        let own = try await engine.devices(includeFamily: false)
        XCTAssertEqual(own.map(\.name), ["Own run"])
        let family = try await engine.devices(includeFamily: true)
        XCTAssertEqual(family.map(\.name), ["Family run"])
    }

    func testExitStatusThreeMeansSignIn() async throws {
        let engine = Engine(command: try makeScript("echo 'sign in first' >&2; exit 3"))
        do {
            _ = try await engine.devices(includeFamily: false)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? EngineError, .needsLogin)
        }
    }

    func testOtherFailuresCarryTheMessage() async throws {
        let engine = Engine(command: try makeScript("echo 'no network' >&2; exit 1"))
        do {
            _ = try await engine.devices(includeFamily: false)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? EngineError, .failed("no network"))
        }
    }

    func testGarbageOutputIsAnError() async throws {
        let engine = Engine(command: try makeScript("echo 'not json'"))
        do {
            _ = try await engine.devices(includeFamily: false)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? EngineError, .failed("Unexpected response from the engine."))
        }
    }

    func testLargeOutputDoesNotStall() async throws {
        // More than a pipe buffer on both streams.
        let engine = Engine(command: try makeScript(#"""
        i=0; while [ $i -lt 4000 ]; do echo "noise noise noise noise noise noise" >&2; i=$((i+1)); done
        printf '['
        i=0; while [ $i -lt 3000 ]; do printf '{"name": "device %s", "percent": 50},' $i; i=$((i+1)); done
        printf '{"name": "last", "percent": 1}]'
        """#))
        let devices = try await engine.devices(includeFamily: false)
        XCTAssertEqual(devices.count, 3001)
    }

    func testLocatePrefersBundledEngineThenInstalledCommand() {
        let resources = URL(fileURLWithPath: "/App/Contents/Resources")
        let home = URL(fileURLWithPath: "/Users/someone")
        let bundled = "/App/Contents/Resources/engine/python/bin/python3"
        let installed = "/Users/someone/.local/bin/batteri"

        let both = Engine.locate(resourceURL: resources, environment: [:], homeDirectory: home) {
            [bundled, installed].contains($0)
        }
        XCTAssertEqual(both?.executable.path, bundled)
        XCTAssertEqual(both?.arguments, ["-I", "-B", "-m", "batteri"])

        let onlyInstalled = Engine.locate(resourceURL: resources, environment: [:], homeDirectory: home) {
            $0 == installed
        }
        XCTAssertEqual(onlyInstalled, EngineCommand(executable: URL(fileURLWithPath: installed)))

        let override = Engine.locate(
            resourceURL: resources, environment: ["BATTERI_ENGINE": "/custom/engine"], homeDirectory: home
        ) { _ in true }
        XCTAssertEqual(override?.executable.path, "/custom/engine")

        XCTAssertNil(Engine.locate(resourceURL: resources, environment: [:], homeDirectory: home) { _ in false })
    }
}

final class LoginSessionTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(LoginSession.parse(#"{"state": "ok"}"#), .signedIn)
        XCTAssertEqual(LoginSession.parse(#"{"state": "needs_code"}"#), .needsCode(retry: false))
        XCTAssertEqual(LoginSession.parse(#"{"state": "needs_code", "code": "bad_code"}"#), .needsCode(retry: true))
        XCTAssertEqual(LoginSession.parse(#"{"state": "error", "code": "bad_credentials"}"#), .failed(.badCredentials))
        XCTAssertEqual(LoginSession.parse(#"{"state": "error", "code": "security_key"}"#), .failed(.securityKey))
        XCTAssertEqual(LoginSession.parse(#"{"state": "error", "code": "unsupported_2sa"}"#), .failed(.unsupportedVerification))
        XCTAssertEqual(LoginSession.parse(#"{"state": "error", "code": "failed", "message": "boom"}"#), .failed(.other("boom")))
        XCTAssertEqual(LoginSession.parse("nonsense"), .failed(.engine))
    }

    /// A stand-in engine that accepts the password "right" and the code 123456.
    private func fakeEngine() throws -> EngineCommand {
        try makeScript(#"""
        [ "$1" = "login" ] && [ "$2" = "--stdio" ] || exit 9
        read -r line
        case "$line" in
          *'"password":"right"'*) echo '{"state": "needs_code"}' ;;
          *) echo '{"state": "error", "code": "bad_credentials"}'; exit 1 ;;
        esac
        while read -r line; do
          case "$line" in
            *'"code":"123456"'*) echo '{"state": "ok"}'; exit 0 ;;
            *) echo '{"state": "needs_code", "code": "bad_code"}' ;;
          esac
        done
        """#)
    }

    func testFullConversationWithOneWrongCode() async throws {
        let session = LoginSession(command: try fakeEngine())
        let first = await session.start(appleID: "anna@example.com", password: "right")
        XCTAssertEqual(first, .needsCode(retry: false))
        let wrong = await session.submit(code: "000000")
        XCTAssertEqual(wrong, .needsCode(retry: true))
        let right = await session.submit(code: "123456")
        XCTAssertEqual(right, .signedIn)
    }

    func testWrongPassword() async throws {
        let session = LoginSession(command: try fakeEngine())
        let reply = await session.start(appleID: "anna@example.com", password: "wrong")
        XCTAssertEqual(reply, .failed(.badCredentials))
        // The conversation is over; a code now has nowhere to go.
        let late = await session.submit(code: "123456")
        XCTAssertEqual(late, .failed(.engine))
    }

    func testEngineThatDiesOrIsMissing() async throws {
        let dies = LoginSession(command: try makeScript("exit 1"))
        let died = await dies.start(appleID: "a@example.com", password: "x")
        XCTAssertEqual(died, .failed(.engine))

        let missing = LoginSession(command: EngineCommand(executable: URL(fileURLWithPath: "/nonexistent/engine")))
        let reply = await missing.start(appleID: "a@example.com", password: "x")
        XCTAssertEqual(reply, .failed(.engine))
    }

    func testCancelEndsTheConversation() async throws {
        let session = LoginSession(command: try fakeEngine())
        _ = await session.start(appleID: "anna@example.com", password: "right")
        await session.cancel()
        let reply = await session.submit(code: "123456")
        XCTAssertEqual(reply, .failed(.engine))
    }
}

final class AccountTests: XCTestCase {
    private func makeAccount() throws -> Account {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("batteri-account-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return Account(directory: directory)
    }

    func testReadsAppleIDWrittenByTheEngine() throws {
        let account = try makeAccount()
        XCTAssertNil(account.appleID)
        try "apple_id = \"anna@example.com\"\n".write(
            to: account.directory.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8
        )
        XCTAssertEqual(account.appleID, "anna@example.com")
    }

    func testSignOutRemovesSessionButNothingElse() throws {
        let account = try makeAccount()
        let manager = FileManager.default
        let session = account.directory.appendingPathComponent("session")
        try manager.createDirectory(at: session, withIntermediateDirectories: true)
        try "cookie".write(to: session.appendingPathComponent("cookies"), atomically: true, encoding: .utf8)
        for name in ["config.toml", "state.json", "unrelated.txt"] {
            try "x".write(to: account.directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try account.signOut()
        let left = try manager.contentsOfDirectory(atPath: account.directory.path)
        XCTAssertEqual(left, ["unrelated.txt"])
        // Signing out twice is harmless.
        XCTAssertNoThrow(try account.signOut())
    }

    func testStandardLocationHonoursOverride() {
        let home = URL(fileURLWithPath: "/Users/someone")
        XCTAssertEqual(Account.standard(environment: [:], homeDirectory: home).directory.path,
                       "/Users/someone/.config/batteri")
        XCTAssertEqual(Account.standard(environment: ["BATTERI_HOME": "/tmp/elsewhere"], homeDirectory: home).directory.path,
                       "/tmp/elsewhere")
    }
}

@MainActor
final class BatteryStoreTests: XCTestCase {
    /// A fetch whose result the test can change between refreshes.
    final class Source: @unchecked Sendable {
        var result: Result<[Device], Error> = .success([])
        var calls: [Bool] = []
        func fetch(_ includeFamily: Bool) async throws -> [Device] {
            calls.append(includeFamily)
            return try result.get()
        }
    }

    func testSuccessfulRefresh() async {
        let source = Source()
        source.result = .success([Device(name: "phone", percent: 80)])
        let date = Date(timeIntervalSince1970: 500)
        let store = BatteryStore(fetch: source.fetch, now: { date })
        XCTAssertEqual(store.phase, .loading)
        await store.refresh(includeFamily: true)
        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.devices.map(\.name), ["phone"])
        XCTAssertEqual(store.updatedAt, date)
        XCTAssertEqual(source.calls, [true])
        XCTAssertFalse(store.isRefreshing)
    }

    func testNeedsLoginClearsDevices() async {
        let source = Source()
        source.result = .success([Device(name: "phone", percent: 80)])
        let store = BatteryStore(fetch: source.fetch)
        await store.refresh(includeFamily: false)
        source.result = .failure(EngineError.needsLogin)
        await store.refresh(includeFamily: false)
        XCTAssertEqual(store.phase, .needsLogin)
        XCTAssertTrue(store.devices.isEmpty)
        XCTAssertNil(store.updatedAt)
    }

    func testFailureKeepsPreviousDevicesAndRecovers() async {
        let source = Source()
        source.result = .success([Device(name: "phone", percent: 80)])
        let store = BatteryStore(fetch: source.fetch)
        await store.refresh(includeFamily: false)
        source.result = .failure(EngineError.failed("offline"))
        await store.refresh(includeFamily: false)
        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.devices.map(\.name), ["phone"])
        XCTAssertEqual(store.lastError, "offline")
        source.result = .success([])
        await store.refresh(includeFamily: false)
        XCTAssertNil(store.lastError)
    }

    func testFailureOnFirstRefreshLeavesLoading() async {
        let source = Source()
        source.result = .failure(EngineError.failed("offline"))
        let store = BatteryStore(fetch: source.fetch)
        await store.refresh(includeFamily: false)
        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.lastError, "offline")
        XCTAssertTrue(store.devices.isEmpty)
    }

    func testMissingEngine() async {
        let source = Source()
        source.result = .failure(EngineError.notFound)
        let store = BatteryStore(fetch: source.fetch)
        await store.refresh(includeFamily: false)
        XCTAssertEqual(store.phase, .engineMissing)
    }

    func testStalenessAndReset() async {
        let source = Source()
        source.result = .success([Device(name: "phone", percent: 80)])
        var clock = Date(timeIntervalSince1970: 0)
        let store = BatteryStore(fetch: source.fetch, now: { clock })
        XCTAssertTrue(store.isStale(after: 60))
        await store.refresh(includeFamily: false)
        XCTAssertFalse(store.isStale(after: 60))
        clock = Date(timeIntervalSince1970: 61)
        XCTAssertTrue(store.isStale(after: 60))
        store.reset()
        XCTAssertEqual(store.phase, .needsLogin)
        XCTAssertTrue(store.devices.isEmpty)
    }
}
