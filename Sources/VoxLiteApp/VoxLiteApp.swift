import AppKit
import Carbon
import SwiftUI
import VoxLiteDomain
import VoxLiteFeature
internal import Combine

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var viewModel: AppViewModel?
    private var monitorStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.stopMonitor()
    }

    /// 当用户通过其他途径（如 Spotlight 再次激活 App）时，重新显示主窗口
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openMainWindow()
        }
        return true
    }

    @MainActor func startMonitorOnce() {
        guard !monitorStarted, let vm = viewModel, !vm.showOnboarding else { return }
        monitorStarted = true
        vm.startMonitor()
    }

    @MainActor func openMainWindow() {
        NSApp.windows
            .first { !($0 is NSPanel) && $0.identifier?.rawValue == "main" }
            .map { $0.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - App

@main
struct VoxLiteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = VoxLiteApp.makeViewModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // 主窗口 —— 引导 + 运行态全部在这里
        Window("轻音 · Vox", id: "main") {
            MainWindowView()
                .environmentObject(model)
                .onAppear {
                    guard appDelegate.viewModel == nil else { return }
                    appDelegate.viewModel = model
                    appDelegate.startMonitorOnce()
                    DispatchQueue.main.async {
                        NSApp.windows
                            .first { !($0 is NSPanel) }?
                            .isMovableByWindowBackground = true
                    }
                }
                .onChange(of: model.showOnboarding) { _, isOnboarding in
                    if !isOnboarding {
                        appDelegate.startMonitorOnce()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 920, height: 640)

        // 菜单栏 —— 仅作状态展示 + 快捷入口
        MenuBarExtra {
            MenuBarQuickView(openMainWindow: {
                openWindow(id: "main")
                appDelegate.openMainWindow()
            })
            .environmentObject(model)
        } label: {
            switch model.appSettings.menuBarDisplayMode {
            case .iconOnly:
                Image(systemName: model.showRecordingAnimation
                      ? "waveform.circle.fill" : "waveform")
            case .iconAndSummary:
                HStack(spacing: 4) {
                    Image(systemName: model.showRecordingAnimation
                          ? "waveform.circle.fill" : "waveform")
                    if !model.menuBarSummary.isEmpty {
                        Text(model.menuBarSummary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    static func makeViewModel() -> AppViewModel {
        VoxLiteFeatureBootstrap.makeDefaultViewModel()
    }
}
