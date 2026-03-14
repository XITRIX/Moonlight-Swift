//
//  Connection.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/19/14.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "Moonlight_Swift-Swift.h"
#import "Connection.h"
//#import "Utils.h"

#import <AVFAudio/AVFAudio.h>
#import <VideoToolbox/VideoToolbox.h>
@import QuartzCore;

//#define SDL_MAIN_HANDLED
//#import <SDL.h>

#include "Limelight.h"
#include "opus_multistream.h"
#include <stdatomic.h>
#include <TargetConditionals.h>
#include <unistd.h>

@implementation Connection {
    SERVER_INFORMATION _serverInfo;
    STREAM_CONFIGURATION _streamConfig;
    CONNECTION_LISTENER_CALLBACKS _clCallbacks;
    DECODER_RENDERER_CALLBACKS _drCallbacks;
    AUDIO_RENDERER_CALLBACKS _arCallbacks;
    char _hostString[256];
    char _appVersionString[32];
    char _gfeVersionString[32];
    char _rtspSessionUrl[128];
}

static NSLock* initLock;
static OpusMSDecoder* opusDecoder;
static id<ConnectionCallbacks> _callbacks;
static int lastFrameNumber;
static int activeVideoFormat;
static video_stats_t currentVideoStats;
static video_stats_t lastVideoStats;
static NSLock* videoStatsLock;

static OPUS_MULTISTREAM_CONFIGURATION audioConfig;
static AVAudioEngine* audioEngine;
static AVAudioPlayerNode* audioPlayer;
static AVAudioFormat* audioFormat;
static dispatch_queue_t audioQueue;
static atomic_int queuedAudioBuffers;

static VideoDecoderRenderer* renderer;

static void ReactivateAudioSession(void)
{
#if !TARGET_OS_TV
    NSError* audioError = nil;
    AVAudioSession* session = [AVAudioSession sharedInstance];
    if (![session setCategory:AVAudioSessionCategoryPlayback
                  withOptions:AVAudioSessionCategoryOptionMixWithOthers
                        error:&audioError]) {
        [Log e: [NSString stringWithFormat:@"Failed to reconfigure audio session: %s\n", audioError.localizedDescription.UTF8String]];
        audioError = nil;
    }

    if (![session setActive:YES error:&audioError]) {
        [Log e: [NSString stringWithFormat:@"Failed to reactivate audio session: %s\n", audioError.localizedDescription.UTF8String]];
    }
#endif
}

static BOOL ConfigureAudioPlaybackGraph(void)
{
    NSError* audioError = nil;

    audioEngine = [[AVAudioEngine alloc] init];
    audioPlayer = [[AVAudioPlayerNode alloc] init];
    [audioEngine attachNode:audioPlayer];
    [audioEngine connect:audioPlayer to:audioEngine.mainMixerNode format:audioFormat];

    ReactivateAudioSession();

    if (![audioEngine startAndReturnError:&audioError]) {
        [Log e: [NSString stringWithFormat:@"Failed to start audio engine: %s\n", audioError.localizedDescription.UTF8String]];
        audioPlayer = nil;
        audioEngine = nil;
        return NO;
    }

    [audioPlayer play];
    return YES;
}

static void ResetAudioPlaybackState(BOOL rebuildGraph)
{
    if (audioPlayer == nil || audioEngine == nil || audioQueue == nil) {
        return;
    }

    dispatch_async(audioQueue, ^{
        AVAudioPlayerNode* oldPlayer = audioPlayer;
        AVAudioEngine* oldEngine = audioEngine;

        [oldPlayer stop];
        [oldPlayer reset];
        [oldEngine stop];
        [oldEngine reset];
        atomic_store(&queuedAudioBuffers, 0);

        if (rebuildGraph) {
            audioPlayer = nil;
            audioEngine = nil;
            ConfigureAudioPlaybackGraph();
        }
    });
}

int DrDecoderSetup(int videoFormat, int width, int height, int redrawRate, void* context, int drFlags)
{
    [renderer setupWithVideoFormat:videoFormat width:width height:height frameRate:redrawRate];
    lastFrameNumber = 0;
    activeVideoFormat = videoFormat;
    memset(&currentVideoStats, 0, sizeof(currentVideoStats));
    memset(&lastVideoStats, 0, sizeof(lastVideoStats));
    return 0;
}

void DrStart(void)
{
    [renderer start];
}

void DrStop(void)
{
    [renderer stop];
}

-(BOOL) getVideoStats:(video_stats_t*)stats
{
    // We return lastVideoStats because it is a complete 1 second window
    [videoStatsLock lock];
    if (lastVideoStats.endTime != 0) {
        memcpy(stats, &lastVideoStats, sizeof(*stats));
        [videoStatsLock unlock];
        return YES;
    }
    
    // No stats yet
    [videoStatsLock unlock];
    return NO;
}

-(NSString*) getActiveCodecName
{
    switch (activeVideoFormat)
    {
        case VIDEO_FORMAT_H264:
            return @"H.264";
        case VIDEO_FORMAT_H265:
            return @"HEVC";
        case VIDEO_FORMAT_H265_MAIN10:
            if (LiGetCurrentHostDisplayHdrMode()) {
                return @"HEVC Main 10 HDR";
            }
            else {
                return @"HEVC Main 10 SDR";
            }
        case VIDEO_FORMAT_AV1_MAIN8:
            return @"AV1";
        case VIDEO_FORMAT_AV1_MAIN10:
            if (LiGetCurrentHostDisplayHdrMode()) {
                return @"AV1 10-bit HDR";
            }
            else {
                return @"AV1 10-bit SDR";
            }
        default:
            return @"UNKNOWN";
    }
}

int DrSubmitDecodeUnit(PDECODE_UNIT decodeUnit)
{
    int offset = 0;
    int ret;
    unsigned char* data = (unsigned char*) malloc(decodeUnit->fullLength);
    if (data == NULL) {
        // A frame was lost due to OOM condition
        return DR_NEED_IDR;
    }
    
    CFTimeInterval now = CACurrentMediaTime();
    if (!lastFrameNumber) {
        currentVideoStats.startTime = now;
        lastFrameNumber = decodeUnit->frameNumber;
    }
    else {
        // Flip stats roughly every second
        if (now - currentVideoStats.startTime >= 1.0f) {
            currentVideoStats.endTime = now;
            
            [videoStatsLock lock];
            lastVideoStats = currentVideoStats;
            [videoStatsLock unlock];
            
            memset(&currentVideoStats, 0, sizeof(currentVideoStats));
            currentVideoStats.startTime = now;
        }
        
        // Any frame number greater than m_LastFrameNumber + 1 represents a dropped frame
        currentVideoStats.networkDroppedFrames += decodeUnit->frameNumber - (lastFrameNumber + 1);
        currentVideoStats.totalFrames += decodeUnit->frameNumber - (lastFrameNumber + 1);
        lastFrameNumber = decodeUnit->frameNumber;
    }
    
    if (decodeUnit->frameHostProcessingLatency != 0) {
        if (currentVideoStats.minHostProcessingLatency == 0 || decodeUnit->frameHostProcessingLatency < currentVideoStats.minHostProcessingLatency) {
            currentVideoStats.minHostProcessingLatency = decodeUnit->frameHostProcessingLatency;
        }
        
        if (decodeUnit->frameHostProcessingLatency > currentVideoStats.maxHostProcessingLatency) {
            currentVideoStats.maxHostProcessingLatency = decodeUnit->frameHostProcessingLatency;
        }
        
        currentVideoStats.framesWithHostProcessingLatency++;
        currentVideoStats.totalHostProcessingLatency += decodeUnit->frameHostProcessingLatency;
    }
    
    currentVideoStats.receivedFrames++;
    currentVideoStats.totalFrames++;

    PLENTRY entry = decodeUnit->bufferList;
    while (entry != NULL) {
        // Submit parameter set NALUs directly since no copy is required by the decoder
        if (entry->bufferType != BUFFER_TYPE_PICDATA) {
            ret = [renderer submitDecodeBuffer: entry->data
                                        length: entry->length
                                        bufferType: entry->bufferType
                                        decodeUnit: decodeUnit];
            if (ret != DR_OK) {
                free(data);
                return ret;
            }
        }
        else {
            memcpy(&data[offset], entry->data, entry->length);
            offset += entry->length;
        }

        entry = entry->next;
    }

    // This function will take our picture data buffer
    return [renderer submitDecodeBuffer:data
                                 length: offset
                             bufferType:BUFFER_TYPE_PICDATA
                             decodeUnit:decodeUnit];
}

int ArInit(int audioConfiguration, POPUS_MULTISTREAM_CONFIGURATION opusConfig, void* context, int flags)
{
    int err;
    NSError* audioError = nil;
    
    (void)audioConfiguration;
    (void)context;
    (void)flags;
    
    if (opusConfig == NULL) {
        return -1;
    }
    
    audioConfig = *opusConfig;
    
    opusDecoder = opus_multistream_decoder_create(opusConfig->sampleRate,
                                                  opusConfig->channelCount,
                                                  opusConfig->streams,
                                                  opusConfig->coupledStreams,
                                                  opusConfig->mapping,
                                                  &err);
    if (opusDecoder == NULL || err != OPUS_OK) {
        [Log e: [NSString stringWithFormat:@"Failed to create Opus decoder: %d\n", err]];
        ArCleanup();
        return -1;
    }
    
    audioQueue = dispatch_queue_create("com.moonlight.audio-playback", DISPATCH_QUEUE_SERIAL);
    atomic_store(&queuedAudioBuffers, 0);
    
    audioFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16
                                                   sampleRate:opusConfig->sampleRate
                                                     channels:opusConfig->channelCount
                                                  interleaved:YES];
    if (audioFormat == nil) {
        [Log e: @"Failed to create audio format\n"];
        ArCleanup();
        return -1;
    }
    
#if !TARGET_OS_TV
    AVAudioSession* session = [AVAudioSession sharedInstance];
    if (![session setCategory:AVAudioSessionCategoryPlayback
                  withOptions:AVAudioSessionCategoryOptionMixWithOthers
                        error:&audioError]) {
        [Log e: [NSString stringWithFormat:@"Failed to configure audio session: %s\n", audioError.localizedDescription.UTF8String]];
        audioError = nil;
    }
    
    if (![session setActive:YES error:&audioError]) {
        [Log e: [NSString stringWithFormat:@"Failed to activate audio session: %s\n", audioError.localizedDescription.UTF8String]];
        audioError = nil;
    }
#endif
    
    if (!ConfigureAudioPlaybackGraph()) {
        ArCleanup();
        return -1;
    }

    return 0;
}

void ArCleanup(void)
{
    if (audioPlayer != nil) {
        [audioPlayer reset];
        [audioPlayer stop];
        audioPlayer = nil;
    }
    
    if (audioEngine != nil) {
        [audioEngine stop];
        [audioEngine reset];
        audioEngine = nil;
    }
    
    audioFormat = nil;
    audioQueue = nil;
    atomic_store(&queuedAudioBuffers, 0);
    
    if (opusDecoder != NULL) {
        opus_multistream_decoder_destroy(opusDecoder);
        opusDecoder = NULL;
    }
}

void ArDecodeAndPlaySample(char* sampleData, int sampleLength)
{
    int decodeLen;
    
    if (opusDecoder == NULL || audioPlayer == nil || audioFormat == nil || audioQueue == nil) {
        return;
    }
    
    // Don't queue if there's already more than 30 ms of audio data waiting
    // in Moonlight's audio queue.
    if (LiGetPendingAudioDuration() > 30) {
        return;
    }
    
    // Audio is real-time. If the local player queue is already backed up,
    // drop this sample instead of blocking the decoder thread and letting
    // Moonlight's upstream audio packet queue overflow.
    if (atomic_load(&queuedAudioBuffers) > 10) {
        return;
    }
    
    AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:audioFormat
                                                              frameCapacity:audioConfig.samplesPerFrame];
    if (buffer == nil) {
        [Log e: @"Failed to allocate audio PCM buffer\n"];
        return;
    }
    
    AudioBufferList* audioBufferList = buffer.mutableAudioBufferList;
    if (audioBufferList == NULL || audioBufferList->mNumberBuffers == 0 || audioBufferList->mBuffers[0].mData == NULL) {
        [Log e: @"Audio buffer list is invalid\n"];
        return;
    }
    
    decodeLen = opus_multistream_decode(opusDecoder,
                                        (const unsigned char*)sampleData,
                                        sampleLength,
                                        (opus_int16*)audioBufferList->mBuffers[0].mData,
                                        audioConfig.samplesPerFrame,
                                        0);
    if (decodeLen <= 0) {
        if (decodeLen < 0) {
            [Log e: [NSString stringWithFormat:@"Failed to decode Opus sample: %d\n", decodeLen]];
        }
        return;
    }
    
    audioBufferList->mBuffers[0].mDataByteSize = sizeof(short) * decodeLen * audioConfig.channelCount;
    buffer.frameLength = decodeLen;
    
    atomic_fetch_add(&queuedAudioBuffers, 1);
    dispatch_async(audioQueue, ^{
        [audioPlayer scheduleBuffer:buffer
                            atTime:nil
                           options:0
                 completionHandler:^{
            atomic_fetch_sub(&queuedAudioBuffers, 1);
        }];
        
        if (!audioPlayer.isPlaying) {
            [audioPlayer play];
        }
    });
}

void ClStageStarting(int stage)
{
    NSString* string = [[NSString alloc] initWithCString:LiGetStageName(stage) encoding:NSUTF8StringEncoding];
    [_callbacks stageStarting:string];
}

void ClStageComplete(int stage)
{
    NSString* string = [[NSString alloc] initWithCString:LiGetStageName(stage) encoding:NSUTF8StringEncoding];
    [_callbacks stageComplete:string];
}

void ClStageFailed(int stage, int errorCode)
{
    NSString* stageString = [[NSString alloc] initWithCString:LiGetStageName(stage) encoding:NSUTF8StringEncoding];
    [_callbacks stageFailed:stageString withError:errorCode portTestFlags:LiGetPortFlagsFromStage(stage)];
}

void ClConnectionStarted(void)
{
    [_callbacks connectionStarted];
}

void ClConnectionTerminated(int errorCode)
{
    [_callbacks connectionTerminated: errorCode];
}

void ClLogMessage(const char* format, ...)
{
    va_list va;
    va_start(va, format);
    vfprintf(stderr, format, va);
    va_end(va);
}

void ClRumble(unsigned short controllerNumber, unsigned short lowFreqMotor, unsigned short highFreqMotor)
{
    [_callbacks rumble:controllerNumber lowFreqMotor:lowFreqMotor highFreqMotor:highFreqMotor];
}

void ClConnectionStatusUpdate(int status)
{
    [_callbacks connectionStatusUpdate:status];
}

void ClSetHdrMode(bool enabled)
{
    [renderer setHdrMode:enabled];
    [_callbacks setHdrMode:enabled];
}

void ClRumbleTriggers(uint16_t controllerNumber, uint16_t leftTriggerMotor, uint16_t rightTriggerMotor)
{
    [_callbacks rumbleTriggers:controllerNumber leftTrigger:leftTriggerMotor rightTrigger:rightTriggerMotor];
}

void ClSetMotionEventState(uint16_t controllerNumber, uint8_t motionType, uint16_t reportRateHz)
{
    [_callbacks setMotionEventState:controllerNumber motionType:motionType reportRateHz:reportRateHz];
}

void ClSetControllerLED(uint16_t controllerNumber, uint8_t r, uint8_t g, uint8_t b)
{
    [_callbacks setControllerLed:controllerNumber r:r g:g b:b];
}

-(void) handleAudioSessionInterruption:(NSNotification*)notification
{
#if !TARGET_OS_TV
    NSNumber* typeValue = notification.userInfo[AVAudioSessionInterruptionTypeKey];
    if (typeValue.unsignedIntegerValue == AVAudioSessionInterruptionTypeBegan) {
        ResetAudioPlaybackState(NO);
    }
    else {
        ResetAudioPlaybackState(YES);
    }
#else
    (void)notification;
#endif
}

-(void) handleAudioSessionRouteChange:(NSNotification*)notification
{
    (void)notification;
    ResetAudioPlaybackState(YES);
}

-(void) handleAudioSessionMediaServicesReset:(NSNotification*)notification
{
    (void)notification;
    ResetAudioPlaybackState(YES);
}

-(void) handleAudioEngineConfigurationChange:(NSNotification*)notification
{
    (void)notification;
    ResetAudioPlaybackState(YES);
}

-(void) terminate
{
    // Interrupt any action blocking LiStartConnection(). This is
    // thread-safe and done outside initLock on purpose, since we
    // won't be able to acquire it if LiStartConnection is in
    // progress.
    LiInterruptConnection();
    
    // We dispatch this async to get out because this can be invoked
    // on a thread inside common and we don't want to deadlock. It also avoids
    // blocking on the caller's thread waiting to acquire initLock.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [initLock lock];
        LiStopConnection();
        [initLock unlock];
    });
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(id) initWithConfig:(StreamConfiguration*)config renderer:(VideoDecoderRenderer*)myRenderer connectionCallbacks:(id<ConnectionCallbacks>)callbacks
{
    self = [super init];

    // Use a lock to ensure that only one thread is initializing
    // or deinitializing a connection at a time.
    if (initLock == nil) {
        initLock = [[NSLock alloc] init];
    }
    
    if (videoStatsLock == nil) {
        videoStatsLock = [[NSLock alloc] init];
    }
    
    NSString *rawAddress = [Utils addressPortStringToAddress:config.host];
    strncpy(_hostString,
            [rawAddress cStringUsingEncoding:NSUTF8StringEncoding],
            sizeof(_hostString) - 1);
    strncpy(_appVersionString,
            [config.appVersion cStringUsingEncoding:NSUTF8StringEncoding],
            sizeof(_appVersionString) - 1);
    if (config.gfeVersion != nil) {
        strncpy(_gfeVersionString,
                [config.gfeVersion cStringUsingEncoding:NSUTF8StringEncoding],
                sizeof(_gfeVersionString) - 1);
    }
    if (config.rtspSessionUrl != nil) {
        strncpy(_rtspSessionUrl,
                [config.rtspSessionUrl cStringUsingEncoding:NSUTF8StringEncoding],
                sizeof(_rtspSessionUrl) - 1);
    }

    LiInitializeServerInformation(&_serverInfo);
    _serverInfo.address = _hostString;
    _serverInfo.serverInfoAppVersion = _appVersionString;
    if (config.gfeVersion != nil) {
        _serverInfo.serverInfoGfeVersion = _gfeVersionString;
    }
    if (config.rtspSessionUrl != nil) {
        _serverInfo.rtspSessionUrl = _rtspSessionUrl;
    }
    _serverInfo.serverCodecModeSupport = config.serverCodecModeSupport;

    renderer = myRenderer;
    _callbacks = callbacks;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleAudioSessionInterruption:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleAudioSessionRouteChange:)
                                                 name:AVAudioSessionRouteChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleAudioSessionMediaServicesReset:)
                                                 name:AVAudioSessionMediaServicesWereResetNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleAudioEngineConfigurationChange:)
                                                 name:AVAudioEngineConfigurationChangeNotification
                                               object:nil];

    LiInitializeStreamConfiguration(&_streamConfig);
    _streamConfig.width = config.width;
    _streamConfig.height = config.height;
    _streamConfig.fps = config.frameRate;
    _streamConfig.bitrate = config.bitRate;
    _streamConfig.supportedVideoFormats = config.supportedVideoFormats;
    _streamConfig.audioConfiguration = config.audioConfiguration;
    
    // Since we require iOS 12 or above, we're guaranteed to be running
    // on a 64-bit device with ARMv8 crypto instructions, so we don't
    // need to check for that here.
    _streamConfig.encryptionFlags = ENCFLG_ALL;
    
    if ([Utils isActiveNetworkVPN]) {
        // Force remote streaming mode when a VPN is connected
        _streamConfig.streamingRemotely = STREAM_CFG_REMOTE;
        _streamConfig.packetSize = 1024;
    }
    else {
        // Detect remote streaming automatically based on the IP address of the target
        _streamConfig.streamingRemotely = STREAM_CFG_AUTO;
        _streamConfig.packetSize = 1392;
    }

    memcpy(_streamConfig.remoteInputAesKey, [config.riKey bytes], [config.riKey length]);
    memset(_streamConfig.remoteInputAesIv, 0, 16);
    int riKeyId = htonl(config.riKeyId);
    memcpy(_streamConfig.remoteInputAesIv, &riKeyId, sizeof(riKeyId));

    LiInitializeVideoCallbacks(&_drCallbacks);
    _drCallbacks.setup = DrDecoderSetup;
    _drCallbacks.start = DrStart;
    _drCallbacks.stop = DrStop;
    _drCallbacks.capabilities = CAPABILITY_PULL_RENDERER |
                                CAPABILITY_REFERENCE_FRAME_INVALIDATION_HEVC |
                                CAPABILITY_REFERENCE_FRAME_INVALIDATION_AV1;

    LiInitializeAudioCallbacks(&_arCallbacks);
    _arCallbacks.init = ArInit;
    _arCallbacks.cleanup = ArCleanup;
    _arCallbacks.decodeAndPlaySample = ArDecodeAndPlaySample;
    _arCallbacks.capabilities = CAPABILITY_SUPPORTS_ARBITRARY_AUDIO_DURATION;

    LiInitializeConnectionCallbacks(&_clCallbacks);
    _clCallbacks.stageStarting = ClStageStarting;
    _clCallbacks.stageComplete = ClStageComplete;
    _clCallbacks.stageFailed = ClStageFailed;
    _clCallbacks.connectionStarted = ClConnectionStarted;
    _clCallbacks.connectionTerminated = ClConnectionTerminated;
    _clCallbacks.logMessage = ClLogMessage;
    _clCallbacks.rumble = ClRumble;
    _clCallbacks.connectionStatusUpdate = ClConnectionStatusUpdate;
    _clCallbacks.setHdrMode = ClSetHdrMode;
    _clCallbacks.rumbleTriggers = ClRumbleTriggers;
    _clCallbacks.setMotionEventState = ClSetMotionEventState;
    _clCallbacks.setControllerLED = ClSetControllerLED;

    return self;
}

-(void) main
{
    [initLock lock];
    LiStartConnection(&_serverInfo,
                      &_streamConfig,
                      &_clCallbacks,
                      &_drCallbacks,
                      &_arCallbacks,
                      NULL, 0,
                      NULL, 0);
    [initLock unlock];
}

@end
