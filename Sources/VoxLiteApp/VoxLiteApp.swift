import AppKit
import Carbon
import SwiftUI
import VoxLiteDomain
import VoxLiteFeature
internal import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var viewModel: AppViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let vm = viewModel, !vm.showOnboarding {
            vm.startMonitor()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.stopMonitor()
    }
}

@main
struct VoxLiteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = VoxLiteApp.makeViewModel()
    @State private var isCapturingHotKey = false
    @State private var hotKeyInputText = ""
    @State private var pendingHotKey: HotKeyConfiguration?
    @State private var previousHotKey: HotKeyConfiguration?

    var body: some Scene {
        MenuBarExtra("VoxLite", systemImage: "waveform") {
            VStack(alignment: .leading, spacing: 10) {
                if model.showOnboarding {
                    onboardingView
                } else {
                    runtimeView
                }
            }
            .padding()
            .frame(width: 360)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: model.showOnboarding, initial: true) { _, _ in
            if appDelegate.viewModel == nil {
                appDelegate.viewModel = model
                if !model.showOnboarding {
                    model.startMonitor()
                }
            }
        }
    }
}

private extension VoxLiteApp {
    var onboardingView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Vox 初始化引导")
                .font(.headline)
            Text("步骤 \(model.onboardingStep)/4")
                .font(.caption)
                .foregroundStyle(.secondary)
            permissionRow("麦克风", granted: model.permissionSnapshot.microphoneGranted)
            permissionRow("辅助功能", granted: model.permissionSnapshot.accessibilityGranted)
            permissionRow("语音识别", granted: model.permissionSnapshot.speechRecognitionGranted)
            HStack {
                Button("授权麦克风") { Task { await model.requestPermission(.microphone) } }
                Button("授权辅助功能") { Task { await model.requestPermission(.accessibility) } }
            }
            HStack {
                Button("授权语音识别") { Task { await model.requestPermission(.speechRecognition) } }
                Button("刷新状态") { model.refreshPermissionSnapshot() }
            }
            Button("稍后配置") { model.skipOnboarding() }
        }
        .onAppear {
            model.refreshPermissionSnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissionSnapshot()
        }
    }

    var runtimeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.showRecordingAnimation {
                RecordingAnimationView()
                    .frame(height: 180)
            }
            hotKeyRow
            VStack(alignment: .leading, spacing: 4) {
                Text("组件状态")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                componentStatusRow(name: "Speech", status: model.speechStatus)
                componentStatusRow(name: "Foundation Model", status: model.foundationModelStatus)
            }
            Text("状态: \(model.stateText)")
            Text(model.sceneHint)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !model.resourceHint.isEmpty {
                Text(model.resourceHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !model.cleanedText.isEmpty {
                Text("结果：\(model.cleanedText)")
                    .font(.caption)
            }
            if !model.lastError.isEmpty {
                Text("异常：\(model.lastError)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if !model.actionTitle.isEmpty {
                Button(model.actionTitle) {
                    if model.canRetry {
                        Task { await model.retryLatest() }
                    } else {
                        model.openSettingForRecommendedPermission()
                    }
                }
            }
            HStack {
                Button("沟通") { model.switchToCommunication() }
                Button("开发") { model.switchToDevelopment() }
                Button("写作") { model.switchToWriting() }
            }
            Divider()
            Button("退出") {
                appDelegate.viewModel?.stopMonitor()
                NSApplication.shared.terminate(nil)
            }
        }
    }

    var hotKeyRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("录音快捷键")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                HotKeyCaptureInput(
                    text: $hotKeyInputText,
                    isCapturing: $isCapturingHotKey,
                    onStartCapture: startHotKeyCapture,
                    onCapture: { captured in
                        guard let captured else { return }
                        pendingHotKey = captured
                        hotKeyInputText = captured.displayString
                    },
                    onCancel: cancelHotKeyCapture,
                    onSubmit: applyHotKeyCapture
                )
                .frame(height: 28)
                if model.hotKeySettings.hasConflict {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(model.hotKeySettings.conflictMessage)
                }
            }
            if isCapturingHotKey {
                HStack {
                    Button("取消") {
                        cancelHotKeyCapture()
                    }
                    Button("保存") {
                        applyHotKeyCapture()
                    }
                    .disabled(pendingHotKey == nil)
                }
                .font(.caption)
            }
        }
        .onAppear {
            hotKeyInputText = model.hotKeySettings.configuration.displayString
        }
    }

    func permissionRow(_ name: String, granted: Bool) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text("\(name)：\(granted ? "已授权" : "待授权")")
                .font(.caption)
        }
    }

    func componentStatusRow(name: String, status: String) -> some View {
        HStack {
            Text("\(name)：")
                .font(.caption)
            Text(status)
                .font(.caption)
                .foregroundStyle(statusColor(status))
        }
    }

    func statusColor(_ status: String) -> Color {
        if status.contains("正常") {
            return .green
        }
        if status.contains("异常") || status.contains("不可用") {
            return .red
        }
        if status.contains("降级") {
            return .orange
        }
        return .secondary
    }

    static func makeViewModel() -> AppViewModel {
        VoxLiteFeatureBootstrap.makeDefaultViewModel()
    }

    func startHotKeyCapture() {
        previousHotKey = model.hotKeySettings.configuration
        pendingHotKey = nil
        hotKeyInputText = ""
        isCapturingHotKey = true
    }

    func cancelHotKeyCapture() {
        if let previousHotKey {
            hotKeyInputText = previousHotKey.displayString
        } else {
            hotKeyInputText = model.hotKeySettings.configuration.displayString
        }
        pendingHotKey = nil
        isCapturingHotKey = false
    }

    func applyHotKeyCapture() {
        guard let pendingHotKey else {
            cancelHotKeyCapture()
            return
        }
        model.updateHotKeyConfiguration(pendingHotKey)
        hotKeyInputText = pendingHotKey.displayString
        previousHotKey = pendingHotKey
        self.pendingHotKey = nil
        isCapturingHotKey = false
    }
}

struct HotKeyCaptureInput: NSViewRepresentable {
    @Binding var text: String
    @Binding var isCapturing: Bool
    let onStartCapture: () -> Void
    let onCapture: (HotKeyConfiguration?) -> Void
    let onCancel: () -> Void
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> HotKeyCaptureTextField {
        let field = HotKeyCaptureTextField()
        field.delegate = context.coordinator
        field.isEditable = false
        field.isBezeled = true
        field.isBordered = true
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.alignment = .left
        field.backgroundColor = .controlBackgroundColor
        field.onMouseDown = {
            onStartCapture()
        }
        field.onCapture = { config in
            onCapture(config)
        }
        field.onCancel = {
            onCancel()
        }
        field.onSubmit = {
            onSubmit()
        }
        return field
    }

    func updateNSView(_ nsView: HotKeyCaptureTextField, context: Context) {
        nsView.stringValue = text.isEmpty ? "点击并按下快捷键" : text
        nsView.isCapturing = isCapturing
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {}
}

final class HotKeyCaptureTextField: NSTextField {
    var onMouseDown: (() -> Void)?
    var onCapture: ((HotKeyConfiguration?) -> Void)?
    var onCancel: (() -> Void)?
    var onSubmit: (() -> Void)?
    var isCapturing = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onMouseDown?()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }
        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            onSubmit?()
            return
        }
        let keyCode = event.keyCode
        if isModifierOnlyKey(keyCode) {
            return
        }
        let modifiers = buildModifierMask(from: event.modifierFlags)
        onCapture?(HotKeyConfiguration(keyCode: keyCode, modifiers: modifiers))
    }

    override func flagsChanged(with event: NSEvent) {
        guard isCapturing else {
            super.flagsChanged(with: event)
            return
        }
        if event.modifierFlags.contains(.function) {
            onCapture?(HotKeyConfiguration.defaultConfiguration)
        }
    }

    private func isModifierOnlyKey(_ keyCode: UInt16) -> Bool {
        keyCode == UInt16(kVK_Command)
            || keyCode == UInt16(kVK_RightCommand)
            || keyCode == UInt16(kVK_Shift)
            || keyCode == UInt16(kVK_RightShift)
            || keyCode == UInt16(kVK_Option)
            || keyCode == UInt16(kVK_RightOption)
            || keyCode == UInt16(kVK_Control)
            || keyCode == UInt16(kVK_RightControl)
            || keyCode == UInt16(kVK_Function)
    }

    private func buildModifierMask(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.control) {
            mask |= HotKeyConfiguration.controlModifierMask
        }
        if flags.contains(.option) {
            mask |= HotKeyConfiguration.optionModifierMask
        }
        if flags.contains(.shift) {
            mask |= HotKeyConfiguration.shiftModifierMask
        }
        if flags.contains(.command) {
            mask |= HotKeyConfiguration.commandModifierMask
        }
        return mask
    }
}

struct RecordingAnimationView: View {
    @State private var opacity: Double = 0.0
    @State private var scale: CGFloat = 0.8
    @State private var audioLevel: CGFloat = 0.3

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onAppear {
                    withAnimation(.easeIn(duration: 0.2)) {
                        opacity = 1.0
                    }
                }
                .onDisappear {
                    withAnimation(.easeOut(duration: 0.3)) {
                        opacity = 0.0
                    }
                }

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.blue.opacity(0.3), .blue.opacity(0.1), .clear],
                                center: .center,
                                startRadius: 30,
                                endRadius: 80
                            )
                        )
                        .frame(width: 120, height: 120)
                        .scaleEffect(scale)

                    Circle()
                        .stroke(Color.blue.opacity(0.5), lineWidth: 3)
                        .frame(width: 60, height: 60)

                    Circle()
                        .fill(Color.blue.opacity(audioLevel))
                        .frame(width: 30, height: 30)
                }
                .onReceive(timer) { _ in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        scale = CGFloat.random(in: 0.9...1.1)
                        audioLevel = CGFloat.random(in: 0.3...0.8)
                    }
                }

                Text("录音中...")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.2)) {
                opacity = 1.0
                scale = 1.0
            }
        }
    }
}
