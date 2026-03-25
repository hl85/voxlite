import AppKit
import SwiftUI
import VoxLiteCore
import VoxLiteDomain
import VoxLiteFeature

struct MainWindowView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSkillEditorPresented = false
    @State private var editorSkillId: String?
    @State private var draftSkillName = ""
    @State private var draftSkillHint = ""
    @State private var draftSkillTemplate = ""
    @State private var draftIsDefault = false
    @State private var draftBindings: [AppBinding] = []
    @State private var selectedRunningAppBundleId = ""
    @State private var isHotKeyCapturing = false
    @State private var hotKeyCaptureText = ""
    @State private var easterEggTapCount = 0
    @State private var easterEggTimer: Timer?
    @State private var showTestMenu = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: palette.windowGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            HStack(spacing: 0) {
                sidebar
                Divider().overlay(palette.divider)
                ScrollView {
                    Group {
                        switch model.selectedModule {
                        case .welcome:
                            welcomeModule
                        case .home:
                            homeModule
                        case .skills:
                            skillsModule
                        case .settings:
                            settingsModule
                        }
                    }
                    .padding(18)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeInOut(duration: 0.2), value: model.selectedModule)
                }
                .background(palette.mainBackground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(palette.windowSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(palette.windowBorder, lineWidth: 1)
            )
            .shadow(color: palette.windowShadow, radius: 20, y: 8)
            .padding(12)
        }
        .frame(width: 920, height: 600)
        .sheet(isPresented: $isSkillEditorPresented) {
            skillEditorSheet
        }
    }
}

private extension MainWindowView {
    struct Palette {
        let windowGradient: [Color]
        let sidebarBackground: Color
        let sidebarText: Color
        let sidebarMutedText: Color
        let sidebarActiveText: Color
        let sidebarActiveBackground: Color
        let sidebarBorder: Color
        let cardBackground: Color
        let cardBorder: Color
        let titleText: Color
        let bodyText: Color
        let mutedText: Color
        let divider: Color
        let windowSurface: Color
        let windowBorder: Color
        let mainBackground: Color
        let windowShadow: Color
    }

    var palette: Palette {
        if colorScheme == .dark {
            return Palette(
                windowGradient: [Color(hex: "#0f1d40"), Color(hex: "#0b1020")],
                sidebarBackground: Color(hex: "#0f1730").opacity(0.88),
                sidebarText: Color(hex: "#f4f7ff"),
                sidebarMutedText: Color(hex: "#9cabd7"),
                sidebarActiveText: Color(hex: "#f4f7ff"),
                sidebarActiveBackground: Color(hex: "#3f57bf").opacity(0.42),
                sidebarBorder: Color(hex: "#3a4d83"),
                cardBackground: Color(hex: "#17223f").opacity(0.78),
                cardBorder: Color(hex: "#2b3760"),
                titleText: Color(hex: "#f4f7ff"),
                bodyText: Color(hex: "#d6e1ff"),
                mutedText: Color(hex: "#9cabd7"),
                divider: Color(hex: "#314678"),
                windowSurface: Color(hex: "#111a35"),
                windowBorder: Color(hex: "#2b3760"),
                mainBackground: Color(hex: "#111b36"),
                windowShadow: Color(hex: "#000000").opacity(0.35)
            )
        }
        return Palette(
            windowGradient: [Color(hex: "#f3f7ff"), Color(hex: "#e8eefc")],
            sidebarBackground: Color(hex: "#eef3ff"),
            sidebarText: Color(hex: "#24325f"),
            sidebarMutedText: Color(hex: "#4e6198"),
            sidebarActiveText: Color(hex: "#273a7a"),
            sidebarActiveBackground: Color(hex: "#dfe8ff"),
            sidebarBorder: Color(hex: "#c6d5f8"),
            cardBackground: Color.white,
            cardBorder: Color(hex: "#d9e1fb"),
            titleText: Color(hex: "#24325f"),
            bodyText: Color(hex: "#344a86"),
            mutedText: Color(hex: "#6071a5"),
            divider: Color(hex: "#d3ddfb"),
            windowSurface: Color(hex: "#f5f8ff"),
            windowBorder: Color(hex: "#d7dff9"),
            mainBackground: Color(hex: "#fafcff"),
            windowShadow: Color(hex: "#a7b8e8").opacity(0.35)
        )
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Voxlite（轻音）")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.sidebarText)
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 18)
                .contentShape(Rectangle())
                .onTapGesture {
                    easterEggTapCount += 1
                    easterEggTimer?.invalidate()
                    if easterEggTapCount >= 7 {
                        easterEggTapCount = 0
                        showTestMenu = true
                    } else {
                        easterEggTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                            Task { @MainActor in
                                easterEggTapCount = 0
                            }
                        }
                    }
                }
                .popover(isPresented: $showTestMenu, arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("测试菜单")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(palette.titleText)
                        Divider()
                        Button("重置引导") {
                            model.resetOnboarding()
                            showTestMenu = false
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(palette.bodyText)
                        .font(.system(size: 13))
                    }
                    .padding(12)
                    .frame(width: 160)
                }

            if !model.appSettings.onboardingCompleted {
                menuButton("欢迎", .welcome)
            }
            menuButton("主页", .home)
            menuButton("技能", .skills)
            menuButton("设置", .settings)

            Spacer()
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(VoxDestructiveButtonStyle())
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .frame(width: 190)
        .background(palette.sidebarBackground)
        .overlay(Rectangle().frame(width: 1).foregroundStyle(palette.sidebarBorder), alignment: .trailing)
    }

    func menuButton(_ title: String, _ module: MainModule) -> some View {
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                model.selectModule(module)
            }
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(
                model.selectedModule == module
                ? palette.sidebarActiveBackground
                : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(model.selectedModule == module ? palette.sidebarBorder : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            model.selectedModule == module ? palette.sidebarActiveText : palette.sidebarMutedText
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    var welcomeModule: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionCard(title: "引导进度") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("完成权限授权后请进行一次试运行，验证真实录音链路可用。")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.mutedText)
                    onboardingStepIndicator
                }
            }
            if !model.permissionSnapshot.speechRecognitionGranted && model.speechStatus.contains("不可用") {
                infoBanner("语音识别不可用，请前往「设置」配置语音识别服务。") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        model.selectModule(.settings)
                    }
                }
            }
            sectionCard(title: "权限状态") {
                VStack(spacing: 8) {
                    permissionRow("麦克风权限", granted: model.permissionSnapshot.microphoneGranted) {
                        Task { await model.requestPermission(.microphone) }
                    }
                    permissionRow("辅助功能", granted: model.permissionSnapshot.accessibilityGranted) {
                        Task { await model.requestPermission(.accessibility) }
                    }
                    permissionRow("语音识别权限", granted: model.permissionSnapshot.speechRecognitionGranted) {
                        Task { await model.requestPermission(.speechRecognition) }
                    }
                }
            }
            sectionCard(title: "试运行") {
                HStack {
                    Text(model.trialRunPassed ? "试运行已通过" : "请按住 \(model.hotKeySettings.configuration.displayString) 录音并松开完成试运行")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.mutedText)
                    Spacer()
                    Button("刷新权限") {
                        model.refreshPermissionSnapshot()
                    }
                    .buttonStyle(VoxSecondaryButtonStyle())
                    Button("开始试运行") {
                        model.startMonitor()
                        model.lastError = "请按住 \(model.hotKeySettings.configuration.displayString) 说话，松开后完成一次真实试运行"
                    }
                    .buttonStyle(VoxPrimaryButtonStyle())
                    .disabled(!model.permissionSnapshot.allGranted)
                }
            }
        }
    }

    var onboardingStepIndicator: some View {
        let steps: [(String, Int)] = [
            ("麦克风权限", 1), ("辅助功能", 2), ("语音识别", 3), ("试运行", 4), ("完成", 5)
        ]
        let currentStep = model.trialRunPassed ? 5 : model.onboardingStep
        return HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                let isDone = currentStep > step.1
                let isActive = currentStep == step.1
                guideStep(step.0, active: isActive, done: isDone)
                if index < steps.count - 1 {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isDone ? Color(hex: "#1d8252") : palette.mutedText.opacity(0.5))
                        .padding(.horizontal, 3)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentStep)
    }

    func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(palette.bodyText)
            Spacer()
            if granted {
                statusPill("已授权", tone: .ok)
            } else {
                Button("待授权", action: action)
                    .buttonStyle(VoxLightCapsuleButtonStyle())
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(palette.mainBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.cardBorder, lineWidth: 1))
    }

    var homeModule: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionCard(title: "运行状态") {
                VStack(spacing: 8) {
                    statusItemRow("Speech", model.speechStatus)
                    statusItemRow("Foundation Model", model.foundationModelStatus)
                    statusItemRow("清洗策略", model.cleanStyleTag)
                    errorDisplayRow()
                }
            }
            sectionCard(title: "语音识别历史记录") {
                if model.historyItems.isEmpty {
                    Text("暂无记录")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.mutedText)
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(model.historyItems.prefix(model.appSettings.historyLimit))) { item in
                            historyItemRow(item)
                        }
                    }
                }
            }
        }
    }

    var skillsModule: some View {
        let modelUnavailable = model.foundationModelAvailability == .deviceNotEligible
            || model.foundationModelAvailability == .unavailable
        return VStack(alignment: .leading, spacing: 12) {
            if modelUnavailable {
                infoBanner("模型暂不可用，部分功能受限。请前往「设置 → 模型设置」配置远端模型。") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        model.selectModule(.settings)
                    }
                }
            }
            HStack {
                Text("技能管理")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(palette.titleText)
                Spacer()
                Button("添加技能") {
                    startAddSkillEditor()
                }
                .buttonStyle(VoxPrimaryButtonStyle())
                .disabled(modelUnavailable)
                .opacity(modelUnavailable ? 0.55 : 1)
            }
            ForEach(model.skillSnapshot.profiles) { skill in
                sectionCard(title: "") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(skill.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(palette.mutedText)
                            Spacer()
                            if model.skillSnapshot.matching.defaultSkillId == skill.id {
                                defaultSkillTag("默认技能✓")
                            }
                        }
                        Text(skill.styleHint)
                            .font(.system(size: 13))
                            .foregroundStyle(palette.mutedText)
                        fieldBlock(title: "提示词", value: skill.template)
                        fieldBlock(title: "应用匹配", value: formattedBindings(for: skill.id))
                        HStack(spacing: 10) {
                            Button("编辑") {
                                startEditSkillEditor(skill)
                            }
                            .buttonStyle(VoxSecondaryButtonStyle())
                            .disabled(modelUnavailable)
                            Button("删除") {
                                _ = model.deleteSkill(skill.id)
                            }
                            .buttonStyle(VoxSecondaryButtonStyle())
                            .disabled(skill.type == .preinstalled)
                            .opacity(skill.type == .preinstalled ? 0.45 : 1)
                            Spacer()
                        }
                    }
                }
            }
        }
        .onAppear {
            model.reloadSkillSnapshot()
        }
    }

    var settingsModule: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionCard(title: "基础设置") {
                VStack(spacing: 10) {
                    settingRow("录音快捷键") {
                        HotKeyCaptureInput(
                            text: $hotKeyCaptureText,
                            isCapturing: $isHotKeyCapturing,
                            onStartCapture: {
                                isHotKeyCapturing = true
                                hotKeyCaptureText = ""
                            },
                            onCapture: { config in
                                guard let config else { return }
                                hotKeyCaptureText = config.displayString
                                model.updateHotKeyConfiguration(config)
                                isHotKeyCapturing = false
                            },
                            onCancel: {
                                isHotKeyCapturing = false
                                hotKeyCaptureText = model.appSettings.hotKeyDescription
                            },
                            onSubmit: {
                                isHotKeyCapturing = false
                            }
                        )
                        .frame(width: 200, height: 24)
                        .onAppear {
                            hotKeyCaptureText = model.appSettings.hotKeyDescription
                        }
                    }
                    settingRow("开机自动启动") {
                        Toggle("", isOn: Binding(
                            get: { model.appSettings.launchAtLoginEnabled },
                            set: { model.setLaunchAtLogin($0) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                    settingRow("状态栏菜单") {
                        Picker("", selection: Binding(
                            get: { model.appSettings.menuBarDisplayMode },
                            set: { newMode in
                                model.appSettings.menuBarDisplayMode = newMode
                                model.setMenuBarSummaryVisible(newMode == .iconAndSummary)
                            }
                        )) {
                            Text("仅图标").tag(MenuBarDisplayMode.iconOnly)
                            Text("图标+摘要").tag(MenuBarDisplayMode.iconAndSummary)
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                }
            }
            sectionCard(title: "权限入口") {
                VStack(spacing: 8) {
                    permissionSettingRow("麦克风", granted: model.permissionSnapshot.microphoneGranted) {
                        model.openSystemSettings(for: .microphone)
                    }
                    permissionSettingRow("辅助功能", granted: model.permissionSnapshot.accessibilityGranted) {
                        model.openSystemSettings(for: .accessibility)
                    }
                    permissionSettingRow("语音识别", granted: model.permissionSnapshot.speechRecognitionGranted) {
                        model.openSystemSettings(for: .speechRecognition)
                    }
                }
            }
            ModelSettingsView()
        }
        .onAppear {
            model.refreshPermissionSnapshot()
        }
    }

    func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(palette.mutedText)
            Spacer()
            content()
        }
        .padding(.vertical, 2)
    }

    func permissionSettingRow(_ name: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(palette.bodyText)
            Spacer()
            if granted {
                statusPill("已授权", tone: .ok)
            } else {
                statusPill("未授权", tone: .warn)
            }
            Button("打开系统设置") { action() }
                .buttonStyle(VoxLightCapsuleButtonStyle())
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(palette.mainBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.cardBorder, lineWidth: 1))
    }

    func statusRow(_ name: String, _ status: String) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(palette.mutedText)
            Spacer()
            Text(status)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.titleText)
        }
        .padding(.vertical, 2)
    }

    func statusItemRow(_ name: String, _ status: String) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(palette.bodyText)
            Spacer()
            statusPill(statusText(status), tone: statusTone(status))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(palette.mainBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.cardBorder, lineWidth: 1))
    }

    func errorDisplayRow() -> some View {
        Group {
            if model.lastError.isEmpty {
                statusItemRow("最后错误", "无")
            } else {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.lastError)
                            .font(.system(size: 12))
                            .foregroundStyle(palette.bodyText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if model.canRetry {
                            HStack {
                                Spacer()
                                Button("重试") {
                                    Task { await model.retryLatest() }
                                }
                                .buttonStyle(VoxSecondaryButtonStyle())
                            }
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    HStack {
                        Text("最后错误")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.bodyText)
                        Spacer()
                        statusPill("有错误", tone: .danger)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(palette.mainBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.cardBorder, lineWidth: 1))
            }
        }
    }

    func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if title.isEmpty == false {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.mutedText)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.cardBorder, lineWidth: 1))
    }

    func fieldBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(palette.mutedText)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(palette.bodyText)
                .lineLimit(3)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.mainBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.cardBorder, lineWidth: 1))
    }

    func formattedBindings(for skillId: String) -> String {
        let bindings = model.bindingsForSkill(skillId)
        if bindings.isEmpty {
            return "未绑定应用"
        }
        return bindings.map { "\($0.appName) (\($0.bundleId))" }.joined(separator: "，")
    }

    var runningApps: [AppBinding] {
        NSWorkspace.shared.runningApplications
            .compactMap { app -> AppBinding? in
                guard let bundleId = app.bundleIdentifier,
                      let appName = app.localizedName,
                      appName.isEmpty == false else { return nil }
                return AppBinding(bundleId: bundleId, appName: appName)
            }
            .sorted { $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
    }

    func startAddSkillEditor() {
        editorSkillId = nil
        draftSkillName = ""
        draftSkillHint = ""
        draftSkillTemplate = "{{text}}"
        draftIsDefault = false
        draftBindings = []
        selectedRunningAppBundleId = runningApps.first?.bundleId ?? ""
        isSkillEditorPresented = true
    }

    func startEditSkillEditor(_ skill: SkillProfile) {
        editorSkillId = skill.id
        draftSkillName = skill.name
        draftSkillHint = skill.styleHint
        draftSkillTemplate = skill.template
        draftIsDefault = model.skillSnapshot.matching.defaultSkillId == skill.id
        draftBindings = model.bindingsForSkill(skill.id)
        selectedRunningAppBundleId = runningApps.first?.bundleId ?? ""
        isSkillEditorPresented = true
    }

    func saveSkillEditor() {
        let name = draftSkillName.trimmingCharacters(in: .whitespacesAndNewlines)
        let hint = draftSkillHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = draftSkillTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false, hint.isEmpty == false, template.isEmpty == false else { return }
        let skillId: String
        if let existingSkillId = editorSkillId,
           let existing = model.skillSnapshot.profiles.first(where: { $0.id == existingSkillId }) {
            var updated = existing
            updated.name = name
            updated.styleHint = hint
            updated.template = template
            model.updateSkill(updated)
            skillId = existingSkillId
        } else {
            skillId = model.addCustomSkill(name: name, template: template, styleHint: hint)
        }
        model.setBundleBindings(skillId: skillId, bindings: draftBindings)
        if draftIsDefault {
            model.setDefaultSkill(skillId)
        } else if model.skillSnapshot.matching.defaultSkillId == skillId {
            model.setDefaultSkill("transcribe")
        }
        isSkillEditorPresented = false
    }

    func addSelectedRunningAppBinding() {
        guard let selected = runningApps.first(where: { $0.bundleId == selectedRunningAppBundleId }) else { return }
        if draftBindings.contains(where: { $0.bundleId == selected.bundleId }) == false {
            draftBindings.append(selected)
            draftBindings.sort { $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
        }
    }

    var skillEditorSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(editorSkillId == nil ? "添加技能" : "编辑技能")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.titleText)
                Spacer()
            }
            Group {
                TextField("技能名", text: $draftSkillName)
                TextField("一句话简介", text: $draftSkillHint)
                TextField("提示词模板（使用 {{text}}）", text: $draftSkillTemplate, axis: .vertical)
                    .lineLimit(3...6)
            }
            .textFieldStyle(.roundedBorder)
            Toggle("设为默认技能", isOn: $draftIsDefault)
            VStack(alignment: .leading, spacing: 8) {
                Text("匹配应用")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.bodyText)
                HStack {
                    Picker("运行中应用", selection: $selectedRunningAppBundleId) {
                        ForEach(runningApps, id: \.bundleId) { app in
                            Text("\(app.appName) (\(app.bundleId))").tag(app.bundleId)
                        }
                    }
                    Button("添加应用") {
                        addSelectedRunningAppBinding()
                    }
                    .buttonStyle(VoxSecondaryButtonStyle())
                }
                ForEach(draftBindings) { binding in
                    HStack {
                        Text("\(binding.appName) (\(binding.bundleId))")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.bodyText)
                        Spacer()
                        Button("移除") {
                            draftBindings.removeAll { $0.bundleId == binding.bundleId }
                        }
                        .buttonStyle(VoxSecondaryButtonStyle())
                    }
                }
            }
            Spacer()
            HStack {
                Spacer()
                Button("取消") {
                    isSkillEditorPresented = false
                }
                .buttonStyle(VoxSecondaryButtonStyle())
                Button("保存") {
                    saveSkillEditor()
                }
                .buttonStyle(VoxPrimaryButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 620, height: 520)
        .background(palette.windowSurface)
    }

    enum StatusTone {
        case ok
        case warn
        case danger
        case neutral
        case disabled
    }

    func statusTone(_ raw: String) -> StatusTone {
        if raw.contains("已就绪") || raw.contains("正常") || raw.contains("成功") || raw == "无" {
            return .ok
        }
        if raw.contains("等待") || raw.contains("提示") || raw.contains("请开启 Apple Intelligence") || raw.contains("待处理") || raw.contains("待授权") || raw.contains("Idle") || raw.contains("关闭") {
            return .warn
        }
        if raw.contains("终止") || raw.contains("不支持") || raw.contains("不可用") {
            return .disabled
        }
        if raw.contains("异常") || raw.contains("失败") || raw == "有" {
            return .danger
        }
        return .neutral
    }

    func statusText(_ raw: String) -> String {
        if raw == "Idle" { return "待处理" }
        return raw
    }

    func statusPill(_ text: String, tone: StatusTone) -> some View {
        let fg: Color
        let bg: Color
        switch tone {
        case .ok:
            fg = Color(hex: "#148452")
            bg = Color(hex: "#d8f6e9")
        case .warn:
            fg = Color(hex: "#9b6a18")
            bg = Color(hex: "#fff2dd")
        case .danger:
            fg = Color(hex: "#9f1f3a")
            bg = Color(hex: "#ffe4ea")
        case .neutral:
            fg = palette.bodyText
            bg = Color(hex: "#edf2ff")
        case .disabled:
            fg = Color(hex: "#6b7280")
            bg = Color(hex: "#e5e7eb")
        }
        return Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bg)
            .clipShape(Capsule())
    }

    func infoBanner(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(text)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Color(hex: "#2556b9"))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "#e0ecff"))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "#a8c6ff"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    func defaultSkillTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(hex: "#148452"))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(hex: "#d8f6e9"))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color(hex: "#bdeccf"), lineWidth: 1)
            )
    }

    func guideStep(_ title: String, active: Bool, done: Bool) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(done ? Color(hex: "#1d8252") : (active ? palette.bodyText : palette.mutedText.opacity(0.8)))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                done
                ? Color(hex: "#e7fff1")
                : (active ? Color(hex: "#d9e6ff") : Color(hex: "#edf2ff"))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(done ? Color(hex: "#bdeccf") : Color(hex: "#ccdaff"), lineWidth: 1)
            )
    }

    func historyItemRow(_ item: TranscriptHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(item.outputText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.titleText)
                    .lineLimit(1)
                Spacer()
                statusPill(item.succeeded ? "成功" : "失败", tone: item.succeeded ? .ok : .danger)
            }
            Text("原文：\(item.sourceText)")
                .font(.system(size: 12))
                .foregroundStyle(palette.mutedText)
                .lineLimit(1)
            Text("\(item.appName) · \(item.skillName)")
                .font(.system(size: 12))
                .foregroundStyle(palette.mutedText)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(palette.mainBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.cardBorder, lineWidth: 1))
    }
}
