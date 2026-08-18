import Combine
import Foundation

/// Installs an independent, read-only post-offload export hook.
///
/// Important: this does NOT run inside BLEManager's offload completion path. It observes the same
/// `lastSyncedAt` signal the app already uses for post-offload refresh, debounces it, and launches a
/// detached utility task. Receiver/network failure therefore cannot delay or fail strap sync.
@MainActor
final class SelfHostedPushScheduler {
    static let shared = SelfHostedPushScheduler()

    private var cancellable: AnyCancellable?

    private init() {}

    func install(model: AppModel) {
        guard cancellable == nil else { return }
        cancellable = model.live.$lastSyncedAt
            .dropFirst()
            .compactMap { $0 }
            .removeDuplicates()
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak model] _ in
                guard SelfHostedPushSettings.enabled, let model else { return }
                Task(priority: .utility) {
                    guard let store = await model.repo.storeHandle() else { return }
                    _ = await SelfHostedPushWorker.shared.run(store: store)
                }
            }
    }
}
