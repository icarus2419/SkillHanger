import Foundation
import Testing
@testable import AgentAwakeCore

@Test func parsesCurrentPowerReadings() {
    let baseline = "System-wide power settings:\nCurrently in use:\n sleep 1\n"
    let active = "System-wide power settings:\n SleepDisabled        1\n"
    #expect(LidProbePolicy.sleepDisabled(in: baseline) == 0)
    #expect(LidProbePolicy.sleepDisabled(in: active) == 1)
    #expect(LidProbePolicy.sleepDisabled(in: "SleepDisabled unknown") == nil)
    let battery = "Now drawing from 'Battery Power'\n -InternalBattery-0 32%; discharging;"
    #expect(LidProbePolicy.batteryPercent(in: battery) == 32)
    #expect(LidProbePolicy.isOnBattery(battery))
    #expect(LidProbePolicy.lidState(in: #"| |   "AppleClamshellState" = Yes"#) == true)
    #expect(LidProbePolicy.lidState(in: #"| |   "AppleClamshellState" = No"#) == false)
    #expect(LidProbePolicy.lidState(in: "no lid key") == nil)
}

@Test func probeRestoresOnDeadlineBatteryThermalOrReboot() {
    let baseline = Date(timeIntervalSince1970: 1_000)
    let deadline = baseline.addingTimeInterval(180)
    #expect(LidProbePolicy.restoreReason(now: baseline.addingTimeInterval(60), deadline: deadline, originalBootTime: 100, currentBootTime: 101, batteryPercent: 35, onBattery: true, thermal: .nominal) == nil)
    #expect(LidProbePolicy.restoreReason(now: deadline, deadline: deadline, originalBootTime: 100, currentBootTime: 101, batteryPercent: 35, onBattery: true, thermal: .nominal) == .deadline)
    #expect(LidProbePolicy.restoreReason(now: baseline, deadline: deadline, originalBootTime: 100, currentBootTime: 101, batteryPercent: 20, onBattery: true, thermal: .nominal) == .lowBattery)
    #expect(LidProbePolicy.restoreReason(now: baseline, deadline: deadline, originalBootTime: 100, currentBootTime: 101, batteryPercent: nil, onBattery: true, thermal: .nominal) == .unknownBattery)
    #expect(LidProbePolicy.restoreReason(now: baseline, deadline: deadline, originalBootTime: 100, currentBootTime: 101, batteryPercent: 35, onBattery: true, thermal: .serious) == .thermal)
    #expect(LidProbePolicy.restoreReason(now: baseline, deadline: deadline, originalBootTime: 100, currentBootTime: 200, batteryPercent: 35, onBattery: true, thermal: .nominal) == .newBoot)
    #expect(LidProbePolicy.restoreReason(now: baseline, deadline: deadline, originalBootTime: 100, currentBootTime: 101, batteryPercent: 35, onBattery: false, thermal: .nominal) == .powerSourceChanged)
}
