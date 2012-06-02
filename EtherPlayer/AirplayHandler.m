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

#include <arpa/inet.h>

@interface AirplayHandler ()

- (void)transcodeInput;

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

- (void)airplay
{
    NSArray             *sockArray = nil;
    NSData              *sockData = nil;
    NSURL               *baseUrl = nil;
    NSURLRequest        *request;
    char                addressBuffer[100];
    struct sockaddr_in  *sockAddress;
    
    sockArray = m_targetService.addresses;
    sockData = [sockArray objectAtIndex:0];
    
    sockAddress = (struct sockaddr_in*) [sockData bytes];
    
    int sockFamily = sockAddress->sin_family;
    if (sockFamily == AF_INET || sockFamily == AF_INET6) {
        const char* addressStr = inet_ntop(sockFamily,
                                           &(sockAddress->sin_addr), addressBuffer,
                                           sizeof(addressBuffer));
        int port = ntohs(sockAddress->sin_port);
        if (addressStr && port) {
            NSString *address = [NSString stringWithFormat:@"http://%s:%d", addressStr, port];
            NSLog(@"Found service at %@", address);
            baseUrl = [NSURL URLWithString:address];
        }
    }
    
    //  reverse
    request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"/reverse" relativeToURL:baseUrl]];
    
    //  play
    
    //  rate
    
    //  (GET)scrub
    
    //  (GET)playback-info
}

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
