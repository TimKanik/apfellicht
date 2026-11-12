import CoreGraphics
import Foundation

/// Zugriff auf `corebrightnessd` über das private Framework CoreBrightness.
///
/// Alles hier ist private, undokumentierte API (gemessen auf Mac17,13 mit macOS 27.2). Sie wird
/// dynamisch geladen; `init` liefert `nil`, wenn sie fehlt.
@MainActor
public final class BrightnessService {
    private typealias CopyFn = @convention(c) (AnyObject, Selector, NSString) -> Unmanaged<AnyObject>?
    private typealias SetFn = @convention(c) (AnyObject, Selector, AnyObject, NSString) -> Bool
    private typealias SetIDFn = @convention(c) (AnyObject, Selector, AnyObject, NSString, UInt64) -> Bool
    private typealias KbdGetFn = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias KbdBoolFn = @convention(c) (AnyObject, Selector, UInt64) -> Bool
    private typealias KbdSetFn = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
    private typealias KbdAutoFn = @convention(c) (AnyObject, Selector, Bool, UInt64) -> Bool
    private typealias GetDisplayBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetDisplayBrightness = @convention(c) (UInt32, Float) -> Int32

    private let client: NSObject
    private let keyboardClient: NSObject?
    private let copySel = NSSelectorFromString("copyPropertyForKey:")
    private let setSel = NSSelectorFromString("setProperty:forKey:")
    private let setKbdSel = NSSelectorFromString("setProperty:withKey:keyboardID:")
    private let setDispSel = NSSelectorFromString("setProperty:withKey:andDisplay:")
    private let copyFn: CopyFn
    private let setFn: SetFn
    private let setKbdFn: SetIDFn?
    private let setDispFn: SetIDFn?
    private let getDisplayBrightness: GetDisplayBrightness?
    private let setDisplayBrightness: SetDisplayBrightness?

    /// Die Hintergrundbeleuchtungen der eingebauten Tastatur.
    public let keyboardIDs: [UInt64]

    public init?() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
              let type = NSClassFromString("BrightnessSystemClient") as? NSObject.Type,
              type.instancesRespond(to: copySel), type.instancesRespond(to: setSel)
        else { return nil }
        client = type.init()
        copyFn = unsafeBitCast(client.method(for: copySel), to: CopyFn.self)
        setFn = unsafeBitCast(client.method(for: setSel), to: SetFn.self)
        setKbdFn = type.instancesRespond(to: setKbdSel) ? unsafeBitCast(client.method(for: setKbdSel), to: SetIDFn.self) : nil
        setDispFn = type.instancesRespond(to: setDispSel) ? unsafeBitCast(client.method(for: setDispSel), to: SetIDFn.self) : nil

        if let kType = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
            let k = kType.init()
            keyboardClient = k
            let ids = k.perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?.takeRetainedValue() as? [NSNumber] ?? []
            let builtInSel = NSSelectorFromString("isKeyboardBuiltIn:")
            let builtIn = k.responds(to: builtInSel) ? unsafeBitCast(k.method(for: builtInSel), to: KbdBoolFn.self) : nil
            keyboardIDs = ids.map(\.uint64Value).filter { builtIn?(k, builtInSel, $0) ?? true }
        } else {
            keyboardClient = nil
            keyboardIDs = []
        }

        if dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) != nil {
            let h = dlopen(nil, RTLD_LAZY)
            getDisplayBrightness = dlsym(h, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetDisplayBrightness.self) }
            setDisplayBrightness = dlsym(h, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetDisplayBrightness.self) }
        } else {
            getDisplayBrightness = nil
            setDisplayBrightness = nil
        }
    }

    // MARK: corebrightnessd

    public func value(_ key: String) -> Any? {
        copyFn(client, copySel, key as NSString)?.takeRetainedValue()
    }

    @discardableResult
    public func set(_ value: Any, _ key: String) -> Bool {
        setFn(client, setSel, value as AnyObject, key as NSString)
    }

    /// Schickt einen Key nur an die Tastaturbeleuchtung.
    public func setKeyboards(_ value: Any, _ key: String) {
        guard let setKbdFn else { return }
        for id in keyboardIDs { _ = setKbdFn(client, setKbdSel, value as AnyObject, key as NSString, id) }
    }

    /// Schickt einen Key an die Module der Displays (Helligkeit, True Tone), nicht ans Logo.
    public func setDisplays(_ value: Any, _ key: String, onlyExternal: Bool) {
        guard let setDispFn,
              let list = self.value("CBDisplayList") as? [String: Any],
              let ids = list["CBDisplayDeviceIDs"] as? [NSNumber]
        else { return }
        for id in ids where !onlyExternal || CGDisplayIsBuiltin(id.uint32Value) == 0 {
            _ = setDispFn(client, setDispSel, value as AnyObject, key as NSString, id.uint64Value)
        }
    }

    public var logoState: [String: Any] { value("LEPWMState") as? [String: Any] ?? [:] }

    public func logoState(_ key: String) -> Double? {
        (logoState[key] as? NSNumber)?.doubleValue
    }

    /// Lässt `corebrightnessd` die Logo-Helligkeit neu berechnen, ohne dass das Display sich ändert:
    /// Die Displayhelligkeit wird auf genau den Wert gesetzt, den sie schon hat.
    public func nudgeRecompute() {
        guard let getDisplayBrightness, let setDisplayBrightness else { return }
        let display = builtInDisplayID ?? CGMainDisplayID()
        var b: Float = 0
        guard getDisplayBrightness(display, &b) == 0 else { return }
        _ = setDisplayBrightness(display, b)
    }

    public var builtInDisplayID: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    public var hasExternalDisplay: Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }

    // MARK: Tastatur

    /// Helligkeit der eingebauten Tastatur, 0–1 (Apples Regler).
    public var keyboardBrightness: Float? {
        guard let k = keyboardClient, let id = keyboardIDs.first else { return nil }
        let sel = NSSelectorFromString("brightnessForKeyboard:")
        guard k.responds(to: sel) else { return nil }
        return unsafeBitCast(k.method(for: sel), to: KbdGetFn.self)(k, sel, id)
    }

    public func setKeyboardBrightness(_ value: Float) {
        guard let k = keyboardClient else { return }
        let sel = NSSelectorFromString("setBrightness:forKeyboard:")
        guard k.responds(to: sel) else { return }
        let fn = unsafeBitCast(k.method(for: sel), to: KbdSetFn.self)
        for id in keyboardIDs { _ = fn(k, sel, max(0, min(1, value)), id) }
    }

    /// Schaltet Apples Automatik nach Umgebungslicht für die Tastatur ab, damit der Wert fest bleibt.
    public func disableKeyboardAutoBrightness() {
        guard let k = keyboardClient else { return }
        let sel = NSSelectorFromString("enableAutoBrightness:forKeyboard:")
        guard k.responds(to: sel) else { return }
        let fn = unsafeBitCast(k.method(for: sel), to: KbdAutoFn.self)
        for id in keyboardIDs { _ = fn(k, sel, false, id) }
    }
}
