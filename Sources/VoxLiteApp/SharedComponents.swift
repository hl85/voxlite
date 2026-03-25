import SwiftUI
import AppKit
import Carbon
import VoxLiteDomain
import VoxLiteFeature

// MARK: - MenuBar Quick View

struct MenuBarQuickView: View {
    @EnvironmentObject private var model: AppViewModel
    let openMainWindow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 状态行
            HStack(spacing: 10) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: stateColor.opacity(0.8), radius: 4)
                Text("Vox · \(model.stateText)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "#f4f7ff"))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if model.showRecordingAnimation {
                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { _ in AnimatedBar() }
                }
                .frame(height: 24)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }

            if model.appSettings.showRecentSummary && !model.menuBarSummary.isEmpty {
                Text(model.menuBarSummary)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#9cabd7"))
                    .lineLimit(2)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }

            if !model.lastError.isEmpty {
                Text(model.lastError)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#ffbf53"))
                    .lineLimit(2)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }

            Divider().opacity(0.2)

            // 快捷按钮
            Button {
                openMainWindow()
            } label: {
                Label("打开主界面", systemImage: "macwindow")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(hex: "#c7d4ff"))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider().opacity(0.2)

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Color(hex: "#ff6a7c").opacity(0.8))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 240)
        .background(Color(hex: "#0f1d40"))
    }

    var stateColor: Color {
        switch model.stateText {
        case "Recording": return Color(hex: "#ff6a7c")
        case "Processing": return Color(hex: "#ffbf53")
        case "Done": return Color(hex: "#4cd08d")
        case "Failed": return Color(hex: "#ff6a7c")
        default: return Color(hex: "#4cd08d")
        }
    }
}

// MARK: - Animated Waveform Bar

struct AnimatedBar: View {
    @State private var scale: CGFloat = 0.55

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(
                LinearGradient(
                    colors: [Color(hex: "#7d8dff"), Color(hex: "#39d1ff")],
                    startPoint: .bottom, endPoint: .top
                )
            )
            .frame(width: 4, height: 28)
            .scaleEffect(y: scale, anchor: .bottom)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: Double.random(in: 0.5...1.0))
                    .repeatForever(autoreverses: true)
                ) {
                    scale = CGFloat.random(in: 0.3...1.0)
                }
            }
    }
}

// MARK: - Button Styles

struct VoxPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(primaryBackground.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var primaryBackground: Color {
        colorScheme == .dark ? Color(hex: "#3e57cc") : Color(hex: "#4160d0")
    }
}

struct VoxSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(secondaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(secondaryBackground.opacity(configuration.isPressed ? 0.6 : 0.9))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(secondaryBorder, lineWidth: 1))
    }

    private var secondaryText: Color {
        colorScheme == .dark ? Color(hex: "#c7d4ff") : Color(hex: "#334b92")
    }

    private var secondaryBackground: Color {
        colorScheme == .dark ? Color(hex: "#17223f") : Color(hex: "#edf2ff")
    }

    private var secondaryBorder: Color {
        colorScheme == .dark ? Color(hex: "#2b3760") : Color(hex: "#c6d6ff")
    }
}

struct VoxSceneButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(hex: "#c7d4ff"))
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(
                configuration.isPressed
                ? Color(hex: "#7d8dff").opacity(0.25)
                : Color(hex: "#17223f").opacity(0.8)
            )
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(hex: "#2b3760"), lineWidth: 1))
    }
}

struct VoxDestructiveButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(destructiveText.opacity(0.9))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(destructiveText.opacity(configuration.isPressed ? 0.2 : 0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var destructiveText: Color {
        colorScheme == .dark ? Color(hex: "#ff6a7c") : Color(hex: "#c7364f")
    }
}

struct VoxLightCapsuleButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(backgroundColor.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(borderColor, lineWidth: 1))
    }

    private var textColor: Color {
        colorScheme == .dark ? Color(hex: "#d3deff") : Color(hex: "#3f57bf")
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(hex: "#1c2a55") : Color(hex: "#edf2ff")
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color(hex: "#445da6") : Color(hex: "#c5d4ff")
    }
}

// MARK: - Color helper

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
