import Foundation

public enum DemoPackets {
    /// Deterministic synthetic data, never a recorded or calibrated hardware measurement.
    public static func sample(nominalDenominator: Double, index: Int, partial: Bool = false) -> MeasurementPacket {
        let denominator = nominalDenominator.isFinite && nominalDenominator > 0 ? nominalDenominator : 125
        let pattern = [0.018, -0.011, 0.025, 0.006, -0.017, 0.012, 0.031]
        let position = Int(index.magnitude % UInt(pattern.count))
        // Cap the base exposure at 60 seconds before its small deterministic variation;
        // this also prevents conversion traps for tiny input.
        let base = min(60_000_000, max(100, 1_000_000 / denominator))
        let duration = Int64((base * (1 + pattern[position])).rounded())
        let blOpen: Int64 = 1_000
        let centerOpen: Int64 = 7_100
        let trOpen: Int64 = 13_300
        let blDuration = max(1, Int64((Double(duration) * 0.992).rounded()))
        let trDuration = max(1, Int64((Double(duration) * 1.008).rounded()))
        // Inverse calibration here makes the derived event times internally consistent.
        return MeasurementPacket(
            firmware_version: "demo-1.0",
            bottomLeftOpen: blOpen + 25,
            bottomLeftClose: blOpen + blDuration - 32,
            centerOpen: centerOpen,
            centerClose: centerOpen + duration,
            topRightOpen: partial ? -1 : trOpen - 40,
            topRightClose: partial ? -1 : trOpen + trDuration - 10,
            bottomLeftOpenOffset: -25,
            bottomLeftCloseOffset: 32,
            topRightOpenOffset: 40,
            topRightCloseOffset: 10
        )
    }
}
