import SwiftUI

@available(iOS 26.0, *)
private struct CuratorPointsServiceKey: EnvironmentKey {
    static let defaultValue: CuratorPointsService? = nil
}

@available(iOS 26.0, *)
extension EnvironmentValues {
    var curatorPointsService: CuratorPointsService? {
        get { self[CuratorPointsServiceKey.self] }
        set { self[CuratorPointsServiceKey.self] = newValue }
    }
}
