import Foundation

/// Verbindung zwischen der Kontrollzentrum-Erweiterung und der laufenden App: ein Mach-Port, den die
/// App anbietet. Die Erweiterung ist sandboxed und darf nur diesen einen Namen erreichen.
///
/// Wird auch in die Erweiterung kompiliert, nutzt also nichts sonst aus ApfellichtCore.
public enum ControlLink {
    public static let logoKind = "de.timkanik.apfellicht.logo"
    public static let keyboardKind = "de.timkanik.apfellicht.keyboard"
    public static let extensionSuffix = ".Controls"

    public static func portName(forApp bundleID: String) -> String { bundleID + ".control" }

    public enum Request: Int32, Sendable {
        case state = 1
        case logoOn = 2
        case logoOff = 3
        case keyboardOn = 4
        case keyboardOff = 5
    }

    public struct State: Equatable, Sendable {
        public var logoOn: Bool
        public var keyboardOn: Bool

        public init(logoOn: Bool, keyboardOn: Bool) {
            self.logoOn = logoOn
            self.keyboardOn = keyboardOn
        }

        public init?(data: Data) {
            guard data.count == 2 else { return nil }
            let b = Array(data)
            self.init(logoOn: b[0] != 0, keyboardOn: b[1] != 0)
        }

        public var data: Data { Data([logoOn ? 1 : 0, keyboardOn ? 1 : 0]) }
    }

    public enum Outcome: Equatable, Sendable {
        case answered(State)
        case notRunning
        case noAnswer
    }

    private static let lock = NSLock()

    public static func send(_ request: Request, toApp bundleID: String, timeout: Double = 1) -> Outcome {
        lock.lock()
        defer { lock.unlock() }
        guard let port = CFMessagePortCreateRemote(nil, portName(forApp: bundleID) as CFString) else { return .notRunning }
        defer { CFMessagePortInvalidate(port) }
        var reply: Unmanaged<CFData>?
        let result = CFMessagePortSendRequest(port, request.rawValue, nil, timeout, timeout,
                                              CFRunLoopMode.defaultMode.rawValue, &reply)
        let data = reply?.takeRetainedValue() as Data?
        switch result {
        case kCFMessagePortSuccess:
            return data.flatMap(State.init(data:)).map(Outcome.answered) ?? .noAnswer
        case kCFMessagePortIsInvalid, kCFMessagePortBecameInvalidError:
            return .notRunning
        default:
            return .noAnswer
        }
    }
}

/// Beantwortet die Anfragen der Erweiterung in der App, auf dem Main-Runloop in allen Modi.
@MainActor
public final class ControlLinkServer {
    public typealias Handler = @MainActor (ControlLink.Request) -> ControlLink.State

    private let handler: Handler
    private var port: CFMessagePort?

    public init?(appBundleID: String, handler: @escaping Handler) {
        self.handler = handler
        var context = CFMessagePortContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        var shouldFree: DarwinBoolean = false
        guard let port = CFMessagePortCreateLocal(nil, ControlLink.portName(forApp: appBundleID) as CFString, { _, id, _, info in
            guard let info, let request = ControlLink.Request(rawValue: id) else { return nil }
            let server = Unmanaged<ControlLinkServer>.fromOpaque(info).takeUnretainedValue()
            let state = MainActor.assumeIsolated { server.handler(request) }
            return Unmanaged.passRetained(state.data as CFData)
        }, &context, &shouldFree) else { return nil }
        guard !shouldFree.boolValue else { return nil }
        self.port = port
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMessagePortCreateRunLoopSource(nil, port, 0), .commonModes)
    }

    public func invalidate() {
        if let port { CFMessagePortInvalidate(port) }
        port = nil
    }
}
