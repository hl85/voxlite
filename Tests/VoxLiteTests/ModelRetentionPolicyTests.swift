import Testing
@testable import VoxLiteSystem
@testable import VoxLiteDomain

struct ModelRetentionPolicyTests {

    // MARK: - Device Tier Tests

    @Test
    func DeviceTierRetentionCapability() {
        #expect(DeviceTier.appleSilicon.retentionCapability == .full)
        #expect(DeviceTier.intelOrConstrained.retentionCapability == .limited)
        #expect(DeviceTier.unsupported.retentionCapability == .minimal)
    }

    @Test
    func DeviceTierDescription() {
        #expect(DeviceTier.appleSilicon.description == "Apple Silicon")
        #expect(DeviceTier.intelOrConstrained.description == "Intel/受限平台")
        #expect(DeviceTier.unsupported.description == "不支持的平台")
    }

    // MARK: - Resource Pressure Level Tests

    @Test
    func ResourcePressureLevelShouldReleaseAssets() {
        #expect(ResourcePressureLevel.normal.shouldReleaseAssets == false)
        #expect(ResourcePressureLevel.elevated.shouldReleaseAssets)
        #expect(ResourcePressureLevel.critical.shouldReleaseAssets)
    }

    @Test
    func ResourcePressureLevelShouldReleaseAnalyzer() {
        #expect(ResourcePressureLevel.normal.shouldReleaseAnalyzer == false)
        #expect(ResourcePressureLevel.elevated.shouldReleaseAnalyzer == false)
        #expect(ResourcePressureLevel.critical.shouldReleaseAnalyzer)
    }

    @Test
    func ResourcePressureLevelDescription() {
        #expect(ResourcePressureLevel.normal.description == "正常")
        #expect(ResourcePressureLevel.elevated.description == "升高")
        #expect(ResourcePressureLevel.critical.description == "临界")
    }

    // MARK: - Retention Decision Tests

    @Test
    func RetentionDecisionShouldReleaseAssets() {
        #expect(RetentionDecision.retainAll.shouldReleaseAssets == false)
        #expect(RetentionDecision.releaseAssetsOnly.shouldReleaseAssets)
        #expect(RetentionDecision.releaseAll.shouldReleaseAssets)
    }

    @Test
    func RetentionDecisionShouldReleaseAnalyzer() {
        #expect(RetentionDecision.retainAll.shouldReleaseAnalyzer == false)
        #expect(RetentionDecision.releaseAssetsOnly.shouldReleaseAnalyzer == false)
        #expect(RetentionDecision.releaseAll.shouldReleaseAnalyzer)
    }

    @Test
    func RetentionDecisionDescription() {
        #expect(RetentionDecision.retainAll.description == "保留所有资源")
        #expect(RetentionDecision.releaseAssetsOnly.description == "释放资产但保留分析器")
        #expect(RetentionDecision.releaseAll.description == "释放所有资源")
    }

    // MARK: - Retention Policy Configuration Tests

    @Test
    func DefaultConfiguration() {
        let config = RetentionPolicyConfiguration.default

        #expect(config.cpuElevatedThreshold == 30.0)
        #expect(config.cpuCriticalThreshold == 60.0)
        #expect(config.memoryElevatedThresholdMB == 300.0)
        #expect(config.memoryCriticalThresholdMB == 500.0)
        #expect(config.enableOnConstrainedDevices)
        #expect(config.assetReleaseTimeoutSeconds == 300.0)
        #expect(config.analyzerReleaseTimeoutSeconds == 600.0)
    }

    @Test
    func ConservativeConfiguration() {
        let config = RetentionPolicyConfiguration.conservative

        #expect(config.cpuElevatedThreshold == 20.0)
        #expect(config.cpuCriticalThreshold == 40.0)
        #expect(config.memoryElevatedThresholdMB == 200.0)
        #expect(config.memoryCriticalThresholdMB == 350.0)
        #expect(config.enableOnConstrainedDevices)
        #expect(config.assetReleaseTimeoutSeconds == 180.0)
        #expect(config.analyzerReleaseTimeoutSeconds == 300.0)
    }

    @Test
    func CustomConfiguration() {
        let config = RetentionPolicyConfiguration(
            cpuElevatedThreshold: 25.0,
            cpuCriticalThreshold: 50.0,
            memoryElevatedThresholdMB: 250.0,
            memoryCriticalThresholdMB: 400.0,
            enableOnConstrainedDevices: false,
            assetReleaseTimeoutSeconds: 120.0,
            analyzerReleaseTimeoutSeconds: 240.0
        )

        #expect(config.cpuElevatedThreshold == 25.0)
        #expect(config.cpuCriticalThreshold == 50.0)
        #expect(config.memoryElevatedThresholdMB == 250.0)
        #expect(config.memoryCriticalThresholdMB == 400.0)
        #expect(config.enableOnConstrainedDevices == false)
        #expect(config.assetReleaseTimeoutSeconds == 120.0)
        #expect(config.analyzerReleaseTimeoutSeconds == 240.0)
    }

    // MARK: - Model Retention Policy Tests

    @Test
    func PolicyInitializationWithExplicitDeviceTier() {
        let policy = ModelRetentionPolicy(
            configuration: .default,
            deviceTier: .appleSilicon
        )

        #expect(policy.currentDeviceTier == .appleSilicon)
        #expect(policy.isRetentionEnabled)
    }

    @Test
    func PolicyRetentionEnabledForAppleSilicon() {
        let policy = ModelRetentionPolicy(
            configuration: .default,
            deviceTier: .appleSilicon
        )

        #expect(policy.isRetentionEnabled)
    }

    @Test
    func PolicyRetentionEnabledForIntelWithConfig() {
        let config = RetentionPolicyConfiguration(
            enableOnConstrainedDevices: true
        )
        let policy = ModelRetentionPolicy(
            configuration: config,
            deviceTier: .intelOrConstrained
        )

        #expect(policy.isRetentionEnabled)
    }

    @Test
    func PolicyRetentionDisabledForIntelWithConfig() {
        let config = RetentionPolicyConfiguration(
            enableOnConstrainedDevices: false
        )
        let policy = ModelRetentionPolicy(
            configuration: config,
            deviceTier: .intelOrConstrained
        )

        #expect(policy.isRetentionEnabled == false)
    }

    @Test
    func PolicyRetentionDisabledForUnsupported() {
        let policy = ModelRetentionPolicy(
            configuration: .default,
            deviceTier: .unsupported
        )

        #expect(policy.isRetentionEnabled == false)
    }

    @Test
    func RecommendedConfigurationForAppleSilicon() {
        let policy = ModelRetentionPolicy(
            deviceTier: .appleSilicon
        )

        let config = policy.recommendedConfiguration
        #expect(config.cpuElevatedThreshold == 30.0)
    }

    @Test
    func RecommendedConfigurationForIntel() {
        let policy = ModelRetentionPolicy(
            deviceTier: .intelOrConstrained
        )

        let config = policy.recommendedConfiguration
        #expect(config.cpuElevatedThreshold == 20.0)
    }

    // MARK: - Evaluation Tests

    @Test
    func EvaluateNormalPressureAppleSilicon() {
        let policy = ModelRetentionPolicy(
            configuration: .default,
            deviceTier: .appleSilicon
        )

        let snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 10.0,
            memoryMB: 150.0
        )

        let decision = policy.evaluate(snapshot: snapshot)
        #expect(decision == .retainAll)
    }

    @Test
    func EvaluateElevatedPressureAppleSilicon() {
        let policy = ModelRetentionPolicy(
            configuration: .default,
            deviceTier: .appleSilicon
        )

        // Elevated CPU but not critical
        let snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 35.0,
            memoryMB: 150.0
        )

        let decision = policy.evaluate(snapshot: snapshot)
        // Apple Silicon can retain during elevated pressure
        #expect(decision == .retainAll)
    }

    @Test
    func EvaluateCriticalPressureAppleSilicon() {
        let policy = ModelRetentionPolicy(
            configuration: .default,
            deviceTier: .appleSilicon
        )

        let snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 65.0,
            memoryMB: 150.0
        )

        let decision = policy.evaluate(snapshot: snapshot)
        // Apple Silicon releases assets but keeps analyzer
        #expect(decision == .releaseAssetsOnly)
    }

    @Test
    func EvaluateCriticalMemoryPressureAppleSilicon() {
        let policy = ModelRetentionPolicy(
            configuration: .default,
            deviceTier: .appleSilicon
        )

        let snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 10.0,
            memoryMB: 550.0
        )

        let decision = policy.evaluate(snapshot: snapshot)
        // Critical memory pressure
        #expect(decision == .releaseAssetsOnly)
    }

    @Test
    func EvaluateNormalPressureIntel() {
        let policy = ModelRetentionPolicy(
            configuration: .default,
            deviceTier: .intelOrConstrained
        )

        let snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 10.0,
            memoryMB: 150.0
        )

        let decision = policy.evaluate(snapshot: snapshot)
        #expect(decision == .retainAll)
    }

    @Test
    func EvaluateElevatedPressureIntel() {
        let policy = ModelRetentionPolicy(
            configuration: .default,
            deviceTier: .intelOrConstrained
        )

        let snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 35.0,
            memoryMB: 350.0
        )

        let decision = policy.evaluate(snapshot: snapshot)
        // Intel releases assets during elevated pressure
        #expect(decision == .releaseAssetsOnly)
    }

    @Test
    func EvaluateCriticalPressureIntel() {
        let policy = ModelRetentionPolicy(
            configuration: .default,
            deviceTier: .intelOrConstrained
        )

        let snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 65.0,
            memoryMB: 550.0
        )

        let decision = policy.evaluate(snapshot: snapshot)
        // Intel does full release during critical pressure
        #expect(decision == .releaseAll)
    }

    @Test
    func EvaluateUnsupportedPlatform() {
        let policy = ModelRetentionPolicy(
            configuration: .default,
            deviceTier: .unsupported
        )

        let snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 10.0,
            memoryMB: 150.0
        )

        let decision = policy.evaluate(snapshot: snapshot)
        // Unsupported platforms always release all
        #expect(decision == .releaseAll)
    }

    // MARK: - Edge Cases

    @Test
    func EvaluateBoundaryConditions() {
        let policy = ModelRetentionPolicy(
            configuration: .default,
            deviceTier: .appleSilicon
        )

        // Exactly at elevated threshold
        var snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 30.0,
            memoryMB: 100.0
        )
        var decision = policy.evaluate(snapshot: snapshot)
        #expect(decision == .retainAll)

        // Just above elevated threshold
        snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 30.1,
            memoryMB: 100.0
        )
        decision = policy.evaluate(snapshot: snapshot)
        // Still retain on Apple Silicon during elevated pressure
        #expect(decision == .retainAll)

        // Exactly at critical threshold
        snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 60.0,
            memoryMB: 100.0
        )
        decision = policy.evaluate(snapshot: snapshot)
        // At critical threshold, should release assets
        #expect(decision == .releaseAssetsOnly)
    }

    @Test
    func MultiplePressureSources() {
        let policy = ModelRetentionPolicy(
            configuration: .default,
            deviceTier: .appleSilicon
        )

        // Both CPU and memory at elevated levels
        var snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 35.0,
            memoryMB: 350.0
        )
        var decision = policy.evaluate(snapshot: snapshot)
        // Elevated pressure on both - Apple Silicon can retain
        #expect(decision == .retainAll)

        // CPU critical, memory elevated
        snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 65.0,
            memoryMB: 350.0
        )
        decision = policy.evaluate(snapshot: snapshot)
        // Critical pressure - release assets
        #expect(decision == .releaseAssetsOnly)

        // Both critical
        snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 65.0,
            memoryMB: 550.0
        )
        decision = policy.evaluate(snapshot: snapshot)
        // Critical on both - release assets
        #expect(decision == .releaseAssetsOnly)
    }
}

// MARK: - Model Retention Policy Integration Tests

extension ModelRetentionPolicyTests {

    @Test
    func AppleSiliconNormalPressureRetainsAll() {
        let policy = ModelRetentionPolicy(
            configuration: .default,
            deviceTier: .appleSilicon
        )

        let snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 10.0,
            memoryMB: 150.0
        )

        let decision = policy.evaluate(snapshot: snapshot)
        #expect(decision == .retainAll)
    }

    @Test
    func AppleSiliconElevatedPressureRetainsAll() {
        let policy = ModelRetentionPolicy(
            configuration: .default,
            deviceTier: .appleSilicon
        )

        let snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 35.0,
            memoryMB: 150.0
        )

        let decision = policy.evaluate(snapshot: snapshot)
        // Apple Silicon can retain during elevated pressure
        #expect(decision == .retainAll)
    }

    @Test
    func AppleSiliconCriticalPressureReleasesAssets() {
        let policy = ModelRetentionPolicy(
            configuration: .default,
            deviceTier: .appleSilicon
        )

        let snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 65.0,
            memoryMB: 150.0
        )

        let decision = policy.evaluate(snapshot: snapshot)
        // Critical pressure - release assets but keep analyzer
        #expect(decision == .releaseAssetsOnly)
    }

    @Test
    func IntelNormalPressureRetainsAll() {
        let policy = ModelRetentionPolicy(
            configuration: .default,
            deviceTier: .intelOrConstrained
        )

        let snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 10.0,
            memoryMB: 150.0
        )

        let decision = policy.evaluate(snapshot: snapshot)
        #expect(decision == .retainAll)
    }

    @Test
    func IntelElevatedPressureReleasesAssets() {
        let policy = ModelRetentionPolicy(
            configuration: .default,
            deviceTier: .intelOrConstrained
        )

        let snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 35.0,
            memoryMB: 150.0
        )

        let decision = policy.evaluate(snapshot: snapshot)
        // Intel releases assets during elevated pressure
        #expect(decision == .releaseAssetsOnly)
    }

    @Test
    func IntelCriticalPressureReleasesAll() {
        let policy = ModelRetentionPolicy(
            configuration: .default,
            deviceTier: .intelOrConstrained
        )

        let snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 65.0,
            memoryMB: 150.0
        )

        let decision = policy.evaluate(snapshot: snapshot)
        // Critical pressure - full release
        #expect(decision == .releaseAll)
    }

    @Test
    func UnsupportedPlatformAlwaysReleasesAll() {
        let policy = ModelRetentionPolicy(
            configuration: .default,
            deviceTier: .unsupported
        )

        // Even with normal pressure
        let snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 10.0,
            memoryMB: 150.0
        )

        let decision = policy.evaluate(snapshot: snapshot)
        // Unsupported platforms always release all
        #expect(decision == .releaseAll)
    }

    @Test
    func MemoryPressureOnly() {
        let policy = ModelRetentionPolicy(
            configuration: .default,
            deviceTier: .appleSilicon
        )

        // Elevated memory only
        var snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 10.0,
            memoryMB: 350.0
        )
        var decision = policy.evaluate(snapshot: snapshot)
        #expect(decision == .retainAll)

        // Critical memory only
        snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 10.0,
            memoryMB: 550.0
        )
        decision = policy.evaluate(snapshot: snapshot)
        #expect(decision == .releaseAssetsOnly)
    }

    @Test
    func ConservativeConfigurationIntegration() {
        let policy = ModelRetentionPolicy(
            configuration: .conservative,
            deviceTier: .intelOrConstrained
        )

        // Just at conservative elevated threshold (20%)
        let snapshot = RuntimeResourceSnapshot(
            cpuUsagePercent: 21.0,
            memoryMB: 150.0
        )

        let decision = policy.evaluate(snapshot: snapshot)
        // Intel with elevated pressure releases assets
        #expect(decision == .releaseAssetsOnly)
    }
}
