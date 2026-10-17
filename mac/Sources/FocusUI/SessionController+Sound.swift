import Foundation

/// Easing the sound down while you are off task on a video site (SoundEase.swift). One second at a time, from the tick.
extension SessionController {
    /// True when the volume should be down now: you switched it on, a real nudge is showing ("interrupted", after sustained agreement), the
    /// window is a video site, and it is not a practice session. In a call the session is paused, so this is false there.
    var soundShouldEase: Bool {
        guard prefs.easeSound, isActive, !shadow, presence.state == "interrupted", let w = currentWindow else { return false }
        return SoundEase.looksLikeVideo(w)
    }

    func tickSound() {
        guard let volume = systemVolume else { return }
        guard let now = volume.read() else { return }
        // You moved the volume yourself during this nudge: it stays yours until the nudge is over.
        if soundLetGo { if !soundShouldEase { soundLetGo = false }; return }
        if var s = easedSound {
            if abs(now - s.lastSet) > SoundEase.tolerance { easedSound = nil; soundLetGo = true; onSoundSaved?(nil); return }
            let goal = soundShouldEase ? s.original * SoundEase.fraction : s.original
            let next = SoundEase.step(from: now, to: goal, rate: soundShouldEase ? SoundEase.downRate : SoundEase.upRate)
            if next != now { if volume.write(next) { s.lastSet = next } else { easedSound = nil; onSoundSaved?(nil); return } }
            easedSound = s
            if !soundShouldEase, next == s.original { easedSound = nil; onSoundSaved?(nil) }
            else { onSoundSaved?(SoundEase.Saved(original: s.original, lowered: s.lastSet)) }   // where it is now, so a crash can tell it is untouched
            return
        }
        guard soundShouldEase, now >= SoundEase.minimumOriginal else { return }
        let first = SoundEase.step(from: now, to: now * SoundEase.fraction, rate: SoundEase.downRate)
        guard volume.write(first) else { return }
        easedSound = EasedSound(original: now, lastSet: first)
        onSoundSaved?(SoundEase.Saved(original: now, lowered: first))
    }

    /// Gives the volume back now (session over, quitting, paused): to where it was, unless you changed it since.
    public func restoreSound() {
        guard let s = easedSound, let volume = systemVolume else { easedSound = nil; return }
        if let now = volume.read(), abs(now - s.lastSet) <= SoundEase.tolerance { _ = volume.write(s.original) }
        easedSound = nil; soundLetGo = false
        onSoundSaved?(nil)
    }

    /// At launch, after a crash or a force quit that left the volume lowered.
    public func recoverSound(saved: SoundEase.Saved?) {
        guard let volume = systemVolume, let back = SoundEase.recover(saved: saved, current: volume.read()) else { onSoundSaved?(nil); return }
        _ = volume.write(back)
        onSoundSaved?(nil)
    }
}

struct EasedSound: Equatable { var original: Float, lastSet: Float }
