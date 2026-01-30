// PolicySelectorFactory.swift
// Factory for creating progression policy selectors based on mode.

import Foundation
import TrainingEngine

/// Mode for policy selection behavior.
public enum PolicySelectorMode: String, CaseIterable {
    /// Control mode: always baseline, no exploration or shadow logging.
    case control
    
    /// Shadow mode: execute baseline but log counterfactual shadow policy for offline evaluation.
    case shadow
    
    /// Explore mode: actually execute bandit-selected policies (Thompson sampling).
    case explore
}

/// Factory for creating progression policy selectors.
enum PolicySelectorFactory {
    
    /// UserDefaults key for persisting the selected mode.
    static let modeKey = "ironforge.policySelector.mode"
    
    /// Gets the current mode from UserDefaults (defaults to shadow).
    static func currentMode() -> PolicySelectorMode {
        guard let rawValue = UserDefaults.standard.string(forKey: modeKey),
              let mode = PolicySelectorMode(rawValue: rawValue) else {
            return .shadow // Default to shadow mode for data collection
        }
        return mode
    }
    
    /// Saves the mode to UserDefaults.
    static func setMode(_ mode: PolicySelectorMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: modeKey)
    }
    
    /// Creates a policy selector based on the specified mode.
    ///
    /// - Parameters:
    ///   - mode: The policy selection mode.
    ///   - stateStore: The bandit state store (used for shadow and explore modes).
    /// - Returns: A configured policy selector.
    static func make(
        mode: PolicySelectorMode,
        stateStore: BanditStateStore = UserDefaultsBanditStateStore.shared
    ) -> any ProgressionPolicySelector {
        switch mode {
        case .control:
            return ControlModePolicySelector.shared
            
        case .shadow:
            return ShadowModePolicySelector(stateStore: stateStore)
            
        case .explore:
            return ThompsonSamplingBanditPolicySelector(
                stateStore: stateStore,
                gateConfig: .default,
                isEnabled: true
            )
        }
    }
    
    /// Creates a policy selector using the persisted mode from UserDefaults.
    ///
    /// - Parameter stateStore: The bandit state store.
    /// - Returns: A configured policy selector.
    static func makeFromPersistedMode(
        stateStore: BanditStateStore = UserDefaultsBanditStateStore.shared
    ) -> any ProgressionPolicySelector {
        make(mode: currentMode(), stateStore: stateStore)
    }
}
