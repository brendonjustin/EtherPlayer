//
//  AirplayConstants.m
//  EtherPlayer
//
//  Created by Brendon Justin on 5/3/16.
//  Copyright © 2016 Brendon Justin. All rights reserved.
//

#import "AirplayConstants.h"

#import <Foundation/Foundation.h>

const BOOL kAHEnableDebugOutput = YES;
const BOOL kAHAssumeReverseTimesOut = NO;
const NSUInteger    kAHVideo = 0,
                    kAHPhoto = 1,
                    kAHVideoFairPlay = 2,
                    kAHVideoVolumeControl = 3,
                    kAHVideoHTTPLiveStreams = 4,
                    kAHSlideshow = 5,
                    kAHScreen = 7,
                    kAHScreenRotate = 8,
                    kAHAudio = 9,
                    kAHAudioRedundant = 11,
                    kAHFPSAPv2pt5_AES_GCM = 12,
                    kAHPhotoCaching = 13;
const NSUInteger    kAHRequestTagReverse = 1,
                    kAHRequestTagPlay = 2;
const NSUInteger    kAHPropertyRequestPlaybackAccess = 1,
                    kAHPropertyRequestPlaybackError = 2;
