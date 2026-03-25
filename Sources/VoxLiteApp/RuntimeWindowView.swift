import SwiftUI
import VoxLiteDomain
import VoxLiteFeature

// MARK: - Runtime Window

struct RuntimeWindowView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var isCapturingHotKey = false
    @State private var hotKeyInputText = ""
    @State private var pendingHotKey: HotKeyConfiguration?
    @State private var previousHotKey: HotKeyConfiguration?

    var body: some View {
        HStack(spacing: 0) {
            // 左侧侧边栏
            runtimeSidebar

            Divider().opacity(0.15)

            // 右侧内容
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if model.showRecordingAnimation {
                        recordingBanner
                    }
                    sceneSection
                    statusSection
                    resultSection
                    if !model.lastError.isEmpty || !model.actionTitle.isEmpty {
                        errorSection
                    }
                    hotKeySection
                    Spacer(minLength: 20)
                }
                .padding(28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 920, height: 580)
        .background(windowBackground)
        .onAppear {
            hotKeyInputText = model.hotKeySettings.configuration.displayString
        }
    }
}

// MARK: - Runtime subviews
private extension RuntimeWindowView {

    var windowBackground: some View {
        LinearGradient(
            colors: [Color(hex: "#0f1d40"), Color(hex: "#0b1020")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    // MARK: Sidebar
    var runtimeSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand
            HStack(spacing: 10) {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(hex: "#7d8dff"), Color(hex: "#39d1ff")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 10, height: 10)
                    .shadow(color: Color(hex: "#47a2ff").opacity(0.9), radius: 6)
                Text("Vox Runtime")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: "#c7d4ff"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider().opacity(0.15).padding(.horizontal, 16)
            Spacer().frame(height: 12)

            // State indicator
            sidebarStateCard

            Spacer()

            // KPIs
            VStack(alignment: .leading, spacing: 8) {
                if !model.resourceHint.isEmpty {
                    Text(model.resourceHint)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#9cabd7"))
                        .padding(.horizontal, 16)
                }
                Divider().opacity(0.15).padding(.horizontal, 16)
                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(VoxDestructiveButtonStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 220)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }

    var sidebarStateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            stateBadge
            VStack(alignment: .leading, spacing: 4) {
                componentRow("Speech", status: model.speechStatus)
                componentRow("Foundation Model", status: model.foundationModelStatus)
            }
        }
        .padding(14)
        .background(Color(hex: "#17223f").opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#2b3760"), lineWidth: 1))
        .padding(.horizontal, 12)
    }

    var stateBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)
                .shadow(color: stateColor.opacity(0.8), radius: 4)
            Text(model.stateText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "#f4f7ff"))
        }
    }

    var stateColor: Color {
        switch model.stateText {
        case "Recording": return Color(hex: "#ff6a7c")
        case "Processing": return Color(hex: "#ffbf53")
        case "Done": return Color(hex: "#4cd08d")
        case "Failed": return Color(hex: "#ff6a7c")
        default: return Color(hex: "#9cabd7")
        }
    }

    func componentRow(_ name: String, status: String) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "#9cabd7"))
            Spacer()
            Text(status)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(statusColor(status))
        }
    }

    func statusColor(_ status: String) -> Color {
        if status.contains("正常") { return Color(hex: "#4cd08d") }
        if status.contains("异常") || status.contains("不可用") { return Color(hex: "#ff6a7c") }
        if status.contains("降级") { return Color(hex: "#ffbf53") }
        return Color(hex: "#9cabd7")
    }

    // MARK: Recording Banner
    var recordingBanner: some View {
        HStack(spacing: 16) {
            waveformBars
            VStack(alignment: .leading, spacing: 4) {
                Text("录音中…")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "#f4f7ff"))
                Text("松开 Fn 键即可结束录音")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#9cabd7"))
            }
            Spacer()
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color(hex: "#7d8dff").opacity(0.18), Color(hex: "#39d1ff").opacity(0.08)],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "#5169c5").opacity(0.5), lineWidth: 1))
    }

    var waveformBars: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<6, id: \.self) { _ in
                AnimatedBar()
            }
        }
        .frame(height: 32)
    }

    // MARK: Scene Section
    var sceneSection: some View {
        sectionCard(title: "输入场景") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    sceneButton("沟通", action: model.switchToCommunication)
                    sceneButton("开发", action: model.switchToDevelopment)
                    sceneButton("写作", action: model.switchToWriting)
                }
                Text(model.sceneHint)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#9cabd7"))
            }
        }
    }

    func sceneButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(VoxSceneButtonStyle())
    }

    // MARK: Status Section
    var statusSection: some View {
        sectionCard(title: "组件状态") {
            HStack(spacing: 16) {
                componentCard("Speech 识别", status: model.speechStatus)
                componentCard("Foundation Model", status: model.foundationModelStatus)
            }
        }
    }

    func componentCard(_ name: String, status: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "#9cabd7"))
            Text(status)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(statusColor(status))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(hex: "#17223f").opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#2b3760"), lineWidth: 1))
    }

    // MARK: Result Section
    @ViewBuilder
    var resultSection: some View {
        if !model.cleanedText.isEmpty {
            sectionCard(title: "清洗结果") {
                Text(model.cleanedText)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#f4f7ff"))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Error Section
    var errorSection: some View {
        sectionCard(title: "状态提示") {
            VStack(alignment: .leading, spacing: 10) {
                if !model.lastError.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color(hex: "#ffbf53"))
                        Text(model.lastError)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "#f4f7ff"))
                    }
                }
                if !model.actionTitle.isEmpty {
                    Button(model.actionTitle) {
                        if model.canRetry {
                            Task { await model.retryLatest() }
                        } else {
                            model.openSettingForRecommendedPermission()
                        }
                    }
                    .buttonStyle(VoxPrimaryButtonStyle())
                }
            }
        }
    }

    // MARK: HotKey Section
    var hotKeySection: some View {
        sectionCard(title: "录音快捷键") {
            HStack(spacing: 12) {
                HotKeyCaptureInput(
                    text: $hotKeyInputText,
                    isCapturing: $isCapturingHotKey,
                    onStartCapture: { startHotKeyCapture() },
                    onCapture: { captured in
                        guard let captured else { return }
                        pendingHotKey = captured
                        hotKeyInputText = captured.displayString
                    },
                    onCancel: { cancelHotKeyCapture() },
                    onSubmit: { applyHotKeyCapture() }
                )
                .frame(width: 180, height: 30)

                if model.hotKeySettings.hasConflict {
                    Label(model.hotKeySettings.conflictMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#ffbf53"))
                }

                if isCapturingHotKey {
                    Button("取消") { cancelHotKeyCapture() }
                        .buttonStyle(VoxSecondaryButtonStyle())
                    Button("保存") { applyHotKeyCapture() }
                        .buttonStyle(VoxPrimaryButtonStyle())
                        .disabled(pendingHotKey == nil)
                }
            }
        }
    }

    // MARK: Section Card Helper
    func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "#9cabd7"))
                .textCase(.uppercase)
                .tracking(0.8)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(hex: "#17223f").opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "#2b3760"), lineWidth: 1))
    }

    // MARK: HotKey capture helpers
    func startHotKeyCapture() {
        previousHotKey = model.hotKeySettings.configuration
        pendingHotKey = nil
        hotKeyInputText = ""
        isCapturingHotKey = true
    }

    func cancelHotKeyCapture() {
        hotKeyInputText = (previousHotKey ?? model.hotKeySettings.configuration).displayString
        pendingHotKey = nil
        isCapturingHotKey = false
    }

    func applyHotKeyCapture() {
        guard let pending = pendingHotKey else { cancelHotKeyCapture(); return }
        model.updateHotKeyConfiguration(pending)
        hotKeyInputText = pending.displayString
        previousHotKey = pending
        pendingHotKey = nil
        isCapturingHotKey = false
    }
}
