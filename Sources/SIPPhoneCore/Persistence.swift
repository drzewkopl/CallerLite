import Foundation

final class JSONStore {
    let directory: URL

    init(name: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func load<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        let url = directory.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, to file: String) {
        let url = directory.appendingPathComponent(file)
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
