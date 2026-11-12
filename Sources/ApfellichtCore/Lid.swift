import Foundation
import IOKit

/// Der Deckel, direkt aus `IOPMrootDomain` gelesen (`AppleClamshellState`).
public enum Lid {
    public static var isClosed: Bool? {
        let root = IORegistryEntryFromPath(kIOMainPortDefault, "IOPower:/IOPowerConnection/IOPMrootDomain")
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (value as? Bool) ?? (value as? NSNumber)?.boolValue
    }
}
