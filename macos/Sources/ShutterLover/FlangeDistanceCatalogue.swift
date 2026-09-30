import Foundation

/// Nominal mount geometry, independent of a particular camera's measured tolerances.
struct FlangeMount: Identifiable, Equatable {
    let id: String
    let name: String
    let aliases: [String]
    let defaultDistanceMM: Double
    let sourceURLs: [URL]
    let notes: String
}

enum FlangeDistanceCatalogue {
    static let sourcesCheckedOn = "2026-09-30"
    static let brianSmithURL = URL(string: "https://briansmith.com/flange-focal-distance-guide/")!
    static let wikipediaURL = URL(string: "https://en.wikipedia.org/wiki/Flange_focal_distance")!
    static let sourceURLs = [brianSmithURL, wikipediaURL]

    // Only names, numeric facts and our own explanatory notes are reproduced. Source
    // differences remain visible instead of averaging incompatible specifications.
    static let mounts: [FlangeMount] = [
        mount("samsung-nx-mini", "Samsung NX mini", 6.95, ["NX mini", "Samsung NX-M"], sources: [wikipediaURL]),
        mount("pentax-q", "Pentax Q", 9.2, ["Q mount"]),
        mount("industrial-m58", "Industrial M58×0.75", 12, ["M58×0.75", "M58×0.75 mm mount"], sources: [wikipediaURL]),
        mount("d", "D mount", 12.29, []),
        mount("cs", "CS mount", 12.526, [], notes: "Wikipedia gives 12.526 mm; Brian Smith lists 12.50 mm. The default uses Wikipedia's value."),
        mount("nikon-z", "Nikon Z", 16, []),
        mount("dji-dl", "DJI DL", 16.84, []),
        mount("nikon-1", "Nikon 1", 17, []),
        mount("c", "C mount", 17.526, []),
        mount("fujifilm-x", "Fujifilm X", 17.7, ["Fuji X"], notes: "Fujifilm's mirrorless mount. Fujica X for film SLRs has a different distance."),
        mount("canon-ef-m", "Canon EF-M", 18, ["EF-M"]),
        mount("sony-e", "Sony E", 18, ["Sony FE", "Sony E/FE"]),
        mount("hasselblad-xcd", "Hasselblad XCD", 18.14, ["Hasselblad X system", "XCD"], notes: "Nominal distance; Wikipedia also lists a +0.05/−0.00 mm tolerance."),
        mount("sony-fz", "Sony FZ", 19, []),
        mount("micro-four-thirds", "Micro Four Thirds", 19.25, ["Micro Four Thirds System", "MFT", "M4/3", "Micro 4/3", "Micro 4/3rds"]),
        mount("canon-rf", "Canon RF", 20, ["Canon RF-S", "RF", "RF-S"]),
        mount("leica-l", "Leica / Panasonic / Sigma L", 20, ["L mount", "Leica L", "Panasonic L", "Sigma L", "L-Mount Alliance"]),
        mount("jvc-third-inch", "JVC 1/3-inch bayonet", 25, ["JVC 1/3″ bayonet mount", "JVC 1/3\" bayonet mount", "JVC 1/3 bayonet"]),
        mount("samsung-nx", "Samsung NX", 25.5, ["NX"]),
        mount("fujifilm-g", "Fujifilm G", 26.7, ["Fujifilm GFX", "Fuji G", "Fuji GFX"]),
        mount("pentax-auto-110", "Pentax Auto 110", 27, ["Pentax 110"]),
        mount("red-one", "RED ONE interchangeable mount", 27.3, ["RED ONE"]),
        mount("chaika-m39", "Chaika M39", 27.5, ["Chaika", "M39"], sources: [wikipediaURL], notes: "Half-frame Chaika variant. M39 alone is ambiguous; select the actual camera mount."),
        mount("leica-m", "Leica M", 27.8, ["M mount", "Voigtländer VM", "Epson EM", "Zeiss ZM", "Konica KM", "Minolta M"], notes: "The default is the 27.8 mm inner-rail reference. Wikipedia also lists 27.95 mm to the outer rails; check which surface you are using."),
        mount("leica-ltm", "Leica thread mount (LTM / L39)", 28.8, ["Leica LTM", "Leica thread mount", "Leica screw mount", "LTM", "L39", "Leica M39", "M39×26tpi", "M39"], notes: "Leica uses a 39 mm, 26 tpi thread. Other M39 families can have different pitches or flange distances."),
        mount("zorki-m39", "Zorki M39×1/28.8", 28.8, ["Zorki M39", "M39×1/28.8", "M39×1/28,8", "M39", "M39×1"], sources: [wikipediaURL], notes: "Zorki's 28.8 mm M39×1 variant. Generic M39 or M39×1 does not uniquely identify this mount."),
        mount("olympus-pen-f", "Olympus PEN F (film)", 28.95, ["Olympus PEN F", "Olympus Pen-F film"], notes: "Film half-frame SLR mount. The digital PEN-F uses Micro Four Thirds."),
        mount("contax-g", "Contax G", 29, []),
        mount("kiev-16u", "Kiev-16U", 31, [], sources: [wikipediaURL]),
        mount("hasselblad-xpan", "Hasselblad XPan / Fujifilm TX", 34.27, ["Hasselblad XPan", "Fujifilm TX", "XPan"], sources: [wikipediaURL]),
        mount("contax-rf", "Contax RF", 34.85, ["Contax rangefinder"]),
        mount("nikon-s", "Nikon S", 34.85, ["Nikon rangefinder"]),
        mount("half-inch-tv", "1/2-inch TV bayonet (non-Sony)", 35.74, ["1/2″ TV bayonet mount", "1/2\" TV bayonet mount", "1/2 TV bayonet"], notes: "JVC, Hitachi and Panasonic type. Sony's 1/2-inch bayonet has a different distance."),
        mount("minolta-v", "Minolta V", 36, ["Minolta Vectis"]),
        mount("sony-half-inch-tv", "Sony 1/2-inch TV bayonet", 38, ["Sony 1/2″ TV bayonet mount", "Sony 1/2\" TV bayonet mount", "Sony 1/2 TV bayonet"]),
        mount("panavision-sp70", "Panavision SP70", 38, ["SP70"], sources: [wikipediaURL]),
        mount("four-thirds", "Four Thirds", 38.67, ["Four Thirds System", "Olympus Four Thirds", "Olympus Four Thirds System", "4/3"], notes: "SLR Four Thirds mount; Micro Four Thirds has a different distance."),
        mount("nikonos", "Nikonos", 39, [], notes: "Wikipedia gives 39 mm for the underwater scale-focus system; Brian Smith lists 28 mm. The default uses Wikipedia's value. Verify your camera before positioning."),
        mount("aaton", "Aaton", 40, [], sources: [wikipediaURL]),
        mount("konica-f", "Konica F", 40.5, []),
        mount("konica-ar", "Konica AR", 40.5, ["AR mount"]),
        mount("canon-fl", "Canon FL", 42, ["FL"]),
        mount("canon-fd", "Canon FD", 42, ["FD", "Canon new FD", "Canon nFD"]),
        mount("start", "Start (Soviet SLR)", 42, ["Start"], sources: [wikipediaURL]),
        mount("minolta-sr", "Minolta SR / MC / MD", 43.5, ["Minolta SR", "Minolta MC", "Minolta MD", "Minolta MC/MD", "Minolta SR/MC/MD", "MC/MD"]),
        mount("fujica-x", "Fujica X", 43.5, [], notes: "Fujica film SLR mount. Fujifilm X mirrorless cameras use 17.7 mm."),
        mount("petri-bayonet", "Petri bayonet", 43.5, [], sources: [wikipediaURL]),
        mount("pentaflex", "Pentaflex (16 mm)", 44, ["Pentaflex", "Pentaflex 16"]),
        mount("canon-ef", "Canon EF", 44, ["EF", "Canon EOS EF"]),
        mount("canon-ef-s", "Canon EF-S", 44, ["EF-S"], sources: [wikipediaURL]),
        mount("sigma-sa", "Sigma SA", 44, []),
        mount("paxette-m39", "Braun Paxette M39×1", 44, ["Braun Paxette M39", "Paxette M39", "Paxette M39×1", "M39", "M39×1"], sources: [wikipediaURL], notes: "Paxette rangefinder screw mount, not the Paxette Reflex DKL variant. Generic M39 is ambiguous."),
        mount("kiev-automat", "Kiev Automat", 44, [], sources: [wikipediaURL]),
        mount("arri-lpl", "Arri LPL", 44, ["LPL"]),
        mount("praktica-b", "Praktica B", 44.4, ["Praktica bayonet", "Praktica PB", "PB mount"], notes: "Wikipedia gives 44.4 mm; Brian Smith lists 44 mm. The default uses Wikipedia's value."),
        mount("sony-minolta-a", "Minolta / Sony A", 44.5, ["Minolta A", "Konica Minolta A", "Sony A", "Minolta/Sony A", "A mount"]),
        mount("rollei-qbm", "Rollei / Voigtländer QBM", 44.5, ["Rollei QBM", "Voigtländer QBM", "QBM"]),
        mount("samsung-kenox", "Samsung Kenox", 44.5, [], sources: [wikipediaURL]),
        mount("exakta", "Exakta", 44.7, ["Exakta 35mm"], notes: "35 mm Exakta mount. Exakta 66 uses the Pentacon Six mount."),
        mount("zenit-m39", "Zenit M39×1/45.2", 45.2, ["Zenit M39", "Zenit M39×1", "M39×1/45.2", "M39×1/45,2", "M39", "M39×1"], notes: "Wikipedia distinguishes early Zenit SLRs at 45.2 mm; Brian Smith's generic M39×1 entry says 45.46 mm. The default uses the specifically identified Zenit variant."),
        mount("asahiflex-m37", "Asahiflex M37×1", 45.46, ["M37×1", "Asahiflex"], sources: [wikipediaURL]),
        mount("m42", "M42×1", 45.46, ["M42", "M42 screw", "Pentax screw mount", "Praktica screw mount"], notes: "The 1 mm pitch SLR screw mount. T-mount uses M42×0.75 and a different distance."),
        mount("pentax-k", "Pentax K", 45.46, ["K mount", "PK mount"]),
        mount("contax-yashica", "Contax / Yashica C/Y", 45.5, ["Contax C/Y", "Contax Yashica", "Contax/Yashica", "C/Y", "CY mount", "Yashica C/Y"]),
        mount("mamiya-z", "Mamiya Z", 45.5, [], sources: [wikipediaURL]),
        mount("kodak-dkl", "Kodak Retina DKL", 45.7, ["Kodak DKL", "Retina DKL", "DKL"], notes: "Kodak Retina variant. Generic DKL also describes other systems, including a different Zenit distance."),
        mount("bessamatic-dkl", "Voigtländer Bessamatic DKL", 45.7, ["Bessamatic DKL", "DKL"], notes: "Bessamatic/Ultramatic variant. Select the specific DKL family."),
        mount("paxette-reflex-dkl", "Braun Paxette Reflex DKL", 45.7, ["Paxette Reflex DKL", "DKL"], sources: [wikipediaURL], notes: "Reflex DKL variant, not the 44 mm Paxette rangefinder M39 screw mount."),
        mount("vitessa-dkl", "Voigtländer Vitessa T DKL", 45.7, ["Vitessa T DKL", "DKL"], notes: "Vitessa T DKL variant. Select the specific DKL family."),
        mount("yashica-ma", "Yashica MA", 45.8, [], notes: "Wikipedia labels this distance as measured."),
        mount("olympus-om", "Olympus OM", 46, ["OM mount"]),
        mount("nikon-f", "Nikon F", 46.5, ["Nikon F AI", "Nikon F AI-S"]),
        mount("leica-r", "Leica R", 47, []),
        mount("zenit-dkl", "KMZ Zenit DKL", 47.58, ["Zenit DKL", "DKL"], notes: "Zenit 4/5/6 variant; not the 45.7 mm DKL families."),
        mount("b4", "B4 2/3-inch TV bayonet", 48, ["B4", "B4 2/3″ TV bayonet mount", "B4 2/3\" TV bayonet mount"]),
        mount("contax-n", "Contax N", 48, []),
        mount("tamron-adaptall", "Tamron Adaptall / Adaptall-2", 50.7, ["Tamron Adaptall", "Tamron Adaptall-2", "Adaptall", "Adaptall-2"], sources: [wikipediaURL], notes: "Interchangeable lens adapter interface, not a native camera mount. Use the camera body's mount when an adapter is fitted."),
        mount("arri-standard", "Arri Standard", 52, ["Arri STD"]),
        mount("arri-b", "Arri B", 52, ["Arri bayonet"]),
        mount("arri-pl", "Arri PL", 52, ["PL mount"]),
        mount("16-sp", "16-SP", 52, [], sources: [wikipediaURL]),
        mount("leica-s", "Leica S", 53, []),
        mount("mini-t", "Mini T-mount", 55, ["Mini T", "M37×0.75"], sources: [wikipediaURL]),
        mount("t", "T-mount", 55, ["T2 mount", "M42×0.75"], notes: "Interchangeable lens adapter interface. Use the body's mount when an adapter is fitted. M42×1 is a different system."),
        mount("ys", "YS mount", 55, [], notes: "Interchangeable lens adapter interface with aperture coupling. Use the body's mount when an adapter is fitted."),
        mount("mamiya-6", "Mamiya 6", 56.2, [], sources: [wikipediaURL], notes: "Wikipedia flags the published distance as potentially imprecise; verify before use."),
        mount("vivitar-tx", "Vivitar TX", 56.25, [], sources: [wikipediaURL], notes: "Interchangeable lens adapter interface. Use the body's mount when an adapter is fitted."),
        mount("1ksr-1m", "1KSR-1M", 57, [], sources: [wikipediaURL]),
        mount("panavision-pv", "Panavision PV", 57.15, ["PV mount"]),
        mount("mamiya-7", "Mamiya 7", 59, [], sources: [wikipediaURL]),
        mount("oct-19", "OCT-19", 61, [], sources: [wikipediaURL]),
        mount("1ksr-2m", "1KSR-2M", 61, [], sources: [wikipediaURL]),
        mount("hasselblad-h", "Hasselblad H", 61.63, ["Hasselblad H system"], sources: [wikipediaURL]),
        mount("ricoh-126c", "Ricoh 126C-Flex", 62.22, [], sources: [wikipediaURL]),
        mount("mamiya-645", "Mamiya 645", 63.3, []),
        mount("novoflex-a", "Novoflex A", 63.3, [], sources: [wikipediaURL], notes: "Wikipedia labels this adapter interface distance as measured. Use the camera mount when an adapter is fitted."),
        mount("contax-645", "Contax 645", 64, []),
        mount("bronica-etr", "Zenza Bronica ETR", 69, ["Bronica ETR"], sources: [wikipediaURL]),
        mount("pentax-645", "Pentax 645", 70.87, []),
        mount("rollei-slx", "Rollei SLX", 74, []),
        mount("pentacon-six", "Pentacon Six", 74.1, ["Pentacon 6", "P6", "Exakta 66", "Kiev 60"]),
        mount("hasselblad-v", "Hasselblad V", 74.9, ["Hasselblad V system", "Hasselblad 500/2000", "Hasselblad 500 / 2000"]),
        mount("kowa-six", "Kowa Six / Super 66", 79, ["Kowa Six", "Kowa Super 66"], sources: [wikipediaURL]),
        mount("hasselblad-early-f", "Hasselblad 1000F / 1600F", 82.1, ["Hasselblad 1000F", "Hasselblad 1600F", "Hasselblad 1000F & 1600F"]),
        mount("salyut-kiev", "Salyut / Kiev", 82.1, ["Salyut", "Salyut-S", "Kiev 88", "Zenit 80", "Zenith 80"], sources: [wikipediaURL]),
        mount("pentax-67", "Pentax 6×7", 85, ["Pentax 67", "Pentax 6x7"], notes: "Brian Smith gives 85 mm; Wikipedia gives both 84.95 and 85 mm. The default uses the shared 85 mm value."),
        mount("bronica-sq", "Zenza Bronica SQ", 85, ["Bronica SQ"], sources: [wikipediaURL]),
        mount("bronica-gs", "Zenza Bronica GS", 85, ["Bronica GS", "Bronica GS-1"], sources: [wikipediaURL]),
        mount("bronica-s2a", "Zenza Bronica S2A", 101.7, ["Bronica S2A"], sources: [wikipediaURL]),
        mount("rollei-sl66", "Rollei SL66", 102.8, []),
        mount("mamiya-rz", "Mamiya RZ67", 105, ["Mamiya RZ"]),
        mount("mamiya-rb", "Mamiya RB67", 112, ["Mamiya RB"], notes: "Wikipedia gives 112 mm; Brian Smith lists 111 mm. The default uses Wikipedia's value. Verify the reference surface before positioning.")
    ].sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    /// Formatting normalization only: no brand, model, substring or fuzzy inference.
    static func normalize(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: #"\s*[-‐‑–—]?\s*mount\s*$"#, with: "", options: .regularExpression)
        return folded.unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(String.init).joined()
    }

    /// Multiple matches deliberately preserve ambiguous thread/mount names.
    static func matches(_ mount: String) -> [FlangeMount] {
        let key = normalize(mount)
        guard !key.isEmpty else { return [] }
        return mounts.filter { normalize($0.name) == key || $0.aliases.contains { normalize($0) == key } }
    }

    private static func mount(_ id: String, _ name: String, _ distance: Double, _ aliases: [String], sources: [URL] = sourceURLs, notes: String = "") -> FlangeMount {
        FlangeMount(id: id, name: name, aliases: aliases, defaultDistanceMM: distance, sourceURLs: sources, notes: notes)
    }
}
