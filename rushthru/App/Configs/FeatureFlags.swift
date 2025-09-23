import Foundation

/// Represents the application bootstrap lifecycle. Used to drive developer-only
/// diagnostics UI as well as feature gating during initialization.
public enum BootState: Equatable {
    case coldStart
    case running
    case degraded(reason: String? = nil)

    public var isDegraded: Bool {
        if case .degraded = self { return true }
        return false
    }
}

/// Feature switches that can be toggled per build configuration. The enum can be
/// extended as new verticals land without changing the storage format.
public enum FeatureFlag: String, CaseIterable, Sendable {
    case capture
    case refill
    case search
    case csv
    case bulkCounts
    case locations
    case activityLog
}

/// Strongly-typed registry for feature toggles. In debug builds it is mutable so
/// that previews and unit tests can flip switches as needed. Release builds use the
/// static defaults defined per configuration.
public struct FeatureFlags: Sendable {
    public private(set) var enabledFlags: [FeatureFlag: Bool]
    public var bootState: BootState

    public init(
        bootState: BootState = .coldStart,
        enabledFlags: [FeatureFlag: Bool] = FeatureFlags.defaultFlagMap
    ) {
        self.bootState = bootState
        self.enabledFlags = enabledFlags
    }

    public mutating func setEnabled(_ isEnabled: Bool, for flag: FeatureFlag) {
        enabledFlags[flag] = isEnabled
    }

    public func isEnabled(_ flag: FeatureFlag) -> Bool {
        enabledFlags[flag, default: false]
    }
}

#if DEBUG
public extension FeatureFlags {
    static var preview: FeatureFlags {
        var flags = FeatureFlags(bootState: .running)
        FeatureFlag.allCases.forEach { flags.setEnabled(true, for: $0) }
        return flags
    }
}
#endif

public extension FeatureFlags {
    static let defaultFlagMap: [FeatureFlag: Bool] = {
        var defaults: [FeatureFlag: Bool] = [:]
        FeatureFlag.allCases.forEach { defaults[$0] = true }
        return defaults
    }()
}
