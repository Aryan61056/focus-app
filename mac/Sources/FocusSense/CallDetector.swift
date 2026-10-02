import AppKit
import CoreAudio
import CoreMediaIO

/// True while any app is using the camera or the default microphone. Asks the system only whether a device is running somewhere:
/// no audio or video is opened, so no permission is needed and nothing is captured.
public enum CallDetector {
    static let conferencingApps: Set<String> = ["zoom.us", "zoom", "microsoft teams", "microsoft teams (work or school)", "teams", "facetime", "webex", "cisco webex meetings",
                                                 "discord", "skype", "slack", "around", "whereby", "gather"]

    /// A camera in use counts as a call. A microphone alone does not, because dictation, voice memos or an app that simply holds the
    /// microphone open would pause the session all day (one was holding it on the dev Mac). The microphone counts only with a
    /// conferencing app in front.
    public static func inCall(frontApp: String = NSWorkspace.shared.frontmostApplication?.localizedName ?? "") -> Bool {
        cameraRunning() || (conferencingApps.contains(frontApp.lowercased()) && microphoneRunning())
    }

    static func microphoneRunning() -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var dev = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr, dev != 0 else { return false }
        var run: UInt32 = 0; size = UInt32(MemoryLayout<UInt32>.size)
        var r = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(dev, &r, 0, nil, &size, &run) == noErr && run != 0
    }

    static func cameraRunning() -> Bool {
        var addr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal), mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == 0, size > 0 else { return false }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &ids) == 0 else { return false }
        for d in ids {
            var run: UInt32 = 0; var got: UInt32 = 0
            var p = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal), mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            if CMIOObjectGetPropertyData(d, &p, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &run) == 0, run != 0 { return true }
        }
        return false
    }
}
