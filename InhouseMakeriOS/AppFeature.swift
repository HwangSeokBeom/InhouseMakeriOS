import ComposableArchitecture
import Foundation

struct AppFeature: Reducer {
    struct State: Equatable {
        var selectedTab: AppTab = .home
        var phase: Phase = .bootstrapping
    }

    enum Phase: Equatable {
        case bootstrapping
        case unauthenticated
        case authenticated
    }

    enum Action: Equatable {
        case selectedTabChanged(AppTab)
        case phaseChanged(Phase)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .selectedTabChanged(tab):
                state.selectedTab = tab
                return .none

            case let .phaseChanged(phase):
                state.phase = phase
                return .none
            }
        }
    }
}

struct MainTabFeature: Reducer {
    struct State: Equatable {
        var selectedTab: AppTab = .home
    }

    enum Action: Equatable {
        case selectedTabChanged(AppTab)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .selectedTabChanged(tab):
                state.selectedTab = tab
                return .none
            }
        }
    }
}

// TODO: Move the legacy AppSessionViewModel/AppRouter shell into AppFeature/MainTabFeature
// once the 2nd and 3rd migration waves replace the remaining ObservableObject screens.
