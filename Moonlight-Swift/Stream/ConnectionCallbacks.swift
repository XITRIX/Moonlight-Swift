//
//  ConnectionCallbacks.swift
//  Moonlight-Swift
//
//  Created by Daniil Vinogradov on 12/03/2026.
//

import Foundation

@objc
protocol ConnectionCallbacks: AnyObject {
    func connectionStarted()
    func connectionTerminated(_ errorCode: Int)
    func stageStarting(_ stageName: String)
    func stageComplete(_ stageName: String)
    func stageFailed(_ stageName: String, withError errorCode: Int, portTestFlags: Int)
    func launchFailed(_ message: String)
    func rumble(_ controllerNumber: UInt16, lowFreqMotor: UInt16, highFreqMotor: UInt16)
    func connectionStatusUpdate(_ status: Int)
    func setHdrMode(_ enabled: Bool)
    func rumbleTriggers(_ controllerNumber: UInt16, leftTrigger: UInt16, rightTrigger: UInt16)
    func setMotionEventState(_ controllerNumber: UInt16, motionType: UInt8, reportRateHz: UInt16)
    func setControllerLed(_ controllerNumber: UInt16, r: UInt8, g: UInt8, b: UInt8)
    func videoContentShown()
}
