//
//  VideoDecoderRenderer.swift
//  Moonlight-Swift
//
//  Created by Daniil Vinogradov on 12/03/2026.
//

import UIKit

//@objcMembers
//class VideoDecoderRenderer: NSObject {
//    init(_ renderView: UIView, callbacks: ConnectionCallbacks, streamAspectRatio aspectRatio: CGFloat, useFramePacing: Bool) {
//        
//    }
//
//    func setupWithVideoFormat(_ videoFormat: Int32, width: Int, height: Int, frameRate: Int) {
//
//    }
//
//    func start() {}
//    func stop() {}
//
//    func submitDecodeBuffer(_ data: Data, bufferType: Int, decodeUnit: PDECODE_UNIT) -> Int {
//        return 0
//    }
//
//    func setHdrMode(_ enabled: Bool) {
//        
//    }
//}


import Foundation
import UIKit
import AVFoundation
import CoreMedia
import QuartzCore

// Make sure this symbol is visible to Swift from your bridging header:
//
// extern int ff_isom_write_av1c(AVIOContext *pb, const uint8_t *buf, int size,
//                               int write_seq_header);

@objcMembers
final class VideoDecoderRenderer: NSObject {
    private let view: AVView
    private weak var callbacks: ConnectionCallbacks?
    private let streamAspectRatio: CGFloat

    private var displayLayer: AVSampleBufferDisplayLayer = .init()
    private var videoFormat: Int32 = 0
    private var frameRate: Int32 = 0

    // NSData is convenient here because we need stable byte pointers
    private var parameterSetBuffers: [NSData] = []

    private var masteringDisplayColorVolume: Data?
    private var contentLightLevelInfo: Data?
    private var formatDesc: CMFormatDescription?

    private var displayLink: CADisplayLink?
    private let framePacing: Bool

    private let minimumStartCodeSize = 3
    private let nalLengthPrefixSize = 4

    private var isH264: Bool { (videoFormat & VIDEO_FORMAT_MASK_H264) != 0 }
    private var isH265: Bool { (videoFormat & VIDEO_FORMAT_MASK_H265) != 0 }
    private var isAV1: Bool { (videoFormat & VIDEO_FORMAT_MASK_AV1) != 0 }

    init(
        view: AVView,
        callbacks: ConnectionCallbacks?,
        streamAspectRatio aspectRatio: Float,
        useFramePacing: Bool
    ) {
        self.view = view
        self.callbacks = callbacks
        self.streamAspectRatio = CGFloat(aspectRatio)
        self.framePacing = useFramePacing
        super.init()
        reinitializeDisplayLayer()
    }

    private func reinitializeDisplayLayer() {
//        let oldLayer = displayLayer

//        let newLayer = view.avLayer //AVSampleBufferDisplayLayer()
//        newLayer.backgroundColor = UIColor.black.cgColor
//
//        let bounds = view.bounds
//        let videoSize: CGSize
//        if bounds.width > bounds.height * streamAspectRatio {
//            videoSize = CGSize(width: bounds.height * streamAspectRatio, height: bounds.height)
//        } else {
//            videoSize = CGSize(width: bounds.width, height: bounds.width / streamAspectRatio)
//        }

//        newLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
//        newLayer.bounds = CGRect(origin: .zero, size: videoSize)
//        newLayer.videoGravity = .resize
//        newLayer.isHidden = true

//        if oldLayer.superlayer != nil {
//            view.layer.replaceSublayer(oldLayer, with: newLayer)
//        } else {
//            view.layer.addSublayer(newLayer)
//        }

        displayLayer = view.avLayer
        formatDesc = nil
    }

    func setup(videoFormat: Int32, width: Int32, height: Int32, frameRate: Int32) {
        self.videoFormat = videoFormat
        self.frameRate = frameRate
        _ = width
        _ = height
    }

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(displayLinkCallback(_:)))
        if #available(iOS 15.0, tvOS 15.0, *) {
            let rate = Float(frameRate)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
        } else {
            link.preferredFramesPerSecond = Int(frameRate)
        }
        link.add(to: .main, forMode: .default)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc
    private func displayLinkCallback(_ sender: CADisplayLink) {
        var handle: VIDEO_FRAME_HANDLE?
        var du: PDECODE_UNIT?

        while LiPollNextVideoFrame(&handle, &du) {
            LiCompleteVideoFrame(handle, DrSubmitDecodeUnit(du))

            if framePacing {
                let dt = sender.targetTimestamp - sender.timestamp
                if dt > 0 {
                    let displayRefreshRate = 1.0 / dt
                    if displayRefreshRate >= Double(frameRate) * 0.9 {
                        if LiGetPendingVideoFrames() == 1 {
                            break
                        }
                    }
                }
            }
        }
    }

    private func annexBStartCodeLength(
        _ data: UnsafePointer<UInt8>,
        offset: Int,
        totalLength: Int
    ) -> Int {
        guard offset + 3 <= totalLength else { return 0 }
        guard data[offset] == 0, data[offset + 1] == 0 else { return 0 }

        if data[offset + 2] == 1 {
            return 3
        }

        if offset + 4 <= totalLength,
           data[offset + 2] == 0,
           data[offset + 3] == 1 {
            return 4
        }

        return 0
    }

    private func collectParameterSet(
        _ data: UnsafePointer<UInt8>,
        length: Int
    ) {
        let startLen = annexBStartCodeLength(data, offset: 0, totalLength: length)
        let strippedOffset = startLen > 0 ? startLen : 0
        let strippedLength = max(0, length - strippedOffset)

        let psData = NSData(bytes: data.advanced(by: strippedOffset), length: strippedLength)
        parameterSetBuffers.append(psData)
    }

    private func updateAnnexBBuffer(
        frameBuffer: CMBlockBuffer,
        dataBuffer: CMBlockBuffer,
        offset: Int,
        startCodeLength: Int,
        nalLength: Int
    ) {
        let oldOffset = CMBlockBufferGetDataLength(frameBuffer)

        var status = CMBlockBufferAppendMemoryBlock(
            frameBuffer,
            memoryBlock: nil,
            length: nalLengthPrefixSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: nalLengthPrefixSize,
            flags: 0
        )
        if status != kCMBlockBufferNoErr {
            Log.e("CMBlockBufferAppendMemoryBlock failed: \(Int(status))")
            return
        }

        let dataLength = nalLength - startCodeLength
        let lengthBytes: [UInt8] = [
            UInt8((dataLength >> 24) & 0xFF),
            UInt8((dataLength >> 16) & 0xFF),
            UInt8((dataLength >> 8) & 0xFF),
            UInt8(dataLength & 0xFF)
        ]

        status = lengthBytes.withUnsafeBytes { rawBytes in
            CMBlockBufferReplaceDataBytes(
                with: rawBytes.baseAddress!,
                blockBuffer: frameBuffer,
                offsetIntoDestination: oldOffset,
                dataLength: nalLengthPrefixSize
            )
        }
        if status != kCMBlockBufferNoErr {
            Log.e("CMBlockBufferReplaceDataBytes failed: \(Int(status))")
            return
        }

        status = CMBlockBufferAppendBufferReference(
            frameBuffer,
            targetBBuf: dataBuffer,
            offsetToData: offset + startCodeLength,
            dataLength: dataLength,
            flags: 0
        )
        if status != kCMBlockBufferNoErr {
            Log.e("CMBlockBufferAppendBufferReference failed: \(Int(status))")
        }
    }

    private func appendLengthPrefixedAnnexBNALUs(
        from data: UnsafePointer<UInt8>,
        length: Int,
        into frameBuffer: CMBlockBuffer,
        using dataBuffer: CMBlockBuffer
    ) {
        var nalOffsets: [(offset: Int, startCodeLength: Int)] = []

        var i = 0
        while i <= length - minimumStartCodeSize {
            let startCodeLength = annexBStartCodeLength(data, offset: i, totalLength: length)
            if startCodeLength > 0 {
                nalOffsets.append((i, startCodeLength))
                i += startCodeLength
            } else {
                i += 1
            }
        }

        guard !nalOffsets.isEmpty else { return }

        for index in nalOffsets.indices {
            let current = nalOffsets[index]
            let nextOffset = (index + 1 < nalOffsets.count) ? nalOffsets[index + 1].offset : length

            updateAnnexBBuffer(
                frameBuffer: frameBuffer,
                dataBuffer: dataBuffer,
                offset: current.offset,
                startCodeLength: current.startCodeLength,
                nalLength: nextOffset - current.offset
            )
        }
    }

    private func createH264FormatDescription() -> CMFormatDescription? {
        let parameterSetCount = parameterSetBuffers.count
        guard parameterSetCount > 0 else {
            Log.e("No H264 parameter sets available")
            return nil
        }

        let parameterSetPointers: [UnsafePointer<UInt8>] = parameterSetBuffers.map {
            $0.bytes.assumingMemoryBound(to: UInt8.self)
        }
        let parameterSetSizes: [Int] = parameterSetBuffers.map { $0.length }

        Log.i("Constructing new H264 format description")

        var desc: CMFormatDescription?
        let status = parameterSetPointers.withUnsafeBufferPointer { pointerBuffer in
            parameterSetSizes.withUnsafeBufferPointer { sizeBuffer in
                CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: parameterSetCount,
                    parameterSetPointers: pointerBuffer.baseAddress!,
                    parameterSetSizes: sizeBuffer.baseAddress!,
                    nalUnitHeaderLength: Int32(nalLengthPrefixSize),
                    formatDescriptionOut: &desc
                )
            }
        }

        guard status == noErr else {
            Log.e("Failed to create H264 format description: \(Int(status))")
            return nil
        }

        return desc
    }

    private func createHEVCFormatDescription() -> CMFormatDescription? {
        let parameterSetCount = parameterSetBuffers.count
        guard parameterSetCount > 0 else {
            Log.e("No HEVC parameter sets available")
            return nil
        }

        let parameterSetPointers: [UnsafePointer<UInt8>] = parameterSetBuffers.map {
            $0.bytes.assumingMemoryBound(to: UInt8.self)
        }
        let parameterSetSizes: [Int] = parameterSetBuffers.map { $0.length }

        Log.i("Constructing new HEVC format description")

        var videoFormatParams: [NSString: Any] = [:]
        if let contentLightLevelInfo {
            videoFormatParams[kCMFormatDescriptionExtension_ContentLightLevelInfo as NSString] = contentLightLevelInfo
        }
        if let masteringDisplayColorVolume {
            videoFormatParams[kCMFormatDescriptionExtension_MasteringDisplayColorVolume as NSString] = masteringDisplayColorVolume
        }

        var desc: CMFormatDescription?
        let status = parameterSetPointers.withUnsafeBufferPointer { pointerBuffer in
            parameterSetSizes.withUnsafeBufferPointer { sizeBuffer in
                CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: parameterSetCount,
                    parameterSetPointers: pointerBuffer.baseAddress!,
                    parameterSetSizes: sizeBuffer.baseAddress!,
                    nalUnitHeaderLength: Int32(nalLengthPrefixSize),
                    extensions: videoFormatParams.isEmpty ? nil : (videoFormatParams as CFDictionary),
                    formatDescriptionOut: &desc
                )
            }
        }

        guard status == noErr else {
            Log.e("Failed to create HEVC format description: \(Int(status))")
            return nil
        }

        return desc
    }

    #if FFMPEG_AV1_AVAILABLE

    private func getAv1CodecConfigurationBox(_ frameData: Data) -> Data? {
        var ioctx: UnsafeMutablePointer<AVIOContext>?
        let openErr = avio_open_dyn_buf(&ioctx)
        if openErr < 0 {
            Log.e("avio_open_dyn_buf() failed: \(openErr)")
            return nil
        }

        let writeErr: Int32 = frameData.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                  let ioctx else {
                return -1
            }

            return ff_isom_write_av1c(ioctx, base, Int32(frameData.count), 1)
        }

        if writeErr < 0 {
            Log.e("ff_isom_write_av1c() failed: \(writeErr)")
        }

        var av1cBuf: UnsafeMutablePointer<UInt8>?
        let av1cBufLen = avio_close_dyn_buf(ioctx, &av1cBuf)

        Log.i("av1C block is \(av1cBufLen) bytes")

        defer {
            if let av1cBuf {
                av_free(av1cBuf)
            }
        }

        guard writeErr >= 0, av1cBufLen > 0, let av1cBuf else {
            return nil
        }

        return Data(bytes: av1cBuf, count: Int(av1cBufLen))
    }

    private func createAV1FormatDescription(forIDRFrame frameData: Data) -> CMFormatDescription? {
        var extensions: [NSString: Any] = [:]

        var cbsCtx: UnsafeMutablePointer<CodedBitstreamContext>?
        let initErr = ff_cbs_init(&cbsCtx, AV_CODEC_ID_AV1, nil)
        if initErr < 0 {
            Log.e("ff_cbs_init() failed: \(initErr)")
            return nil
        }

        var cbsFrag = CodedBitstreamFragment()
        defer {
            ff_cbs_fragment_free(&cbsFrag)
            ff_cbs_close(&cbsCtx)
        }

        var avPacket = AVPacket()
        let readErr: Int32 = frameData.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                  let cbsCtx else {
                return -1
            }

            avPacket.data = UnsafeMutablePointer(mutating: base)
            avPacket.size = Int32(frameData.count)
            return ff_cbs_read_packet(cbsCtx, &cbsFrag, &avPacket)
        }

        if readErr < 0 {
            Log.e("ff_cbs_read_packet() failed: \(readErr)")
            return nil
        }

        extensions[kCMFormatDescriptionExtension_FormatName as NSString] = "av01"
        extensions[kCMFormatDescriptionExtension_Depth as NSString] = 24

        guard let cbsCtx,
              let privData = cbsCtx.pointee.priv_data else {
            Log.e("AV1 coded bitstream context missing priv_data")
            return nil
        }

        let bitstreamCtx = privData.assumingMemoryBound(to: CodedBitstreamAV1Context.self)
        guard let seqHeader = bitstreamCtx.pointee.sequence_header else {
            Log.e("AV1 sequence header not found in IDR frame!")
            return nil
        }

        switch seqHeader.pointee.color_config.color_primaries {
        case 1:
            extensions[kCMFormatDescriptionExtension_ColorPrimaries as NSString] =
                kCMFormatDescriptionColorPrimaries_ITU_R_709_2
        case 6:
            extensions[kCMFormatDescriptionExtension_ColorPrimaries as NSString] =
                kCMFormatDescriptionColorPrimaries_SMPTE_C
        case 9:
            extensions[kCMFormatDescriptionExtension_ColorPrimaries as NSString] =
                kCMFormatDescriptionColorPrimaries_ITU_R_2020
        default:
            Log.w("Unsupported color_primaries value: \(seqHeader.pointee.color_config.color_primaries)")
        }

        switch seqHeader.pointee.color_config.transfer_characteristics {
        case 1, 6:
            extensions[kCMFormatDescriptionExtension_TransferFunction as NSString] =
                kCMFormatDescriptionTransferFunction_ITU_R_709_2
        case 7:
            extensions[kCMFormatDescriptionExtension_TransferFunction as NSString] =
                kCMFormatDescriptionTransferFunction_SMPTE_240M_1995
        case 8:
            extensions[kCMFormatDescriptionExtension_TransferFunction as NSString] =
                kCMFormatDescriptionTransferFunction_Linear
        case 14, 15:
            extensions[kCMFormatDescriptionExtension_TransferFunction as NSString] =
                kCMFormatDescriptionTransferFunction_ITU_R_2020
        case 16:
            extensions[kCMFormatDescriptionExtension_TransferFunction as NSString] =
                kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ
        case 17:
            extensions[kCMFormatDescriptionExtension_TransferFunction as NSString] =
                kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG
        default:
            Log.w("Unsupported transfer_characteristics value: \(seqHeader.pointee.color_config.transfer_characteristics)")
        }

        switch seqHeader.pointee.color_config.matrix_coefficients {
        case 1:
            extensions[kCMFormatDescriptionExtension_YCbCrMatrix as NSString] =
                kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2
        case 6:
            extensions[kCMFormatDescriptionExtension_YCbCrMatrix as NSString] =
                kCMFormatDescriptionYCbCrMatrix_ITU_R_601_4
        case 7:
            extensions[kCMFormatDescriptionExtension_YCbCrMatrix as NSString] =
                kCMFormatDescriptionYCbCrMatrix_SMPTE_240M_1995
        case 9:
            extensions[kCMFormatDescriptionExtension_YCbCrMatrix as NSString] =
                kCMFormatDescriptionYCbCrMatrix_ITU_R_2020
        default:
            Log.w("Unsupported matrix_coefficients value: \(seqHeader.pointee.color_config.matrix_coefficients)")
        }

        extensions[kCMFormatDescriptionExtension_FullRangeVideo as NSString] =
            NSNumber(value: seqHeader.pointee.color_config.color_range == 1)
        extensions[kCMFormatDescriptionExtension_FieldCount as NSString] = 1

        switch seqHeader.pointee.color_config.chroma_sample_position {
        case 1:
            extensions[kCMFormatDescriptionExtension_ChromaLocationTopField as NSString] =
                kCMFormatDescriptionChromaLocation_Left
        case 2:
            extensions[kCMFormatDescriptionExtension_ChromaLocationTopField as NSString] =
                kCMFormatDescriptionChromaLocation_TopLeft
        default:
            Log.w("Unsupported chroma_sample_position value: \(seqHeader.pointee.color_config.chroma_sample_position)")
        }

        if let contentLightLevelInfo {
            extensions[kCMFormatDescriptionExtension_ContentLightLevelInfo as NSString] = contentLightLevelInfo
        }

        if let masteringDisplayColorVolume {
            extensions[kCMFormatDescriptionExtension_MasteringDisplayColorVolume as NSString] = masteringDisplayColorVolume
        }

        if let av1c = getAv1CodecConfigurationBox(frameData) {
            extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as NSString] = [
                "av1C": av1c
            ]
        }

        extensions["BitsPerComponent"] = NSNumber(value: bitstreamCtx.pointee.bit_depth)

        var desc: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_AV1,
            width: Int32(bitstreamCtx.pointee.frame_width),
            height: Int32(bitstreamCtx.pointee.frame_height),
            extensions: extensions as CFDictionary,
            formatDescriptionOut: &desc
        )

        if status != noErr {
            Log.e("Failed to create AV1 format description: \(Int(status))")
            return nil
        }

        return desc
    }

    #endif

    func submitDecodeBuffer(
        _ data: UnsafeMutablePointer<UInt8>?,
        length: Int32,
        bufferType: Int32,
        decodeUnit du: PDECODE_UNIT?
    ) -> Int32 {
        guard let data, let du else {
            return DR_NEED_IDR
        }

        let length = Int(length)

        func freeInputIfNeeded() {
            if bufferType == BUFFER_TYPE_PICDATA {
                free(data)
            }
        }

        if du.pointee.frameType == FRAME_TYPE_IDR {
            if bufferType != BUFFER_TYPE_PICDATA {
                if bufferType == BUFFER_TYPE_VPS || bufferType == BUFFER_TYPE_SPS || bufferType == BUFFER_TYPE_PPS {
                    collectParameterSet(UnsafePointer(data), length: length)
                }

                // Data is NOT to be freed here.
                return DR_OK
            }

            formatDesc = nil

            if isH264 {
                formatDesc = createH264FormatDescription()
                parameterSetBuffers.removeAll()
            } else if isH265 {
                formatDesc = createHEVCFormatDescription()
                parameterSetBuffers.removeAll()
            } else if isAV1 {
                #if FFMPEG_AV1_AVAILABLE
                let fullFrameData = Data(bytesNoCopy: data, count: length, deallocator: .none)
                Log.i("Constructing new AV1 format description")
                formatDesc = createAV1FormatDescription(forIDRFrame: fullFrameData)
                #else
                Log.e("AV1 stream received, but FFMPEG_AV1_AVAILABLE is disabled")
                formatDesc = nil
                #endif
            } else {
                Log.e("Unsupported codec format: \(videoFormat)")
                freeInputIfNeeded()
                return DR_NEED_IDR
            }
        }

        guard let formatDesc else {
            freeInputIfNeeded()
            return DR_NEED_IDR
        }

        if displayLayer.status == .failed {
            Log.e("Display layer rendering failed: \(String(describing: displayLayer.error))")
            reinitializeDisplayLayer()
            freeInputIfNeeded()
            return DR_NEED_IDR
        }

        var dataBlockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: data,
            blockLength: length,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: length,
            flags: 0,
            blockBufferOut: &dataBlockBuffer
        )
        if status != kCMBlockBufferNoErr {
            Log.e("CMBlockBufferCreateWithMemoryBlock failed: \(Int(status))")
            freeInputIfNeeded()
            return DR_NEED_IDR
        }

        guard let dataBlockBuffer else {
            freeInputIfNeeded()
            return DR_NEED_IDR
        }

        var frameBlockBuffer: CMBlockBuffer?
        status = CMBlockBufferCreateEmpty(
            allocator: kCFAllocatorDefault,
            capacity: 0,
            flags: 0,
            blockBufferOut: &frameBlockBuffer
        )
        if status != kCMBlockBufferNoErr {
            Log.e("CMBlockBufferCreateEmpty failed: \(Int(status))")
            return DR_NEED_IDR
        }

        guard let frameBlockBuffer else {
            return DR_NEED_IDR
        }

        if isH264 || isH265 {
            appendLengthPrefixedAnnexBNALUs(
                from: UnsafePointer(data),
                length: length,
                into: frameBlockBuffer,
                using: dataBlockBuffer
            )
        } else {
            status = CMBlockBufferAppendBufferReference(
                frameBlockBuffer,
                targetBBuf: dataBlockBuffer,
                offsetToData: 0,
                dataLength: length,
                flags: 0
            )
            if status != kCMBlockBufferNoErr {
                Log.e("CMBlockBufferAppendBufferReference failed: \(Int(status))")
                return DR_NEED_IDR
            }
        }

        var sampleBuffer: CMSampleBuffer?
        var sampleTiming = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: CMTimeValue(du.pointee.presentationTimeUs), timescale: 1_000_000),
            decodeTimeStamp: .invalid
        )

        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: frameBlockBuffer,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &sampleTiming,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        if status != noErr {
            Log.e("CMSampleBufferCreate failed: \(Int(status))")
            return DR_NEED_IDR
        }

        guard let sampleBuffer else {
            return DR_NEED_IDR
        }

        displayLayer.enqueue(sampleBuffer)

        if du.pointee.frameType == FRAME_TYPE_IDR {
            displayLayer.isHidden = false
            callbacks?.videoContentShown()
        }

        return DR_OK
    }

    func setHdrMode(_ enabled: Bool) {
        var hdrMetadata = SS_HDR_METADATA()
        let hasMetadata = enabled && LiGetHdrMetadata(&hdrMetadata)
        var metadataChanged = false

        if hasMetadata,
           hdrMetadata.displayPrimaries.0.x != 0,
           hdrMetadata.maxDisplayLuminance != 0 {
            var mdcv = Data()
            mdcv.reserveCapacity(24)

            // GBR order while SS_HDR_METADATA is RGB order
            appendBigEndian(hdrMetadata.displayPrimaries.1.x, to: &mdcv)
            appendBigEndian(hdrMetadata.displayPrimaries.1.y, to: &mdcv)

            appendBigEndian(hdrMetadata.displayPrimaries.2.x, to: &mdcv)
            appendBigEndian(hdrMetadata.displayPrimaries.2.y, to: &mdcv)

            appendBigEndian(hdrMetadata.displayPrimaries.0.x, to: &mdcv)
            appendBigEndian(hdrMetadata.displayPrimaries.0.y, to: &mdcv)

            appendBigEndian(hdrMetadata.whitePoint.x, to: &mdcv)
            appendBigEndian(hdrMetadata.whitePoint.y, to: &mdcv)

            appendBigEndian(UInt32(hdrMetadata.maxDisplayLuminance) * 10_000, to: &mdcv)
            appendBigEndian(UInt32(hdrMetadata.minDisplayLuminance), to: &mdcv)

            if masteringDisplayColorVolume == nil || masteringDisplayColorVolume != mdcv {
                masteringDisplayColorVolume = mdcv
                metadataChanged = true
            }
        } else if masteringDisplayColorVolume != nil {
            masteringDisplayColorVolume = nil
            metadataChanged = true
        }

        if hasMetadata,
           hdrMetadata.maxContentLightLevel != 0,
           hdrMetadata.maxFrameAverageLightLevel != 0 {
            var cll = Data()
            cll.reserveCapacity(4)

            appendBigEndian(hdrMetadata.maxContentLightLevel, to: &cll)
            appendBigEndian(hdrMetadata.maxFrameAverageLightLevel, to: &cll)

            if contentLightLevelInfo == nil || contentLightLevelInfo != cll {
                contentLightLevelInfo = cll
                metadataChanged = true
            }
        } else if contentLightLevelInfo != nil {
            contentLightLevelInfo = nil
            metadataChanged = true
        }

        if metadataChanged {
            LiRequestIdrFrame()
        }
    }

    private func appendBigEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { rawBuffer in
            data.append(contentsOf: rawBuffer)
        }
    }
}
