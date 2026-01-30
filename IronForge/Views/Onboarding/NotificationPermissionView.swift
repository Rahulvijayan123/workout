import SwiftUI

struct NotificationPermissionView: View {
    let onContinue: () -> Void
    
    @StateObject private var notificationService = NotificationService.shared
    @State private var isRequesting = false
    @State private var hasResponded = false
    
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    let brightViolet = Color(red: 0.68, green: 0.35, blue: 1.0)
    let deepIndigo = Color(red: 0.38, green: 0.15, blue: 0.72)
    let coolGrey = Color(red: 0.53, green: 0.60, blue: 0.65)
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    Spacer(minLength: 40)
                    
                    // Icon
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [neonPurple.opacity(0.3), neonPurple.opacity(0.05)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 80
                                )
                            )
                            .frame(width: 160, height: 160)
                        
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [neonPurple, brightViolet],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: neonPurple.opacity(0.5), radius: 20)
                    }
                    
                    // Header
                    VStack(spacing: 12) {
                        Text("STAY ON TRACK")
                            .font(IronFont.header(13))
                            .tracking(6)
                            .foregroundColor(coolGrey)
                        
                        Text("Enable Notifications")
                            .font(IronFont.headerMedium(28))
                            .tracking(2)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Benefits
                    VStack(alignment: .leading, spacing: 16) {
                        NotificationBenefitRow(
                            icon: "alarm.fill",
                            title: "Workout Reminders",
                            description: "Never miss a training session",
                            color: neonPurple
                        )
                        
                        NotificationBenefitRow(
                            icon: "flame.fill",
                            title: "Streak Alerts",
                            description: "Keep your momentum going",
                            color: Color.orange
                        )
                        
                        NotificationBenefitRow(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "Progress Updates",
                            description: "Celebrate your PRs and milestones",
                            color: Color.green
                        )
                        
                        NotificationBenefitRow(
                            icon: "bed.double.fill",
                            title: "Recovery Insights",
                            description: "Rest day reminders and tips",
                            color: Color.cyan
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial.opacity(0.4))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                    
                    Spacer(minLength: 120)
                }
            }
            
            // Bottom buttons
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.clear, Color(red: 0.02, green: 0.02, blue: 0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 30)
                
                VStack(spacing: 12) {
                    // Enable button
                    Button {
                        requestNotifications()
                    } label: {
                        HStack(spacing: 10) {
                            if isRequesting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            Text("ENABLE NOTIFICATIONS")
                                .font(IronFont.bodySemibold(15))
                                .tracking(1.5)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: [brightViolet, deepIndigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: neonPurple.opacity(0.4), radius: 12, y: 4)
                    }
                    .disabled(isRequesting)
                    
                    // Skip button
                    Button {
                        onContinue()
                    } label: {
                        Text("Maybe Later")
                            .font(IronFont.body(14))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
                .background(Color(red: 0.02, green: 0.02, blue: 0.02))
            }
        }
    }
    
    private func requestNotifications() {
        isRequesting = true
        
        Task {
            let granted = await notificationService.requestAuthorization()
            
            await MainActor.run {
                isRequesting = false
                hasResponded = true
                
                // Add badge for enabling notifications
                if granted {
                    UserDefaults.standard.set(true, forKey: "hasEnabledNotifications")
                }
                
                // Continue regardless of result
                onContinue()
            }
        }
    }
}

// MARK: - Notification Benefit Row
private struct NotificationBenefitRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(color)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(color.opacity(0.15))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(IronFont.bodySemibold(14))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(IronFont.body(12))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
        }
    }
}

#Preview {
    ZStack {
        Color(red: 0.02, green: 0.02, blue: 0.02)
            .ignoresSafeArea()
        NotificationPermissionView(onContinue: {})
    }
}
