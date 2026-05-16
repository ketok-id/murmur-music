import Foundation

/// `UserDefaults`-backed CRUD for `Scene` objects.
final class SceneStore: ObservableObject {
    @Published private(set) var scenes: [Scene] = []

    private let key = "youtube-audio-widget.scenes.v1"

    init() { load() }

    func add(_ scene: Scene) {
        scenes.append(scene)
        save()
    }

    func remove(id: UUID) {
        scenes.removeAll { $0.id == id }
        save()
    }

    func update(_ scene: Scene) {
        guard let i = scenes.firstIndex(where: { $0.id == scene.id }) else { return }
        scenes[i] = scene
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Scene].self, from: data) else { return }
        scenes = list
    }

    private func save() {
        if let data = try? JSONEncoder().encode(scenes) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
