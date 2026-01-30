import SwiftUI

struct WorkoutSplitView: View {
    @EnvironmentObject var appState: AppState
    let onContinue: () -> Void
    
    @State private var selectedSplit: WorkoutSplit = .pushPullLegs
    @State private var showingCustomBuilder = false
    
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    let brightViolet = Color(red: 0.68, green: 0.35, blue: 1.0)
    let deepIndigo = Color(red: 0.38, green: 0.15, blue: 0.72)
    let coolGrey = Color(red: 0.53, green: 0.60, blue: 0.65)
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Header - Tech/System style
                VStack(spacing: 8) {
                    Text("PROGRAM STRUCTURE")
                        .font(IronFont.header(13))
                        .tracking(6)
                        .foregroundColor(coolGrey)
                    
                    Text("TRAINING SPLIT")
                        .font(IronFont.headerMedium(22))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)
                
                // Split options
                VStack(spacing: 10) {
                    ForEach(WorkoutSplit.allCases, id: \.self) { split in
                        TechSplitCard(
                            split: split,
                            isSelected: selectedSplit == split,
                            neonPurple: neonPurple
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedSplit = split
                                if split == .custom {
                                    showingCustomBuilder = true
                                }
                            }
                        }
                    }
                }
                
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                // Gradient fade from transparent to background
                LinearGradient(
                    colors: [Color.clear, Color(red: 0.02, green: 0.02, blue: 0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 30)
                
                TactileGlassButton(
                    title: "NEXT PHASE",
                    isEnabled: true,
                    brightViolet: brightViolet,
                    deepIndigo: deepIndigo
                ) {
                    saveAndContinue()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
                .background(Color(red: 0.02, green: 0.02, blue: 0.02))
            }
        }
        .sheet(isPresented: $showingCustomBuilder) {
            CustomSplitBuilderView(
                schedule: $appState.userProfile.customWeeklySchedule,
                onSave: {
                    showingCustomBuilder = false
                }
            )
        }
    }
    
    private func saveAndContinue() {
        appState.userProfile.workoutSplit = selectedSplit
        onContinue()
    }
}

// MARK: - Custom Split Builder View
struct CustomSplitBuilderView: View {
    @Binding var schedule: CustomWeeklySchedule
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedDay: DayOfWeek? = nil
    
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    let coolGrey = Color(red: 0.53, green: 0.60, blue: 0.65)
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(red: 0.02, green: 0.02, blue: 0.02)
                    .ignoresSafeArea()
                
                // Ambient glow
                GeometryReader { geo in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [neonPurple.opacity(0.2), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 250
                            )
                        )
                        .frame(width: 500, height: 500)
                        .offset(x: geo.size.width * 0.3, y: -100)
                }
                .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Text("DESIGN YOUR SPLIT")
                                .font(IronFont.header(13))
                                .tracking(4)
                                .foregroundColor(coolGrey)
                            
                            Text("Tap a day to assign a workout type")
                                .font(IronFont.body(14))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .padding(.top, 16)
                        
                        // Summary
                        HStack {
                            Text("\(schedule.workoutDaysCount) WORKOUT DAYS")
                                .font(IronFont.label(11))
                                .tracking(2)
                                .foregroundColor(neonPurple)
                            
                            Spacer()
                            
                            Text("\(7 - schedule.workoutDaysCount) REST DAYS")
                                .font(IronFont.label(11))
                                .tracking(2)
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .padding(.horizontal, 4)
                        
                        // Days of the week
                        VStack(spacing: 10) {
                            ForEach(DayOfWeek.allCases, id: \.self) { day in
                                DayScheduleRow(
                                    day: day,
                                    workoutType: schedule[day],
                                    isSelected: selectedDay == day,
                                    neonPurple: neonPurple,
                                    onTap: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            selectedDay = (selectedDay == day) ? nil : day
                                        }
                                    }
                                )
                                
                                // Workout type picker when day is selected
                                if selectedDay == day {
                                    WorkoutTypePickerGrid(
                                        selectedType: Binding(
                                            get: { schedule[day] },
                                            set: { newType in
                                                schedule[day] = newType
                                            }
                                        ),
                                        neonPurple: neonPurple
                                    )
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                }
                            }
                        }
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationTitle("Custom Split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white.opacity(0.6))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                    }
                    .foregroundColor(neonPurple)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Day Schedule Row
private struct DayScheduleRow: View {
    let day: DayOfWeek
    let workoutType: WorkoutDayType
    let isSelected: Bool
    let neonPurple: Color
    let onTap: () -> Void
    
    private var typeColor: Color {
        let c = workoutType.color
        return Color(red: c.red, green: c.green, blue: c.blue)
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Day indicator
                Text(day.shortName)
                    .font(IronFont.bodySemibold(14))
                    .foregroundColor(workoutType == .rest ? .white.opacity(0.4) : .white)
                    .frame(width: 50, alignment: .leading)
                
                // Workout type badge
                HStack(spacing: 8) {
                    Image(systemName: workoutType.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(typeColor)
                    
                    Text(workoutType.rawValue.uppercased())
                        .font(IronFont.label(11))
                        .tracking(1)
                        .foregroundColor(workoutType == .rest ? .white.opacity(0.4) : .white)
                }
                
                Spacer()
                
                // Edit indicator
                Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? neonPurple : .white.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial.opacity(0.4))
                    RoundedRectangle(cornerRadius: 16)
                        .fill(workoutType == .rest ? Color.white.opacity(0.02) : typeColor.opacity(0.08))
                    
                    if isSelected {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(neonPurple.opacity(0.1))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? neonPurple.opacity(0.5) : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workout Type Picker Grid
private struct WorkoutTypePickerGrid: View {
    @Binding var selectedType: WorkoutDayType
    let neonPurple: Color
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(WorkoutDayType.allCases, id: \.self) { type in
                WorkoutTypeChip(
                    type: type,
                    isSelected: selectedType == type,
                    neonPurple: neonPurple
                ) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        selectedType = type
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Workout Type Chip
private struct WorkoutTypeChip: View {
    let type: WorkoutDayType
    let isSelected: Bool
    let neonPurple: Color
    let onTap: () -> Void
    
    private var typeColor: Color {
        let c = type.color
        return Color(red: c.red, green: c.green, blue: c.blue)
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isSelected ? typeColor : .white.opacity(0.5))
                
                Text(type.rawValue)
                    .font(IronFont.label(9))
                    .tracking(0.5)
                    .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? typeColor.opacity(0.2) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? typeColor.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tech Split Card (No radio button - background shift is the indicator)
struct TechSplitCard: View {
    let split: WorkoutSplit
    let isSelected: Bool
    let neonPurple: Color
    let purpleGlow = Color(red: 0.85, green: 0.71, blue: 0.99) // #D8B4FE for glows
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Icon in small glass container (32x32)
                Image(systemName: split.icon)
                    .font(.system(size: 18, weight: .ultraLight))
                    .foregroundColor(isSelected ? neonPurple : .white.opacity(0.5))
                    .shadow(color: isSelected ? purpleGlow.opacity(0.6) : .clear, radius: 6)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? neonPurple.opacity(0.12) : Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(isSelected ? 0.15 : 0.06), lineWidth: 1)
                            )
                    )
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(split.rawValue.uppercased())
                        .font(IronFont.bodyMedium(14)) // Medium weight for dark mode
                        .foregroundColor(isSelected ? .white : .white.opacity(0.8))
                    
                    Text(split.description)
                        .font(IronFont.bodyMedium(11))
                        .foregroundColor(Color(red: 0.61, green: 0.64, blue: 0.69)) // Silver #9CA3AF
                }
                
                Spacer()
                
                // Selection chevron (subtle, not radio button)
                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(neonPurple.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    // Base glass layer
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial.opacity(0.4))
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.03))
                    
                    // Selected: Deep Purple Glass (rgba(168, 85, 247, 0.15))
                    if isSelected {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                RadialGradient(
                                    colors: [neonPurple.opacity(0.18), neonPurple.opacity(0.08), Color.clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 150
                                )
                            )
                    }
                    
                    // Inner glow (light catching curvature)
                    VStack {
                        LinearGradient(
                            colors: [Color.white.opacity(isSelected ? 0.12 : 0.08), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 25)
                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            )
            .overlay(
                // Specular ridge: Top brighter than bottom
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: isSelected
                                ? [purpleGlow.opacity(0.5), neonPurple.opacity(0.2), Color.black.opacity(0.2)]
                                : [Color.white.opacity(0.2), Color.white.opacity(0.06), Color.black.opacity(0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: isSelected ? purpleGlow.opacity(0.25) : .clear, radius: 14, y: 5)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    OnboardingContainerView()
        .environmentObject(AppState())
}
