import SwiftUI
import SwiftData

private struct DTOMapperKey: EnvironmentKey {
    static let defaultValue: DTOMapper? = nil
}

extension EnvironmentValues {
    var dtoMapper: DTOMapper? {
        get { self[DTOMapperKey.self] }
        set { self[DTOMapperKey.self] = newValue }
    }
}
