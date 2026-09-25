import Foundation
import DiskHealthCore

/// Estimate of the theoretical and practical maximum throughput for an external connection.
public struct LinkSpeedEstimate: Equatable, Sendable {
    public let linkSpeedText: String
    public let practicalMaxMBps: Int
    public let explanation: String

    public init(linkSpeedText: String, practicalMaxMBps: Int, explanation: String) {
        self.linkSpeedText = linkSpeedText
        self.practicalMaxMBps = practicalMaxMBps
        self.explanation = explanation
    }
}

/// Computes the theoretical maximum link throughput for external drives.
///
/// Under macOS, users often wonder why an external NVMe or SATA SSD doesn't reach its rated drive speed.
/// The interface link (USB standard, port, or cable) is frequently the bottleneck.
///
/// Theoretical / practical throughput formulas:
/// - USB 2.0 (480 Mb/s): 480 / 8 = 60 MB/s line rate.
///   USB 2.0 transaction protocol framing, token packets, SOF and polling limit practical bulk throughput to ~43 MB/s.
/// - USB 3.0 / 3.1 Gen 1 / 3.2 Gen 1 (5 Gb/s): uses 8b/10b encoding (20% line overhead) -> 500 MB/s.
///   Packet headers, flow control ACK and UASP/BOT overhead yield ~440–450 MB/s practical maximum.
/// - USB 3.1 Gen 2 / 3.2 Gen 2 (10 Gb/s): uses 128b/132b encoding (3% line overhead) -> 1,212 MB/s line rate.
///   UASP transport framing and protocol yield ~1,050 MB/s practical maximum.
/// - USB 3.2 Gen 2x2 (20 Gb/s): dual-lane 10 Gb/s with 128b/132b encoding -> ~2,050 MB/s practical maximum.
/// - Thunderbolt 3 / 4 / USB4 (40 Gb/s): allocates a PCIe 3.0 x4 tunnel (capped at ~22–32 Gb/s data payload) -> ~2,800–3,000 MB/s practical maximum.
/// - If the link speed is unknown or the drive is internal, returns nil.
public enum LinkSpeedEstimator {
    public static func estimate(for physical: PhysicalDisk) -> LinkSpeedEstimate? {
        guard physical.isExternal else { return nil }

        // 1. Thunderbolt NVMe / USB4 PCIe tunnel
        if physical.driveConnection == .thunderboltNVMe {
            let label = "Thunderbolt / USB4"
            let speed = 3000
            let speedFormatted = Formatters.integer(speed)
            let speedUnit = Formatters.speedUnit
            let explanation = L(
                "\(label) link: approx. \(speedFormatted) \(speedUnit) practical maximum",
                "Lien \(label) : environ \(speedFormatted) \(speedUnit) maximum en pratique"
            )
            return LinkSpeedEstimate(linkSpeedText: label, practicalMaxMBps: speed, explanation: explanation)
        }

        // 2. USB connection
        if physical.driveConnection == .usb || physical.connection == .usb {
            guard let bps = physical.usbLinkSpeedBps, bps > 0 else { return nil }

            let practicalMBps: Int
            let linkText: String

            if bps <= 480_000_000 {
                linkText = "USB 480 Mb/s"
                practicalMBps = 43
            } else if bps <= 5_000_000_000 {
                linkText = "USB 5 Gb/s"
                practicalMBps = 450
            } else if bps <= 10_000_000_000 {
                linkText = "USB 10 Gb/s"
                practicalMBps = 1050
            } else if bps <= 20_000_000_000 {
                linkText = "USB 20 Gb/s"
                practicalMBps = 2050
            } else {
                let speedGbps = Int((Double(bps) / 1_000_000_000.0).rounded())
                linkText = "USB \(speedGbps) Gb/s"
                practicalMBps = Int((Double(bps) / 8_000_000.0 * 0.9).rounded())
            }

            let speedFormatted = Formatters.integer(practicalMBps)
            let speedUnit = Formatters.speedUnit
            let explanation = L(
                "\(linkText) link: approx. \(speedFormatted) \(speedUnit) practical maximum",
                "Lien \(linkText) : environ \(speedFormatted) \(speedUnit) maximum en pratique"
            )
            return LinkSpeedEstimate(linkSpeedText: linkText, practicalMaxMBps: practicalMBps, explanation: explanation)
        }

        return nil
    }
}
