import Foundation
import IOKit.ps

/// The Mac's own battery, for the notch's Battery widget. Read from the system's power source list; nothing leaves the Mac and
/// nothing is kept. A desktop Mac has no battery, so `read()` is nil there.
enum BatteryReader {
    struct Reading { var percent: Int; var charging: Bool; var pluggedIn: Bool }

    static func read() -> Reading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let now = d[kIOPSCurrentCapacityKey] as? Int, let full = d[kIOPSMaxCapacityKey] as? Int, full > 0 else { continue }
            let state = d[kIOPSPowerSourceStateKey] as? String
            return Reading(percent: min(100, Int((Double(now) / Double(full) * 100).rounded())),
                           charging: (d[kIOPSIsChargingKey] as? Bool) ?? false,
                           pluggedIn: state == kIOPSACPowerValue)
        }
        return nil
    }
}
