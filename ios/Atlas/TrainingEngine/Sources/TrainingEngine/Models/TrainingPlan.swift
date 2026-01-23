// TrainingPlan.swift
// Training plan configuration supporting both AI-generated and user-defined workouts.

import Foundation

/// Schedule type for workout templates.
public enum ScheduleType: Codable, Sendable, Hashable {
    /// Fixed mapping of weekdays to templates.
    case fixedWeekday(mapping: [Int: WorkoutTemplateId]) // 1 = Sunday, 7 = Saturday
    
    /// Rotation through templates in order.
    case rotation(order: [WorkoutTemplateId])
    
    /// User chooses each day (no automatic scheduling).
    case manual
}

/// Configuration for deload behavior.
public struct DeloadConfig: Codable, Sendable, Hashable {
    /// Percentage to reduce load during deload (e.g., 0.10 = 10% reduction).
    public let intensityReduction: Double
    
    /// Number of sets to reduce (e.g., 1 = drop 1 set per exercise).
    public let volumeReduction: Int
    
    /// Scheduled deload every N weeks (nil = no scheduled deloads).
    public let scheduledDeloadWeeks: Int?
    
    /// Readiness threshold below which to consider deload.
    public let readinessThreshold: Int
    
    /// Consecutive low-readiness days required to trigger deload.
    public let lowReadinessDaysRequired: Int
    
    public init(
        intensityReduction: Double = 0.10,
        volumeReduction: Int = 1,
        scheduledDeloadWeeks: Int? = nil,
        readinessThreshold: Int = 50,
        lowReadinessDaysRequired: Int = 3
    ) {
        self.intensityReduction = max(0, min(0.5, intensityReduction))
        self.volumeReduction = max(0, min(3, volumeReduction))
        self.scheduledDeloadWeeks = scheduledDeloadWeeks
        self.readinessThreshold = max(0, min(100, readinessThreshold))
        self.lowReadinessDaysRequired = max(1, lowReadinessDaysRequired)
    }
    
    /// Default deload configuration.
    public static let `default` = DeloadConfig()
}

/// A complete training plan.
public struct TrainingPlan: Codable, Sendable, Hashable {
    /// Plan identifier.
    public let id: UUID
    
    /// Plan name.
    public let name: String
    
    /// All workout templates in this plan.
    public let templates: [WorkoutTemplateId: WorkoutTemplate]
    
    /// How templates are scheduled.
    public let schedule: ScheduleType
    
    /// Per-exercise progression policy overrides.
    /// Key is exercise ID, value is the policy to use.
    public let progressionPolicies: [String: ProgressionPolicyType]

    /// Per-exercise in-session adjustment policy overrides.
    /// Key is exercise ID, value is the in-session policy to use.
    public let inSessionPolicies: [String: InSessionAdjustmentPolicyType]
    
    /// Pool of exercises available for substitutions.
    public let substitutionPool: [Exercise]
    
    /// Deload configuration.
    public let deloadConfig: DeloadConfig?
    
    /// Load rounding policy.
    public let loadRoundingPolicy: LoadRoundingPolicy
    
    /// Creation timestamp.
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        name: String,
        templates: [WorkoutTemplateId: WorkoutTemplate],
        schedule: ScheduleType,
        progressionPolicies: [String: ProgressionPolicyType] = [:],
        inSessionPolicies: [String: InSessionAdjustmentPolicyType] = [:],
        substitutionPool: [Exercise] = [],
        deloadConfig: DeloadConfig? = .default,
        loadRoundingPolicy: LoadRoundingPolicy = .standardPounds,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.templates = templates
        self.schedule = schedule
        self.progressionPolicies = progressionPolicies
        self.inSessionPolicies = inSessionPolicies
        self.substitutionPool = substitutionPool
        self.deloadConfig = deloadConfig
        self.loadRoundingPolicy = loadRoundingPolicy
        self.createdAt = createdAt
    }
    
    /// All template IDs in this plan.
    public var templateIds: [WorkoutTemplateId] {
        Array(templates.keys)
    }
    
    /// Gets the rotation order if using rotation schedule.
    public var rotationOrder: [WorkoutTemplateId]? {
        if case .rotation(let order) = schedule {
            return order
        }
        return nil
    }
}

// MARK: - TrainingPlan Codable (backward compatible defaults)

extension TrainingPlan {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case templates
        case schedule
        case progressionPolicies
        case inSessionPolicies
        case substitutionPool
        case deloadConfig
        case loadRoundingPolicy
        case createdAt
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        
        // `Dictionary<UUID, T>` encodes to an array by default in JSON because keys aren't strings.
        // For interoperability, support BOTH:
        // - our native Swift Codable representation (`[WorkoutTemplateId: WorkoutTemplate]`)
        // - a string-keyed object representation (`[String: WorkoutTemplate]`)
        do {
            let stringKeyed = try container.decode([String: WorkoutTemplate].self, forKey: .templates)
            var mapped: [WorkoutTemplateId: WorkoutTemplate] = [:]
            mapped.reserveCapacity(stringKeyed.count)
            for (k, v) in stringKeyed {
                if let id = UUID(uuidString: k) {
                    mapped[id] = v
                }
            }
            self.templates = mapped
        } catch {
            self.templates = try container.decode([WorkoutTemplateId: WorkoutTemplate].self, forKey: .templates)
        }
        self.schedule = try container.decode(ScheduleType.self, forKey: .schedule)
        self.progressionPolicies = try container.decodeIfPresent([String: ProgressionPolicyType].self, forKey: .progressionPolicies) ?? [:]
        self.inSessionPolicies = try container.decodeIfPresent([String: InSessionAdjustmentPolicyType].self, forKey: .inSessionPolicies) ?? [:]
        self.substitutionPool = try container.decodeIfPresent([Exercise].self, forKey: .substitutionPool) ?? []
        self.deloadConfig = try container.decodeIfPresent(DeloadConfig.self, forKey: .deloadConfig)
        self.loadRoundingPolicy = try container.decodeIfPresent(LoadRoundingPolicy.self, forKey: .loadRoundingPolicy) ?? .standardPounds
        // Be tolerant to different JSON date formats (numeric Date vs ISO-8601 string).
        do {
            self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        } catch {
            if let raw = try container.decodeIfPresent(String.self, forKey: .createdAt) {
                let f = ISO8601DateFormatter()
                self.createdAt = f.date(from: raw) ?? Date()
            } else {
                self.createdAt = Date()
            }
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        
        // Prefer a JSON-friendly representation with string keys for template IDs.
        let stringKeyed = Dictionary(uniqueKeysWithValues: templates.map { ($0.key.uuidString, $0.value) })
        try container.encode(stringKeyed, forKey: .templates)
        try container.encode(schedule, forKey: .schedule)
        try container.encode(progressionPolicies, forKey: .progressionPolicies)
        try container.encode(inSessionPolicies, forKey: .inSessionPolicies)
        try container.encode(substitutionPool, forKey: .substitutionPool)
        try container.encodeIfPresent(deloadConfig, forKey: .deloadConfig)
        try container.encode(loadRoundingPolicy, forKey: .loadRoundingPolicy)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

// MARK: - ScheduleType Codable

extension ScheduleType {
    enum CodingKeys: String, CodingKey {
        case type
        case mapping
        case order
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "fixedWeekday":
            let mapping = try container.decode([Int: WorkoutTemplateId].self, forKey: .mapping)
            self = .fixedWeekday(mapping: mapping)
        case "rotation":
            let order = try container.decode([WorkoutTemplateId].self, forKey: .order)
            self = .rotation(order: order)
        case "manual":
            self = .manual
        default:
            self = .manual
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .fixedWeekday(let mapping):
            try container.encode("fixedWeekday", forKey: .type)
            try container.encode(mapping, forKey: .mapping)
        case .rotation(let order):
            try container.encode("rotation", forKey: .type)
            try container.encode(order, forKey: .order)
        case .manual:
            try container.encode("manual", forKey: .type)
        }
    }
}
