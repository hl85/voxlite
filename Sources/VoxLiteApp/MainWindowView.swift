import SwiftUI
import VoxLiteDomain
import VoxLiteFeature

// MARK: - MainWindowView

struct MainWindowView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        if model.showOnboarding {
            OnboardingWindowView()
                .transition(.opacity)
        } else {
            RuntimeWindowView()
                .transition(.opacity)
        }
    }
}

// MARK: - Onboarding Window

struct OnboardingWindowView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        HStack(spacing: 0) {
            // 左侧导航栏
            VStack(alignment: .leading, spacing: 0) {
                brandHeader
                Divider().opacity(0.15).padding(.horizontal, 16)
                Spacer().frame(height: 12)
                stepList
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    kpiRow("状态反馈", value: "<100ms")
                    kpiRow("端到端 P50", value: "<1.0s")
                }
                .padding(16)
            }
            .frame(width: 220)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))

            Divider().opacity(0.15)

            // 右侧内容区
            VStack(alignment: .leading, spacing: 20) {
                onboardingHeader
                permissionCards
                Spacer()
                actionRow
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 920, height: 580)
        .background(windowBackground)
        .onAppear { model.refreshPermissionSnapshot() }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            model.refreshPermissionSnapshot()
        }
    }
}

// MARK: - Onboarding subviews

private extension OnboardingWindowView {

    var windowBackground: some View {
        LinearGradient(
            colors: [Color(hex: "#0f1d40"), Color(hex: "#0b1020")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    var brandHeader: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(LinearGradient(
                    colors: [Color(hex: "#7d8dff"), Color(hex: "#39d1ff")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 10, height: 10)
                .shadow(color: Color(hex: "#47a2ff").opacity(0.9), radius: 6)
            Text("Vox 初始化引导")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: "#c7d4ff"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    var stepList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(stepTitles.enumerated()), id: \.offset) { index, title in
                HStack(spacing: 8) {
                    if index < model.onboardingStep - 1 {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(hex: "#4cd08d"))
                            .font(.system(size: 13))
                    } else if index == model.onboardingStep - 1 {
                        Circle()
                            .fill(Color(hex: "#7d8dff"))
                            .frame(width: 8, height: 8)
                            .padding(.leading, 2)
                    } else {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 8, height: 8)
                            .padding(.leading, 2)
                    }
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(
                            index <= model.onboardingStep - 1
                            ? Color(hex: "#c7d4ff")
                            : Color(hex: "#9cabd7").opacity(0.6)
                        )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    index == model.onboardingStep - 1
                    ? Color(hex: "#7d8dff").opacity(0.12) : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 8)
    }

    var stepTitles: [String] { ["欢迎", "麦克风权限", "辅助功能权限", "语音识别权限"] }

    func kpiRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(hex: "#d8e0ff"))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "#9cabd7"))
        }
    }

    var onboardingHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("三步完成初始化")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(hex: "#f4f7ff"))
            Text("完成权限授权后，按住 Fn 键即可开始录音，松开自动清洗并写入当前焦点输入框。")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "#9cabd7"))
        }
    }

    var permissionCards: some View {
        VStack(spacing: 12) {
            permissionCard(
                icon: "mic.fill", title: "麦克风",
                description: "采集语音输入，音频仅在本地处理，不上传。",
                granted: model.permissionSnapshot.microphoneGranted,
                action: { Task { await model.requestPermission(.microphone) } }
            )
            permissionCard(
                icon: "accessibility", title: "辅助功能",
                description: "监听 Fn 键事件并将文本写入当前焦点输入框。",
                granted: model.permissionSnapshot.accessibilityGranted,
                action: { Task { await model.requestPermission(.accessibility) } }
            )
            permissionCard(
                icon: "waveform.badge.mic", title: "语音识别",
                description: "将录音转换为文字，优先端侧处理，保障隐私。",
                granted: model.permissionSnapshot.speechRecognitionGranted,
                action: { Task { await model.requestPermission(.speechRecognition) } }
            )
        }
    }

    func permissionCard(
        icon: String, title: String, description: String,
        granted: Bool, action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(granted
                          ? Color(hex: "#1f824f").opacity(0.2)
                          : Color(hex: "#7d8dff").opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(granted ? Color(hex: "#4cd08d") : Color(hex: "#7d8dff"))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "#f4f7ff"))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#9cabd7"))
            }
            Spacer()
            if granted {
                Label("已授权", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "#4cd08d"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: "#4cd08d").opacity(0.12))
                    .clipShape(Capsule())
            } else {
                Button("授权") { action() }
                    .buttonStyle(VoxPrimaryButtonStyle())
            }
        }
        .padding(16)
        .background(Color(hex: "#17223f").opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "#2b3760"), lineWidth: 1)
        )
    }

    var actionRow: some View {
        HStack(spacing: 12) {
            Button("刷新权限状态") { model.refreshPermissionSnapshot() }
                .buttonStyle(VoxSecondaryButtonStyle())
            Spacer()
            Button("稍后配置，跳过引导") { model.skipOnboarding() }
                .buttonStyle(VoxSecondaryButtonStyle())
        }
    }
}
