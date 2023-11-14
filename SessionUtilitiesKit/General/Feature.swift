// Copyright © 2023 Rangeproof Pty Ltd. All rights reserved.
//
// stringlint:disable

import Foundation

public final class Features {
    public static let legacyGroupDepricationDate: Date = Date.distantFuture         // TODO: Set this date
}

public extension FeatureStorage {
    static let debugDisappearingMessageDurations: FeatureConfig<Bool> = Dependencies.create(
        identifier: "debugDisappearingMessageDurations"
    )
    
    static let updatedDisappearingMessages: FeatureConfig<Bool> = Dependencies.create(
        identifier: "updatedDisappearingMessages",
        automaticChangeBehaviour: Feature<Bool>.ChangeBehaviour(
            value: true,
            condition: .after(timestamp: Date.distantFuture.timeIntervalSince1970)   // TODO: Set this date
        )
    )
    
    static let updatedGroups: FeatureConfig<Bool> = Dependencies.create(
        identifier: "updatedGroups",
        automaticChangeBehaviour: Feature<Bool>.ChangeBehaviour(
            value: true,
            condition: .after(timestamp: Features.legacyGroupDepricationDate.timeIntervalSince1970)
        )
    )
    
    static let updatedGroupsRemoveMessagesOnKick: FeatureConfig<Bool> = Dependencies.create(
        identifier: "updatedGroupsRemoveMessagesOnKick"
    )
    
    static let updatedGroupsAllowHistoricAccessOnInvite: FeatureConfig<Bool> = Dependencies.create(
        identifier: "updatedGroupsAllowHistoricAccessOnInvite"
    )
    
    static let updatedGroupsAllowDisplayPicture: FeatureConfig<Bool> = Dependencies.create(
        identifier: "updatedGroupsAllowDisplayPicture"
    )
    
    static let updatedGroupsAllowDescriptionEditing: FeatureConfig<Bool> = Dependencies.create(
        identifier: "updatedGroupsAllowDescriptionEditing"
    )
    
    static let updatedGroupsAllowPromotions: FeatureConfig<Bool> = Dependencies.create(
        identifier: "updatedGroupsAllowPromotions"
    )
}

// MARK: - FeatureOption

public protocol FeatureOption: RawRepresentable, CaseIterable, Equatable where RawValue == Int {
    associatedtype Events: FeatureEvent
    
    static var defaultOption: Self { get }
    
    var isValidOption: Bool { get }
    var title: String { get }
    var subtitle: String? { get }
}

public extension FeatureOption {
    var isValidOption: Bool { true }
}

// MARK: - FeatureEvent

public protocol FeatureEvent: Equatable, Hashable {
    static var updateValueEvent: Self { get }
}

// MARK: - FeatureType

public protocol FeatureType {}

// MARK: - Feature<T>

public struct Feature<T: FeatureOption>: FeatureType {
    public struct ChangeBehaviour {
        let value: T
        let condition: ChangeCondition
    }
    
    public indirect enum ChangeCondition {
        case after(timestamp: TimeInterval)
        case afterFork(hard: Int, soft: Int)
        
        case either(ChangeCondition, ChangeCondition)
        case both(ChangeCondition, ChangeCondition)
        
        static func after(date: Date) -> ChangeCondition { return .after(timestamp: date.timeIntervalSince1970) }
    }
    
    private let identifier: String
    public let options: [T]
    public let defaultOption: T
    public let automaticChangeBehaviour: ChangeBehaviour?
    
    // MARK: - Initialization
    
    public init(
        identifier: String,
        options: [T],
        defaultOption: T,
        automaticChangeBehaviour: ChangeBehaviour? = nil
    ) {
        guard T.self == Bool.self || !options.appending(defaultOption).contains(where: { $0.rawValue == 0 }) else {
            preconditionFailure("A rawValue of '0' is a protected value (it indicates unset)")
        }
        
        self.identifier = identifier
        self.options = options
        self.defaultOption = defaultOption
        self.automaticChangeBehaviour = automaticChangeBehaviour
    }
    
    // MARK: - Functions
    
    internal func currentValue(using dependencies: Dependencies) -> T {
        let selectedOption: Int = dependencies[defaults: .appGroup].integer(forKey: identifier)
        let maybeSelectedOption: T? = T(rawValue: selectedOption)
        
        /// If we have an explicitly set `selectedOption` then we should use that, otherwise we should check if any of the
        /// `automaticChangeBehaviour` conditions have been met, and if so use the specified value
        guard let selectedOption: T = maybeSelectedOption, selectedOption.isValidOption else {
            func automaticChangeConditionMet(_ condition: ChangeCondition) -> Bool {
                switch condition {
                    case .after(let timestamp): return (dependencies.dateNow.timeIntervalSince1970 >= timestamp)
                    
                    case .afterFork(let hard, let soft):
                        let currentHardFork: Int = dependencies[defaults: .standard, key: .hardfork]
                        let currentSoftFork: Int = dependencies[defaults: .standard, key: .softfork]
                        let currentVersion: Version = Version(major: currentHardFork, minor: currentSoftFork, patch: 0)
                        let requiredVersion: Version = Version(major: hard, minor: soft, patch: 0)
                        
                        return (requiredVersion >= currentVersion)

                    case .either(let firstCondition, let secondCondition):
                        return (
                            automaticChangeConditionMet(firstCondition) ||
                            automaticChangeConditionMet(secondCondition)
                        )
                        
                    case .both(let firstCondition, let secondCondition):
                        return (
                            automaticChangeConditionMet(firstCondition) &&
                            automaticChangeConditionMet(secondCondition)
                        )
                }
            }
            
            /// If the change conditions have been met then use the automatic value, otherwise use the default value
            guard
                let automaticChangeBehaviour: ChangeBehaviour = automaticChangeBehaviour,
                automaticChangeConditionMet(automaticChangeBehaviour.condition)
            else { return defaultOption }
            
            return automaticChangeBehaviour.value
        }
        
        /// We had an explicitly selected option so return that
        return selectedOption
    }
    
    internal func setValue(to updatedValue: T?, using dependencies: Dependencies) {
        dependencies[defaults: .appGroup].set(updatedValue?.rawValue, forKey: identifier)
    }
}

// MARK: - Convenience

public struct FeatureValue<R> {
    private let valueGenerator: (Dependencies) -> R
    
    public init<F: FeatureOption>(feature: FeatureConfig<F>, _ valueGenerator: @escaping (F) -> R) {
        self.valueGenerator = { [feature] dependencies in
            valueGenerator(dependencies[feature: feature])
        }
    }
    
    // MARK: - Functions
    
    public func value(using dependencies: Dependencies = Dependencies()) -> R {
        return valueGenerator(dependencies)
    }
}

// MARK: - Bool FeatureOption

extension Bool: FeatureOption {
    public static let allCases: [Bool] = [false, true]
    
    public enum Events: FeatureEvent {
        case updatedFlag
        
        public static var updateValueEvent: Events = .updatedFlag
    }
    
    // MARK: - Initialization
    
    public var rawValue: Int { return (self ? 1 : 0) }
    
    public init?(rawValue: Int) {
        self = (rawValue != 0)
    }
    
    // MARK: - Feature Option
    
    public static var defaultOption: Bool = false
    
    public var title: String {
        return (self ? "Enabled" : "Disabled")
    }
    
    public var subtitle: String? {
        return (self ? "Enabled" : "Disabled")
    }
}
