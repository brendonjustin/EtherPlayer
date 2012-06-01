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

//  private properties
@synthesize m_video;
@synthesize m_streamOutput;
@synthesize m_outputPath;

- (void)transcodeInput
{
    NSUInteger  videoBitrate;
    NSUInteger  audioBitrate;
    NSUInteger  audioChannels;
    NSUInteger  width;
    NSUInteger  height;
    
    m_streamOutput = [VLCStreamOutput streamOutputWithOptionDictionary:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                  [NSDictionary dictionaryWithObjectsAndKeys:
                                                                   @"h264", @"videoCodec",
                           [NSString stringWithFormat:@"%u", videoBitrate], @"videoBitrate",
                                                                   @"mp4a", @"audioCodec",
                           [NSString stringWithFormat:@"%u", audioBitrate], @"audioBitrate",
                          [NSString stringWithFormat:@"%u", audioChannels], @"channels",
                                  [NSString stringWithFormat:@"%u", width], @"width",
                                 [NSString stringWithFormat:@"%u", height], @"canvasHeight",
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
