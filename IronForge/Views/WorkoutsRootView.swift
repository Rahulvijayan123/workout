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
    
    private var recentBiometrics: [DailyBiometrics] {
        Array(dailyBiometrics.suffix(60))
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                header
                
                quickActions
                
                backendStatus
                
                progressionStatus
                
                templatesSection
                
                historySection
                
                Spacer(minLength: 120)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WORKOUTS")
                .font(IronFont.header(28))
                .tracking(2)
                .foregroundColor(.ironTextPrimary)
            
            Text("Build templates, start sessions, and log sets.")
                .font(IronFont.body(15))
                .foregroundColor(.ironTextTertiary)
        }
    }
    
    private var quickActions: some View {
        HStack(spacing: 12) {
            Button {
                workoutStore.startEmptySession()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.fill")
                    Text("QUICK START")
                        .tracking(1)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeonGlowButtonStyle(isPrimary: true))
            
            Button {
                onCreateTemplate()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                    Text("NEW TEMPLATE")
                        .tracking(1)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeonGlowButtonStyle(isPrimary: false))
        }
    }
    
    private var backendStatus: some View {
        ExerciseBackendStatusCard()
    }
    
    private var progressionStatus: some View {
        ProgressionEngineSelfTestCard()
    }
    
    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TEMPLATES")
                .font(IronFont.label(11))
                .tracking(2)
                .foregroundColor(.ironTextTertiary)
            
            VStack(spacing: 10) {
                ForEach(workoutStore.templates) { template in
                    TemplateRow(template: template) {
                        let readiness = ReadinessScoreCalculator.todayScore(from: recentBiometrics) ?? 75
                        workoutStore.startSession(
                            from: template,
                            userProfile: appState.userProfile,
                            readiness: readiness,
                            dailyBiometrics: recentBiometrics
                        )
                    } onEdit: {
                        onEditTemplate(template)
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
                Text("No sessions yet. Start one and log your sets.")
                    .font(IronFont.body(14))
                    .foregroundColor(.ironTextTertiary)
                    .padding(16)
                    .liquidGlass()
            } else {
                VStack(spacing: 10) {
                    ForEach(workoutStore.sessions.prefix(5)) { session in
                        SessionRow(session: session)
                    }
                }
            }
        }
    }
}

private struct ExerciseBackendStatusCard: View {
    @EnvironmentObject var workoutStore: WorkoutStore
    @State private var count: Int?
    @State private var lastRefreshed: Date?
    @State private var isRefreshing = false
    
    private var backendName: String {
        (workoutStore.exerciseRepository is ExerciseDBRepository) ? "ExerciseDB API" : "Local Seed Library"
    }
    
    private var backendDetail: String {
        if workoutStore.exerciseRepository is ExerciseDBRepository {
            let base = UserDefaults.standard.string(forKey: "ironforge.exerciseDB.baseURL") ?? "(unset)"
            return "Base URL: \(base)"
        }
        return "Built-in seed exercises (works offline)."
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EXERCISE BACKEND")
                        .font(IronFont.label(11))
                        .tracking(2)
                        .foregroundColor(.ironTextTertiary)
                    
                    Text(backendName)
                        .font(IronFont.bodySemibold(15))
                        .foregroundColor(.ironTextPrimary)
                }
                
                Spacer()
                
                Button {
                    refresh()
                } label: {
                    HStack(spacing: 8) {
                        if isRefreshing {
                            ProgressView()
                                .tint(.ironPurple)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("TEST")
                            .tracking(1)
                    }
                    .font(IronFont.bodySemibold(12))
                }
                .buttonStyle(NeonGlowButtonStyle(isPrimary: false))
            }
            
            Text(backendDetail)
                .font(IronFont.body(13))
                .foregroundColor(.ironTextTertiary)
                .lineLimit(2)
            
            if let count {
                Text("Fetched \(count) exercises \(lastRefreshed.map { "• \($0.formatted(date: .omitted, time: .shortened))" } ?? "")")
                    .font(IronFont.body(12))
                    .foregroundColor(count > 0 ? .ironTextSecondary : .red.opacity(0.8))
            } else {
                Text("Tap TEST to verify exercise search + metadata.")
                    .font(IronFont.body(12))
                    .foregroundColor(.ironTextTertiary)
            }
        }
        .padding(14)
        .liquidGlass()
        .onAppear {
            if count == nil {
                refresh()
            }
        }
    }
    
    private func refresh() {
        isRefreshing = true
        Task {
            let results = await workoutStore.exerciseRepository.search(query: "")
            await MainActor.run {
                count = results.count
                lastRefreshed = Date()
                isRefreshing = false
            }
        }
    }
}

private struct ProgressionEngineSelfTestCard: View {
    /// Tests TrainingEngine's double progression policy
    private var allPass: Bool {
        // Test 1: All sets at top of range → should increase load
        let test1Pass: Bool = {
            let prescription = TrainingEngine.SetPrescription(
                setCount: 3,
                targetRepsRange: 6...10,
                targetRIR: 2,
                tempo: .standard,
                restSeconds: 120,
                loadStrategy: .absolute,
                targetPercentage: nil,
                increment: TrainingEngine.Load.pounds(5)
            )
            
            let sets = [
                TrainingEngine.SetResult(reps: 10, load: .pounds(100), completed: true, isWarmup: false),
                TrainingEngine.SetResult(reps: 10, load: .pounds(100), completed: true, isWarmup: false),
                TrainingEngine.SetResult(reps: 10, load: .pounds(100), completed: true, isWarmup: false)
            ]
            
            let result = TrainingEngine.ExerciseSessionResult(
                exerciseId: "test",
                prescription: prescription,
                sets: sets,
                order: 0
            )
            
            let decision = TrainingEngine.DoubleProgressionPolicy.evaluateProgression(
                config: .default,
                prescription: prescription,
                lastResult: result
            )
            
            if case .increaseLoad = decision { return true }
            return false
        }()
        
        // Test 2: All sets within range → should increase reps
        let test2Pass: Bool = {
            let prescription = TrainingEngine.SetPrescription(
                setCount: 3,
                targetRepsRange: 6...10,
                targetRIR: 2,
                tempo: .standard,
                restSeconds: 120,
                loadStrategy: .absolute,
                targetPercentage: nil,
                increment: TrainingEngine.Load.pounds(5)
            )
            
            let sets = [
                TrainingEngine.SetResult(reps: 8, load: .pounds(100), completed: true, isWarmup: false),
                TrainingEngine.SetResult(reps: 8, load: .pounds(100), completed: true, isWarmup: false),
                TrainingEngine.SetResult(reps: 7, load: .pounds(100), completed: true, isWarmup: false)
            ]
            
            let result = TrainingEngine.ExerciseSessionResult(
                exerciseId: "test",
                prescription: prescription,
                sets: sets,
                order: 0
            )
            
            let decision = TrainingEngine.DoubleProgressionPolicy.evaluateProgression(
                config: .default,
                prescription: prescription,
                lastResult: result
            )
            
            if case .increaseReps = decision { return true }
            return false
        }()
        
        // Test 3: Below min reps → failure
        let test3Pass: Bool = {
            let prescription = TrainingEngine.SetPrescription(
                setCount: 3,
                targetRepsRange: 6...10,
                targetRIR: 2,
                tempo: .standard,
                restSeconds: 120,
                loadStrategy: .absolute,
                targetPercentage: nil,
                increment: TrainingEngine.Load.pounds(5)
            )
            
            let sets = [
                TrainingEngine.SetResult(reps: 5, load: .pounds(100), completed: true, isWarmup: false),
                TrainingEngine.SetResult(reps: 5, load: .pounds(100), completed: true, isWarmup: false),
                TrainingEngine.SetResult(reps: 5, load: .pounds(100), completed: true, isWarmup: false)
            ]
            
            let result = TrainingEngine.ExerciseSessionResult(
                exerciseId: "test",
                prescription: prescription,
                sets: sets,
                order: 0
            )
            
            let decision = TrainingEngine.DoubleProgressionPolicy.evaluateProgression(
                config: .default,
                prescription: prescription,
                lastResult: result
            )
            
            if case .failure = decision { return true }
            return false
        }()
        
        return test1Pass && test2Pass && test3Pass
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TRAINING ENGINE")
                        .font(IronFont.label(11))
                        .tracking(2)
                        .foregroundColor(.ironTextTertiary)
                    
                    Text(allPass ? "Self-test PASS" : "Self-test FAIL")
                        .font(IronFont.bodySemibold(15))
                        .foregroundColor(allPass ? .ironTextPrimary : .red.opacity(0.85))
                }
                
                Spacer()
                
                Image(systemName: allPass ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .foregroundColor(allPass ? .ironPurple : .red.opacity(0.85))
                    .shadow(color: allPass ? Color.ironPurpleGlow.opacity(0.4) : .clear, radius: 10, x: 0, y: 4)
            }
            
            Text("TrainingEngine: double progression (add reps → add load → deload on misses).")
                .font(IronFont.body(13))
                .foregroundColor(.ironTextTertiary)
        }
        .padding(14)
        .liquidGlass()
    }
}

private struct TemplateRow: View {
    let template: WorkoutTemplate
    let onStart: () -> Void
    let onEdit: () -> Void
    
    var body: some View {
        Button(action: onStart) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.ironPurple.opacity(0.18))
                        .frame(width: 52, height: 52)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.ironPurple.opacity(0.35), lineWidth: 1)
                        }
                    Image(systemName: "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.ironPurple)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name.uppercased())
                        .font(IronFont.bodySemibold(16))
                        .tracking(1)
                        .foregroundColor(.ironTextPrimary)
                    
                    Text("\(template.exercises.count) exercise\(template.exercises.count == 1 ? "" : "s")")
                        .font(IronFont.body(13))
                        .foregroundColor(.ironTextTertiary)
                }
                
                Spacer()
                
                Button(action: onEdit) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.ironTextSecondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.glassWhite))
                        .overlay(Circle().stroke(Color.glassBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .liquidGlass()
        }
        .buttonStyle(.plain)
    }
}

private struct SessionRow: View {
    let session: WorkoutSession
    
    var body: some View {
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
            
            Text("\(session.exercises.count)")
                .font(IronFont.headerMedium(16))
                .foregroundColor(.ironTextSecondary)
        }
        .padding(14)
        .liquidGlass()
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
                    Text("\(templateExercise.setsTarget) sets • \(templateExercise.repRangeMin)-\(templateExercise.repRangeMax) reps • +\(Int(templateExercise.increment)) lb")
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
    
    init(templateExercise: WorkoutTemplateExercise, onSave: @escaping (WorkoutTemplateExercise) -> Void, onCancel: @escaping () -> Void) {
        _templateExercise = State(initialValue: templateExercise)
        self.onSave = onSave
        self.onCancel = onCancel
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
                    
                    // Sets & Reps
                    VStack(alignment: .leading, spacing: 12) {
                        Text("VOLUME")
                            .font(IronFont.label(11))
                            .tracking(2)
                            .foregroundColor(.ironTextTertiary)
                        
                        VStack(spacing: 10) {
                            StepperField(title: "Sets", value: $templateExercise.setsTarget, range: 1...10)
                            
                            HStack(spacing: 12) {
                                StepperField(title: "Reps (min)", value: $templateExercise.repRangeMin, range: 1...50)
                                StepperField(title: "Reps (max)", value: $templateExercise.repRangeMax, range: 1...50)
                            }
                        }
                        .padding(14)
                        .liquidGlass()
                    }
                    
                    // Progression Settings
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PROGRESSION")
                            .font(IronFont.label(11))
                            .tracking(2)
                            .foregroundColor(.ironTextTertiary)
                        
                        VStack(spacing: 10) {
                            StepperField(title: "Increment (lb)", value: Binding(
                                get: { Int(templateExercise.increment) },
                                set: { templateExercise.increment = Double($0) }
                            ), range: 1...25)
                            
                            StepperField(title: "Failure Threshold", value: $templateExercise.failureThreshold, range: 1...5)
                            
                            DeloadFactorField(value: $templateExercise.deloadFactor)
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
                        
                        Text("When all sets hit max reps, weight increases by the increment. If you miss the min reps \(templateExercise.failureThreshold) time\(templateExercise.failureThreshold == 1 ? "" : "s"), weight drops to \(Int(templateExercise.deloadFactor * 100))% (deload).")
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
            .navigationTitle("Exercise Settings")
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
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(results) { ex in
                                Button {
                                    onPick(ex)
                                    dismiss()
                                } label: {
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
                                    .padding(14)
                                    .liquidGlass()
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
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
                    VStack(spacing: 12) {
                        ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, exercise in
                            SessionExerciseRow(
                                exercise: exercise,
                                onTap: {
                                    selectedExerciseIndex = index
                                }
                            )
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
        .confirmationDialog("Finish workout?", isPresented: $showingFinishConfirm, titleVisibility: .visible) {
            Button("Finish & Save", role: .none) {
                workoutStore.updateActiveSession(session)
                workoutStore.finishActiveSession()
            }
            Button("Keep Logging", role: .cancel) {}
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
    
    @State private var showingCompletionAlert = false
    @State private var completionSnapshot: NextPrescriptionSnapshot?
    
    private var exercise: ExercisePerformance {
        session.exercises[exerciseIndex]
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    
                    // Last time summary
                    if let lastPerformance = workoutStore.lastPerformance(for: exercise.exercise.id) {
                        LastTimeSummaryCard(performance: lastPerformance)
                    }
                    
                    // Current session suggestion
                    suggestionCard
                    
                    // Sets
                    VStack(spacing: 10) {
                        ForEach(Array(session.exercises[exerciseIndex].sets.enumerated()), id: \.element.id) { setIndex, _ in
                            SetRow(set: $session.exercises[exerciseIndex].sets[setIndex])
                        }
                    }
                    
                    // Add/Remove set buttons
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
                    
                    // Complete Exercise button
                    if !exercise.isCompleted {
                        Button {
                            completeExercise()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("COMPLETE EXERCISE")
                                    .tracking(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NeonGlowButtonStyle(isPrimary: true))
                        .disabled(!canComplete)
                        .opacity(canComplete ? 1 : 0.5)
                    }
                    
                    // Show prescription after completion
                    if let snapshot = exercise.nextPrescription {
                        NextPrescriptionCard(snapshot: snapshot)
                    }
                    
                    Spacer(minLength: 120)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }
            .navigationTitle("Log Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Exercise Completed", isPresented: $showingCompletionAlert) {
                Button("OK") { }
            } message: {
                if let snapshot = completionSnapshot {
                    Text("Next time: \(formatWeight(snapshot.nextWorkingWeight)) lb x \(snapshot.targetReps) reps\n\(snapshot.reason.displayText)")
                }
            }
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.exercise.displayName.uppercased())
                .font(IronFont.header(20))
                .tracking(2)
                .foregroundColor(.ironTextPrimary)
            
            Text("\(exercise.exercise.target.capitalized) • \(exercise.exercise.equipment.capitalized) • \(exercise.setsTarget)x\(exercise.repRangeMin)-\(exercise.repRangeMax)")
                .font(IronFont.body(14))
                .foregroundColor(.ironTextTertiary)
        }
    }
    
    private var suggestionCard: some View {
        let state = workoutStore.getExerciseState(for: exercise.exercise.id)
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(.ironPurple)
                Text("Target")
                    .font(IronFont.bodySemibold(14))
                    .foregroundColor(.ironTextPrimary)
            }
            
            if let state = state {
                Text("\(formatWeight(state.currentWorkingWeight)) lb x \(exercise.repRangeMin)-\(exercise.repRangeMax) reps for \(exercise.setsTarget) sets")
                    .font(IronFont.body(13))
                    .foregroundColor(.ironTextSecondary)
            } else {
                Text("Enter your working weight on the first set to initialize tracking.")
                    .font(IronFont.body(13))
                    .foregroundColor(.ironTextSecondary)
            }
        }
        .padding(14)
        .liquidGlass()
    }
    
    private var suggestedWeight: Double {
        // If user has started logging, use current first-set weight
        if let w = session.exercises[exerciseIndex].sets.first?.weight, w > 0 { return w }
        
        // Otherwise, use state weight or 0
        return workoutStore.getExerciseState(for: exercise.exercise.id)?.currentWorkingWeight ?? 0
    }
    
    private var canComplete: Bool {
        // Must have at least one completed set with weight > 0
        let completed = session.exercises[exerciseIndex].sets.filter { $0.isCompleted }
        return !completed.isEmpty && completed.contains(where: { $0.weight > 0 })
    }
    
    private func completeExercise() {
        // Initialize state if needed
        let exerciseId = exercise.exercise.id
        if workoutStore.getExerciseState(for: exerciseId) == nil {
            if let firstWeight = session.exercises[exerciseIndex].sets.first(where: { $0.isCompleted && $0.weight > 0 })?.weight {
                workoutStore.initializeExerciseState(exerciseId: exerciseId, initialWeight: firstWeight)
            }
        }
        
        // Complete and get prescription
        if let snapshot = workoutStore.completeExercise(performanceId: exercise.id) {
            // Update local session state
            if let updatedSession = workoutStore.activeSession {
                session = updatedSession
            }
            completionSnapshot = snapshot
            showingCompletionAlert = true
        }
    }
    
    private func formatWeight(_ w: Double) -> String {
        if w == floor(w) { return "\(Int(w))" }
        return String(format: "%.1f", w)
    }
}

// MARK: - Last Time Summary Card
private struct LastTimeSummaryCard: View {
    let performance: ExercisePerformance
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.ironTextTertiary)
                Text("Last Time")
                    .font(IronFont.bodySemibold(14))
                    .foregroundColor(.ironTextPrimary)
            }
            
            let completed = performance.sets.filter(\.isCompleted)
            if !completed.isEmpty {
                let avgWeight = completed.map(\.weight).reduce(0, +) / Double(completed.count)
                let avgReps = completed.map(\.reps).reduce(0, +) / completed.count
                
                Text("\(completed.count) sets • \(formatWeight(avgWeight)) lb • ~\(avgReps) reps avg")
                    .font(IronFont.body(13))
                    .foregroundColor(.ironTextSecondary)
                
                if let prescription = performance.nextPrescription {
                    Text("Suggested: \(prescription.reason.displayText)")
                        .font(IronFont.body(12))
                        .foregroundColor(.ironTextTertiary)
                }
            } else {
                Text("No completed sets")
                    .font(IronFont.body(13))
                    .foregroundColor(.ironTextTertiary)
            }
        }
        .padding(14)
        .liquidGlass()
    }
    
    private func formatWeight(_ w: Double) -> String {
        if w == floor(w) { return "\(Int(w))" }
        return String(format: "%.1f", w)
    }
}

// MARK: - Next Prescription Card
private struct NextPrescriptionCard: View {
    let snapshot: NextPrescriptionSnapshot
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.forward.circle.fill")
                    .foregroundColor(.ironPurple)
                Text("Next Time")
                    .font(IronFont.bodySemibold(14))
                    .foregroundColor(.ironTextPrimary)
            }
            
            Text("\(formatWeight(snapshot.nextWorkingWeight)) lb x \(snapshot.targetReps) reps for \(snapshot.setsTarget) sets")
                .font(IronFont.body(15))
                .foregroundColor(.ironTextPrimary)
            
            Text(snapshot.reason.detailText)
                .font(IronFont.body(13))
                .foregroundColor(.ironTextTertiary)
                .lineSpacing(3)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.ironPurple.opacity(0.1))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.ironPurple.opacity(0.3), lineWidth: 1)
        }
    }
    
    private func formatWeight(_ w: Double) -> String {
        if w == floor(w) { return "\(Int(w))" }
        return String(format: "%.1f", w)
    }
}

// MARK: - Set Row
private struct SetRow: View {
    @Binding var set: WorkoutSet
    
    @State private var weightText: String = ""
    
    var body: some View {
        HStack(spacing: 12) {
            Button {
                set.isCompleted.toggle()
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(set.isCompleted ? .ironPurple : .ironTextTertiary)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("REPS")
                    .font(IronFont.label(9))
                    .tracking(1.2)
                    .foregroundColor(.ironTextTertiary)
                Stepper(value: $set.reps, in: 0...100) {
                    Text("\(set.reps)")
                        .font(IronFont.bodySemibold(14))
                        .foregroundColor(.ironTextPrimary)
                }
                .tint(.ironPurple)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("WEIGHT")
                    .font(IronFont.label(9))
                    .tracking(1.2)
                    .foregroundColor(.ironTextTertiary)
                
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
                .font(IronFont.bodySemibold(14))
                .foregroundColor(.ironTextPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.ironSurface))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.glassBorder, lineWidth: 1))
                .tint(.ironPurple)
            }
            .frame(width: 120)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.glassWhite))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.glassBorder, lineWidth: 1))
    }
    
    private func formatWeight(_ w: Double) -> String {
        if w == floor(w) { return "\(Int(w))" }
        return String(format: "%.1f", w)
    }
}

// MARK: - Backward Compatibility Alias
private typealias TemplateEditorView = WorkoutBuilderView
