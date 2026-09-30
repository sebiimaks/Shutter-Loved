import XCTest
@testable import ShutterLover

final class FlangeDistanceCatalogueTests: XCTestCase {
    func testCommonMountDistancesAndFormattingAliases() throws {
        for (name, distance) in [(" Nikon F-mount ", 46.5), ("CANON FD", 42), ("Canon EF", 44), ("Pentax K", 45.46), ("M42×1", 45.46), ("Contax C/Y", 45.5)] {
            let matches = FlangeDistanceCatalogue.matches(name)
            XCTAssertEqual(matches.count, 1, name)
            XCTAssertEqual(try XCTUnwrap(matches.first).defaultDistanceMM, distance, accuracy: 0.000_001, name)
        }
        XCTAssertEqual(FlangeDistanceCatalogue.matches("Voigtlander QBM").first?.id, "rollei-qbm")
    }

    func testM39NamesRemainAmbiguousUnlessVariantIsSpecified() throws {
        XCTAssertGreaterThan(FlangeDistanceCatalogue.matches("M39").count, 1)
        let metric = FlangeDistanceCatalogue.matches("M39×1")
        XCTAssertEqual(Set(metric.map(\.id)), ["zorki-m39", "zenit-m39", "paxette-m39"])
        XCTAssertFalse(metric.contains { $0.id == "leica-ltm" })
        for (name, distance) in [("LTM", 28.8), ("Zorki M39", 28.8), ("Zenit M39", 45.2), ("Paxette M39", 44), ("Chaika M39", 27.5)] {
            let matches = FlangeDistanceCatalogue.matches(name)
            XCTAssertEqual(matches.count, 1, name)
            XCTAssertEqual(try XCTUnwrap(matches.first).defaultDistanceMM, distance, accuracy: 0.000_001)
        }
        XCTAssertGreaterThan(FlangeDistanceCatalogue.matches("DKL").count, 1)
    }

    func testSimilarNamesCannotSilentlySelectAnotherMount() {
        XCTAssertEqual(FlangeDistanceCatalogue.matches("Fujifilm X").first?.defaultDistanceMM, 17.7)
        XCTAssertEqual(FlangeDistanceCatalogue.matches("Fujica X").first?.defaultDistanceMM, 43.5)
        XCTAssertEqual(FlangeDistanceCatalogue.matches("Micro Four Thirds").first?.defaultDistanceMM, 19.25)
        XCTAssertEqual(FlangeDistanceCatalogue.matches("Four Thirds").first?.defaultDistanceMM, 38.67)
        XCTAssertEqual(FlangeDistanceCatalogue.matches("M42x0.75").first?.defaultDistanceMM, 55)
        XCTAssertEqual(FlangeDistanceCatalogue.matches("M37x0.75").first?.defaultDistanceMM, 55)
        XCTAssertEqual(FlangeDistanceCatalogue.matches("M37x1").first?.defaultDistanceMM, 45.46)
        for unknown in ["", "  ", "mount", "Nikon", "Fujica", "X", "Leica", "Canon VIL", "Nikon F3", "Olympus PEN F digital", "Canon EF adapted to Sony E", "Mystery Nikon F mount"] {
            XCTAssertTrue(FlangeDistanceCatalogue.matches(unknown).isEmpty, unknown)
        }
    }

    func testConflictingPublishedValuesHaveVisibleExplanations() throws {
        for (id, distance) in [("praktica-b", 44.4), ("nikonos", 39), ("cs", 12.526), ("mamiya-rb", 112), ("pentax-67", 85), ("leica-m", 27.8)] {
            let mount = try XCTUnwrap(FlangeDistanceCatalogue.mounts.first { $0.id == id })
            XCTAssertEqual(mount.defaultDistanceMM, distance, accuracy: 0.000_001)
            XCTAssertFalse(mount.notes.isEmpty)
            XCTAssertEqual(mount.sourceURLs, FlangeDistanceCatalogue.sourceURLs)
        }
    }

    func testCatalogueIntegrityAndEveryDisplayNameResolvesToItsOwnEntry() {
        let catalogue = FlangeDistanceCatalogue.mounts
        XCTAssertGreaterThan(catalogue.count, 100)
        XCTAssertEqual(Set(catalogue.map(\.id)).count, catalogue.count)
        XCTAssertEqual(FlangeDistanceCatalogue.sourcesCheckedOn, "2026-09-30")
        for mount in catalogue {
            XCTAssertTrue(mount.defaultDistanceMM.isFinite && mount.defaultDistanceMM > 0, mount.id)
            XCTAssertFalse(mount.sourceURLs.isEmpty, mount.id)
            XCTAssertTrue(mount.sourceURLs.allSatisfy { FlangeDistanceCatalogue.sourceURLs.contains($0) }, mount.id)
            XCTAssertEqual(FlangeDistanceCatalogue.matches(mount.name).map(\.id), [mount.id], mount.name)
        }
    }
}
