import Foundation

struct TesterGuideSection: Identifiable {
    let id: String
    let title: String
    let body: String
}

struct TesterGuide: Identifiable {
    let id: String
    let title: String
    let summary: String
    let compatibility: String
    let manualTitle: String
    let manualURL: URL
    let sections: [TesterGuideSection]
}

/// Concise, independently worded manual summaries. Sources/revisions stay visible in the UI.
/// Do not apply Shutter Lover's reset procedure to the Baby mk II's measurement sequence.
enum TesterGuideCatalog {
    static let guides: [TesterGuide] = [
        TesterGuide(
            id: "shutter-lover", title: "Shutter Lover", summary: "Three sensors · Focal-plane curtain timing",
            compatibility: "USB readings supported. Choose a saved tester to record its identity with each reading; reconnect and firmware qualification remain hardware checks.",
            manualTitle: "Manufacturer manual · English 1.1.0 · pages 1–4",
            manualURL: URL(string: "https://photographyelectronics.com/wp-content/uploads/2025/06/ShutterLover_UserManual_en_1.1.0_-_Release.pdf")!,
            sections: [
                .init(id: "mount", title: "1. Position the sensor", body: "Remove the lens. Secure the sensor at the film plane, cable right when facing the camera. Fit the adapter for medium format. Connect sensor and USB, then switch on."),
                .init(id: "light", title: "2. Match your calibration distance", body: "Center the tester parallel to the lens mount. Use the LED-to-sensor distance supplied for your individual unit. Tripods help maintain alignment. Avoid looking into the LEDs."),
                .init(id: "test", title: "3. Check alignment on the tester", body: "Long-press: Measurement → Test → Information. Short-press from Test or Information returns to Measurement. In Test, use a slow exposure or Bulb; all three sensor indicators should illuminate. Information shows firmware and calibration values."),
                .init(id: "measure", title: "4. Record and repeat", body: "Return to Measurement mode, select the camera speed and release its shutter. Partial readings appear after roughly two seconds. Briefly press the tester’s reset button before the next reading."),
                .init(id: "interpret", title: "5. Interpret the result", body: "Open/Close measure corner-to-corner curtain travel across the 32 × 20 mm sensor rectangle. Full-frame travel in this app is an estimate.")
            ]),
        TesterGuide(
            id: "baby-mki", title: "Baby Shutter Tester Mk I", summary: "Original model · Single-sensor exposure measurement",
            compatibility: "Manual display readings supported. Choose Mk I in the test, then Add manual reading. Follow the manual for your firmware; Mk II modes do not apply.",
            manualTitle: "Manufacturer manual index · Mk I firmware 2.0.1+, 2.0.0, or 1.1.0–1.2.1",
            manualURL: URL(string: "https://github.com/sebastienroy/shutter_speed_tester/wiki/Shutter-Testers-documentation")!,
            sections: [
                .init(id: "version", title: "1. Check the firmware", body: "Information mode shows the firmware version. Open the manual index below and choose the matching Mk I document. The following setup notes describe manual 2.0.1; older firmware has separate instructions."),
                .init(id: "setup", title: "2. Position and align", body: "Put the sensor at the film plane, centered and secure; use the adapter for medium format. Aim the tester’s LED at the sensor. Use Test mode with a slow exposure or Bulb to check alignment."),
                .init(id: "calibration", title: "3. Calibrate for fast speeds", body: "For 1/250 s and faster, keep the setup fixed and use subdued ambient light. With firmware 2.0.1, adjust LED distance in Test mode until the center dot appears and the value is between −10 and +10. Follow your version’s full procedure."),
                .init(id: "read", title: "4. Measure and transcribe", body: "Return to Measurement without changing the setup, release the shutter, and copy the displayed result into Add manual reading. Press the tester’s reset button before each new measurement."),
                .init(id: "limits", title: "5. Interpret this model’s reading", body: "Mk I measures a single exposure value. It does not measure curtain travel. At fast leaf-shutter settings, its displayed time may differ from effective exposure; do not treat it as the Mk II’s integration measurement.")
            ]),
        TesterGuide(
            id: "baby-mkii", title: "Baby Shutter Tester mk II", summary: "One sensor · Effective exposure time",
            compatibility: "Manual display readings supported, including optional mode and E₀. Manufacturer firmware 1.1.0 adds USB output; automatic Baby USB acquisition is a future app feature.",
            manualTitle: "Manufacturer manual · English 1.0.0-B · firmware 1.0.0 · pages 2–8",
            manualURL: URL(string: "https://photographyelectronics.com/wp-content/uploads/2025/08/BabyShutterTester_mkII_UserManual_en_1.0.0_-B.pdf")!,
            sections: [
                .init(id: "setup", title: "1. Choose lighting for the shutter", body: "Power from USB or two AAA batteries. For focal-plane checks, open the back, position the sensor at the film plane, remove the lens and aim the built-in LED toward the sensor. Leaf shutters require a diffuser source covering the lens."),
                .init(id: "auto", title: "2. Automatic mode", body: "Use Automatic for handheld checks from 1/15 to 1/1000 s. Readings update on each shutter release. Keep illumination constant during each exposure; a reset between every shot is not required."),
                .init(id: "global", title: "3. Global mode", body: "Hold the tester’s reset/mode button for more than two seconds to change modes. For Global, use the diffuser, fixed illumination and unchanged aperture. Work from slow to fast; a short press clears the stored maximum illumination. Avoid Global with uncontrollable automatic aperture."),
                .init(id: "signal", title: "4. Check illumination", body: "E₀ above 90 approaches saturation: reduce illumination. Below 10 weakens reliability. If E₀ falls at faster speeds despite identical lighting, use Global."),
                .init(id: "read", title: "5. Read effective time", body: "Compare effective time, shown in milliseconds or reciprocal seconds, with the camera setting. This single sensor does not measure curtain travel.")
            ])
    ]
}
