import UIKit

@MainActor
private extension UIApplication {
    var preferredWindowScenes: [UIWindowScene] {
        let windowScenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeWindowScenes = windowScenes.filter { $0.activationState == .foregroundActive }
        return activeWindowScenes.isEmpty ? windowScenes : activeWindowScenes
    }

    var preferredKeyWindow: UIWindow? {
        for scene in preferredWindowScenes {
            if let keyWindow = scene.windows.first(where: \.isKeyWindow) {
                return keyWindow
            }
        }

        for scene in preferredWindowScenes {
            if let visibleWindow = scene.windows.first(where: { !$0.isHidden }) {
                return visibleWindow
            }
        }

        return nil
    }
}

@MainActor
func topViewController() -> UIViewController? {
    topViewController(from: UIApplication.shared.preferredKeyWindow?.rootViewController)
}

func currentDeviceModelDescription() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machineIdentifier = withUnsafePointer(to: &systemInfo.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1) {
            String(cString: $0)
        }
    }

    let modelName = UIDevice.current.model
    if machineIdentifier.isEmpty {
        return modelName
    }
    return "\(modelName) (\(machineIdentifier))"
}

@MainActor
private func topViewController(from rootViewController: UIViewController?) -> UIViewController? {
    if let navigationController = rootViewController as? UINavigationController {
        return topViewController(from: navigationController.visibleViewController ?? navigationController.topViewController)
    }

    if let tabBarController = rootViewController as? UITabBarController {
        return topViewController(from: tabBarController.selectedViewController)
    }

    if let presentedViewController = rootViewController?.presentedViewController {
        return topViewController(from: presentedViewController)
    }

    return rootViewController
}
