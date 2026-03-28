import VoxLiteDomain

/// 策略链注入器：按顺序尝试每个策略，首个成功即返回；全部失败返回最后结果
public final class InjectionStrategyChain: InjectionStrategyServing {
    public let strategies: [TextInjecting]

    public init(strategies: [TextInjecting]) {
        precondition(!strategies.isEmpty, "InjectionStrategyChain requires at least one strategy")
        self.strategies = strategies
    }

    public func injectText(_ text: String) -> InjectResult {
        var lastResult: InjectResult?
        for strategy in strategies {
            let result = strategy.injectText(text)
            if result.success {
                return result
            }
            lastResult = result
        }
        // precondition 保证 strategies 非空，lastResult 必有值
        return lastResult!
    }
}
