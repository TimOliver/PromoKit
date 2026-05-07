@testable import PromoKit

/// Records every provider value passed to a coordinator's `providerUpdatedHandler` so tests
/// can react to (or assert on) the sequence of resolution outcomes.
final class ProviderResolutionRecorder {
    private(set) var resolvedProviders: [PromoProvider?] = []
    var onUpdate: ((PromoProvider?) -> Void)?

    func record(_ provider: PromoProvider?) {
        resolvedProviders.append(provider)
        onUpdate?(provider)
    }
}
