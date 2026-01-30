import SwiftUI
import TrainingEngine
import SwiftData

struct WorkoutsRootView: View {
    @EnvironmentObject var workoutStore: WorkoutStore
    @State private var showingTemplateEditor = false
    @State private var templateToEdit: WorkoutTemplate?
    
    var body: some View {
        NavigationStack {
            Group {
                if let session = workoutStore.activeSession {
                    WorkoutSessionView(session: session)
                } else {
                    WorkoutsDashboardView(
                        onCreateTemplate: {
                            templateToEdit = nil
                            showingTemplateEditor = true
                        },
                        onEditTemplate: { template in
                            templateToEdit = template
                            showingTemplateEditor = true
                        }
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showingTemplateEditor) {
            WorkoutBuilderView(template: templateToEdit) { result in
                switch result {
                case .created(let template):
                    workoutStore.createTemplate(name: template.name, exercises: template.exercises)
                case .updated(let template):
                    workoutStore.updateTemplate(template)
                case .cancelled:
                    break
                }
                showingTemplateEditor = false
                templateToEdit = nil
            }
        }
    }
}

// MARK: - Dashboard
private struct WorkoutsDashboardView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var workoutStore: WorkoutStore
    @Query(sort: \DailyBiometrics.date) private var dailyBiometrics: [DailyBiometrics]
    let onCreateTemplate: () -> Void
    let onEditTemplate: (WorkoutTemplate) -> Void
    
    @State private var selectedSession: WorkoutSession?
    
    // Pre-workout check-in state
    @State private var showingPreWorkoutCheckIn = false
    @State private var pendingTemplate: WorkoutTemplate?
    @State private var pendingSession: WorkoutSession?
    
    private var recentBiometrics: [DailyBiometrics] {
        Array(dailyBiometrics.suffix(60))
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // 1. THE VOID - Solid dark backdrop (glassmorphism needs contrast)
            Color.ironBackground
                .ignoresSafeArea()
            
            // 2. Content
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    
                    quickActions
                    
                    templatesSection
                    
                    historySection
                    
                    Spacer(minLength: 120)
                }
                // Force the scroll content to adopt the device width.
                // This prevents any background/glow views from making the layout wider than the screen.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        // 3. Ambient glow (pure background — cannot affect layout size)
        .background(
            AmbientGlowBackground()
                .ignoresSafeArea()
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            ChromaticText(
                text: "WORKOUTS",
                font: IronFont.header(28),
                offset: 0.8
            )
            .tracking(2)
            
            Text("Build templates, start sessions, and log sets.")
                .font(IronFont.body(15))
                .foregroundColor(.ironTextTertiary)
        }
    }
    
    private var quickActions: some View {
        Button {
            onCreateTemplate()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                Text("MAKE YOUR OWN TEMPLATE")
                    .font(IronFont.bodySemibold(13))
                    .tracking(1.5)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                ZStack {
                    // Frosted glass background
                    RoundedRectangle(cornerRadius: 27)
                        .fill(.ultraThinMaterial)
                        .opacity(0.6)
                    
                    // Dark tint
                    RoundedRectangle(cornerRadius: 27)
                        .fill(Color(red: 0.08, green: 0.08, blue: 0.1).opacity(0.7))
                    
                    // Dashed border pattern inside
                    RoundedRectangle(cornerRadius: 27)
                        .strokeBorder(
                            Color.white.opacity(0.15),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                        .padding(4)
                }
            )
            .overlay {
                RoundedRectangle(cornerRadius: 27)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.35), .white.opacity(0.12), Color.ironPurple.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
            .shadow(color: Color.ironPurple.opacity(0.25), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TEMPLATES")
                .font(IronFont.label(11))
                .tracking(2)
                .foregroundColor(.ironTextTertiary)
            
            if workoutStore.templates.isEmpty {
                Text("No templates yet. Tap above to create your own.")
                    .font(IronFont.body(14))
                    .foregroundColor(.ironTextTertiary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass()
            } else {
                // Vertical list of template cards (simpler, no overflow)
                VStack(spacing: 12) {
                    ForEach(workoutStore.templates) { template in
                        TemplateListCard(template: template) {
                            // Create a pending session for check-in
                            let readiness = ReadinessScoreCalculator.todayScore(from: recentBiometrics) ?? 75
                            pendingTemplate = template
                            // Pre-create session so check-in can modify it
                            let sessionPlan = TrainingEngineBridge.recommendSessionForTemplate(
                                date: Date(),
                                templateId: template.id,
                                userProfile: appState.userProfile,
                                templates: workoutStore.templates,
                                sessions: workoutStore.sessions,
                                liftStates: workoutStore.exerciseStates,
                                readiness: readiness,
                                dailyBiometrics: recentBiometrics,
                                policySelector: workoutStore.policySelector
                            )
                            pendingSession = TrainingEngineBridge.convertSessionPlanToUIModel(
                                sessionPlan,
                                templateId: template.id,
                                templateName: template.name,
                                computedReadinessScore: readiness,
                                exerciseStates: workoutStore.exerciseStates,
                                sessions: workoutStore.sessions
                            )
                            showingPreWorkoutCheckIn = true
                        } onEdit: {
                            onEditTemplate(template)
                        }
                    }
                }
            }
        }
    }
    
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECENT")
                .font(IronFont.label(11))
                .tracking(2)
                .foregroundColor(.ironTextTertiary)
            
            if workoutStore.sessions.isEmpty {
                DataStreamPlaceholder()
            } else {
                VStack(spacing: 10) {
                    ForEach(workoutStore.sessions.prefix(5)) { session in
                        SessionRow(session: session) {
                            selectedSession = session
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedSession) { session in
            SessionDetailView(session: session)
        }
        .sheet(isPresented: $showingPreWorkoutCheckIn) {
            if var session = pendingSession {
                PreWorkoutCheckInSheet(
                    session: Binding(
                        get: { session },
                        set: { session = $0 }
                    ),
                    neonPurple: .ironPurple,
                    onStart: {
                        // Apply check-in data and start session
                        workoutStore.activeSession = session
                        workoutStore.saveActiveSession()
                        showingPreWorkoutCheckIn = false
                        pendingTemplate = nil
                        pendingSession = nil
                    },
                    onCancel: {
                        // Skip check-in, start session without data
                        if let template = pendingTemplate {
                            let readiness = ReadinessScoreCalculator.todayScore(from: recentBiometrics) ?? 75
                            workoutStore.startSession(
                                from: template,
                                userProfile: appState.userProfile,
                                readiness: readiness,
                                dailyBiometrics: recentBiometrics
                            )
                        }
                        showingPreWorkoutCheckIn = false
                        pendingTemplate = nil
                        pendingSession = nil
                    }
                )
            }
        }
    }
}

// MARK: - Session Detail View
private struct SessionDetailView: View {
    let session: WorkoutSession
    @Environment(\.dismiss) private var dismiss
    
    private var duration: String {
        guard let endedAt = session.endedAt else { return "--" }
        let seconds = Int(endedAt.timeIntervalSince(session.startedAt))
        let minutes = seconds / 60
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
    
    private var totalSets: Int {
        session.exercises.reduce(0) { $0 + $1.sets.filter { $0.isCompleted }.count }
    }
    
    private var totalVolume: Double {
        session.exercises.reduce(0) { total, exercise in
            total + exercise.sets.filter { $0.isCompleted }.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.ironBackground
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // Summary Card
                        summaryCard
                        
                        // Exercises
                        exercisesSection
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle(session.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var summaryCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                summaryItem(title: "Duration", value: duration, icon: "clock.fill")
                summaryItem(title: "Sets", value: "\(totalSets)", icon: "number")
                summaryItem(title: "Volume", value: formatVolume(totalVolume), icon: "scalemass.fill")
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            HStack {
                Text(session.startedAt.formatted(date: .complete, time: .shortened))
                    .font(IronFont.body(13))
                    .foregroundColor(.ironTextTertiary)
                
                Spacer()
                
                if session.wasDeload {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Deload")
                    }
                    .font(IronFont.bodySemibold(12))
                    .foregroundColor(.orange)
                }
            }
        }
        .padding(18)
        .liquidGlass()
    }
    
    private func summaryItem(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.ironPurple)
            
            Text(value)
                .font(IronFont.headerMedium(18))
                .foregroundColor(.ironTextPrimary)
            
            Text(title)
                .font(IronFont.label(10))
                .foregroundColor(.ironTextTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EXERCISES")
                .font(IronFont.label(11))
                .tracking(2)
                .foregroundColor(.ironTextTertiary)
            
            VStack(spacing: 12) {
                ForEach(session.exercises) { exercise in
                    exerciseCard(exercise)
                }
            }
        }
    }
    
    private func exerciseCard(_ exercise: ExercisePerformance) -> some View {
        let completedSets = exercise.sets.filter { $0.isCompleted }
        let maxWeight = completedSets.map(\.weight).max() ?? 0
        let totalReps = completedSets.map(\.reps).reduce(0, +)
        
        return VStack(alignment: .leading, spacing: 12) {
            // Exercise header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.exercise.displayName.uppercased())
                        .font(IronFont.bodySemibold(15))
                        .tracking(1)
                        .foregroundColor(.ironTextPrimary)
                    
                    Text("\(exercise.exercise.target.capitalized) • \(exercise.exercise.equipment.capitalized)")
                        .font(IronFont.body(12))
                        .foregroundColor(.ironTextTertiary)
                }
                
                Spacer()
                
                // Completion badge
                if exercise.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.ironPurple)
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Summary stats
            HStack(spacing: 16) {
                statBadge(label: "Max", value: "\(formatWeight(maxWeight)) lb")
                statBadge(label: "Sets", value: "\(completedSets.count)")
                statBadge(label: "Reps", value: "\(totalReps)")
            }
            
            // Individual sets
            VStack(spacing: 6) {
                ForEach(Array(completedSets.enumerated()), id: \.offset) { index, set in
                    HStack {
                        Text("Set \(index + 1)")
                            .font(IronFont.body(12))
                            .foregroundColor(.ironTextTertiary)
                            .frame(width: 50, alignment: .leading)
                        
                        if set.isWarmup {
                            Text("WARMUP")
                                .font(IronFont.label(9))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange.opacity(0.2)))
                        }
                        
                        Spacer()
                        
                        Text("\(formatWeight(set.weight)) lb × \(set.reps)")
                            .font(IronFont.bodySemibold(13))
                            .foregroundColor(.ironTextPrimary)
                        
                        if let rpe = set.rpeObserved {
                            Text("RPE \(Int(rpe))")
                                .font(IronFont.body(11))
                                .foregroundColor(.ironTextTertiary)
                                .frame(width: 45, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .liquidGlass()
    }
    
    private func statBadge(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(IronFont.bodySemibold(14))
                .foregroundColor(.ironTextPrimary)
            Text(label)
                .font(IronFont.label(9))
                .foregroundColor(.ironTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
    }
    
    private func formatWeight(_ w: Double) -> String {
        if w == floor(w) { return "\(Int(w))" }
        return String(format: "%.1f", w)
    }
    
    private func formatVolume(_ v: Double) -> String {
        if v >= 1000 {
            return String(format: "%.1fk", v / 1000)
        }
        return "\(Int(v))"
    }
}

// MARK: - Template List Card (Mission Briefing Style)
private struct TemplateListCard: View {
    @EnvironmentObject var workoutStore: WorkoutStore
    let template: WorkoutTemplate
    let onStart: () -> Void
    let onEdit: () -> Void
    
    @State private var showingRenameAlert = false
    @State private var newName = ""
    
    private let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    
    // Estimate workout duration based on exercise count
    private var estimatedDuration: Int {
        max(20, template.exercises.count * 8)
    }
    
    // Determine workout type based on template name
    private var workoutType: WorkoutTargetType {
        let name = template.name.lowercased()
        if name.contains("push") || name.contains("chest") || name.contains("tricep") {
            return .push
        } else if name.contains("pull") || name.contains("back") || name.contains("bicep") {
            return .pull
        } else if name.contains("leg") || name.contains("squat") || name.contains("lower") {
            return .legs
        } else if name.contains("upper") {
            return .upper
        } else if name.contains("full") {
            return .fullBody
        } else if name.contains("arm") {
            return .arms
        } else if name.contains("shoulder") {
            return .shoulders
        } else {
            return .general
        }
    }
    
    // Training focus label
    private var trainingFocus: String {
        // Check exercises for rep ranges to determine focus
        let avgReps = template.exercises.isEmpty ? 8 : template.exercises.map { ($0.repRangeMin + $0.repRangeMax) / 2 }.reduce(0, +) / max(1, template.exercises.count)
        if avgReps <= 5 {
            return "STRENGTH"
        } else if avgReps <= 10 {
            return "HYPERTROPHY"
        } else {
            return "ENDURANCE"
        }
    }
    
    var body: some View {
        Button(action: onStart) {
            HStack(spacing: 14) {
                // Wireframe Target Icon (replaces play button)
                WorkoutTargetIcon(type: workoutType, neonPurple: neonPurple)
                
                // Template info with metadata chips
                VStack(alignment: .leading, spacing: 8) {
                    Text(template.name.uppercased())
                        .font(IronFont.bodySemibold(15))
                        .tracking(1)
                        .foregroundColor(.ironTextPrimary)
                        .lineLimit(1)
                    
                    // Metadata Chips Row
                    HStack(spacing: 6) {
                        MetadataChip(text: "\(estimatedDuration) MIN")
                        MetadataChip(text: "\(template.exercises.count) EXERCISES")
                    }
                }
                
                Spacer()
                
                // GO Chevron indicator
                HStack(spacing: 4) {
                    Text("GO")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1)
                        .foregroundColor(neonPurple)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(neonPurple)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(neonPurple.opacity(0.12))
                        .overlay(
                            Capsule()
                                .stroke(neonPurple.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .opacity(0.5)
                    
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(red: 0.06, green: 0.06, blue: 0.08).opacity(0.8))
                    
                    // Top glossy highlight
                    VStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.08), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .frame(height: 40)
                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.08),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Edit Template", systemImage: "pencil")
            }
            
            Button {
                newName = template.name
                showingRenameAlert = true
            } label: {
                Label("Rename", systemImage: "character.cursor.ibeam")
            }
            
            Button(role: .destructive) {
                workoutStore.deleteTemplate(template)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Rename Template", isPresented: $showingRenameAlert) {
            TextField("Template name", text: $newName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    var updatedTemplate = template
                    updatedTemplate.name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    workoutStore.updateTemplate(updatedTemplate)
                }
            }
        } message: {
            Text("Enter a new name for this template")
        }
    }
}

// MARK: - Workout Target Type
private enum WorkoutTargetType {
    case push, pull, legs, upper, fullBody, arms, shoulders, general
    
    // Highlighted body region for the figure
    var highlightOffset: CGPoint {
        switch self {
        case .push: return CGPoint(x: 0, y: -6)      // Chest area
        case .pull: return CGPoint(x: 0, y: -2)      // Back/upper torso
        case .legs: return CGPoint(x: 0, y: 12)      // Legs area
        case .upper: return CGPoint(x: 0, y: -4)     // Upper body
        case .fullBody: return CGPoint(x: 0, y: 2)   // Full body center
        case .arms: return CGPoint(x: -6, y: -2)     // Arms area
        case .shoulders: return CGPoint(x: 0, y: -8) // Shoulder area
        case .general: return CGPoint(x: 0, y: 0)    // Center
        }
    }
    
    var highlightSize: CGFloat {
        switch self {
        case .legs: return 20
        case .upper, .fullBody: return 24
        default: return 16
        }
    }
}

// MARK: - Workout Target Icon (Body Figure with Highlighted Region)
private struct WorkoutTargetIcon: View {
    let type: WorkoutTargetType
    let neonPurple: Color
    
    var body: some View {
        ZStack {
            // Glass container
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.03))
                .frame(width: 56, height: 56)
            
            // Inner glow based on type
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    RadialGradient(
                        colors: [neonPurple.opacity(0.15), neonPurple.opacity(0.05), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 35
                    )
                )
                .frame(width: 56, height: 56)
            
            // Border
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    LinearGradient(
                        colors: [neonPurple.opacity(0.5), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .frame(width: 56, height: 56)
            
            // Body figure with highlighted region
            ZStack {
                // Highlight glow behind the figure
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [neonPurple.opacity(0.8), neonPurple.opacity(0.3), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: type.highlightSize
                        )
                    )
                    .frame(width: type.highlightSize * 2, height: type.highlightSize * 2)
                    .offset(x: type.highlightOffset.x, y: type.highlightOffset.y)
                    .blur(radius: 4)
                
                // Base human figure (outline style)
                Image(systemName: "figure.stand")
                    .font(.system(size: 28, weight: .ultraLight))
                    .foregroundColor(.white.opacity(0.4))
                
                // Highlighted human figure overlay
                Image(systemName: "figure.stand")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [neonPurple, neonPurple.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .mask(
                        // Mask to show only the highlighted region
                        Circle()
                            .fill(Color.white)
                            .frame(width: type.highlightSize * 2.5, height: type.highlightSize * 2.5)
                            .offset(x: type.highlightOffset.x, y: type.highlightOffset.y)
                            .blur(radius: 6)
                    )
                    .shadow(color: neonPurple.opacity(0.6), radius: 4)
            }
        }
        .shadow(color: neonPurple.opacity(0.2), radius: 8)
    }
}

// MARK: - Metadata Chip
private struct MetadataChip: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.8)
            .foregroundColor(Color(red: 0.61, green: 0.64, blue: 0.69))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
    }
}

private struct SessionRow: View {
    let session: WorkoutSession
    let onTap: () -> Void
    
    private var totalSets: Int {
        session.exercises.reduce(0) { $0 + $1.sets.filter { $0.isCompleted }.count }
    }
    
    private var duration: String {
        guard let endedAt = session.endedAt else { return "--" }
        let seconds = Int(endedAt.timeIntervalSince(session.startedAt))
        let minutes = seconds / 60
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.ironPurple.opacity(0.18))
                        .frame(width: 46, height: 46)
                        .overlay(Circle().stroke(Color.ironPurple.opacity(0.35), lineWidth: 1))
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.ironPurple)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.name.uppercased())
                        .font(IronFont.bodySemibold(15))
                        .tracking(1)
                        .foregroundColor(.ironTextPrimary)
                    
                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(IronFont.body(13))
                        .foregroundColor(.ironTextTertiary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(duration)
                        .font(IronFont.bodySemibold(14))
                        .foregroundColor(.ironTextSecondary)
                    Text("\(totalSets) sets")
                        .font(IronFont.body(11))
                        .foregroundColor(.ironTextTertiary)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.ironTextTertiary)
            }
            .padding(14)
            .liquidGlass()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workout Builder (Template Editor)
private struct WorkoutBuilderView: View {
    enum Result {
        case created(WorkoutTemplate)
        case updated(WorkoutTemplate)
        case cancelled
    }
    
    @EnvironmentObject var workoutStore: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String
    @State private var exercises: [WorkoutTemplateExercise]
    @State private var showingPicker = false
    @State private var exerciseToEdit: WorkoutTemplateExercise?
    
    private let existingTemplate: WorkoutTemplate?
    private let onDone: (Result) -> Void
    
    init(template: WorkoutTemplate?, onDone: @escaping (Result) -> Void) {
        self.existingTemplate = template
        self.onDone = onDone
        _name = State(initialValue: template?.name ?? "")
        _exercises = State(initialValue: template?.exercises ?? [])
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(existingTemplate == nil ? "NEW TEMPLATE" : "EDIT TEMPLATE")
                        .font(IronFont.header(22))
                        .tracking(2)
                        .foregroundColor(.ironTextPrimary)
                    
                    LiquidGlassTextField(placeholder: "Template name", text: $name)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("EXERCISES")
                                .font(IronFont.label(11))
                                .tracking(2)
                                .foregroundColor(.ironTextTertiary)
                            Spacer()
                            Button {
                                showingPicker = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus")
                                    Text("ADD")
                                        .tracking(1)
                                }
                                .font(IronFont.bodySemibold(13))
                            }
                            .buttonStyle(NeonGlowButtonStyle(isPrimary: false))
                        }
                        
                        if exercises.isEmpty {
                            Text("Add exercises to build your template.")
                                .font(IronFont.body(14))
                                .foregroundColor(.ironTextTertiary)
                                .padding(16)
                                .liquidGlass()
                        } else {
                            VStack(spacing: 10) {
                                ForEach(exercises) { te in
                                    TemplateExerciseRow(
                                        templateExercise: te,
                                        onTap: {
                                            exerciseToEdit = te
                                        },
                                        onDelete: {
                                            exercises.removeAll { $0.id == te.id }
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 120)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDone(.cancelled)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || exercises.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView { picked in
                let ref = ExerciseRef(from: picked)
                exercises.append(WorkoutTemplateExercise(exercise: ref))
                showingPicker = false
            }
        }
        .sheet(item: $exerciseToEdit) { exercise in
            ExerciseSettingsView(
                templateExercise: exercise,
                onSave: { updated in
                    if let idx = exercises.firstIndex(where: { $0.id == updated.id }) {
                        exercises[idx] = updated
                    }
                    exerciseToEdit = nil
                },
                onCancel: {
                    exerciseToEdit = nil
                }
            )
        }
    }
    
    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        
        if var existing = existingTemplate {
            existing.name = cleanName
            existing.exercises = exercises
            onDone(.updated(existing))
        } else {
            let new = WorkoutTemplate(name: cleanName, exercises: exercises)
            onDone(.created(new))
        }
        dismiss()
    }
}

// MARK: - Template Exercise Row (Compact)
private struct TemplateExerciseRow: View {
    let templateExercise: WorkoutTemplateExercise
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(templateExercise.exercise.displayName.uppercased())
                        .font(IronFont.bodySemibold(14))
                        .tracking(1)
                        .foregroundColor(.ironTextPrimary)
                    
                    Text("\(templateExercise.exercise.target.capitalized) • \(templateExercise.exercise.equipment.capitalized)")
                        .font(IronFont.body(12))
                        .foregroundColor(.ironTextTertiary)
                    
                    // Settings summary
                    Text("\(templateExercise.setsTarget) sets • \(templateExercise.repRangeMin)-\(templateExercise.repRangeMax) reps")
                        .font(IronFont.body(11))
                        .foregroundColor(.ironTextSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.ironTextTertiary)
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.8))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .liquidGlass()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Exercise Settings View (Full Settings Editor)
private struct ExerciseSettingsView: View {
    @State private var templateExercise: WorkoutTemplateExercise
    let onSave: (WorkoutTemplateExercise) -> Void
    let onCancel: () -> Void
    
    @State private var repGoal: RepGoal
    
    init(templateExercise: WorkoutTemplateExercise, onSave: @escaping (WorkoutTemplateExercise) -> Void, onCancel: @escaping () -> Void) {
        _templateExercise = State(initialValue: templateExercise)
        self.onSave = onSave
        self.onCancel = onCancel
        
        // Pick a sensible default based on the existing rep range.
        let lb = templateExercise.repRangeMin
        let ub = max(lb, templateExercise.repRangeMax)
        if lb <= 4 || ub <= 6 {
            _repGoal = State(initialValue: .strength)
        } else if lb >= 10 {
            _repGoal = State(initialValue: .endurance)
        } else {
            _repGoal = State(initialValue: .hypertrophy)
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text(templateExercise.exercise.displayName.uppercased())
                            .font(IronFont.header(20))
                            .tracking(2)
                            .foregroundColor(.ironTextPrimary)
                        
                        Text("\(templateExercise.exercise.target.capitalized) • \(templateExercise.exercise.equipment.capitalized)")
                            .font(IronFont.body(14))
                            .foregroundColor(.ironTextTertiary)
                    }
                    
                    // Volume (minimal required input)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("VOLUME")
                            .font(IronFont.label(11))
                            .tracking(2)
                            .foregroundColor(.ironTextTertiary)
                        
                        VStack(spacing: 10) {
                            StepperField(title: "Sets", value: $templateExercise.setsTarget, range: 1...10)
                        }
                        .padding(14)
                        .liquidGlass()
                    }
                    
                    // Rep goal presets (keeps UI simple; sets min/max for the engine)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("REP GOAL")
                            .font(IronFont.label(11))
                            .tracking(2)
                            .foregroundColor(.ironTextTertiary)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    goalChip(.strength)
                                    goalChip(.hypertrophy)
                                    goalChip(.endurance)
                                }
                                .padding(.vertical, 2)
                            }
                            
                            Text("\(templateExercise.repRangeMin)–\(max(templateExercise.repRangeMin, templateExercise.repRangeMax)) reps")
                                .font(IronFont.body(13))
                                .foregroundColor(.ironTextSecondary)
                        }
                        .padding(14)
                        .liquidGlass()
                    }
                    
                    // Info Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.ironPurple)
                            Text("How Progression Works")
                                .font(IronFont.bodySemibold(14))
                                .foregroundColor(.ironTextPrimary)
                        }
                        
                        Text("Templates only define structure (sets + rep goal). During the workout you’ll log weight + reps, then rate how hard the set felt.")
                            .font(IronFont.body(13))
                            .foregroundColor(.ironTextTertiary)
                            .lineSpacing(3)
                    }
                    .padding(14)
                    .liquidGlass()
                    
                    Spacer(minLength: 120)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }
            .navigationTitle("Template Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // Validate rep range
                        if templateExercise.repRangeMin > templateExercise.repRangeMax {
                            templateExercise.repRangeMax = templateExercise.repRangeMin
                        }
                        onSave(templateExercise)
                    }
                }
            }
        }
    }
    
    private enum RepGoal: String, CaseIterable {
        case strength
        case hypertrophy
        case endurance
        
        var title: String {
            switch self {
            case .strength: return "Strength"
            case .hypertrophy: return "Hypertrophy"
            case .endurance: return "Endurance"
            }
        }
        
        var icon: String {
            switch self {
            case .strength: return "bolt.fill"
            case .hypertrophy: return "circle.grid.2x2.fill"
            case .endurance: return "waveform.path.ecg"
            }
        }
        
        var range: ClosedRange<Int> {
            switch self {
            case .strength: return 3...6
            case .hypertrophy: return 6...10
            case .endurance: return 10...15
            }
        }
    }
    
    private func goalChip(_ goal: RepGoal) -> some View {
        SelectionChip(
            title: goal.title,
            icon: goal.icon,
            isSelected: repGoal == goal
        ) {
            repGoal = goal
            templateExercise.repRangeMin = goal.range.lowerBound
            templateExercise.repRangeMax = goal.range.upperBound
        }
    }
}

private struct DeloadFactorField: View {
    @Binding var value: Double
    
    private let options: [(label: String, value: Double)] = [
        ("95%", 0.95),
        ("90%", 0.90),
        ("85%", 0.85),
        ("80%", 0.80)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DELOAD FACTOR")
                .font(IronFont.label(9))
                .tracking(1.2)
                .foregroundColor(.ironTextTertiary)
            
            HStack(spacing: 8) {
                ForEach(options, id: \.value) { option in
                    Button {
                        value = option.value
                    } label: {
                        Text(option.label)
                            .font(IronFont.bodySemibold(13))
                            .foregroundColor(value == option.value ? .white : .ironTextSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background {
                                Capsule()
                                    .fill(value == option.value ? Color.ironPurple : Color.glassWhite)
                            }
                            .overlay {
                                Capsule()
                                    .stroke(value == option.value ? Color.ironPurple.opacity(0.6) : Color.glassBorder, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct StepperField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(IronFont.label(9))
                .tracking(1.2)
                .foregroundColor(.ironTextTertiary)
            
            Stepper(value: $value, in: range) {
                Text("\(value)")
                    .font(IronFont.bodySemibold(14))
                    .foregroundColor(.ironTextPrimary)
                    .frame(minWidth: 28, alignment: .leading)
            }
            .tint(.ironPurple)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Exercise Picker
private struct ExercisePickerView: View {
    @EnvironmentObject var workoutStore: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    
    let onPick: (Exercise) -> Void
    
    @State private var query: String = ""
    @State private var results: [Exercise] = []
    @State private var isSearching: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                LiquidGlassTextField(placeholder: "Search exercises (bench, squat, pull...)", text: $query)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                
                if isSearching {
                    ProgressView()
                        .tint(.ironPurple)
                        .padding(.top, 24)
                } else if results.isEmpty {
                    Text("No matches. Try a different search.")
                        .font(IronFont.body(14))
                        .foregroundColor(.ironTextTertiary)
                        .padding(.top, 24)
                } else {
                    List {
                        ForEach(results) { ex in
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(ex.displayName.uppercased())
                                        .font(IronFont.bodySemibold(14))
                                        .tracking(1)
                                        .foregroundColor(.ironTextPrimary)
                                    
                                    Text("\(ex.displayTarget) • \(ex.displayEquipment)")
                                        .font(IronFont.body(12))
                                        .foregroundColor(.ironTextTertiary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.ironPurple)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onPick(ex)
                                dismiss()
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear { performSearch() }
        .onChange(of: query) { _, _ in performSearch() }
    }
    
    private func performSearch() {
        let q = query
        isSearching = true
        Task {
            let found = await workoutStore.exerciseRepository.search(query: q)
            await MainActor.run {
                results = found
                isSearching = false
            }
        }
    }
}

// MARK: - Session View (Exercise List with Navigation to Logging)
private struct WorkoutSessionView: View {
    @EnvironmentObject var workoutStore: WorkoutStore
    
    @State var session: WorkoutSession
    @State private var showingPicker = false
    @State private var showingFinishConfirm = false
    @State private var selectedExerciseIndex: Int?
    @State private var isEditMode = false
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                sessionHeader
                
                Button {
                    showingPicker = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                        Text("ADD EXERCISE")
                            .tracking(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(NeonGlowButtonStyle(isPrimary: false))
                
                if session.exercises.isEmpty {
                    Text("Add exercises, then log sets/reps/weight.")
                        .font(IronFont.body(14))
                        .foregroundColor(.ironTextTertiary)
                        .padding(16)
                        .liquidGlass()
                } else {
                    // Edit mode toggle
                    if session.exercises.count > 1 {
                        HStack {
                            Spacer()
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    isEditMode.toggle()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: isEditMode ? "checkmark" : "arrow.up.arrow.down")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(isEditMode ? "DONE" : "REORDER")
                                        .font(IronFont.label(10))
                                        .tracking(1)
                                }
                                .foregroundColor(.ironPurple)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color.ironPurple.opacity(0.12))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(Color.ironPurple.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.bottom, 4)
                    }
                    
                    VStack(spacing: 12) {
                        ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, exercise in
                            HStack(spacing: 12) {
                                // Drag handle in edit mode
                                if isEditMode {
                                    VStack(spacing: 4) {
                                        Button {
                                            moveExercise(from: index, direction: -1)
                                        } label: {
                                            Image(systemName: "chevron.up")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(index == 0 ? .white.opacity(0.2) : .ironPurple)
                                        }
                                        .disabled(index == 0)
                                        
                                        Button {
                                            moveExercise(from: index, direction: 1)
                                        } label: {
                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(index == session.exercises.count - 1 ? .white.opacity(0.2) : .ironPurple)
                                        }
                                        .disabled(index == session.exercises.count - 1)
                                    }
                                    .frame(width: 30)
                                }
                                
                                SessionExerciseRow(
                                    exercise: exercise,
                                    onTap: {
                                        if !isEditMode {
                                            selectedExerciseIndex = index
                                        }
                                    }
                                )
                                
                                // Delete button in edit mode
                                if isEditMode {
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            removeExercise(at: index)
                                        }
                                    } label: {
                                        Image(systemName: "trash.fill")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.red.opacity(0.8))
                                            .frame(width: 44, height: 44)
                                            .background(
                                                Circle()
                                                    .fill(Color.red.opacity(0.15))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                
                Spacer(minLength: 120)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    workoutStore.cancelActiveSession()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Finish") {
                    showingFinishConfirm = true
                }
                .disabled(session.exercises.isEmpty)
            }
        }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView { picked in
                workoutStore.addExerciseToActiveSession(ExerciseRef(from: picked))
                if let s = workoutStore.activeSession {
                    session = s
                }
                showingPicker = false
            }
        }
        .sheet(item: Binding(
            get: { selectedExerciseIndex.map { SelectedExerciseIndex(index: $0) } },
            set: { selectedExerciseIndex = $0?.index }
        )) { selected in
            ExerciseLoggingView(
                session: $session,
                exerciseIndex: selected.index,
                workoutStore: workoutStore
            )
        }
        .sheet(isPresented: $showingFinishConfirm) {
            PostWorkoutSummarySheet(
                session: $session,
                neonPurple: .ironPurple,
                onFinish: {
                    workoutStore.updateActiveSession(session)
                    workoutStore.finishActiveSession()
                    showingFinishConfirm = false
                },
                onCancel: {
                    showingFinishConfirm = false
                }
            )
        }
        .onChange(of: session) { _, newValue in
            workoutStore.updateActiveSession(newValue)
        }
    }
    
    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SESSION")
                .font(IronFont.label(11))
                .tracking(2)
                .foregroundColor(.ironTextTertiary)
            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened).uppercased())
                .font(IronFont.bodySemibold(14))
                .tracking(1)
                .foregroundColor(.ironTextSecondary)
        }
    }
    
    // MARK: - Exercise Management
    
    private func moveExercise(from index: Int, direction: Int) {
        let newIndex = index + direction
        guard newIndex >= 0 && newIndex < session.exercises.count else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            session.exercises.swapAt(index, newIndex)
            workoutStore.updateActiveSession(session)
        }
    }
    
    private func removeExercise(at index: Int) {
        guard index >= 0 && index < session.exercises.count else { return }
        session.exercises.remove(at: index)
        workoutStore.updateActiveSession(session)
        
        // Exit edit mode if no exercises left or only one
        if session.exercises.count <= 1 {
            isEditMode = false
        }
    }
}

// Helper for sheet item binding
private struct SelectedExerciseIndex: Identifiable {
    let index: Int
    var id: Int { index }
}

// MARK: - Session Exercise Row (Compact)
private struct SessionExerciseRow: View {
    let exercise: ExercisePerformance
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Completion indicator
                ZStack {
                    Circle()
                        .fill(exercise.isCompleted ? Color.ironPurple.opacity(0.18) : Color.glassWhite)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(exercise.isCompleted ? Color.ironPurple.opacity(0.35) : Color.glassBorder, lineWidth: 1))
                    
                    Image(systemName: exercise.isCompleted ? "checkmark" : "dumbbell.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(exercise.isCompleted ? .ironPurple : .ironTextTertiary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.exercise.displayName.uppercased())
                        .font(IronFont.bodySemibold(14))
                        .tracking(1)
                        .foregroundColor(.ironTextPrimary)
                    
                    Text("\(exercise.setsTarget)x\(exercise.repRangeMin)-\(exercise.repRangeMax) • \(completionSummary)")
                        .font(IronFont.body(12))
                        .foregroundColor(.ironTextTertiary)
                }
                
                Spacer()
                
                // Completion pill
                Text("\(exercise.sets.filter(\.isCompleted).count)/\(exercise.sets.count)")
                    .font(IronFont.label(10))
                    .tracking(1)
                    .foregroundColor(exercise.isCompleted ? .white : .ironTextSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        Capsule()
                            .fill(exercise.isCompleted ? Color.ironPurple : Color.glassWhite)
                    }
                    .overlay {
                        Capsule()
                            .stroke(exercise.isCompleted ? Color.ironPurple.opacity(0.6) : Color.glassBorder, lineWidth: 1)
                    }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.ironTextTertiary)
            }
            .padding(14)
            .liquidGlass()
        }
        .buttonStyle(.plain)
    }
    
    private var completionSummary: String {
        let completed = exercise.sets.filter(\.isCompleted)
        if completed.isEmpty {
            return "Not started"
        }
        let avgWeight = completed.map(\.weight).reduce(0, +) / Double(completed.count)
        return "\(formatWeight(avgWeight)) lb"
    }
    
    private func formatWeight(_ w: Double) -> String {
        if w == floor(w) { return "\(Int(w))" }
        return String(format: "%.1f", w)
    }
}

// MARK: - Exercise Logging View (Full Set Editor)
private struct ExerciseLoggingView: View {
    @Binding var session: WorkoutSession
    let exerciseIndex: Int
    let workoutStore: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var animatePulse = false
    @FocusState private var isWeightFieldFocused: Bool
    
    private var exercise: ExercisePerformance {
        session.exercises[exerciseIndex]
    }
    
    /// How many prior workouts (completed sessions) we have for this exercise with at least one
    /// completed *working* set (non-warmup, weight > 0). Used to gate recommendations on cold start.
    private var priorLoggedWorkoutsCount: Int {
        let history = workoutStore.performanceHistory(for: exercise.exercise.id, limit: 10)
        return history.filter { perf in
            perf.sets.contains(where: { $0.isCompleted && !$0.isWarmup && $0.weight > 0 })
        }.count
    }
    
    private var hasEnoughHistoryForSuggestions: Bool {
        priorLoggedWorkoutsCount >= 2
    }
    
    private let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    private let goldLight = Color(red: 1.0, green: 0.9, blue: 0.5)
    private let goldMid = Color(red: 0.95, green: 0.75, blue: 0.25)
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Deep charcoal background matching home page
                Color(red: 0.02, green: 0.02, blue: 0.02)
                    .ignoresSafeArea()
                
                // Ambient glow blobs
                GeometryReader { geo in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [neonPurple.opacity(0.25), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 200
                            )
                        )
                        .frame(width: 400, height: 400)
                        .offset(x: geo.size.width * 0.5, y: -100)
                        .blur(radius: 60)
                    
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(red: 0.1, green: 0.3, blue: 0.7).opacity(0.15), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 150
                            )
                        )
                        .frame(width: 300, height: 300)
                        .offset(x: -50, y: geo.size.height * 0.6)
                        .blur(radius: 40)
                }
                .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // Premium Header
                        exerciseHeader
                        
                        // Comparison Cards - Last Session vs This Week
                        comparisonSection
                        
                        // Log Your Sets Section
                        setsSection
                        
                        // Action Buttons
                        actionButtons
                        
                        // Post-completion prescription
                        if let snapshot = exercise.nextPrescription {
                            calibrationResultCard(snapshot: snapshot)
                        }
                        
                        Spacer(minLength: 120)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isWeightFieldFocused = false
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(neonPurple)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                animatePulse = true
            }
        }
    }
    
    // MARK: - Premium Header
    private var exerciseHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(exercise.exercise.displayName.uppercased())
                .font(IronFont.header(24))
                .tracking(2)
                .foregroundColor(.white)
            
            HStack(spacing: 12) {
                Label(exercise.exercise.target.capitalized, systemImage: "figure.strengthtraining.traditional")
                    .font(IronFont.body(12))
                    .foregroundColor(.white.opacity(0.5))
                
                Text("•")
                    .foregroundColor(.white.opacity(0.3))
                
                Label(exercise.exercise.equipment.capitalized, systemImage: "dumbbell.fill")
                    .font(IronFont.body(12))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
    
    // MARK: - Comparison Section (Last Session vs This Week)
    private var comparisonSection: some View {
        // On first-time logging, don't show a "comparison" that implies a recommendation.
        // We show a calibration card instead.
        if workoutStore.lastPerformance(for: exercise.exercise.id) == nil {
            return AnyView(thisWeekCard)
        }
        
        return AnyView(
            VStack(spacing: 14) {
                // Last Session Card
                lastSessionCard
                
                // Arrow indicator
                Image(systemName: "arrow.down")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(neonPurple.opacity(0.6))
                
                // This Week Try Card (highlighted)
                thisWeekCard
            }
        )
    }
    
    private var lastSessionCard: some View {
        let lastPerformance = workoutStore.lastPerformance(for: exercise.exercise.id)
        let lastCompleted = lastPerformance?.sets.filter(\.isCompleted) ?? []
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(goldMid.opacity(0.8))
                
                Text("LAST SESSION")
                    .font(IronFont.label(11))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.5))
                
                Spacer()
            }
            
            if !lastCompleted.isEmpty {
                let avgWeight = lastCompleted.map(\.weight).reduce(0, +) / Double(lastCompleted.count)
                let avgReps = lastCompleted.map(\.reps).reduce(0, +) / lastCompleted.count
                
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(formatWeight(avgWeight))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                    
                    Text("lb")
                        .font(IronFont.body(14))
                        .foregroundColor(.white.opacity(0.4))
                    
                    Text("×")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.horizontal, 4)
                    
                    Text("\(avgReps)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                    
                    Text("reps")
                        .font(IronFont.body(14))
                        .foregroundColor(.white.opacity(0.4))
                }
                
                Text("\(lastCompleted.count) sets completed")
                    .font(IronFont.body(12))
                    .foregroundColor(.white.opacity(0.35))
            } else {
                Text("No previous session")
                    .font(IronFont.body(15))
                    .foregroundColor(.white.opacity(0.4))
                
                Text("This is your first time logging this exercise")
                    .font(IronFont.body(12))
                    .foregroundColor(.white.opacity(0.25))
            }
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .opacity(0.5)
                
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.1).opacity(0.8))
                
                // Top glossy highlight
                VStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.08), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .frame(height: 50)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    private var thisWeekCard: some View {
        let state = workoutStore.getExerciseState(for: exercise.exercise.id)
        let targetWeight = state?.currentWorkingWeight ?? 0
        let calibratingStep = min(2, priorLoggedWorkoutsCount + 1)
        let isReady = hasEnoughHistoryForSuggestions && targetWeight > 0
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                // Pulsing indicator
                ZStack {
                    Circle()
                        .fill(neonPurple.opacity(0.3))
                        .frame(width: 10, height: 10)
                        .scaleEffect(animatePulse ? 1.8 : 1.0)
                        .opacity(animatePulse ? 0 : 0.8)
                    
                    Circle()
                        .fill(neonPurple)
                        .frame(width: 8, height: 8)
                }
                
                Text(isReady ? "THIS WEEK TRY" : "CALIBRATING")
                    .font(IronFont.label(11))
                    .tracking(2)
                    .foregroundColor(neonPurple)
                
                Spacer()
                
                if isReady {
                    // Ready badge
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(red: 0.3, green: 1, blue: 0.5))
                            .frame(width: 5, height: 5)
                        Text("READY")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1)
                            .foregroundColor(Color(red: 0.3, green: 1, blue: 0.5))
                    }
                } else {
                    // Calibration badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(goldMid.opacity(0.8))
                            .frame(width: 5, height: 5)
                        Text("LEARNING \(calibratingStep)/2")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1)
                            .foregroundColor(goldMid.opacity(0.9))
                    }
                }
            }
            
            if isReady {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(formatWeight(targetWeight))")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: neonPurple.opacity(0.5), radius: 10)
                    
                    Text("lb")
                        .font(IronFont.bodySemibold(16))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Text("×")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.horizontal, 6)
                    
                    Text("\(exercise.repRangeMin)-\(exercise.repRangeMax)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: neonPurple.opacity(0.5), radius: 10)
                    
                    Text("reps")
                        .font(IronFont.bodySemibold(16))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                // Progression hint
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 11))
                        .foregroundColor(goldMid.opacity(0.7))
                    
                    Text("Hit \(exercise.repRangeMax) reps on all sets → weight increases next time")
                        .font(IronFont.body(12))
                        .foregroundColor(.white.opacity(0.45))
                }
                .padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(exercise.repRangeMin)-\(exercise.repRangeMax)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, .white.opacity(0.85)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: neonPurple.opacity(0.35), radius: 8)
                        
                        Text("reps")
                            .font(IronFont.bodySemibold(16))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Text("Log weight + reps below. Mark warmups. Rate hardness after each working set.")
                        .font(IronFont.body(13))
                        .foregroundColor(.white.opacity(0.55))
                        .lineSpacing(3)
                    
                    Text("Recommendations unlock after 2 workouts.")
                        .font(IronFont.body(12))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(.ultraThinMaterial)
                    .opacity(0.6)
                
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(red: 0.06, green: 0.05, blue: 0.12).opacity(0.85))
                
                // Radial glow from inside
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        RadialGradient(
                            colors: [neonPurple.opacity(0.15), neonPurple.opacity(0.05), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 200
                        )
                    )
                
                // Top glossy highlight
                VStack {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.12), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .frame(height: 60)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 22))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(
                    LinearGradient(
                        colors: [neonPurple.opacity(0.7), neonPurple.opacity(0.3), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: neonPurple.opacity(0.2), radius: 20, y: 8)
    }
    
    // MARK: - Sets Section
    private var setsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("LOG YOUR SETS")
                    .font(IronFont.label(11))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.45))
                
                Spacer()
                
                Text("\(session.exercises[exerciseIndex].sets.filter(\.isCompleted).count)/\(session.exercises[exerciseIndex].sets.count)")
                    .font(IronFont.bodySemibold(13))
                    .foregroundColor(neonPurple)
            }
            
            VStack(spacing: 10) {
                ForEach(Array(session.exercises[exerciseIndex].sets.enumerated()), id: \.element.id) { setIndex, _ in
                    let previousSetCompletedAt: Date? = setIndex > 0 
                        ? session.exercises[exerciseIndex].sets[setIndex - 1].completedAt 
                        : nil
                    
                    PremiumSetRow(
                        setNumber: setIndex + 1,
                        set: $session.exercises[exerciseIndex].sets[setIndex],
                        targetReps: exercise.repRangeMin...exercise.repRangeMax,
                        targetRIR: exercise.targetRIR,
                        neonPurple: neonPurple,
                        isWeightFocused: $isWeightFieldFocused,
                        previousSetCompletedAt: previousSetCompletedAt
                    )
                }
            }
        }
    }
    
    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Add/Remove set row
            HStack(spacing: 12) {
                Button {
                    let newSet = WorkoutSet(
                        reps: exercise.repRangeMin,
                        weight: suggestedWeight,
                        isCompleted: false
                    )
                    session.exercises[exerciseIndex].sets.append(newSet)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("ADD SET")
                            .tracking(1)
                    }
                    .font(IronFont.bodySemibold(13))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(NeonGlowButtonStyle(isPrimary: false))
                
                Button {
                    if session.exercises[exerciseIndex].sets.count > 1 {
                        session.exercises[exerciseIndex].sets.removeLast()
                    }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(NeonGlowButtonStyle(isPrimary: false))
                .disabled(session.exercises[exerciseIndex].sets.count <= 1)
                .opacity(session.exercises[exerciseIndex].sets.count <= 1 ? 0.5 : 1)
            }
            
            // Save & Close button - exercises remain editable until workout is finalized
            Button {
                saveAndClose()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: exercise.sets.contains(where: { $0.isCompleted }) ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                    Text(exercise.sets.contains(where: { $0.isCompleted }) ? "SAVE & CLOSE" : "CLOSE")
                        .tracking(1.5)
                }
                .font(IronFont.bodySemibold(15))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeonGlowButtonStyle(isPrimary: canComplete))
        }
    }
    
    // MARK: - Calibration Result Card
    private func calibrationResultCard(snapshot: NextPrescriptionSnapshot) -> some View {
        let isReady = hasEnoughHistoryForSuggestions
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(neonPurple)
                
                Text(isReady ? "SYSTEM CALIBRATED" : "BASELINE RECORDED")
                    .font(IronFont.label(11))
                    .tracking(2)
                    .foregroundColor(neonPurple)
                
                Spacer()
                
                Image(systemName: isReady ? "checkmark.seal.fill" : "waveform.path.ecg")
                    .foregroundColor(isReady ? Color(red: 0.3, green: 1, blue: 0.5) : goldMid.opacity(0.9))
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            if isReady {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Next Session Target")
                        .font(IronFont.body(12))
                        .foregroundColor(.white.opacity(0.5))
                    
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(formatWeight(snapshot.nextWorkingWeight))")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("lb")
                            .font(IronFont.body(14))
                            .foregroundColor(.white.opacity(0.4))
                        
                        Text("×")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.3))
                            .padding(.horizontal, 4)
                        
                        Text("\(snapshot.targetReps)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("reps")
                            .font(IronFont.body(14))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            } else {
                Text("Keep logging for 1–2 workouts. Once we have enough signal, you’ll start seeing suggested targets here.")
                    .font(IronFont.body(13))
                    .foregroundColor(.white.opacity(0.55))
                    .lineSpacing(3)
            }
            
            // Reason explanation
            if isReady {
                HStack(spacing: 8) {
                    Image(systemName: snapshot.reason.icon)
                        .font(.system(size: 12))
                        .foregroundColor(goldMid.opacity(0.8))
                    
                    Text(snapshot.reason.detailText)
                        .font(IronFont.body(13))
                        .foregroundColor(.white.opacity(0.6))
                        .lineSpacing(3)
                }
                .padding(.top, 4)
            }
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .opacity(0.5)
                
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.05, green: 0.08, blue: 0.05).opacity(0.8))
                
                // Success glow
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.3, green: 1, blue: 0.5).opacity(0.1), Color.clear],
                            center: .topTrailing,
                            startRadius: 0,
                            endRadius: 200
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [Color(red: 0.3, green: 1, blue: 0.5).opacity(0.5), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    // MARK: - Helpers
    private var suggestedWeight: Double {
        if let w = session.exercises[exerciseIndex].sets.first?.weight, w > 0 { return w }
        return workoutStore.getExerciseState(for: exercise.exercise.id)?.currentWorkingWeight ?? 0
    }
    
    private var canComplete: Bool {
        let completed = session.exercises[exerciseIndex].sets.filter { $0.isCompleted }
        return !completed.isEmpty && completed.contains(where: { $0.weight > 0 })
    }
    
    private func saveAndClose() {
        let exerciseId = exercise.exercise.id
        
        // Initialize exercise state if this is the first time logging
        if workoutStore.getExerciseState(for: exerciseId) == nil {
            if let firstWeight = session.exercises[exerciseIndex].sets.first(where: { $0.isCompleted && $0.weight > 0 })?.weight {
                workoutStore.initializeExerciseState(exerciseId: exerciseId, initialWeight: firstWeight)
            }
        }
        
        // Save progress without marking exercise as completed
        // Exercises remain editable until the entire workout is finalized
        workoutStore.saveExerciseProgress(performanceId: exercise.id)
        
        if let updatedSession = workoutStore.activeSession {
            session = updatedSession
        }
        dismiss()
    }
    
    private func formatWeight(_ w: Double) -> String {
        if w == floor(w) { return "\(Int(w))" }
        return String(format: "%.1f", w)
    }
}

// MARK: - Premium Set Row
private struct PremiumSetRow: View {
    let setNumber: Int
    @Binding var set: WorkoutSet
    let targetReps: ClosedRange<Int>
    let targetRIR: Int
    let neonPurple: Color
    var isWeightFocused: FocusState<Bool>.Binding
    /// Previous set's completion time (for calculating rest time)
    var previousSetCompletedAt: Date?
    
    @State private var weightText: String = ""
    @State private var showModificationReason: Bool = false
    
    /// Check if the set values differ from recommended
    private var wasModified: Bool {
        guard set.isCompleted else { return false }
        if let recWeight = set.recommendedWeight, abs(set.weight - recWeight) > 0.1 { return true }
        if let recReps = set.recommendedReps, set.reps != recReps { return true }
        return false
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                // Completion toggle with set number
                Button {
                    let wasCompleted = set.isCompleted
                    set.isCompleted.toggle()
                    
                    // Track completion time for rest time calculation
                    if set.isCompleted && !wasCompleted {
                        set.completedAt = Date()
                        
                        // Calculate rest time from previous set
                        if let prevTime = previousSetCompletedAt {
                            set.actualRestSeconds = Int(Date().timeIntervalSince(prevTime))
                        }
                        
                        // Mark as modified if values differ from recommended
                        if let recWeight = set.recommendedWeight, abs(set.weight - recWeight) > 0.1 {
                            set.isUserModified = true
                        }
                        if let recReps = set.recommendedReps, set.reps != recReps {
                            set.isUserModified = true
                        }
                        
                        // Show modification reason picker if modified and no reason set
                        if set.isUserModified && set.modificationReason == nil {
                            showModificationReason = true
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(set.isCompleted ? neonPurple.opacity(0.2) : Color.white.opacity(0.03))
                            .frame(width: 44, height: 44)
                        
                        Circle()
                            .stroke(set.isCompleted ? neonPurple : Color.white.opacity(0.15), lineWidth: 2)
                            .frame(width: 44, height: 44)
                        
                        if set.isCompleted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(neonPurple)
                        } else {
                            Text("\(setNumber)")
                                .font(IronFont.bodySemibold(16))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                    .shadow(color: set.isCompleted ? neonPurple.opacity(0.4) : .clear, radius: 8)
                }
                .buttonStyle(.plain)
                
                // Weight input
                VStack(alignment: .leading, spacing: 4) {
                    Text("WEIGHT")
                        .font(IronFont.label(9))
                        .tracking(1.2)
                        .foregroundColor(.white.opacity(0.35))
                    
                    HStack(spacing: 6) {
                        TextField("0", text: Binding(
                            get: { weightText.isEmpty ? formatWeight(set.weight) : weightText },
                            set: { newValue in
                                weightText = newValue
                                if let v = Double(newValue) {
                                    set.weight = v
                                }
                            }
                        ))
                        .keyboardType(.decimalPad)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 70)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .tint(neonPurple)
                        .focused(isWeightFocused)
                        
                        Text("lb")
                            .font(IronFont.body(12))
                            .foregroundColor(.white.opacity(0.35))
                    }
                }
                
                Spacer()
                
                // Reps input
                VStack(alignment: .leading, spacing: 4) {
                    Text("REPS")
                        .font(IronFont.label(9))
                        .tracking(1.2)
                        .foregroundColor(.white.opacity(0.35))
                    
                    HStack(spacing: 8) {
                        Button {
                            if set.reps > 0 { set.reps -= 1 }
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white.opacity(0.5))
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.white.opacity(0.05)))
                                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        
                        Text("\(set.reps)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(repColor)
                            .frame(minWidth: 30)
                        
                        Button {
                            if set.reps < 100 { set.reps += 1 }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white.opacity(0.5))
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.white.opacity(0.05)))
                                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Warmup toggle + per-set effort (hardness) slider
            HStack(spacing: 12) {
                Button {
                    set.isWarmup.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: set.isWarmup ? "flame.fill" : "flame")
                            .font(.system(size: 12, weight: .bold))
                        Text("WARMUP")
                            .font(IronFont.bodySemibold(11))
                            .tracking(1.2)
                    }
                    .foregroundColor(set.isWarmup ? neonPurple : .white.opacity(0.55))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(set.isWarmup ? neonPurple.opacity(0.15) : Color.white.opacity(0.03))
                    )
                    .overlay(
                        Capsule()
                            .stroke(set.isWarmup ? neonPurple.opacity(0.45) : Color.white.opacity(0.10), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("HARDNESS")
                            .font(IronFont.label(9))
                            .tracking(1.2)
                            .foregroundColor(.white.opacity(0.35))
                        Spacer()
                        Text(set.isCompleted ? "\(Int(currentHardness))/10" : "--/10")
                            .font(IronFont.bodySemibold(12))
                            .foregroundColor(set.isCompleted ? neonPurple : .white.opacity(0.35))
                    }
                    
                    Slider(
                        value: Binding(
                            get: { currentHardness },
                            set: { set.rpeObserved = $0 }
                        ),
                        in: 0...10,
                        step: 1
                    )
                    .tint(neonPurple)
                    .disabled(!set.isCompleted)
                    .opacity(set.isCompleted ? 1.0 : 0.35)
                }
            }
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .opacity(0.4)
                
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.1).opacity(0.8))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    set.isCompleted
                        ? LinearGradient(colors: [neonPurple.opacity(0.5), neonPurple.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        )
        .onChange(of: set.isCompleted) { _, isCompleted in
            // When the user completes a set, default the hardness so they're immediately prompted.
            if isCompleted, set.rpeObserved == nil {
                set.rpeObserved = defaultHardness
            }
        }
        .sheet(isPresented: $showModificationReason) {
            ModificationReasonSheet(
                set: $set,
                neonPurple: neonPurple,
                onDismiss: { showModificationReason = false }
            )
            .presentationDetents([.height(400)])
            .presentationDragIndicator(.visible)
        }
    }
    
    private var repColor: Color {
        if set.isWarmup { return .white.opacity(0.65) }
        if set.reps >= targetReps.upperBound {
            return Color(red: 0.3, green: 1, blue: 0.5) // Green - at top
        } else if set.reps >= targetReps.lowerBound {
            return .white // White - in range
        } else {
            return Color(red: 1, green: 0.5, blue: 0.3) // Orange - below
        }
    }
    
    private var defaultHardness: Double {
        let clamped = max(0, min(5, targetRIR))
        return Double(max(0, min(10, 10 - clamped)))
    }
    
    private var currentHardness: Double {
        return set.rpeObserved ?? defaultHardness
    }
    
    private func formatWeight(_ w: Double) -> String {
        if w == floor(w) { return "\(Int(w))" }
        return String(format: "%.1f", w)
    }
}


// MARK: - Pre-Workout Check-In (ML Data Collection)
/// Quick check-in before starting a workout to capture baseline state.
/// Critical for ML model to understand context and adjust expectations.
struct PreWorkoutCheckInSheet: View {
    @Binding var session: WorkoutSession
    let neonPurple: Color
    let onStart: () -> Void
    let onCancel: () -> Void
    
    @State private var readiness: Int = 3
    @State private var soreness: Int = 0
    @State private var energy: Int = 3
    @State private var motivation: Int = 3
    @State private var sleepQuality: Int = 3
    @State private var sleepHours: Double = 7.0
    @State private var wasFasted: Bool = false
    
    // Life stress flags
    @State private var hasIllness: Bool = false
    @State private var hasTravel: Bool = false
    @State private var hasWorkStress: Bool = false
    @State private var hadPoorSleep: Bool = false
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundColor(neonPurple)
                        
                        Text("PRE-WORKOUT CHECK-IN")
                            .font(.system(size: 20, weight: .bold))
                            .tracking(2)
                            .foregroundColor(.white)
                        
                        Text("Quick check helps optimize your workout")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.top, 20)
                    
                    // Readiness (1-5)
                    RatingRow(
                        title: "READINESS",
                        subtitle: "How ready do you feel to train?",
                        value: $readiness,
                        range: 1...5,
                        labels: ["Awful", "Poor", "Okay", "Good", "Great"],
                        color: neonPurple
                    )
                    
                    // Soreness (0-10)
                    RatingRow(
                        title: "MUSCLE SORENESS",
                        subtitle: "Overall soreness level",
                        value: $soreness,
                        range: 0...10,
                        labels: nil,
                        color: Color.orange
                    )
                    
                    // Energy (1-5)
                    RatingRow(
                        title: "ENERGY LEVEL",
                        subtitle: "Physical energy right now",
                        value: $energy,
                        range: 1...5,
                        labels: ["Exhausted", "Low", "Normal", "Good", "High"],
                        color: Color.green
                    )
                    
                    // Motivation (1-5)
                    RatingRow(
                        title: "MOTIVATION",
                        subtitle: "Mental drive to train",
                        value: $motivation,
                        range: 1...5,
                        labels: ["None", "Low", "Okay", "High", "Max"],
                        color: Color.cyan
                    )
                    
                    Divider().background(Color.white.opacity(0.1))
                    
                    // Sleep last night
                    VStack(alignment: .leading, spacing: 12) {
                        Text("LAST NIGHT'S SLEEP")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.5)
                            .foregroundColor(.white.opacity(0.5))
                        
                        HStack(spacing: 16) {
                            // Hours
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Hours")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                
                                HStack {
                                    Text(String(format: "%.1f", sleepHours))
                                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                    
                                    Stepper("", value: $sleepHours, in: 0...14, step: 0.5)
                                        .labelsHidden()
                                }
                            }
                            
                            Spacer()
                            
                            // Quality
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Quality (1-5)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                
                                HStack(spacing: 6) {
                                    ForEach(1...5, id: \.self) { val in
                                        Button {
                                            sleepQuality = val
                                        } label: {
                                            Circle()
                                                .fill(sleepQuality >= val ? Color.indigo : Color.white.opacity(0.1))
                                                .frame(width: 28, height: 28)
                                                .overlay(
                                                    Text("\(val)")
                                                        .font(.system(size: 12, weight: .bold))
                                                        .foregroundColor(sleepQuality >= val ? .white : .white.opacity(0.4))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    
                    // Life stress flags
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ANY SPECIAL CIRCUMSTANCES?")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.5)
                            .foregroundColor(.white.opacity(0.5))
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            StressToggle(label: "Illness/Sick", icon: "pills.fill", isOn: $hasIllness)
                            StressToggle(label: "Traveling", icon: "airplane", isOn: $hasTravel)
                            StressToggle(label: "Work Stress", icon: "briefcase.fill", isOn: $hasWorkStress)
                            StressToggle(label: "Poor Sleep", icon: "moon.zzz.fill", isOn: $hadPoorSleep)
                        }
                        
                        // Fasted toggle
                        HStack {
                            Image(systemName: "fork.knife")
                                .foregroundColor(wasFasted ? neonPurple : .white.opacity(0.4))
                            Text("Training Fasted")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            Toggle("", isOn: $wasFasted)
                                .labelsHidden()
                                .tint(neonPurple)
                        }
                        .padding(.top, 8)
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
            .background(Color(red: 0.06, green: 0.06, blue: 0.08))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        onCancel()
                    }
                    .foregroundColor(.white.opacity(0.6))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start Workout") {
                        applyToSession()
                        onStart()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(neonPurple)
                }
            }
        }
    }
    
    private func applyToSession() {
        session.preWorkoutReadiness = readiness
        session.preWorkoutSoreness = soreness
        session.preWorkoutEnergy = energy
        session.preWorkoutMotivation = motivation
        session.sleepQualityLastNight = sleepQuality
        session.sleepHoursLastNight = sleepHours
        session.wasFasted = wasFasted
        session.lifeStressFlags = LifeStressFlags(
            illness: hasIllness,
            travel: hasTravel,
            workStress: hasWorkStress,
            poorSleep: hadPoorSleep,
            other: false,
            notes: nil
        )
    }
}

// MARK: - Post-Workout Summary (ML Data Collection)
/// Summary screen after finishing a workout to capture session-level feedback.
/// Critical for ML model to learn from subjective outcomes.
struct PostWorkoutSummarySheet: View {
    @Binding var session: WorkoutSession
    let neonPurple: Color
    let onFinish: () -> Void
    let onCancel: () -> Void
    
    @State private var sessionRPE: Int = 5
    @State private var feeling: Int = 3
    @State private var harderThanExpected: Bool = false
    @State private var notes: String = ""
    
    // Pain tracking
    @State private var hasPain: Bool = false
    @State private var painRegion: BodyRegion = .lowerBack
    @State private var painSeverity: Int = 3
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Summary header
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundColor(neonPurple)
                        
                        Text("WORKOUT COMPLETE")
                            .font(.system(size: 20, weight: .bold))
                            .tracking(2)
                            .foregroundColor(.white)
                        
                        Text(sessionSummary)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.top, 20)
                    
                    // Session RPE (1-10) - Most important metric
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("SESSION RPE")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(1.5)
                                .foregroundColor(.white.opacity(0.5))
                            
                            Spacer()
                            
                            Text("\(sessionRPE)/10")
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundColor(rpeColor)
                        }
                        
                        Text("How hard was this session overall?")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                        
                        HStack(spacing: 8) {
                            ForEach(1...10, id: \.self) { val in
                                Button {
                                    sessionRPE = val
                                } label: {
                                    Text("\(val)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(sessionRPE == val ? .white : .white.opacity(0.4))
                                        .frame(width: 28, height: 28)
                                        .background(
                                            Circle()
                                                .fill(sessionRPE == val ? rpeColor : Color.white.opacity(0.05))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        // RPE labels
                        HStack {
                            Text("Easy")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.3))
                            Spacer()
                            Text("Maximum")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(rpeColor.opacity(0.3), lineWidth: 1))
                    
                    // Post-workout feeling (1-5)
                    RatingRow(
                        title: "HOW DO YOU FEEL?",
                        subtitle: "Overall state after workout",
                        value: $feeling,
                        range: 1...5,
                        labels: ["Awful", "Bad", "Okay", "Good", "Great"],
                        color: Color.green
                    )
                    
                    // Harder than expected toggle
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(harderThanExpected ? .orange : .white.opacity(0.4))
                        Text("Harder than expected")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Toggle("", isOn: $harderThanExpected)
                            .labelsHidden()
                            .tint(.orange)
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(12)
                    
                    // Pain tracking
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "bandage.fill")
                                .foregroundColor(hasPain ? .red : .white.opacity(0.4))
                            Text("Any Pain or Discomfort?")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            Toggle("", isOn: $hasPain)
                                .labelsHidden()
                                .tint(.red)
                        }
                        
                        if hasPain {
                            VStack(spacing: 12) {
                                // Body region picker
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Location")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white.opacity(0.5))
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(BodyRegion.allCases, id: \.self) { region in
                                                Button {
                                                    painRegion = region
                                                } label: {
                                                    Text(region.rawValue)
                                                        .font(.system(size: 11, weight: .medium))
                                                        .foregroundColor(painRegion == region ? .white : .white.opacity(0.5))
                                                        .padding(.horizontal, 10)
                                                        .padding(.vertical, 6)
                                                        .background(
                                                            Capsule()
                                                                .fill(painRegion == region ? Color.red.opacity(0.3) : Color.white.opacity(0.05))
                                                        )
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                                
                                // Severity (0-10)
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Severity")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.white.opacity(0.5))
                                        Spacer()
                                        Text("\(painSeverity)/10")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.red)
                                    }
                                    
                                    Slider(value: Binding(
                                        get: { Double(painSeverity) },
                                        set: { painSeverity = Int($0) }
                                    ), in: 1...10, step: 1)
                                    .tint(.red)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(hasPain ? Color.red.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1))
                    
                    // Notes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NOTES (OPTIONAL)")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.5)
                            .foregroundColor(.white.opacity(0.5))
                        
                        TextField("Anything notable about this session...", text: $notes, axis: .vertical)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(3...5)
                            .padding(12)
                            .background(Color.white.opacity(0.03))
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
            .background(Color(red: 0.06, green: 0.06, blue: 0.08))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundColor(.white.opacity(0.6))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Workout") {
                        applyToSession()
                        onFinish()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(neonPurple)
                }
            }
        }
    }
    
    private var sessionSummary: String {
        let exercises = session.exercises.count
        let sets = session.exercises.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count }
        let duration = session.startedAt.distance(to: Date())
        let minutes = Int(duration / 60)
        return "\(exercises) exercises • \(sets) sets • \(minutes) min"
    }
    
    private var rpeColor: Color {
        switch sessionRPE {
        case 1...3: return .green
        case 4...6: return .yellow
        case 7...8: return .orange
        default: return .red
        }
    }
    
    private func applyToSession() {
        session.sessionRPE = sessionRPE
        session.postWorkoutFeeling = feeling
        session.harderThanExpected = harderThanExpected
        session.sessionNotes = notes.isEmpty ? nil : notes
        
        if hasPain {
            let painEntry = PainEntry(region: painRegion, severity: painSeverity)
            session.sessionPainEntries = [painEntry]
        }
    }
}

// MARK: - Helper Views for Check-In/Summary

private struct RatingRow: View {
    let title: String
    let subtitle: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let labels: [String]?
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.5))
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
                Text("\(value)/\(range.upperBound)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
            }
            
            HStack(spacing: 8) {
                ForEach(Array(range), id: \.self) { val in
                    Button {
                        value = val
                    } label: {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(value >= val ? color : Color.white.opacity(0.1))
                                .frame(width: range.count > 6 ? 24 : 32, height: range.count > 6 ? 24 : 32)
                                .overlay(
                                    Text("\(val)")
                                        .font(.system(size: range.count > 6 ? 10 : 12, weight: .bold))
                                        .foregroundColor(value >= val ? .white : .white.opacity(0.4))
                                )
                            
                            if let labels = labels, val <= labels.count {
                                Text(labels[val - 1])
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(.white.opacity(0.3))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

private struct StressToggle: View {
    let label: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isOn ? .white : .white.opacity(0.4))
                
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isOn ? .white : .white.opacity(0.5))
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isOn ? Color.orange.opacity(0.2) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isOn ? Color.orange.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Modification Reason Sheet (ML Data Collection)
/// Quick picker for why the user modified the recommended weight/reps.
/// Critical for ML model to understand when deviations are intentional vs errors.
private struct ModificationReasonSheet: View {
    @Binding var set: WorkoutSet
    let neonPurple: Color
    let onDismiss: () -> Void
    
    private let reasons: [(ComplianceReasonCode, String, String)] = [
        (.feltStrong, "flame.fill", "Felt strong"),
        (.feltWeak, "battery.25", "Felt weak/fatigued"),
        (.pain, "bandage.fill", "Pain/discomfort"),
        (.formConcern, "exclamationmark.triangle.fill", "Form breaking down"),
        (.equipmentUnavailable, "wrench.fill", "Equipment unavailable"),
        (.timeConstraint, "clock.fill", "Short on time"),
        (.warmupInsufficient, "thermometer.snowflake", "Needed more warmup"),
        (.testingMax, "chart.line.uptrend.xyaxis", "Testing max"),
        (.personalPreference, "hand.thumbsup.fill", "Personal preference"),
        (.other, "ellipsis.circle.fill", "Other reason")
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "pencil.and.list.clipboard")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(neonPurple)
                
                Text("WHY THE CHANGE?")
                    .font(.system(size: 18, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white)
                
                Text("This helps us learn your preferences")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.top, 20)
            
            // Reason grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(reasons, id: \.0) { reason, icon, label in
                    Button {
                        set.modificationReason = reason
                        onDismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(set.modificationReason == reason ? neonPurple : .white.opacity(0.6))
                                .frame(width: 24)
                            
                            Text(label)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(set.modificationReason == reason 
                                    ? neonPurple.opacity(0.15) 
                                    : Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(set.modificationReason == reason 
                                    ? neonPurple.opacity(0.5) 
                                    : Color.white.opacity(0.1), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            
            // Skip button
            Button {
                set.modificationReason = .none
                onDismiss()
            } label: {
                Text("Skip")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.bottom, 20)
            
            Spacer()
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
    }
}

// MARK: - Backward Compatibility Alias
private typealias TemplateEditorView = WorkoutBuilderView
