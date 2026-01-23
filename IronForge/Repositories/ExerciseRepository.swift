import Foundation

protocol ExerciseRepository {
    func search(query: String) async -> [Exercise]
    func exercise(id: String) async -> Exercise?
}

/// Offline seed library so the app works without any backend running.
final class LocalExerciseRepository: ExerciseRepository {
    private let exercises: [Exercise]
    
    init(exercises: [Exercise]? = nil) {
        // Load from bundled JSON instead of ExerciseSeeds
        self.exercises = exercises ?? ExerciseLoader.loadBundledExercises()
    }
    
    func search(query: String) async -> [Exercise] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return exercises }
        return exercises.filter { ex in
            ex.name.lowercased().contains(q) ||
            ex.target.lowercased().contains(q) ||
            ex.bodyPart.lowercased().contains(q) ||
            ex.equipment.lowercased().contains(q)
        }
    }
    
    func exercise(id: String) async -> Exercise? {
        exercises.first { $0.id == id }
    }
}

/// Minimal ExerciseDB API client (works with a self-hosted `exercisedb-api` instance,
/// or RapidAPI-backed ExerciseDB if you configure headers).
///
/// Reference: https://github.com/ExerciseDB/exercisedb-api
final class ExerciseDBRepository: ExerciseRepository {
    struct Config: Sendable {
        var baseURL: URL
        /// Optional RapidAPI key (if you're using the hosted ExerciseDB).
        var rapidAPIKey: String?
        /// Optional RapidAPI host header.
        var rapidAPIHost: String?
    }
    
    private let config: Config
    private let urlSession: URLSession
    
    init(config: Config, urlSession: URLSession = .shared) {
        self.config = config
        self.urlSession = urlSession
    }
    
    func search(query: String) async -> [Exercise] {
        // ExerciseDB commonly supports /exercises/name/{name}. If not available, fallback to /exercises and filter.
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return (try? await fetchAll()) ?? []
        }
        
        if let byName = try? await fetchByName(trimmed) {
            return byName
        }
        
        let all = (try? await fetchAll()) ?? []
        let q = trimmed.lowercased()
        return all.filter { $0.name.lowercased().contains(q) }
    }
    
    func exercise(id: String) async -> Exercise? {
        let all = (try? await fetchAll()) ?? []
        return all.first { $0.id == id }
    }
    
    // MARK: - Networking
    
    private func fetchAll() async throws -> [Exercise] {
        let url = config.baseURL.appending(path: "exercises")
        return try await fetch(url: url)
    }
    
    private func fetchByName(_ name: String) async throws -> [Exercise] {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let url = config.baseURL.appending(path: "exercises/name/\(encoded)")
        return try await fetch(url: url)
    }
    
    private func fetch(url: URL) async throws -> [Exercise] {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        
        if let key = config.rapidAPIKey, !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "X-RapidAPI-Key")
        }
        if let host = config.rapidAPIHost, !host.isEmpty {
            request.setValue(host, forHTTPHeaderField: "X-RapidAPI-Host")
        }
        
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([Exercise].self, from: data)
    }
}

// MARK: - Seeds (Deprecated - kept for fallback only)
/// @deprecated Use ExerciseLoader.loadBundledExercises() instead.
/// This is kept only as a fallback for graceful degradation.
enum ExerciseSeeds {
    static let defaultExercises: [Exercise] = [
        Exercise(
            id: "barbell_back_squat",
            name: "barbell back squat",
            bodyPart: "upper legs",
            equipment: "barbell",
            gifUrl: nil,
            target: "quads",
            secondaryMuscles: ["glutes", "hamstrings", "core"],
            instructions: [
                "Set the bar on your upper back and brace your core.",
                "Sit down and back until hips are below parallel.",
                "Drive up through mid-foot, keeping knees tracking over toes."
            ]
        ),
        Exercise(
            id: "barbell_bench_press",
            name: "barbell bench press",
            bodyPart: "chest",
            equipment: "barbell",
            gifUrl: nil,
            target: "pectorals",
            secondaryMuscles: ["triceps", "front deltoids"],
            instructions: [
                "Set your shoulder blades and maintain a slight arch.",
                "Lower the bar under control to your mid-chest.",
                "Press up, keeping wrists stacked over elbows."
            ]
        ),
        Exercise(
            id: "barbell_deadlift",
            name: "barbell deadlift",
            bodyPart: "back",
            equipment: "barbell",
            gifUrl: nil,
            target: "erector spinae",
            secondaryMuscles: ["glutes", "hamstrings", "lats", "traps", "core"],
            instructions: [
                "Set your hips and brace; pull slack out of the bar.",
                "Drive the floor away and stand tall with the bar close.",
                "Lower with control by hinging at the hips."
            ]
        ),
        Exercise(
            id: "pull_up",
            name: "pull up",
            bodyPart: "back",
            equipment: "body weight",
            gifUrl: nil,
            target: "lats",
            secondaryMuscles: ["biceps", "rear deltoids", "mid back"],
            instructions: [
                "Start from a dead hang with shoulders packed.",
                "Pull chest toward the bar by driving elbows down.",
                "Lower under control to full extension."
            ]
        ),
        Exercise(
            id: "dumbbell_shoulder_press",
            name: "dumbbell shoulder press",
            bodyPart: "shoulders",
            equipment: "dumbbell",
            gifUrl: nil,
            target: "delts",
            secondaryMuscles: ["triceps", "upper chest"],
            instructions: [
                "Brace and keep ribs down.",
                "Press dumbbells overhead, finishing with biceps by ears.",
                "Lower under control to shoulder level."
            ]
        )
    ]
}

