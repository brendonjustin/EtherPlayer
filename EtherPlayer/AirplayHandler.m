//
//  AirplayHandler.m
//  EtherPlayer
//
//  Created by Brendon Justin on 5/31/12.
//  Copyright (c) 2012 Brendon Justin. All rights reserved.
//

#import "AirplayHandler.h"

#import <VLCKit/VLCMedia.h>
#import <VLCKit/VLCStreamOutput.h>
#import <VLCKit/VLCStreamSession.h>

@interface AirplayHandler ()

@property (strong, nonatomic) VLCMedia          *m_video;
@property (strong, nonatomic) VLCStreamOutput   *m_output;
@property (strong, nonatomic) VLCStreamSession  *m_session;
@property (strong, nonatomic) NSString          *m_outputPath;

@end

@implementation AirplayHandler

//  public properties
@synthesize inputPath = m_inputPath;
@synthesize targetService = m_targetService;

//  private properties
@synthesize m_video;
@synthesize m_output;
@synthesize m_session;
@synthesize m_outputPath;

//  TODO: intelligently choose bitrates and channels
- (void)transcodeInput
{
    NSString *videoCodec = @"h264";
    NSString *audioCodec = @"mp4a";
    NSString *videoBitrate = @"1024";
    NSString *audioBitrate = @"128";
    NSString *audioChannels = @"2";
    NSString *width = @"640";
    NSString *height = @"480";
    
    m_output = [VLCStreamOutput streamOutputWithOptionDictionary:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                  [NSDictionary dictionaryWithObjectsAndKeys:
                                                                   videoCodec, @"videoCodec",
                                                                   videoBitrate, @"videoBitrate",
                                                                   audioCodec, @"audioCodec",
                                                                   audioBitrate, @"audioBitrate",
                                                                   audioChannels, @"channels",
                                                                   width, @"width",
                                                                   height, @"canvasHeight",
                                                                   @"Yes", @"audio-sync",
                                                                   nil
                                                                   ], @"transcodingOptions",
                                                                  [NSDictionary dictionaryWithObjectsAndKeys:
                                                                   @"mp4", @"muxer",
                                                                   @"file", @"access",
                                                                   m_outputPath, @"destination", 
                                                                   nil
                                                                   ], @"outputOptions",
                                                                  nil
                                                                  ]];
    
    m_session = [[VLCStreamSession alloc] init];
    m_session.media = m_video;
    m_session.streamOutput = m_output;
    
    [m_session startStreaming];
}

@end
