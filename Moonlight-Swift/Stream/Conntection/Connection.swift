import Foundation
import QuartzCore
import VideoToolbox

// MARK: - File-level globals for Limelight C callbacks

private let connectionInitLock = NSLock()
private let videoStatsLock = NSLock()

private weak var globalCallbacks: (any ConnectionCallbacks)?
private weak var globalRenderer: VideoDecoderRenderer?

private var lastFrameNumber: Int32 = 0
private var activeVideoFormat: Int32 = 0
private var currentVideoStats = video_stats_t()
private var lastVideoStats = video_stats_t()

private var audioConfig = OPUS_MULTISTREAM_CONFIGURATION()
private var audioBuffer: UnsafeMutableRawPointer?
private var audioFrameSize: Int32 = 0

// MARK: - Stable C string storage

private final class FixedCString {
    let pointer: UnsafeMutablePointer<CChar>
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        self.pointer = .allocate(capacity: capacity)
        self.pointer.initialize(repeating: 0, count: capacity)
    }

    deinit {
        pointer.deinitialize(count: capacity)
        pointer.deallocate()
    }

    func store(_ string: String?) {
        memset(pointer, 0, capacity)
        guard let string else { return }

        string.withCString { src in
            strncpy(pointer, src, capacity - 1)
            pointer[capacity - 1] = 0
        }
    }
}

// MARK: - Limelight decoder callbacks

private func DrDecoderSetup(
    _ videoFormat: Int32,
    _ width: Int32,
    _ height: Int32,
    _ redrawRate: Int32,
    _ context: UnsafeMutableRawPointer?,
    _ drFlags: Int32
) -> Int32 {
    _ = context
    _ = drFlags

    globalRenderer?.setup(videoFormat: videoFormat, width: width, height: height, frameRate: redrawRate)

    lastFrameNumber = 0
    activeVideoFormat = videoFormat
    memset(&currentVideoStats, 0, MemoryLayout.size(ofValue: currentVideoStats))
    memset(&lastVideoStats, 0, MemoryLayout.size(ofValue: lastVideoStats))
    return 0
}

private func DrStart() {
    globalRenderer?.start()
}

private func DrStop() {
    globalRenderer?.stop()
}

func DrSubmitDecodeUnit(_ decodeUnit: PDECODE_UNIT?) -> Int32 {
    guard let decodeUnit, let renderer = globalRenderer else {
        return DR_NEED_IDR
    }

    let fullLength = Int(decodeUnit.pointee.fullLength)
    guard let raw = malloc(fullLength) else {
        return DR_NEED_IDR
    }

    let data = raw.assumingMemoryBound(to: UInt8.self)
    var offset = 0

    let now = CACurrentMediaTime()

    if lastFrameNumber == 0 {
        currentVideoStats.startTime = now
        lastFrameNumber = decodeUnit.pointee.frameNumber
    } else {
        if now - currentVideoStats.startTime >= 1.0 {
            currentVideoStats.endTime = now

            videoStatsLock.lock()
            lastVideoStats = currentVideoStats
            videoStatsLock.unlock()

            memset(&currentVideoStats, 0, MemoryLayout.size(ofValue: currentVideoStats))
            currentVideoStats.startTime = now
        }

        let dropped = decodeUnit.pointee.frameNumber - (lastFrameNumber + 1)
        currentVideoStats.networkDroppedFrames += dropped
        currentVideoStats.totalFrames += dropped
        lastFrameNumber = decodeUnit.pointee.frameNumber
    }

    if decodeUnit.pointee.frameHostProcessingLatency != 0 {
        if currentVideoStats.minHostProcessingLatency == 0 ||
            decodeUnit.pointee.frameHostProcessingLatency < currentVideoStats.minHostProcessingLatency {
            currentVideoStats.minHostProcessingLatency = Int32(decodeUnit.pointee.frameHostProcessingLatency)
        }

        if decodeUnit.pointee.frameHostProcessingLatency > currentVideoStats.maxHostProcessingLatency {
            currentVideoStats.maxHostProcessingLatency = Int32(decodeUnit.pointee.frameHostProcessingLatency)
        }

        currentVideoStats.framesWithHostProcessingLatency += 1
        currentVideoStats.totalHostProcessingLatency += Int32(decodeUnit.pointee.frameHostProcessingLatency)
    }

    currentVideoStats.receivedFrames += 1
    currentVideoStats.totalFrames += 1

    var entry = decodeUnit.pointee.bufferList
    while let currentEntry = entry {
        if currentEntry.pointee.bufferType != BUFFER_TYPE_PICDATA {
            let ret = renderer.submitDecodeBuffer(
                currentEntry.pointee.data,
                length: currentEntry.pointee.length,
                bufferType: currentEntry.pointee.bufferType,
                decodeUnit: decodeUnit
            )

            if ret != DR_OK {
                free(data)
                return ret
            }
        } else {
            memcpy(data.advanced(by: offset), currentEntry.pointee.data, Int(currentEntry.pointee.length))
            offset += Int(currentEntry.pointee.length)
        }

        entry = currentEntry.pointee.next
    }

    return renderer.submitDecodeBuffer(
        data,
        length: Int32(offset),
        bufferType: BUFFER_TYPE_PICDATA,
        decodeUnit: decodeUnit
    )
}

// MARK: - Limelight audio callbacks

private func ArInit(
    _ audioConfiguration: Int32,
    _ opusConfig: POPUS_MULTISTREAM_CONFIGURATION?,
    _ context: UnsafeMutableRawPointer?,
    _ flags: Int32
) -> Int32 {
    _ = audioConfiguration
    _ = context
    _ = flags

    if let opusConfig {
        audioConfig = opusConfig.pointee
        audioFrameSize = Int32(opusConfig.pointee.samplesPerFrame) *
            Int32(MemoryLayout<Int16>.size) *
            Int32(opusConfig.pointee.channelCount)
    }

    // Original audio path was commented out, so keep this as a stub.
    return 0
}

private func ArCleanup() {
    if audioBuffer != nil {
        free(audioBuffer)
        audioBuffer = nil
    }
}

private func ArDecodeAndPlaySample(_ sampleData: UnsafeMutablePointer<CChar>?, _ sampleLength: Int32) {
    _ = sampleData
    _ = sampleLength
    // Original audio path was commented out, so keep this as a stub.
}

// MARK: - Limelight connection callbacks

private func stringFromStage(_ stage: Int32) -> String {
    guard let ptr = LiGetStageName(stage) else { return "Unknown" }
    return String(cString: ptr)
}

private func ClStageStarting(_ stage: Int32) {
    globalCallbacks?.stageStarting(stringFromStage(stage))
}

private func ClStageComplete(_ stage: Int32) {
    globalCallbacks?.stageComplete(stringFromStage(stage))
}

private func ClStageFailed(_ stage: Int32, _ errorCode: Int32) {
    globalCallbacks?.stageFailed(
        stringFromStage(stage),
        withError: Int(errorCode),
        portTestFlags: Int(LiGetPortFlagsFromStage(stage))
    )
}

private func ClConnectionStarted() {
    globalCallbacks?.connectionStarted()
}

private func ClConnectionTerminated(_ errorCode: Int32) {
    globalCallbacks?.connectionTerminated(Int(errorCode))
}

private func ClRumble(_ controllerNumber: UInt16, _ lowFreqMotor: UInt16, _ highFreqMotor: UInt16) {
    globalCallbacks?.rumble(controllerNumber, lowFreqMotor: lowFreqMotor, highFreqMotor: highFreqMotor)
}

private func ClConnectionStatusUpdate(_ status: Int32) {
    globalCallbacks?.connectionStatusUpdate(Int(status))
}

private func ClSetHdrMode(_ enabled: Bool) {
    globalRenderer?.setHdrMode(enabled)
    globalCallbacks?.setHdrMode(enabled)
}

private func ClRumbleTriggers(_ controllerNumber: UInt16, _ leftTriggerMotor: UInt16, _ rightTriggerMotor: UInt16) {
    globalCallbacks?.rumbleTriggers(controllerNumber, leftTrigger: leftTriggerMotor, rightTrigger: rightTriggerMotor)
}

private func ClSetMotionEventState(_ controllerNumber: UInt16, _ motionType: UInt8, _ reportRateHz: UInt16) {
    globalCallbacks?.setMotionEventState(controllerNumber, motionType: motionType, reportRateHz: reportRateHz)
}

private func ClSetControllerLED(_ controllerNumber: UInt16, _ r: UInt8, _ g: UInt8, _ b: UInt8) {
    globalCallbacks?.setControllerLed(controllerNumber, r: r, g: g, b: b)
}

// MARK: - Connection

final class Connection: Thread {
    private var serverInfo = SERVER_INFORMATION()
    private var streamConfig = STREAM_CONFIGURATION()
    private var clCallbacks = CONNECTION_LISTENER_CALLBACKS()
    private var drCallbacks = DECODER_RENDERER_CALLBACKS()
    private var arCallbacks = AUDIO_RENDERER_CALLBACKS()

    private let hostString = FixedCString(capacity: 256)
    private let appVersionString = FixedCString(capacity: 32)
    private let gfeVersionString = FixedCString(capacity: 32)
    private let rtspSessionUrl = FixedCString(capacity: 128)

    private let renderer: VideoDecoderRenderer
    private let callbacks: any ConnectionCallbacks

    init(
        config: StreamConfiguration,
        renderer: VideoDecoderRenderer,
        connectionCallbacks callbacks: any ConnectionCallbacks
    ) {
        self.renderer = renderer
        self.callbacks = callbacks
        super.init()

        let rawAddress = Utils.addressPortStringToAddress(config.host)
        hostString.store(rawAddress)
        appVersionString.store(config.appVersion)
        gfeVersionString.store(config.gfeVersion)
        rtspSessionUrl.store(config.rtspSessionUrl)

        LiInitializeServerInformation(&serverInfo)
        serverInfo.address = UnsafePointer(hostString.pointer)
        serverInfo.serverInfoAppVersion = UnsafePointer(appVersionString.pointer)

        if config.gfeVersion != nil {
            serverInfo.serverInfoGfeVersion = UnsafePointer(gfeVersionString.pointer)
        }

        if config.rtspSessionUrl != nil {
            serverInfo.rtspSessionUrl = UnsafePointer(rtspSessionUrl.pointer)
        }

        serverInfo.serverCodecModeSupport = config.serverCodecModeSupport

        globalRenderer = renderer
        globalCallbacks = callbacks

        LiInitializeStreamConfiguration(&streamConfig)
        streamConfig.width = Int32(config.width)
        streamConfig.height = Int32(config.height)
        streamConfig.fps = Int32(config.frameRate)
        streamConfig.bitrate = Int32(config.bitRate)
        streamConfig.supportedVideoFormats = Int32(config.supportedVideoFormats.rawValue)
        streamConfig.audioConfiguration = config.audioConfiguration.rawValue
        streamConfig.encryptionFlags = Int32(EncFlag.all.rawValue)

        if Utils.isActiveNetworkVPN() {
            streamConfig.streamingRemotely = STREAM_CFG_REMOTE
            streamConfig.packetSize = 1024
        } else {
            streamConfig.streamingRemotely = STREAM_CFG_AUTO
            streamConfig.packetSize = 1392
        }

        withUnsafeMutableBytes(of: &streamConfig.remoteInputAesKey) { dst in
            dst.copyBytes(from: config.riKey.prefix(dst.count))
        }

        withUnsafeMutableBytes(of: &streamConfig.remoteInputAesIv) { dst in
            dst.initializeMemory(as: UInt8.self, repeating: 0)

            var keyIdBE = UInt32(bitPattern: Int32(config.riKeyId)).bigEndian
            withUnsafeBytes(of: &keyIdBE) { src in
                dst.copyBytes(from: src)
            }
        }

        LiInitializeVideoCallbacks(&drCallbacks)
        drCallbacks.setup = DrDecoderSetup
        drCallbacks.start = DrStart
        drCallbacks.stop = DrStop
        drCallbacks.capabilities = CAPABILITY_PULL_RENDERER |
            CAPABILITY_REFERENCE_FRAME_INVALIDATION_HEVC |
            CAPABILITY_REFERENCE_FRAME_INVALIDATION_AV1

        LiInitializeAudioCallbacks(&arCallbacks)
        arCallbacks.`init` = ArInit
        arCallbacks.cleanup = ArCleanup
        arCallbacks.decodeAndPlaySample = ArDecodeAndPlaySample
        arCallbacks.capabilities = CAPABILITY_SUPPORTS_ARBITRARY_AUDIO_DURATION

        LiInitializeConnectionCallbacks(&clCallbacks)
        clCallbacks.stageStarting = ClStageStarting
        clCallbacks.stageComplete = ClStageComplete
        clCallbacks.stageFailed = ClStageFailed
        clCallbacks.connectionStarted = ClConnectionStarted
        clCallbacks.connectionTerminated = ClConnectionTerminated
        clCallbacks.logMessage = ConnectionLogMessageShim
        clCallbacks.rumble = ClRumble
        clCallbacks.connectionStatusUpdate = ClConnectionStatusUpdate
        clCallbacks.setHdrMode = ClSetHdrMode
        clCallbacks.rumbleTriggers = ClRumbleTriggers
        clCallbacks.setMotionEventState = ClSetMotionEventState
        clCallbacks.setControllerLED = ClSetControllerLED
    }

    func terminateConnection() {
        LiInterruptConnection()

        DispatchQueue.global(qos: .userInitiated).async {
            connectionInitLock.lock()
            LiStopConnection()
            connectionInitLock.unlock()
        }
    }

    func getVideoStats(_ stats: UnsafeMutablePointer<video_stats_t>) -> Bool {
        videoStatsLock.lock()
        defer { videoStatsLock.unlock() }

        if lastVideoStats.endTime != 0 {
            stats.pointee = lastVideoStats
            return true
        }

        return false
    }

    func getActiveCodecName() -> String {
        switch activeVideoFormat {
        case VIDEO_FORMAT_H264:
            return "H.264"

        case VIDEO_FORMAT_H265:
            return "HEVC"

        case VIDEO_FORMAT_H265_MAIN10:
            return LiGetCurrentHostDisplayHdrMode() ? "HEVC Main 10 HDR" : "HEVC Main 10 SDR"

        case VIDEO_FORMAT_AV1_MAIN8:
            return "AV1"

        case VIDEO_FORMAT_AV1_MAIN10:
            return LiGetCurrentHostDisplayHdrMode() ? "AV1 10-bit HDR" : "AV1 10-bit SDR"

        default:
            return "UNKNOWN"
        }
    }

    override func main() {
        connectionInitLock.lock()
        LiStartConnection(
            &serverInfo,
            &streamConfig,
            &clCallbacks,
            &drCallbacks,
            &arCallbacks,
            nil, 0,
            nil, 0
        )
        connectionInitLock.unlock()
    }
}
