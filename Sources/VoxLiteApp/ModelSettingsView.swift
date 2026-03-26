import SwiftUI
import VoxLiteCore
import VoxLiteDomain
import VoxLiteSystem
import VoxLiteFeature

struct ModelSettingsView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var sttProvider: String = RemoteProvider.localOption
    @State private var sttEndpoint: String = ""
    @State private var sttModelName: String = ""
    
    @State private var llmProvider: String = RemoteProvider.localOption
    @State private var llmEndpoint: String = ""
    @State private var llmModelName: String = ""
    
    @State private var apiKeys: [String: String] = [:]
    @State private var validationStatus: [String: ValidationState] = [:]
    @State private var isValidating: [String: Bool] = [:]
    @State private var saveResultMessage: String = ""
    @State private var showSaveResultAlert = false
    
    @State private var sttModelMemory: [String: String] = [:]
    @State private var llmModelMemory: [String: String] = [:]
    
    enum ValidationState {
        case none
        case success
        case failure(String)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionCard(title: "语音识别模型 (STT)") {
                VStack(spacing: 10) {
                    settingRow("服务商") {
                        Picker("", selection: $sttProvider) {
                            Text(RemoteProvider.localOption).tag(RemoteProvider.localOption)
                            ForEach(RemoteProvider.sttSupportedProviders, id: \.rawValue) { provider in
                                Text(provider.displayName).tag(provider.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 200)
                        .onChange(of: sttProvider) { _, newValue in
                            handleSTTProviderChange(newValue)
                        }
                    }

                    if sttProvider != RemoteProvider.localOption,
                       let provider = RemoteProvider(rawValue: sttProvider) {
                        providerFields(for: provider, isSTT: true)
                    }
                }
            }
            
            sectionCard(title: "LLM 模型") {
                VStack(spacing: 10) {
                    settingRow("服务商") {
                        Picker("", selection: $llmProvider) {
                            Text(RemoteProvider.localOption).tag(RemoteProvider.localOption)
                            ForEach(RemoteProvider.allCases, id: \.self) { provider in
                                Text(provider.displayName).tag(provider.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 200)
                        .onChange(of: llmProvider) { _, newValue in
                            handleLLMProviderChange(newValue)
                        }
                    }
                    
                    if llmProvider != RemoteProvider.localOption {
                        if let provider = RemoteProvider(rawValue: llmProvider) {
                            providerFields(for: provider, isSTT: false)
                        }
                    }
                }
            }
            
            HStack {
                Spacer()
                Button("保存配置") {
                    saveConfiguration()
                }
                .buttonStyle(VoxPrimaryButtonStyle())
            }
        }
        .onAppear {
            loadConfiguration()
        }
        .alert("配置已保存", isPresented: $showSaveResultAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(saveResultMessage)
        }
    }
    
    @ViewBuilder
    private func providerFields(for provider: RemoteProvider, isSTT: Bool) -> some View {
        let isCustom = provider == .custom
        
        settingRow("端点地址") {
            if isCustom {
                TextField("https://api.example.com/v1", text: isSTT ? $sttEndpoint : $llmEndpoint)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
            } else {
                Text(provider.defaultEndpoint.absoluteString)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.mutedText)
                    .frame(width: 280, alignment: .leading)
            }
        }
        
        settingRow("模型选择") {
            if isCustom {
                TextField("输入模型名称", text: isSTT ? $sttModelName : $llmModelName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            } else {
                let presets = isSTT ? provider.sttModelPresets : provider.llmModelPresets
                Picker("", selection: isSTT ? $sttModelName : $llmModelName) {
                    ForEach(presets, id: \.self) { preset in
                        Text(preset).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 200)
                .onChange(of: isSTT ? sttModelName : llmModelName) { _, newValue in
                    if isSTT {
                        sttModelMemory[provider.rawValue] = newValue
                    } else {
                        llmModelMemory[provider.rawValue] = newValue
                    }
                }
            }
        }
        
        settingRow("API Key") {
            SecureField("输入 API Key", text: Binding(
                get: { apiKeys[provider.rawValue] ?? "" },
                set: { apiKeys[provider.rawValue] = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 280)
        }
        
        HStack {
            Spacer()
            if isValidating[provider.rawValue] == true {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 8)
            }
            
            if let status = validationStatus[provider.rawValue] {
                switch status {
                case .success:
                    statusPill("连接成功", tone: .ok)
                case .failure(let error):
                    statusPill(error, tone: .danger)
                case .none:
                    EmptyView()
                }
            }
            
            Button("验证连接") {
                validateConnection(for: provider, isSTT: isSTT)
            }
            .buttonStyle(VoxSecondaryButtonStyle())
            .disabled(isValidating[provider.rawValue] == true || (apiKeys[provider.rawValue] ?? "").isEmpty)
        }
    }
    
    private func loadConfiguration() {
        let keychain = KeychainStorage()
        for provider in RemoteProvider.allCases {
            if let key = try? keychain.retrieveAPIKey(for: provider) {
                apiKeys[provider.rawValue] = key
            }
        }
        
        let sttSetting = model.appSettings.speechModel
        if sttSetting.useRemote, sttSetting.provider.supportsSTT {
            sttProvider = sttSetting.provider.rawValue
            sttEndpoint = sttSetting.customEndpoint
            sttModelName = sttSetting.selectedSTTModel
            sttModelMemory[sttProvider] = sttModelName
        } else {
            sttProvider = RemoteProvider.localOption
        }
        
        let llmSetting = model.appSettings.llmModel
        if llmSetting.useRemote {
            llmProvider = llmSetting.provider.rawValue
            llmEndpoint = llmSetting.customEndpoint
            llmModelName = llmSetting.selectedLLMModel
            llmModelMemory[llmProvider] = llmModelName
        } else {
            llmProvider = RemoteProvider.localOption
        }
    }
    
    private func handleSTTProviderChange(_ newValue: String) {
        guard let provider = RemoteProvider(rawValue: newValue) else { return }
        if provider == .custom {
            sttEndpoint = model.appSettings.speechModel.customEndpoint
        } else {
            sttEndpoint = provider.defaultEndpoint.absoluteString
        }
        sttModelName = sttModelMemory[newValue] ?? provider.sttModelPresets.first ?? ""
    }
    
    private func handleLLMProviderChange(_ newValue: String) {
        guard let provider = RemoteProvider(rawValue: newValue) else { return }
        if provider == .custom {
            llmEndpoint = model.appSettings.llmModel.customEndpoint
        } else {
            llmEndpoint = provider.defaultEndpoint.absoluteString
        }
        llmModelName = llmModelMemory[newValue] ?? provider.llmModelPresets.first ?? ""
    }
    
    private func validateConnection(for provider: RemoteProvider, isSTT: Bool) {
        let endpointString = isSTT ? (provider == .custom ? sttEndpoint : provider.defaultEndpoint.absoluteString) : (provider == .custom ? llmEndpoint : provider.defaultEndpoint.absoluteString)
        guard let url = URL(string: endpointString), let apiKey = apiKeys[provider.rawValue], !apiKey.isEmpty else {
            validationStatus[provider.rawValue] = .failure("无效的端点或 API Key")
            return
        }
        
        isValidating[provider.rawValue] = true
        validationStatus[provider.rawValue] = ValidationState.none
        
        Task {
            let validator = ConnectionValidator()
            let result = await validator.validate(baseURL: url, apiKey: apiKey)
            
            await MainActor.run {
                isValidating[provider.rawValue] = false
                switch result {
                case .success:
                    validationStatus[provider.rawValue] = .success
                case .failure(let error):
                    switch error {
                    case .invalidAPIKey:
                        validationStatus[provider.rawValue] = .failure("API Key 无效")
                    case .rateLimited:
                        validationStatus[provider.rawValue] = .failure("请求超限")
                    case .networkError(let msg):
                        validationStatus[provider.rawValue] = .failure("网络错误: \(msg)")
                    case .apiError(_, let msg):
                        validationStatus[provider.rawValue] = .failure("API 错误: \(msg)")
                    case .unknown(let msg):
                        validationStatus[provider.rawValue] = .failure("连接失败: \(msg)")
                    }
                }
            }
        }
    }
    
    private func saveConfiguration() {
        let keychain = KeychainStorage()
        for (providerRaw, key) in apiKeys {
            if let provider = RemoteProvider(rawValue: providerRaw) {
                do {
                    if key.isEmpty {
                        try keychain.deleteAPIKey(for: provider)
                    } else {
                        try keychain.storeAPIKey(key, for: provider)
                    }
                } catch {
                    NSLog("[ModelSettingsView] Failed to update API key for \(provider.rawValue): \(error.localizedDescription)")
                }
            }
        }
        
        var sttSetting = model.appSettings.speechModel
        if sttProvider == RemoteProvider.localOption {
            sttSetting.useRemote = false
        } else if let provider = RemoteProvider(rawValue: sttProvider) {
            sttSetting.useRemote = true
            sttSetting.provider = provider
            sttSetting.customEndpoint = provider == .custom ? sttEndpoint : ""
            sttSetting.selectedSTTModel = sttModelName
        }
        
        var llmSetting = model.appSettings.llmModel
        if llmProvider == RemoteProvider.localOption {
            llmSetting.useRemote = false
        } else if let provider = RemoteProvider(rawValue: llmProvider) {
            llmSetting.useRemote = true
            llmSetting.provider = provider
            llmSetting.customEndpoint = provider == .custom ? llmEndpoint : ""
            llmSetting.selectedLLMModel = llmModelName
        }
        
        model.appSettings.speechModel = sttSetting
        model.appSettings.llmModel = llmSetting
        let switched = model.saveRemoteModelSettings()
        saveResultMessage = switched
            ? "新配置已立即生效，首页、技能页和后续加工链路已刷新。"
            : "配置已保存，但当前正在处理语音；本轮结束后请再次保存或重新进入设置确认状态。"
        showSaveResultAlert = true
    }
}

private extension ModelSettingsView {
    struct Palette {
        let cardBackground: Color
        let cardBorder: Color
        let titleText: Color
        let bodyText: Color
        let mutedText: Color
        let mainBackground: Color
    }

    var palette: Palette {
        if colorScheme == .dark {
            return Palette(
                cardBackground: Color(hex: "#17223f").opacity(0.78),
                cardBorder: Color(hex: "#2b3760"),
                titleText: Color(hex: "#f4f7ff"),
                bodyText: Color(hex: "#d6e1ff"),
                mutedText: Color(hex: "#9cabd7"),
                mainBackground: Color(hex: "#111b36")
            )
        }
        return Palette(
            cardBackground: Color.white,
            cardBorder: Color(hex: "#d9e1fb"),
            titleText: Color(hex: "#24325f"),
            bodyText: Color(hex: "#344a86"),
            mutedText: Color(hex: "#6071a5"),
            mainBackground: Color(hex: "#fafcff")
        )
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

    enum StatusTone {
        case ok
        case warn
        case danger
        case neutral
        case disabled
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
}
