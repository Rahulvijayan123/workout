// SubstitutionRanker.swift
// Deterministic substitution scoring and ranking.

import Foundation

/// Configuration for substitution ranking weights.
public struct SubstitutionRankingConfig: Codable, Sendable, Hashable {
    /// Weight for primary muscle overlap (0-1).
    public let primaryMuscleWeight: Double
    
    /// Weight for secondary muscle overlap (0-1).
    public let secondaryMuscleWeight: Double
    
    /// Weight for movement pattern similarity (0-1).
    public let movementPatternWeight: Double
    
    /// Weight for equipment availability (0-1).
    public let equipmentWeight: Double
    
    /// Bonus for exact equipment match.
    public let exactEquipmentBonus: Double
    
    public init(
        primaryMuscleWeight: Double = 0.40,
        secondaryMuscleWeight: Double = 0.15,
        movementPatternWeight: Double = 0.30,
        equipmentWeight: Double = 0.15,
        exactEquipmentBonus: Double = 0.05
    ) {
        self.primaryMuscleWeight = primaryMuscleWeight
        self.secondaryMuscleWeight = secondaryMuscleWeight
        self.movementPatternWeight = movementPatternWeight
        self.equipmentWeight = equipmentWeight
        self.exactEquipmentBonus = exactEquipmentBonus
    }
    
    /// Default configuration.
    public static let `default` = SubstitutionRankingConfig()
    
    /// Configuration prioritizing muscle overlap.
    public static let muscleFirst = SubstitutionRankingConfig(
        primaryMuscleWeight: 0.50,
        secondaryMuscleWeight: 0.20,
        movementPatternWeight: 0.20,
        equipmentWeight: 0.10,
        exactEquipmentBonus: 0.02
    )
    
    /// Configuration prioritizing movement pattern.
    public static let movementFirst = SubstitutionRankingConfig(
        primaryMuscleWeight: 0.30,
        secondaryMuscleWeight: 0.10,
        movementPatternWeight: 0.45,
        equipmentWeight: 0.15,
        exactEquipmentBonus: 0.05
    )
}

/// Deterministic substitution ranker.
/// Scores candidate exercises based on muscle overlap, movement pattern, and equipment.
public enum SubstitutionRanker {
    
    /// Ranks candidate exercises as substitutes for a given exercise.
    ///
    /// - Parameters:
    ///   - exercise: The exercise to find substitutes for.
    ///   - candidates: Pool of candidate exercises.
    ///   - availableEquipment: User's available equipment.
    ///   - maxResults: Maximum number of results to return.
    ///   - config: Ranking configuration.
    /// - Returns: Sorted array of substitutions (highest score first).
    public static func rank(
        for exercise: Exercise,
        candidates: [Exercise],
        availableEquipment: EquipmentAvailability,
        maxResults: Int = 5,
        config: SubstitutionRankingConfig = .default
    ) -> [Substitution] {
        // Filter out the original exercise and unavailable equipment
        let validCandidates = candidates.filter { candidate in
            candidate.id != exercise.id &&
            availableEquipment.isAvailable(candidate.equipment)
        }
        
        // Score each candidate
        var scoredCandidates: [(exercise: Exercise, score: Double, reasons: [SubstitutionReason])] = []
        
        for candidate in validCandidates {
            let (score, reasons) = computeScore(
                original: exercise,
                candidate: candidate,
                availableEquipment: availableEquipment,
                config: config
            )
            scoredCandidates.append((candidate, score, reasons))
        }
        
        // Sort by score descending, then by name for stable tie-breaking
        scoredCandidates.sort { lhs, rhs in
            if abs(lhs.score - rhs.score) > 0.001 {
                return lhs.score > rhs.score
            }
            return lhs.exercise.name < rhs.exercise.name
        }
        
        // Take top results
        let topCandidates = scoredCandidates.prefix(maxResults)
        
        return topCandidates.map { item in
            Substitution(
                exercise: item.exercise,
                score: item.score,
                reasons: item.reasons
            )
        }
    }
    
    /// Computes the substitution score for a candidate.
    private static func computeScore(
        original: Exercise,
        candidate: Exercise,
        availableEquipment: EquipmentAvailability,
        config: SubstitutionRankingConfig
    ) -> (score: Double, reasons: [SubstitutionReason]) {
        var reasons: [SubstitutionReason] = []
        var totalScore = 0.0
        
        // 1. Primary muscle overlap
        let primaryOverlap = computePrimaryMuscleOverlap(original: original, candidate: candidate)
        let primaryScore = primaryOverlap * config.primaryMuscleWeight
        totalScore += primaryScore
        
        if primaryOverlap > 0 {
            reasons.append(SubstitutionReason(
                category: .muscleOverlap,
                description: "Primary muscle overlap: \(Int(primaryOverlap * 100))%",
                score: primaryOverlap
            ))
        }
        
        // 2. Secondary muscle overlap
        let secondaryOverlap = computeSecondaryMuscleOverlap(original: original, candidate: candidate)
        let secondaryScore = secondaryOverlap * config.secondaryMuscleWeight
        totalScore += secondaryScore
        
        // 3. Movement pattern similarity
        let movementSimilarity = original.movementPattern.similarity(to: candidate.movementPattern)
        let movementScore = movementSimilarity * config.movementPatternWeight
        totalScore += movementScore
        
        if movementSimilarity > 0 {
            reasons.append(SubstitutionReason(
                category: .movementPattern,
                description: movementSimilarity == 1.0
                    ? "Same movement pattern"
                    : "Similar movement pattern (\(Int(movementSimilarity * 100))%)",
                score: movementSimilarity
            ))
        }
        
        // 4. Equipment availability (always available since we filtered)
        let equipmentAvailable = availableEquipment.isAvailable(candidate.equipment)
        let equipmentScore = equipmentAvailable ? config.equipmentWeight : 0
        totalScore += equipmentScore
        
        reasons.append(SubstitutionReason(
            category: .equipmentAvailable,
            description: "Equipment available: \(candidate.equipment.rawValue)",
            score: equipmentAvailable ? 1.0 : 0.0
        ))
        
        // 5. Exact equipment match bonus
        if candidate.equipment == original.equipment {
            totalScore += config.exactEquipmentBonus
            reasons.append(SubstitutionReason(
                category: .equipmentMatch,
                description: "Same equipment type",
                score: 1.0
            ))
        }
        
        // Normalize to 0-1 range
        let maxPossible = config.primaryMuscleWeight + config.secondaryMuscleWeight +
                         config.movementPatternWeight + config.equipmentWeight +
                         config.exactEquipmentBonus
        
        let normalizedScore = totalScore / maxPossible
        
        return (normalizedScore, reasons)
    }
    
    /// Computes primary muscle overlap score.
    private static func computePrimaryMuscleOverlap(
        original: Exercise,
        candidate: Exercise
    ) -> Double {
        let originalPrimary = Set(original.primaryMuscles)
        let candidatePrimary = Set(candidate.primaryMuscles)
        
        guard !originalPrimary.isEmpty else { return 0 }
        
        let intersection = originalPrimary.intersection(candidatePrimary)
        return Double(intersection.count) / Double(originalPrimary.count)
    }
    
    /// Computes secondary muscle overlap score.
    private static func computeSecondaryMuscleOverlap(
        original: Exercise,
        candidate: Exercise
    ) -> Double {
        let originalSecondary = Set(original.secondaryMuscles)
        let candidateSecondary = Set(candidate.secondaryMuscles)
        
        // Also consider primary-to-secondary and secondary-to-primary matches
        let candidatePrimary = Set(candidate.primaryMuscles)
        let originalPrimary = Set(original.primaryMuscles)
        
        // Secondary-to-secondary
        let s2s = originalSecondary.intersection(candidateSecondary)
        // Secondary-to-primary (candidate primary covers original secondary)
        let s2p = originalSecondary.intersection(candidatePrimary)
        // Primary-to-secondary (candidate secondary covers original primary)
        let p2s = originalPrimary.intersection(candidateSecondary)
        
        let totalMatches = s2s.count + s2p.count + p2s.count
        let maxPossible = originalSecondary.count + originalPrimary.count
        
        guard maxPossible > 0 else { return 0 }
        
        return min(1.0, Double(totalMatches) / Double(maxPossible))
    }
    
    /// Finds the best substitute from candidates.
    public static func findBestSubstitute(
        for exercise: Exercise,
        candidates: [Exercise],
        availableEquipment: EquipmentAvailability,
        minimumScore: Double = 0.5
    ) -> Substitution? {
        let ranked = rank(
            for: exercise,
            candidates: candidates,
            availableEquipment: availableEquipment,
            maxResults: 1
        )
        
        guard let best = ranked.first, best.score >= minimumScore else {
            return nil
        }
        
        return best
    }
    
    /// Checks if any valid substitutes exist.
    public static func hasValidSubstitutes(
        for exercise: Exercise,
        candidates: [Exercise],
        availableEquipment: EquipmentAvailability,
        minimumScore: Double = 0.3
    ) -> Bool {
        let ranked = rank(
            for: exercise,
            candidates: candidates,
            availableEquipment: availableEquipment,
            maxResults: 1
        )
        
        return ranked.first.map { $0.score >= minimumScore } ?? false
    }
}
