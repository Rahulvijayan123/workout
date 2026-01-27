import SwiftUI

// MARK: - Reasonableness Label View
/// Minimal prompt for collecting sparse reasonableness labels.
/// 
/// Design principles:
/// - One question only: "Was this recommendation reasonable?"
/// - Optional follow-up only if answer is "No"
/// - Fast to dismiss (skip always available)
/// - Non-intrusive, doesn't block workout flow

struct ReasonablenessLabelView: View {
    let request: PendingLabelRequest
    let onSubmit: (Bool, UnreasonableReason?, String?) -> Void
    let onSkip: () -> Void
    
    @State private var selectedAnswer: Bool?
    @State private var selectedReason: UnreasonableReason?
    @State private var comment: String = ""
    @State private var showFollowUp: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            headerSection
            
            // Context (what the engine recommended)
            contextCard
            
            // Primary question
            primaryQuestion
            
            // Follow-up (only if "No")
            if showFollowUp {
                followUpSection
            }
            
            // Actions
            actionButtons
        }
        .padding(24)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Quick Feedback")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text(triggerDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button(action: onSkip) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var triggerDescription: String {
        switch request.trigger {
        case .increaseRecommended:
            return "We recommended an increase"
        case .deloadRecommended:
            return "We recommended a deload"
        case .afterBreak:
            return "After your break"
        case .afterGrinder:
            return "After a tough set"
        case .afterFailedSet:
            return "After a missed rep target"
        case .acuteLowReadiness:
            return "Low readiness detected"
        case .substitutionChange:
            return "Exercise substitution"
        default:
            return "Your last recommendation"
        }
    }
    
    // MARK: - Context Card
    
    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(request.trajectory.exerciseName)
                .font(.subheadline.weight(.semibold))
            
            HStack(spacing: 16) {
                Label {
                    Text("\(Int(request.trajectory.prescribedWeightKg * 2.205)) lbs")
                } icon: {
                    Image(systemName: "scalemass")
                }
                .font(.caption)
                
                Label {
                    Text("\(request.trajectory.prescribedReps) reps")
                } icon: {
                    Image(systemName: "repeat")
                }
                .font(.caption)
                
                decisionBadge
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    private var decisionBadge: some View {
        let (text, color) = decisionInfo
        return Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
    
    private var decisionInfo: (String, Color) {
        switch request.trajectory.decisionType {
        case .increaseWeight:
            return ("Increase", .green)
        case .increaseReps:
            return ("Add Reps", .green)
        case .hold:
            return ("Hold", .blue)
        case .deload:
            return ("Deload", .orange)
        case .breakReset:
            return ("Reset", .purple)
        }
    }
    
    // MARK: - Primary Question
    
    private var primaryQuestion: some View {
        VStack(spacing: 12) {
            Text("Was this recommendation reasonable?")
                .font(.body.weight(.medium))
                .multilineTextAlignment(.center)
            
            HStack(spacing: 16) {
                answerButton(isYes: true)
                answerButton(isYes: false)
            }
        }
    }
    
    private func answerButton(isYes: Bool) -> some View {
        let isSelected = selectedAnswer == isYes
        
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedAnswer = isYes
                showFollowUp = !isYes
                if isYes {
                    selectedReason = nil
                }
            }
        } label: {
            HStack {
                Image(systemName: isYes ? "checkmark.circle.fill" : "xmark.circle.fill")
                Text(isYes ? "Yes" : "No")
            }
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isSelected ? (isYes ? Color.green : Color.red).opacity(0.15) : Color(.tertiarySystemBackground))
            .foregroundStyle(isSelected ? (isYes ? .green : .red) : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? (isYes ? Color.green : Color.red) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Follow-up Section
    
    private var followUpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What was wrong?")
                .font(.subheadline.weight(.medium))
            
            VStack(spacing: 8) {
                ForEach(UnreasonableReason.allCases, id: \.self) { reason in
                    reasonButton(reason)
                }
            }
            
            // Optional comment (collapsed by default)
            if selectedReason == .other {
                TextField("Tell us more (optional)", text: $comment, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    private func reasonButton(_ reason: UnreasonableReason) -> some View {
        let isSelected = selectedReason == reason
        
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedReason = reason
            }
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .red : .secondary)
                
                Text(reason.displayText)
                    .foregroundStyle(.primary)
                
                Spacer()
            }
            .font(.subheadline)
            .padding(12)
            .background(isSelected ? Color.red.opacity(0.08) : Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("Skip") {
                onSkip()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            
            Button {
                submitLabel()
            } label: {
                Text("Submit")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(canSubmit ? Color.accentColor : Color.gray.opacity(0.3))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .disabled(!canSubmit)
        }
    }
    
    private var canSubmit: Bool {
        guard let answer = selectedAnswer else { return false }
        if !answer && selectedReason == nil { return false }
        return true
    }
    
    private func submitLabel() {
        guard let answer = selectedAnswer else { return }
        onSubmit(
            answer,
            answer ? nil : selectedReason,
            comment.isEmpty ? nil : comment
        )
    }
}

// MARK: - Sheet Presentation Modifier

extension View {
    func reasonablenessLabelSheet(
        request: Binding<PendingLabelRequest?>,
        onSubmit: @escaping (Bool, UnreasonableReason?, String?) -> Void,
        onSkip: @escaping () -> Void
    ) -> some View {
        self.sheet(item: request) { req in
            ReasonablenessLabelView(
                request: req,
                onSubmit: { wasReasonable, reason, comment in
                    onSubmit(wasReasonable, reason, comment)
                    request.wrappedValue = nil
                },
                onSkip: {
                    onSkip()
                    request.wrappedValue = nil
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Compact Inline Version

struct ReasonablenessLabelInline: View {
    let exerciseName: String
    let decisionType: DecisionType
    let onYes: () -> Void
    let onNo: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Was this reasonable?")
                    .font(.caption.weight(.medium))
                Text(exerciseName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: onYes) {
                    Image(systemName: "hand.thumbsup.fill")
                        .font(.body)
                        .foregroundStyle(.green)
                }
                
                Button(action: onNo) {
                    Image(systemName: "hand.thumbsdown.fill")
                        .font(.body)
                        .foregroundStyle(.red)
                }
                
                Button(action: onSkip) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Preview

#Preview("Label Sheet") {
    ReasonablenessLabelView(
        request: PendingLabelRequest(
            id: UUID(),
            trajectory: EngineTrajectory(
                id: UUID(),
                userId: "test",
                sessionId: UUID(),
                decidedAt: Date(),
                exerciseId: "bench_press",
                exerciseName: "Barbell Bench Press",
                priorWorkingWeightKg: 90,
                priorE1RMKg: 100,
                priorFailureCount: 0,
                priorTrend: "improving",
                priorSuccessfulSessions: 5,
                daysSinceLastSession: 3,
                readinessScore: 75,
                wasBreakReturn: false,
                breakDurationDays: nil,
                setsTarget: 3,
                repRangeMin: 6,
                repRangeMax: 10,
                targetRIR: 2,
                incrementKg: 2.27,
                decisionType: .increaseWeight,
                prescribedWeightKg: 92.5,
                prescribedReps: 6,
                weightDeltaKg: 2.5,
                weightDeltaPercent: 2.8,
                isDeload: false,
                deloadReason: nil,
                deloadIntensityReductionPercent: nil,
                deloadVolumeReductionSets: nil,
                decisionReasons: ["hit_top_of_rep_range"],
                guardrailTriggered: false,
                guardrailType: nil,
                originalDecisionType: nil,
                originalPrescribedWeightKg: nil
            ),
            trigger: .increaseRecommended(delta: 5),
            promptAfter: Date(),
            expiresAt: Date().addingTimeInterval(86400),
            priority: 2
        ),
        onSubmit: { wasReasonable, reason, comment in
            print("Submitted: \(wasReasonable), \(reason?.rawValue ?? "none"), \(comment ?? "none")")
        },
        onSkip: {
            print("Skipped")
        }
    )
    .padding()
}

#Preview("Inline Label") {
    ReasonablenessLabelInline(
        exerciseName: "Barbell Squat",
        decisionType: .increaseWeight,
        onYes: {},
        onNo: {},
        onSkip: {}
    )
    .padding()
}
