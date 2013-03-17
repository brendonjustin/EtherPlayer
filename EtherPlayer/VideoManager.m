//
//  OutputVideoCreator.m
//  EtherPlayer
//
//  Created by Brendon Justin on 6/6/12.
//  Copyright (c) 2012 Brendon Justin. All rights reserved.
//

#import "VideoManager.h"

#import "HTTPServer.h"

#import <VLCKit/VLCMedia.h>
#import <VLCKit/VLCStreamOutput.h>
#import <VLCKit/VLCStreamSession.h>

#import <arpa/inet.h>
#import <ifaddrs.h>

const NSString      *kOVCNormalOutputFiletype = @"mp4";
const NSString      *kOVCHLSOutputFiletype = @"ts";
const NSUInteger    kOVCSegmentDuration = 15;
const BOOL          kOVCIncludeSubs = NO;
const BOOL          kOVCCleanTempDir = NO;

@interface VideoManager () <VLCMediaDelegate>

- (void)transcodeMedia:(VLCMedia *)inputMedia;
- (void)waitForOutputStream;

@property (strong, nonatomic) VLCMedia          *m_inputMedia;
@property (strong, nonatomic) VLCStreamSession  *m_session;
@property (strong, nonatomic) NSString          *m_baseFilePath;
@property (strong, nonatomic) NSString          *m_httpAddress;
@property (strong, nonatomic) NSString          *m_httpFilePath;
@property (strong, nonatomic) NSString          *m_outputStreamPath;
@property (strong, nonatomic) NSString          *m_outputStreamFilename;
@property (strong, nonatomic) NSString          *m_m3u8Filename;
@property (strong, nonatomic) NSURL             *m_baseUrl;
@property (strong, nonatomic) HTTPServer        *m_httpServer;
@property (nonatomic) NSUInteger                m_sessionRandom;

@end

@implementation VideoManager

//  public properties
@synthesize delegate;
@synthesize httpFilePath = m_httpFilePath;
@synthesize useHttpLiveStreaming = m_useHLS;

//  private properties
@synthesize m_inputMedia;
@synthesize m_session;
@synthesize m_baseFilePath;
@synthesize m_httpAddress;
@synthesize m_outputStreamPath;
@synthesize m_outputStreamFilename;
@synthesize m_m3u8Filename;
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
        NSString        *bundleIdentifier = nil;
        NSString        *tempDir = nil;
        NSError         *error = nil;
        struct ifaddrs  *ifap;
        struct ifaddrs  *ifap0;
        
        m_httpAddress = nil;
        m_session = nil;
        
        tempDir = NSTemporaryDirectory();
        if (tempDir == nil)
            tempDir = @"/tmp";
        
        bundleIdentifier = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"];
        m_baseFilePath = [tempDir stringByAppendingString:bundleIdentifier];
        m_baseFilePath = [m_baseFilePath stringByAppendingString:@"/"];
        [[NSFileManager defaultManager] createDirectoryAtPath:m_baseFilePath
                                  withIntermediateDirectories:NO 
                                                   attributes:nil 
                                                        error:&error];
        
        //  create our http server and set the port arbitrarily
        m_httpServer = [[HTTPServer alloc] init];
        m_httpServer.documentRoot = m_baseFilePath;
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
        
        //  settings for VLCKit, copied from VLCKit's VLCLibrary.m and slightly modified
        NSMutableArray *defaultParams = [NSMutableArray array];
        [defaultParams addObject:@"--no-color"];                                // Don't use color in output (Xcode doesn't show it)
        [defaultParams addObject:@"--no-video-title-show"];                     // Don't show the title on overlay when starting to play
        [defaultParams addObject:@"--verbose=2"];                               // Let's not wreck the logs
        [defaultParams addObject:@"--no-sout-keep"];
        [defaultParams addObject:@"--vout=macosx"];                             // Select Mac OS X video output
        [defaultParams addObject:@"--text-renderer=quartztext"];                // our CoreText-based renderer
        [defaultParams addObject:@"--extraintf=macosx_dialog_provider"];        // Some extra dialog (login, progress) may come up from here
        [defaultParams addObject:@"--sub-track=0"];
        
        [[NSUserDefaults standardUserDefaults] setObject:defaultParams forKey:@"VLCParams"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    
    return self;
}

- (void)transcodeMediaForPath:(NSString *)mediaPath
{
    m_sessionRandom = arc4random();

    if ([mediaPath rangeOfString:@"file://localhost"].location != NSNotFound) {
        mediaPath = [mediaPath stringByReplacingOccurrencesOfString:@"file://localhost" withString:@""];
        mediaPath = [mediaPath stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    }

    if (m_useHLS) {
        m_outputStreamFilename = [NSString stringWithFormat:@"%lu-#####.%@", m_sessionRandom,
                                  kOVCHLSOutputFiletype];
        
        m_m3u8Filename = [NSString stringWithFormat:@"%lu.m3u8", m_sessionRandom];
        m_httpFilePath = [m_httpAddress stringByAppendingString:m_m3u8Filename];
    } else {
        m_outputStreamFilename = [NSString stringWithFormat:@"%lu.%@", m_sessionRandom,
                                  kOVCNormalOutputFiletype];
        m_httpFilePath = [m_httpAddress stringByAppendingString:m_outputStreamFilename];
    }
    
    m_inputMedia = [VLCMedia mediaWithPath:mediaPath];
    m_inputMedia.delegate = self;
    [m_inputMedia parse];
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
    NSString            *videoFilesPath = nil;
    NSString            *videoFilesUrl = nil;
    NSString            *access = nil;
    NSMutableArray      *audioCodecs = nil;
    NSMutableDictionary *transcodingOptions = nil;
    NSMutableDictionary *outputOptions = nil;
    NSMutableDictionary *streamOutputOptions = nil;
    VLCStreamOutput     *output = nil;
    BOOL                videoNeedsTranscode = NO;
    BOOL                audioNeedsTranscode = NO;
    
    [self stop];
    
    m_session = [VLCStreamSession streamSession];
    m_session.media = inputMedia;
    
    //  AAC is 1630826605
    //  MP3 is 1634168941
    //  AC3 is 540161377
    //  AirPlay devices need not support AC3 audio, so this may need adjusting
    //  VLCKit doesn't support AC3 in MP4, so don't allow it unless we are
    //  using TS, i.e. we are using HTTP Live Streaming
    audioCodecs = [NSMutableArray arrayWithObjects:@"1630826605", @"1634168941", nil];

    if (m_useHLS) {
        [audioCodecs addObject:@"540161377"];
    }
    
    streamOutputOptions = [NSMutableDictionary dictionary];
    
    for (NSDictionary *properties in [inputMedia tracksInformation]) {
        if ([[properties objectForKey:@"type"] isEqualToString:@"video"]) {
            if (width == nil) {
                width = [properties objectForKey:@"width"];
                
                //  AirPlay devices need not support HD, and some that do may
                //  only support up 1280x720, so this may need adjusting
                if ([width integerValue] > 1920) {
                    width = @"1920";
                    videoNeedsTranscode = YES;
                }
                
                //  h264 is 875967080
                //  other video codecs may be supported, further investigation
                //  is required
                if ([[properties objectForKey:@"codec"] integerValue] != 875967080) {
                    videoNeedsTranscode = YES;
                }
            }
        }
        if ([[properties objectForKey:@"type"] isEqualToString:@"audio"]) {
            if (audioChannels == nil) {
                //  AirPlay devices need not support higher than stereo audio, so
                //  this may need adjusting
                audioChannels = [properties objectForKey:@"channelsNumber"];
                if ([audioChannels integerValue] > 6) {
                    audioChannels = @"6";
                    audioNeedsTranscode = YES;
                }

                //  transcode if the audio codec is supported by the intended container
                if (![audioCodecs containsObject:[properties objectForKey:@"codec"]]) {
                    audioChannels = @"2";
                    audioNeedsTranscode = YES;
                }
            }
        }
        if ([[properties objectForKey:@"type"] isEqualToString:@"text"]) {
            if (subs == nil) {
                subs = @"tx3g";
//                subs = @"subt";
            }
        }
    }
    
    videoBitrate = [NSString stringWithFormat:@"%lu", [width integerValue] * 3];
    audioBitrate = [NSString stringWithFormat:@"%lu", [audioChannels integerValue] * 128];
    
    transcodingOptions = [NSMutableDictionary dictionary];

    if (kOVCIncludeSubs && subs != nil) {
        //  VLCKit can't encode subs for MP4, so if we are using HLS then we have
        //  to burn the subs into the video
        if (m_useHLS) {
            [transcodingOptions addEntriesFromDictionary:@{ @"subtitleOverlay" : @YES }];
             videoNeedsTranscode = YES;
        } else {
            [transcodingOptions addEntriesFromDictionary:@{ @"subtitleEncoder" : @"dvbsub" }];
        }
    }

    if (videoNeedsTranscode) {
        [transcodingOptions addEntriesFromDictionary:@{ @"videoCodec" : videoCodec,
                                                        @"videoBitrate" : videoBitrate,
                                                        @"width" : width }];
    }
    
    if (audioNeedsTranscode) {
        [transcodingOptions addEntriesFromDictionary:@{ @"audioCodec" : audioCodec,
                                                        @"audioBitrate" : audioBitrate,
                                                        @"channels" : audioChannels,
                                                        @"audio-sync" : @"Yes" }];
    }

    if ([transcodingOptions count] > 0) {
        [streamOutputOptions addEntriesFromDictionary:@{ @"transcodingOptions" : transcodingOptions }];
    }
    
    videoFilesPath = [m_baseFilePath stringByAppendingString:m_outputStreamFilename];
    videoFilesUrl = [m_httpAddress stringByAppendingString:m_outputStreamFilename];
    
    //  use part of an mrl to set our options all at once
    if (m_useHLS) {
        m_outputStreamPath = [m_baseFilePath stringByAppendingString:m_m3u8Filename];

        access = @"livehttp{seglen=%u,delsegs=false,index=%@,index-url=%@}";
        outputOptions = [NSMutableDictionary dictionaryWithDictionary:
                         @{ @"access" :  [NSString stringWithFormat:access, kOVCSegmentDuration,
                          m_outputStreamPath, videoFilesUrl],
                         @"muxer" : [NSString stringWithFormat:@"%@{use-key-frames}",
                                     kOVCHLSOutputFiletype],
                         @"destination" : videoFilesPath }];
    } else {
        m_outputStreamPath = videoFilesPath;

        access = @"file";
        outputOptions = [NSMutableDictionary dictionaryWithDictionary:
                         @{ @"access" : access,
                         @"muxer" : kOVCNormalOutputFiletype,
                         @"destination" : m_outputStreamPath }];
    }
    
    [streamOutputOptions addEntriesFromDictionary:@{ @"outputOptions" : outputOptions }];
    
    output = [VLCStreamOutput streamOutputWithOptionDictionary:streamOutputOptions];
    
    m_session.streamOutput = output;
    [m_session startStreaming];
}

- (void)stop
{
    //  if m_session exists, it must be stopped
    //  if not, this is still OK since m_session was initialized to nil
    [m_session stopStreaming];
}

//  wait for the output file for this session to be created,
//  i.e. the .m3u8 file for HLS (or the actual video file otherwise) has
//  been created for the input video
- (void)waitForOutputStream
{
    BOOL isA = NO;
    if (isA || [m_session isComplete]) {
        [m_session stopStreaming];
        [delegate outputReady:self];
    } else {
        [NSTimer scheduledTimerWithTimeInterval:2.0
                                         target:self
                                       selector:@selector(waitForOutputStream)
                                       userInfo:nil
                                        repeats:NO];
    }
}

- (double)duration
{
    return m_inputMedia.length.intValue / 1000.0f;
}

- (void)cleanup
{
    NSFileManager           *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator   *directoryEnum = [fileManager enumeratorAtPath:m_baseFilePath];    
    NSError                 *error = nil;
    NSString                *currentFile = nil;
    BOOL                    success;
    
    while (kOVCCleanTempDir && (currentFile = [directoryEnum nextObject])) {
        success = [fileManager removeItemAtPath:[m_baseFilePath stringByAppendingPathComponent:currentFile]
                                          error:&error];
        if (!success && error != nil) {
            NSLog(@"Error deleting temporary file: %@: %@", currentFile, error);
        }
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
                                   selector:@selector(waitForOutputStream)
                                   userInfo:nil
                                    repeats:NO];
}

@end
