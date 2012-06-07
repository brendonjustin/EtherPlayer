//
//  OutputVideoCreator.m
//  EtherPlayer
//
//  Created by Brendon Justin on 6/6/12.
//  Copyright (c) 2012 Brendon Justin. All rights reserved.
//

#import "OutputVideoCreator.h"

#import "HTTPServer.h"

#import <VLCKit/VLCMedia.h>
#import <VLCKit/VLCStreamOutput.h>
#import <VLCKit/VLCStreamSession.h>

#import <arpa/inet.h>
#import <ifaddrs.h>

const NSString      *kOVCOutputFiletype = @"ts";
const NSUInteger    kOVCSegmentDuration = 10;

@interface OutputVideoCreator () <VLCMediaDelegate>

- (void)transcodeMedia:(VLCMedia *)inputMedia;
- (void)createMediaPlist;
- (void)stop;
- (void)waitForPlaylist;

@property (strong, nonatomic) VLCMedia          *m_inputMedia;
@property (strong, nonatomic) VLCStreamSession  *m_session;
@property (strong, nonatomic) NSString          *m_baseOutputPath;
@property (strong, nonatomic) NSString          *m_httpAddress;
@property (strong, nonatomic) NSString          *m_httpFilePath;
@property (strong, nonatomic) NSURL             *m_baseUrl;
@property (strong, nonatomic) HTTPServer        *m_httpServer;
@property (nonatomic) NSUInteger                m_sessionRandom;

@end

@implementation OutputVideoCreator

//  public properties
@synthesize delegate;
@synthesize playRequestData = m_playRequestData;
@synthesize playRequestDataType = m_playRequestDataType;
@synthesize outputSegsFilename = m_outputSegsFilename;
@synthesize outputM3u8Filename = m_outputM3u8Filename;

//  private properties
@synthesize m_inputMedia;
@synthesize m_session;
@synthesize m_baseOutputPath;
@synthesize m_httpAddress;
@synthesize m_httpFilePath;
@synthesize m_baseUrl;
@synthesize m_httpServer;
@synthesize m_sessionRandom;

//  temporary directory code thanks to a Stack Overflow post
//  http://stackoverflow.com/questions/374431/how-do-i-get-the-default-temporary-directory-on-mac-os-x
//  ip address retrieval code also thanks to a Stack Overflow post
//  http://stackoverflow.com/questions/7072989/iphone-ipad-how-to-get-my-ip-address-programmatically
- (id)init
{
    if ((self = [super init])) {
        NSString        *tempDir = nil;
        NSError         *error = nil;
        struct ifaddrs  *ifap;
        struct ifaddrs  *ifap0;
        
        m_httpAddress = nil;
        m_session = nil;
        
        tempDir = NSTemporaryDirectory();
        if (tempDir == nil)
            tempDir = @"/tmp";
        
        m_baseOutputPath = [tempDir stringByAppendingString:@"com.brendonjustin.EtherPlayer/"];
        [[NSFileManager defaultManager] createDirectoryAtPath:m_baseOutputPath
                                  withIntermediateDirectories:NO 
                                                   attributes:nil 
                                                        error:&error];
        
        //  create our http server and set the port arbitrarily
        m_httpServer = [[HTTPServer alloc] init];
        m_httpServer.documentRoot = m_baseOutputPath;
        m_httpServer.port = 6004;
        
        if(![m_httpServer start:&error])
        {
            NSLog(@"Error starting HTTP Server: %@", error);
        }
        
        //  get our IPv4 addresss
        NSString *adapterName = nil;
        NSUInteger success = getifaddrs(&ifap0);
        if (success == 0) {
            //  Loop through linked list of interfaces
            ifap = ifap0;
            while(ifap != NULL) {
                if(ifap->ifa_addr->sa_family == AF_INET) {
                    //  look for en0 and hope it is the primary lan interface as on the MBA and iPhone,
                    //  but take anything aside from loopback as a fallback
                    adapterName = [NSString stringWithUTF8String:ifap->ifa_name];
                    if (m_httpAddress == nil && ![adapterName isEqualToString:@"lo0"]) {
                        //  Get NSString from C String
                        m_httpAddress = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)ifap->ifa_addr)->sin_addr)];
                    }
                    
                    if([[NSString stringWithUTF8String:ifap->ifa_name] isEqualToString:@"en0"]) {
                        //  Get NSString from C String
                        m_httpAddress = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)ifap->ifa_addr)->sin_addr)];               
                    }
                }
                ifap = ifap->ifa_next;
            }
        }
        //  Free memory
        freeifaddrs(ifap0);
        
        if (m_httpAddress == nil) {
            NSLog(@"Error, could not find a non-loopback IPv4 address for myself.");
        } else {
            m_httpAddress = [@"http://" stringByAppendingFormat:@"%@:%u/",
                             m_httpAddress, m_httpServer.port];
        }
    }
    
    return self;
}

- (void)transcodeMediaForPath:(NSString *)mediaPath
{
    m_sessionRandom = arc4random();
    
    m_outputSegsFilename = [NSString stringWithFormat:@"%u-#####.%@", m_sessionRandom,
                            kOVCOutputFiletype];
    
    m_outputM3u8Filename = [NSString stringWithFormat:@"%u.m3u8", m_sessionRandom];
    m_httpFilePath = [m_httpAddress stringByAppendingString:m_outputM3u8Filename];
    
    m_inputMedia = [VLCMedia mediaWithPath:mediaPath];
    m_inputMedia.delegate = self;
    [m_inputMedia parse];
    
    [self createMediaPlist];
}

//  TODO: intelligently choose bitrates and channels
- (void)transcodeMedia:(VLCMedia *)inputMedia
{
    NSString            *videoCodec = @"h264";
    NSString            *audioCodec = @"mp3";
    NSString            *videoBitrate = nil;
    NSString            *audioBitrate = nil;
    NSString            *audioChannels = nil;
    NSString            *width = nil;
    NSString            *subs = nil;
    NSString            *outputPath = nil;
    NSString            *m3u8Out = nil;
    NSString            *videoFilesPath = nil;
    NSString            *mrlString = nil;
    NSMutableDictionary *transcodingOptions = nil;
    NSMutableDictionary *outputOptions = nil;
    NSMutableDictionary *streamOutputOptions = nil;
    VLCStreamOutput     *output = nil;
    BOOL                videoNeedsTranscode = NO;
    BOOL                audioNeedsTranscode = NO;
    
    [self stop];
    
    m_session = [VLCStreamSession streamSession];
    m_session.media = inputMedia;
    
    for (NSDictionary *properties in [inputMedia tracksInformation]) {
        if ([[properties objectForKey:@"type"] isEqualToString:@"video"]) {
            if (width == nil) {
                width = [properties objectForKey:@"width"];
                if ([width integerValue] > 1920) {
                    width = @"1920";
                    videoNeedsTranscode = YES;
                }
                
                //  h264 is 875967080
                //  Only some AirPlay devices support HD, and even those support
                //  up 1280x720, so this may need adjusting
                if ([[properties objectForKey:@"codec"] integerValue] != 875967080) {
                    videoNeedsTranscode = YES;
                }
            }
        }
        if ([[properties objectForKey:@"type"] isEqualToString:@"audio"]) {
            if (audioChannels == nil) {
                audioChannels = [properties objectForKey:@"channelsNumber"];
                if ([audioChannels integerValue] > 6) {
                    audioChannels = @"6";
                    audioNeedsTranscode = YES;
                }
                
                //  AAC is 1630826605
                //  MP3 is ???
                //  AC3 is 540161377
                //  Only some AirPlay devices support AC3 audio, so this may need adjusting
                if ([[properties objectForKey:@"codec"] integerValue] != 1630826605 &&
                    [[properties objectForKey:@"codec"] integerValue] != 540161377) {
                    audioNeedsTranscode = YES;
                }
            }
        }
        if ([[properties objectForKey:@"type"] isEqualToString:@"text"]) {
            if (subs == nil) {
                subs = @"tx3g";
            }
        }
    }
    
    videoBitrate = [NSString stringWithFormat:@"%u", [width integerValue] * 5];
    audioBitrate = [NSString stringWithFormat:@"%u", [audioChannels integerValue] * 128];
    
    transcodingOptions = [NSMutableDictionary dictionary];
    
    if (videoNeedsTranscode) {
        [transcodingOptions addEntriesFromDictionary:[NSDictionary dictionaryWithObjectsAndKeys:
                                                      videoCodec, @"videoCodec",
                                                      videoBitrate, @"videoBitrate",
                                                      width, @"width",
                                                      nil]];
    }
    
    if (audioNeedsTranscode) {
        [transcodingOptions addEntriesFromDictionary:[NSDictionary dictionaryWithObjectsAndKeys:
                                                      audioCodec, @"audioCodec",
                                                      audioBitrate, @"audioBitrate",
                                                      audioChannels, @"channels",
                                                      @"Yes", @"audio-sync",
                                                      nil]];
    }
    
    if (subs != nil) {
        [transcodingOptions addEntriesFromDictionary:[NSDictionary dictionaryWithObjectsAndKeys:
                                                      subs, @"scodec",
                                                      nil]];
    }
    
    outputPath = [m_baseOutputPath stringByAppendingFormat:m_outputSegsFilename];
    videoFilesPath = [m_httpAddress stringByAppendingString:m_outputSegsFilename];
    
    //  use part of an mrl to set our options all at once
    mrlString = @"livehttp{seglen=%u,delsegs=false,index=%@,index-url=%@},mux=ts{use-key-frames},dst=%@";
    
    m3u8Out = [m_baseOutputPath stringByAppendingString:m_outputM3u8Filename];
    
    outputOptions = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                     [NSString stringWithFormat:mrlString, kOVCSegmentDuration,
                      m3u8Out, videoFilesPath, outputPath], @"access",
                     nil];
    
    if (subs != nil) {
        [outputOptions addEntriesFromDictionary:[NSDictionary dictionaryWithObjectsAndKeys:
                                                 @"0", @"sub-track",
                                                 nil]];
    }
    
    streamOutputOptions = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                           outputOptions, @"outputOptions",
                           nil];
    
    if (videoNeedsTranscode || audioNeedsTranscode) {
        [streamOutputOptions addEntriesFromDictionary:[NSDictionary dictionaryWithObjectsAndKeys:
                                                       transcodingOptions, @"transcodingOptions",
                                                       nil]];
    }
    
    output = [VLCStreamOutput streamOutputWithOptionDictionary:streamOutputOptions];
    
    m_session.streamOutput = output;
    [m_session startStreaming];
}

- (void)createMediaPlist
{
    NSDictionary            *dict = nil;
    NSError                 *err = nil;
    NSPropertyListFormat    format;
    
    dict = [NSDictionary dictionaryWithObjectsAndKeys:m_httpFilePath, @"Content-Location",
            [NSString stringWithFormat:@"%f", 0], @"Start-Position", nil];
    [dict writeToFile:[m_baseOutputPath stringByAppendingFormat:@"%u.plist", m_sessionRandom]
           atomically:YES];
    m_playRequestData = [NSData dataWithContentsOfFile:[m_baseOutputPath stringByAppendingFormat:@"%u.plist",
                                                        m_sessionRandom]];
    
    [NSPropertyListSerialization propertyListWithData:m_playRequestData
                                              options:NSPropertyListImmutable
                                               format:&format
                                                error:&err];
    
    if (err != nil) {
        NSLog(@"Error preparing PLIST for current media, %ld", err.code);
    }
    
    if (format == NSPropertyListBinaryFormat_v1_0) {
        m_playRequestDataType = @"application/x-apple-binary-plist";
    } else if (format == NSPropertyListXMLFormat_v1_0) {
        m_playRequestDataType = @"text/x-apple-plist+xml";
    } else {
        //  format == NSPropertyListOpenStepFormat
        //  should never get here, Apple doesn't write out PLISTs in this format any more
    }
}

//  TODO: consider doing more in this function
- (void)stop
{
    //  if m_session exists, it must be stopped
    //  if not, this is still OK since m_session was initialized to nil
    [m_session stopStreaming];
}

//  wait for the playlist file for this session to be created,
//  i.e. the .m3u8 file that says how to play the segments that have
//  been created for the input video
- (void)waitForPlaylist
{
    if ([[NSFileManager defaultManager] fileExistsAtPath:[m_baseOutputPath stringByAppendingString:m_outputM3u8Filename]]) {
        [delegate outputReady:self];
    } else {
        [NSTimer scheduledTimerWithTimeInterval:2.0
                                         target:self
                                       selector:@selector(waitForPlaylist)
                                       userInfo:nil
                                        repeats:NO];
    }
}

#pragma mark -
#pragma mark VLCMediaDelegate functions

//  ignore calls to this function
- (void)media:(VLCMedia *)aMedia metaValueChangedFrom:(id)oldValue forKey:(NSString *)key
{
    NSLog(@"media:metaValueChangedFrom:forKey: called");
    return;
}

//  begin transcoding only after the media has been parsed
- (void)mediaDidFinishParsing:(VLCMedia *)aMedia
{
    [self transcodeMedia:aMedia];
    //  give VLCKit at least one segment duration before checking
    //  for the playlist file
    [NSTimer scheduledTimerWithTimeInterval:kOVCSegmentDuration
                                     target:self
                                   selector:@selector(waitForPlaylist)
                                   userInfo:nil
                                    repeats:NO];
}

@end
