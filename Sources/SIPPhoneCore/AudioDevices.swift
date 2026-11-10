import Foundation
import Combine
import CoreAudio

// MARK: - CoreAudio HAL

struct AudioDevice: Identifiable, Hashable {
    let id: UInt32
    let name: String
    let hasInput: Bool
    let hasOutput: Bool
    let isDefaultInput: Bool
    let isDefaultOutput: Bool
}

enum AudioDeviceLister {

    static func allDevices() -> [AudioDevice] {
        var addr = propAddr(kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr,
              size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }

        let defIn = defaultDeviceID(input: true)
        let defOut = defaultDeviceID(input: false)

        return ids.compactMap { id in
            let name = deviceName(id)
            let hasInput = channelCount(id, scope: kAudioDevicePropertyScopeInput) > 0
            let hasOutput = channelCount(id, scope: kAudioDevicePropertyScopeOutput) > 0
            guard !name.isEmpty, hasInput || hasOutput, name != "Dummy Output" else { return nil }
            return AudioDevice(
                id: id,
                name: name,
                hasInput: hasInput,
                hasOutput: hasOutput,
                isDefaultInput: id == defIn,
                isDefaultOutput: id == defOut
            )
        }
    }

    static func defaultDeviceID(input: Bool) -> AudioDeviceID {
        let sel: AudioObjectPropertySelector = input
            ? kAudioHardwarePropertyDefaultInputDevice
            : kAudioHardwarePropertyDefaultOutputDevice
        var addr = propAddr(sel, kAudioObjectPropertyScopeGlobal)
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    @discardableResult
    static func setDefaultDevice(_ id: AudioDeviceID, input: Bool) -> Bool {
        let sel: AudioObjectPropertySelector = input
            ? kAudioHardwarePropertyDefaultInputDevice
            : kAudioHardwarePropertyDefaultOutputDevice
        var addr = propAddr(sel, kAudioObjectPropertyScopeGlobal)
        var devID = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &devID) == noErr
    }

    // MARK: Internals

    private static func deviceName(_ id: AudioDeviceID) -> String {
        var name = [CChar](repeating: 0, count: 256)
        var size = UInt32(256)
        var addr = propAddr(kAudioDevicePropertyDeviceName, kAudioObjectPropertyScopeGlobal)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr else { return "" }
        name[Int(max(0, min(255, size - 1)))] = 0
        return String(cString: name)
    }

    private static func channelCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var addr = propAddr(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        guard let list = malloc(Int(size))?.assumingMemoryBound(to: AudioBufferList.self) else { return 0 }
        defer { free(list) }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, list) == noErr else { return 0 }
        var channels = 0
        for buffer in UnsafeMutableAudioBufferListPointer(list) {
            channels += Int(buffer.mNumberChannels)
        }
        return channels
    }

    private static func propAddr(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}

// MARK: - Observable manager

@MainActor
public final class DeviceManager: ObservableObject {
    @Published private(set) var devices: [AudioDevice] = []

    private var cancellable: AnyCancellable?

    public init() {
        refresh()
        cancellable = Timer.publish(every: 5, on: .main, in: .default).autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
    }

    var inputDevices: [AudioDevice] { devices.filter(\.hasInput) }
    var outputDevices: [AudioDevice] { devices.filter(\.hasOutput) }
    var selectedInput: AudioDevice? { devices.first(where: \.isDefaultInput) }
    var selectedOutput: AudioDevice? { devices.first(where: \.isDefaultOutput) }

    func selectInput(_ device: AudioDevice) {
        AudioDeviceLister.setDefaultDevice(device.id, input: true)
        refresh()
    }

    func selectOutput(_ device: AudioDevice) {
        AudioDeviceLister.setDefaultDevice(device.id, input: false)
        refresh()
    }

    func refresh() {
        devices = AudioDeviceLister.allDevices()
    }
}
