//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#include <Limelight.h>
#include <Foundation/Foundation.h>
#include <libxml/tree.h>

#include "Connection.h"

typedef NS_ENUM(int32_t, AudioConfiguration) {
    AudioConfigurationStereo      = AUDIO_CONFIGURATION_STEREO,
    AudioConfigurationSurround51  = AUDIO_CONFIGURATION_51_SURROUND,
    AudioConfigurationSurround71  = AUDIO_CONFIGURATION_71_SURROUND,
};

typedef NS_OPTIONS(NSInteger, VideoFormat) {
    VideoFormatH264               = VIDEO_FORMAT_H264,
    VideoFormatH265               = VIDEO_FORMAT_H265,
    VideoFormatH265Main10         = VIDEO_FORMAT_H265_MAIN10,
    VideoFormatAV1Main8           = VIDEO_FORMAT_AV1_MAIN8,
    VideoFormatAV1Main10          = VIDEO_FORMAT_AV1_MAIN10,
};

typedef NS_ENUM(NSInteger, VideoFormatMask) {
    VideoFormatMaskH264               = VIDEO_FORMAT_MASK_H264,
    VideoFormatMaskH265               = VIDEO_FORMAT_MASK_H265,
    VideoFormatMaskAV1                = VIDEO_FORMAT_MASK_AV1,
    VideoFormatMaskAV1Bit10           = VIDEO_FORMAT_MASK_10BIT,
};

typedef NS_ENUM(NSInteger, EncFlag) {
    EncFlagNone          = ENCFLG_NONE,
    EncFlagAudio         = ENCFLG_AUDIO,
    EncFlagVideo         = ENCFLG_VIDEO,
    EncFlagAll           = ENCFLG_ALL,
};

typedef NS_ENUM(NSInteger, StreamCfg) {
    StreamCfgLocal        = STREAM_CFG_LOCAL,
    StreamCfgRemote       = STREAM_CFG_REMOTE,
    StreamCfgAuto         = STREAM_CFG_AUTO,
};

typedef NS_OPTIONS(int32_t, Capability) {
    CapabilityDirectSubmit                          = CAPABILITY_DIRECT_SUBMIT,
    CapabilityReferenceFrameInvalidationAvc         = CAPABILITY_REFERENCE_FRAME_INVALIDATION_AVC,
    CapabilityReferenceFrameInvalidationHevc        = CAPABILITY_REFERENCE_FRAME_INVALIDATION_HEVC,
    CapabilitySlowOpusDecoder                       = CAPABILITY_SLOW_OPUS_DECODER,
    CapabilitySupportArbitraryAudioDuration         = CAPABILITY_SUPPORTS_ARBITRARY_AUDIO_DURATION,
    CapabilityPullRenderer                          = CAPABILITY_PULL_RENDERER,
    CapabilityReferenceFrameInvalidationAv1         = CAPABILITY_REFERENCE_FRAME_INVALIDATION_AV1,
};

NS_INLINE int32_t SurroundAudioInfoFromAudioConfiguration(int32_t configuration) {
    return SURROUNDAUDIOINFO_FROM_AUDIO_CONFIGURATION(configuration);
}

NS_INLINE void MoonlightXMLFree(void *pointer) {
    xmlFree(pointer);
}

typedef NS_ENUM(int8_t, ButtonAction) {
    ButtonActionPress        = BUTTON_ACTION_PRESS,
    ButtonActionRelease       = BUTTON_ACTION_RELEASE,
};

typedef NS_ENUM(int32_t, MouseButton) {
    MouseButtonLeft        = BUTTON_LEFT,
    MouseButtonMiddle       = BUTTON_MIDDLE,
    MouseButtonRight       = BUTTON_RIGHT,
};

typedef NS_OPTIONS(int32_t, ControllerButton) {
    ControllerButtonA           = A_FLAG,
    ControllerButtonB           = B_FLAG,
    ControllerButtonX           = X_FLAG,
    ControllerButtonY           = Y_FLAG,
    ControllerButtonUp          = UP_FLAG,
    ControllerButtonDown        = DOWN_FLAG,
    ControllerButtonLeft        = LEFT_FLAG,
    ControllerButtonRight       = RIGHT_FLAG,
    ControllerButtonLeftBumper  = LB_FLAG,
    ControllerButtonRightBumper = RB_FLAG,
    ControllerButtonPlay        = PLAY_FLAG,
    ControllerButtonBack        = BACK_FLAG,
    ControllerButtonLeftStick   = LS_CLK_FLAG,
    ControllerButtonRightStick  = RS_CLK_FLAG,
    ControllerButtonMisc        = MISC_FLAG,
    ControllerButtonSpecial     = SPECIAL_FLAG,
};
