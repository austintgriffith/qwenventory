import Foundation

/// Models live in an App Group folder, so every app you build with the same
/// team and group uses one copy instead of a few GB each. The group comes
/// from Info.plist (`BrainAppGroup`, set from data/brain.json at build).
/// Set up before any HubClient exists: swift-huggingface reads HF_HUB_CACHE
/// at runtime.
enum SharedModels {
    static let groupID = Bundle.main.object(forInfoDictionaryKey: "BrainAppGroup") as? String ?? ""

    static var hubURL: URL? {
        guard !groupID.isEmpty else { return nil }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("Library/huggingface/hub")
    }

    /// Where models load from: the shared folder, or the app's own cache.
    static var activeHub: URL {
        hubURL
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface/hub")
    }

    /// True when the model's files are already on the phone (copied over
    /// USB by tools/copy-model.sh, or downloaded before).
    static func isOnDisk(_ id: String) -> Bool {
        let snaps = activeHub
            .appendingPathComponent("models--" + id.replacingOccurrences(of: "/", with: "--"))
            .appendingPathComponent("snapshots")
        let fm = FileManager.default
        for snap in (try? fm.contentsOfDirectory(atPath: snaps.path)) ?? [] {
            let dir = snaps.appendingPathComponent(snap)
            let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            if files.contains("config.json"), files.contains(where: { $0.hasSuffix(".safetensors") }) {
                return true
            }
        }
        return false
    }

    static func configure() {
        guard let hub = hubURL else {
            DebugLog.log("no app group, using private cache")
            return
        }
        try? FileManager.default.createDirectory(at: hub, withIntermediateDirectories: true)
        setenv("HF_HUB_CACHE", hub.path, 1)
        DebugLog.log("model cache: \(hub.path)")
        deletePrivateCopies(sharedHub: hub)
    }

    /// Once a model is in the shared folder, the app's own copy is dead
    /// weight. Never deletes from the shared folder: other apps use it.
    private static func deletePrivateCopies(sharedHub: URL) {
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let privateHub = caches.appendingPathComponent("huggingface/hub")
        let shared = Set((try? fm.contentsOfDirectory(atPath: sharedHub.path)) ?? [])
        for sub in [privateHub, privateHub.appendingPathComponent(".locks")] {
            let names = (try? fm.contentsOfDirectory(atPath: sub.path)) ?? []
            for name in names where name.hasPrefix("models--") && shared.contains(name) {
                try? fm.removeItem(at: sub.appendingPathComponent(name))
                DebugLog.log("deleted private copy \(name)")
            }
        }
    }
}
