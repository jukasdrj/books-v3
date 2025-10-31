import SwiftUI

private struct DTOMapperKey: EnvironmentKey {
    static let defaultValue: DTOMapper = {
        let container = try! ModelContainer(for: Work.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return DTOMapper(modelContext: container.mainContext)
    }()
}

extension EnvironmentValues {
    var dtoMapper: DTOMapper {
        get { self[DTOMapperKey.self] }
        set { self[DTOMapperKey.self] = newValue }
    }
}
