import Testing
import Foundation
@testable import BooksTrackerFeature

@Suite("CuratorPointsService")
@MainActor
struct CuratorPointsServiceTests {

    @Test("Award points updates total and persists to UserDefaults")
    @MainActor
    func awardPointsUpdatesTotalAndPersists() async throws {
        let testDefaults = UserDefaults(suiteName: "test.curatorPoints")!
        testDefaults.removePersistentDomain(forName: "test.curatorPoints")

        let service = CuratorPointsService(userDefaults: testDefaults)

        service.awardPoints(10, for: "test action")

        #expect(service.totalPoints == 10)
        #expect(testDefaults.integer(forKey: "com.bookstracker.curatorPoints") == 10)
    }

    @Test("Award multiple times accumulates points")
    @MainActor
    func awardMultipleTimesAccumulatesPoints() async throws {
        let testDefaults = UserDefaults(suiteName: "test.curatorPoints.multi")!
        testDefaults.removePersistentDomain(forName: "test.curatorPoints.multi")

        let service = CuratorPointsService(userDefaults: testDefaults)

        service.awardPoints(10, for: "first action")
        service.awardPoints(15, for: "second action")
        service.awardPoints(5, for: "third action")

        #expect(service.totalPoints == 30)
        #expect(testDefaults.integer(forKey: "com.bookstracker.curatorPoints") == 30)
    }

    @Test("Award zero points does nothing")
    @MainActor
    func awardZeroPointsDoesNothing() async throws {
        let testDefaults = UserDefaults(suiteName: "test.curatorPoints.zero")!
        testDefaults.removePersistentDomain(forName: "test.curatorPoints.zero")

        let service = CuratorPointsService(userDefaults: testDefaults)

        service.awardPoints(10, for: "first")
        service.awardPoints(0, for: "zero")

        #expect(service.totalPoints == 10)
    }

    @Test("Award negative points is ignored")
    @MainActor
    func awardNegativePointsIsIgnored() async throws {
        let testDefaults = UserDefaults(suiteName: "test.curatorPoints.negative")!
        testDefaults.removePersistentDomain(forName: "test.curatorPoints.negative")

        let service = CuratorPointsService(userDefaults: testDefaults)

        service.awardPoints(20, for: "first")
        service.awardPoints(-5, for: "negative")

        #expect(service.totalPoints == 20)
    }

    @Test("Reset points clears total and removes from UserDefaults")
    @MainActor
    func resetPointsClearsTotalAndStorage() async throws {
        let testDefaults = UserDefaults(suiteName: "test.curatorPoints.reset")!
        testDefaults.removePersistentDomain(forName: "test.curatorPoints.reset")

        let service = CuratorPointsService(userDefaults: testDefaults)

        service.awardPoints(25, for: "test")
        #expect(service.totalPoints == 25)

        service.resetPoints()

        #expect(service.totalPoints == 0)
        #expect(testDefaults.object(forKey: "com.bookstracker.curatorPoints") == nil)
    }

    @Test("Service initializes with existing points from UserDefaults")
    @MainActor
    func serviceInitializesWithExistingPoints() async throws {
        let testDefaults = UserDefaults(suiteName: "test.curatorPoints.init")!
        testDefaults.removePersistentDomain(forName: "test.curatorPoints.init")

        // Pre-populate UserDefaults
        testDefaults.set(42, forKey: "com.bookstracker.curatorPoints")

        let service = CuratorPointsService(userDefaults: testDefaults)

        #expect(service.totalPoints == 42)
    }

    @Test("Multiple award calls persist correctly")
    @MainActor
    func multipleAwardCallsPersist() async throws {
        let testDefaults = UserDefaults(suiteName: "test.curatorPoints.persist")!
        testDefaults.removePersistentDomain(forName: "test.curatorPoints.persist")

        let service = CuratorPointsService(userDefaults: testDefaults)

        service.awardPoints(15, for: "cultural origins")
        #expect(testDefaults.integer(forKey: "com.bookstracker.curatorPoints") == 15)

        service.awardPoints(10, for: "gender distribution")
        #expect(testDefaults.integer(forKey: "com.bookstracker.curatorPoints") == 25)

        service.awardPoints(25, for: "cascade bonus")
        #expect(testDefaults.integer(forKey: "com.bookstracker.curatorPoints") == 50)
    }
}
