import ComposableArchitecture
import Foundation

private enum AppContainerKey: DependencyKey {
    static let liveValue = AppContainer()
    static let previewValue = AppContainer()
    static let testValue = AppContainer()
}

extension DependencyValues {
    var appContainer: AppContainer {
        get { self[AppContainerKey.self] }
        set { self[AppContainerKey.self] = newValue }
    }
}

extension UserFacingError {
    static func unexpected(_ title: String, message: String) -> UserFacingError {
        UserFacingError(title: title, message: message)
    }
}

// TODO: As the remaining screens migrate, split AppContainer into smaller TCA clients
// so features can depend on narrower interfaces instead of the whole container.
