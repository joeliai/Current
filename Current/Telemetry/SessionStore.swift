import Foundation

struct SessionArchive: Codable {
    var version = 2
    var sessions: [ChargingSession]
    var activeSession: ChargingSession?
}

final class SessionStore {
    private let queue = DispatchQueue(label: "Current.session-storage", qos: .utility)
    private let url: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Current", isDirectory: true)
        url = directory.appendingPathComponent("sessions-v1.json")
    }

    func load() throws -> SessionArchive? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let archive = try JSONDecoder().decode(SessionArchive.self, from: Data(contentsOf: url))
        guard (1 ... 2).contains(archive.version) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return archive
    }

    func save(
        _ archive: SessionArchive,
        synchronously: Bool = false,
        completion: @escaping (String?) -> Void
    ) {
        let work = { [url] in
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                var directory = url.deletingLastPathComponent()
                var attributes = URLResourceValues()
                attributes.isExcludedFromBackup = true
                try directory.setResourceValues(attributes)
                let data = try JSONEncoder().encode(archive)
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                DispatchQueue.main.async { completion(nil) }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async { completion(message) }
            }
        }
        if synchronously {
            queue.sync(execute: work)
        } else {
            queue.async(execute: work)
        }
    }
}
