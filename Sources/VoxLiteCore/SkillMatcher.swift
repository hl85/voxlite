import VoxLiteDomain

public struct SkillMatcher {
    public init() {}

    public func resolveSkillId(bundleId: String, category: AppCategory, matching: SkillMatchingConfig) -> String {
        if let exact = matching.bundleSkillMap[bundleId] {
            return exact
        }
        if let categoryMatch = matching.categorySkillMap[category] {
            return categoryMatch
        }
        return matching.defaultSkillId
    }
}
