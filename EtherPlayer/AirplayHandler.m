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

@interface AirplayHandler ()

@property (strong, nonatomic) VLCMedia          *m_video;
@property (strong, nonatomic) VLCStreamOutput   *m_streamOutput;
@property (strong, nonatomic) NSString          *m_outputPath;

@end

@implementation AirplayHandler

//  public properties
@synthesize inputPath = m_inputPath;
@synthesize targetService = m_targetService;

//  private properties
@synthesize m_video;
@synthesize m_streamOutput;
@synthesize m_outputPath;

//  TODO: intelligently choose bitrates and channels
- (void)transcodeInput
{
    NSString *audioCodec;
    NSString *videoBitrate;
    NSString *audioBitrate;
    NSString *audioChannels;
    NSString *width;
    NSString *height;
    
    audioCodec = @"mp4a";
    videoBitrate = @"1024";
    audioBitrate = @"128";
    audioChannels = @"2";
    width = @"640";
    height = @"480";
    
    m_streamOutput = [VLCStreamOutput streamOutputWithOptionDictionary:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                  [NSDictionary dictionaryWithObjectsAndKeys:
                                                                   @"h264", @"videoCodec",
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
}

@end
