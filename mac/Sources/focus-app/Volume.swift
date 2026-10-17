import CoreAudio
import FocusUI

/// The Mac's output volume through CoreAudio's virtual main volume of the default output device. Reading and setting need no permission.
/// If the device cannot be set (some HDMI and display speakers), `write` says so and Focus leaves the volume alone.
final class MacVolume: SystemVolume {
    /// 'vmvc', the virtual main volume (kAudioHardwareServiceDeviceProperty_VirtualMainVolume, which the SDK marks deprecated by name only).
    private static let virtualMainVolume: AudioObjectPropertySelector = 0x766D7663

    private func device() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var dev = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr, dev != 0 else { return nil }
        return dev
    }

    private var address: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: Self.virtualMainVolume, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    func read() -> Float? {
        guard let dev = device() else { return nil }
        var addr = address, v = Float32(0), size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectHasProperty(dev, &addr), AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr else { return nil }
        return v
    }

    func write(_ value: Float) -> Bool {
        guard let dev = device() else { return false }
        var addr = address, settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(dev, &addr), AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr, settable.boolValue else { return false }
        var v = Float32(max(0, min(1, value)))
        return AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
    }
}
