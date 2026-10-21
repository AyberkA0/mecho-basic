import AVFoundation
import ApplicationServices
import Cocoa
import ServiceManagement

// MARK: - Ses: kaydet + yankılı çal

final class EchoEngine {
    enum State { case idle, recording, playing }

    var onStateChange: ((State) -> Void)?
    private(set) var state: State = .idle {
        didSet { DispatchQueue.main.async { self.onStateChange?(self.state) } }
    }

    private var recorder: AVAudioEngine?
    private var player: AVAudioEngine?
    private var samples: [Float] = []
    private var sampleRate: Double = 48_000
    private let lock = NSLock()
    private var playbackID = 0

    func startRecording() {
        guard state != .recording else { return }
        stopPlayback()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            NSLog("MechoBasic: mikrofon girişi bulunamadı")
            return
        }
        sampleRate = format.sampleRate
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        do {
            try engine.start()
            recorder = engine
            state = .recording
        } catch {
            NSLog("MechoBasic: kayıt başlatılamadı: \(error)")
            input.removeTap(onBus: 0)
        }
    }

    func stopRecordingAndPlay() {
        guard state == .recording, let engine = recorder else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        recorder = nil

        lock.lock(); let recorded = samples; lock.unlock()
        guard recorded.count > Int(sampleRate * 0.1) else {
            state = .idle
            return
        }
        play(recorded)
    }

    // Çok kanallı girişleri mono'ya indir.
    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        var mono = [Float](repeating: 0, count: frames)
        for ch in 0..<channels {
            let p = data[ch]
            for i in 0..<frames { mono[i] += p[i] }
        }
        if channels > 1 {
            let scale = 1 / Float(channels)
            for i in 0..<frames { mono[i] *= scale }
        }
        lock.lock(); samples.append(contentsOf: mono); lock.unlock()
    }

    private func play(_ recorded: [Float]) {
        guard let monoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: AVAudioFrameCount(recorded.count))
        else { state = .idle; return }
        buffer.frameLength = AVAudioFrameCount(recorded.count)
        recorded.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: recorded.count)
        }

        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        let upmix = AVAudioMixerNode()
        let delay = AVAudioUnitDelay()
        let reverb = AVAudioUnitReverb()

        delay.delayTime = 0.28
        delay.feedback = 45
        delay.wetDryMix = 35
        delay.lowPassCutoff = 7_000
        reverb.loadFactoryPreset(.largeHall)
        reverb.wetDryMix = 30

        [node, upmix, delay, reverb].forEach { engine.attach($0) }
        engine.connect(node, to: upmix, format: monoFormat)
        engine.connect(upmix, to: delay, format: stereoFormat)
        engine.connect(delay, to: reverb, format: stereoFormat)
        engine.connect(reverb, to: engine.mainMixerNode, format: stereoFormat)

        do {
            try engine.start()
        } catch {
            NSLog("MechoBasic: çalma başlatılamadı: \(error)")
            state = .idle
            return
        }
        player = engine
        playbackID += 1
        let id = playbackID
        state = .playing

        node.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            // Yankı kuyruğunun sönmesi için biraz bekle.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                guard let self, self.playbackID == id else { return }
                self.stopPlayback()
            }
        }
        node.play()
    }

    private func stopPlayback() {
        guard let engine = player else { return }
        engine.stop()
        player = nil
        if state == .playing { state = .idle }
    }
}

// MARK: - F6 dinleyici

final class F6Listener {
    private static let f6KeyCode: Int64 = 97

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    private var tap: CFMachPort?
    private var isDown = false

    var isActive: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<F6Listener>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.keyboardEventKeycode) == Self.f6KeyCode else {
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown, !isDown {
            isDown = true
            onPress?()
        } else if type == .keyUp, isDown {
            isDown = false
            onRelease?()
        }
        return nil // F6'yı sistemden yut
    }
}

// MARK: - Menü çubuğu uygulaması

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let echo = EchoEngine()
    private let listener = F6Listener()
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "Erişilebilirlik iznini ver…", action: #selector(openAccessibility), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Girişte başlat", action: #selector(toggleLogin), keyEquivalent: "")
    private var retryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        setIcon(.idle)

        echo.onStateChange = { [weak self] in self?.setIcon($0) }
        listener.onPress = { [weak self] in self?.echo.startRecording() }
        listener.onRelease = { [weak self] in self?.echo.stopRecordingAndPlay() }

        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted { NSLog("MechoBasic: mikrofon izni verilmedi") }
        }

        registerLoginItemOnFirstLaunch()
        startListening()
    }

    private func buildMenu() {
        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Çıkış", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        [permissionItem, loginItem].forEach { $0.target = self }
        statusItem.menu = menu
        refreshMenu()
    }

    private func refreshMenu() {
        statusLine.title = listener.isActive ? "F6'ya basılı tut ve konuş" : "Erişilebilirlik izni bekleniyor"
        permissionItem.isHidden = listener.isActive
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func setIcon(_ state: EchoEngine.State) {
        let name: String
        switch state {
        case .idle: name = "waveform"
        case .recording: name = "mic.fill"
        case .playing: name = "speaker.wave.3.fill"
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Mecho Basic")
        image?.isTemplate = state != .recording
        statusItem.button?.image = image
        statusItem.button?.contentTintColor = state == .recording ? .systemRed : nil
    }

    private func startListening() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        if listener.start() { refreshMenu(); return }
        refreshMenu()
        // İzin verilene kadar tekrar dene.
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, self.listener.start() else { return }
            timer.invalidate()
            self.refreshMenu()
        }
    }

    private func registerLoginItemOnFirstLaunch() {
        let key = "didRegisterLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        try? SMAppService.mainApp.register()
        UserDefaults.standard.set(true, forKey: key)
    }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("MechoBasic: giriş öğesi değiştirilemedi: \(error)")
        }
        refreshMenu()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
