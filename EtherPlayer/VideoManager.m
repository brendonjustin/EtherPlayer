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

@property (strong, nonatomic) VLCMedia          *inputMedia;
@property (strong, nonatomic) VLCStreamSession  *session;
@property (strong, nonatomic) NSString          *baseFilePath;
@property (strong, nonatomic) NSString          *httpAddress;
@property (strong, nonatomic) NSString          *outputStreamPath;
@property (strong, nonatomic) NSString          *outputStreamFilename;
@property (strong, nonatomic) NSString          *m3u8Filename;
@property (strong, nonatomic) NSURL             *baseUrl;
@property (strong, nonatomic) HTTPServer        *httpServer;
@property (nonatomic) NSUInteger                sessionRandom;
@property (nonatomic) BOOL                      useHLS;

@end

@implementation VideoManager

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
        
        self.httpAddress = nil;
        self.session = nil;
        
        tempDir = NSTemporaryDirectory();
        if (tempDir == nil)
            tempDir = @"/tmp";
        
        bundleIdentifier = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"];
        self.baseFilePath = [tempDir stringByAppendingString:bundleIdentifier];
        self.baseFilePath = [self.baseFilePath stringByAppendingString:@"/"];
        [[NSFileManager defaultManager] createDirectoryAtPath:self.baseFilePath
                                  withIntermediateDirectories:NO 
                                                   attributes:nil 
                                                        error:&error];
        
        //  create our http server and set the port arbitrarily
        self.httpServer = [[HTTPServer alloc] init];
        self.httpServer.documentRoot = self.baseFilePath;
        self.httpServer.port = 6004;
        
        if(![self.httpServer start:&error])
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
                    if (self.httpAddress == nil && ![adapterName isEqualToString:@"lo0"]) {
                        //  Get NSString from C String
                        self.httpAddress = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)ifap->ifa_addr)->sin_addr)];
                    }
                    
                    if([[NSString stringWithUTF8String:ifap->ifa_name] isEqualToString:@"en0"]) {
                        //  Get NSString from C String
                        self.httpAddress = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)ifap->ifa_addr)->sin_addr)];               
                    }
                }
                ifap = ifap->ifa_next;
            }
        }
        //  Free memory
        freeifaddrs(ifap0);
        
        if (self.httpAddress == nil) {
            NSLog(@"Error, could not find a non-loopback IPv4 address for myself.");
        } else {
            self.httpAddress = [@"http://" stringByAppendingFormat:@"%@:%u/",
                             self.httpAddress, self.httpServer.port];
        }
        
        //  settings for VLCKit, copied from VLCKit's VLCLibrary.m and slightly modified
        NSMutableArray *defaultParams = [NSMutableArray array];
        [defaultParams addObject:@"--no-color"];                                // Don't use color in output (Xcode doesn't show it)
        [defaultParams addObject:@"--no-video-title-show"];                     // Don't show the title on overlay when starting to play
        [defaultParams addObject:@"--verbose=4"];                               // Let's not wreck the logs
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

- (void)setUseHttpLiveStreaming:(BOOL)useHttpLiveStreaming
{
    self.useHLS = useHttpLiveStreaming;
}

- (BOOL)useHttpLiveStreaming
{
    return self.useHLS;
}

- (void)transcodeMediaForPath:(NSString *)mediaPath
{
    self.sessionRandom = arc4random();

    if ([mediaPath rangeOfString:@"file://localhost"].location != NSNotFound) {
        mediaPath = [mediaPath stringByReplacingOccurrencesOfString:@"file://localhost" withString:@""];
        mediaPath = [mediaPath stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    }

    if (self.useHLS) {
        self.outputStreamFilename = [NSString stringWithFormat:@"%lu-#####.%@", self.sessionRandom,
                                  kOVCHLSOutputFiletype];
        
        self.m3u8Filename = [NSString stringWithFormat:@"%lu.m3u8", self.sessionRandom];
        self.httpFilePath = [self.httpAddress stringByAppendingString:self.m3u8Filename];
    } else {
        self.outputStreamFilename = [NSString stringWithFormat:@"%lu.%@", self.sessionRandom,
                                  kOVCNormalOutputFiletype];
        self.httpFilePath = [self.httpAddress stringByAppendingString:self.outputStreamFilename];
    }
    
    self.inputMedia = [VLCMedia mediaWithPath:mediaPath];
    self.inputMedia.delegate = self;
    [self.inputMedia parse];
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
    
    self.session = [VLCStreamSession streamSession];
    self.session.media = inputMedia;
    
    //  AAC is 1630826605
    //  MP3 is 1634168941
    //  AC3 is 540161377
    //  AirPlay devices need not support AC3 audio, so this may need adjusting
    //  VLCKit doesn't support AC3 in MP4, so don't allow it unless we are
    //  using TS, i.e. we are using HTTP Live Streaming
    audioCodecs = [NSMutableArray arrayWithObjects:@"1630826605", @"1634168941", nil];

    if (self.useHLS) {
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
        if (self.useHLS) {
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
    
    videoFilesPath = [self.baseFilePath stringByAppendingString:self.outputStreamFilename];
    videoFilesUrl = [self.httpAddress stringByAppendingString:self.outputStreamFilename];
    
    //  use part of an mrl to set our options all at once
    if (self.useHLS) {
        self.outputStreamPath = [self.baseFilePath stringByAppendingString:self.m3u8Filename];

        access = @"livehttp{seglen=%u,delsegs=false,index=%@,index-url=%@}";
        outputOptions = [NSMutableDictionary dictionaryWithDictionary:
                         @{ @"access" :  [NSString stringWithFormat:access, kOVCSegmentDuration,
                          self.outputStreamPath, videoFilesUrl],
                         @"muxer" : [NSString stringWithFormat:@"%@{use-key-frames}",
                                     kOVCHLSOutputFiletype],
                         @"destination" : videoFilesPath }];
    } else {
        self.outputStreamPath = videoFilesPath;

        access = @"file";
        outputOptions = [NSMutableDictionary dictionaryWithDictionary:
                         @{ @"access" : access,
                         @"muxer" : kOVCNormalOutputFiletype,
                         @"destination" : self.outputStreamPath }];
    }
    
    [streamOutputOptions addEntriesFromDictionary:@{ @"outputOptions" : outputOptions }];
    
    output = [VLCStreamOutput streamOutputWithOptionDictionary:streamOutputOptions];
    
    self.session.streamOutput = output;
    [self.session startStreaming];
}

- (void)stop
{
    //  if self.session exists, it must be stopped
    //  if not, this is still OK since self.session was initialized to nil
    [self.session stopStreaming];
}

//  wait for the output file for this session to be created,
//  i.e. the .m3u8 file for HLS (or the actual video file otherwise) has
//  been created for the input video
- (void)waitForOutputStream
{
    BOOL isReady = (self.useHLS && [[NSFileManager defaultManager] fileExistsAtPath:self.outputStreamPath]) || [self.session isComplete];
    
    if (isReady) {
        if ([self.session isComplete]) {
            [self.session stopStreaming];
            
            if (!self.useHLS) {
                [self.delegate outputReady:self];
                
                return;
            } else if (self.useHLS && [[NSFileManager defaultManager] fileExistsAtPath:self.outputStreamPath]) {
                NSData          *data = nil;
                NSString        *fileContents = nil;
                NSString        *findString = @"_";
                NSString        *replaceString = @":";
                NSFileHandle    *file = nil;
                
                file = [NSFileHandle fileHandleForUpdatingAtPath:self.outputStreamPath];
                
                if (file != nil) {
                    data = [file readDataToEndOfFile];
                    
                    fileContents = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    
                    //  replace incorrect characters in the playlist file
                    fileContents = [fileContents stringByReplacingOccurrencesOfString:findString
                                                                           withString:replaceString];
                    
                    [file seekToFileOffset:0];
                    [file writeData:[fileContents dataUsingEncoding:NSUTF8StringEncoding]];
                    [file closeFile];
                } else {
                    NSLog(@"Error opening file %@ to insert VOD header", self.outputStreamPath);
                }
                
                [self.delegate outputReady:self];
                
                return;
            }
        }
    }
    
    [NSTimer scheduledTimerWithTimeInterval:2.0
                                     target:self
                                   selector:@selector(waitForOutputStream)
                                   userInfo:nil
                                    repeats:NO];
}

- (double)duration
{
    return self.inputMedia.length.intValue / 1000.0f;
}

- (void)cleanup
{
    NSFileManager           *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator   *directoryEnum = [fileManager enumeratorAtPath:self.baseFilePath];    
    NSError                 *error = nil;
    NSString                *currentFile = nil;
    BOOL                    success;
    
    while (kOVCCleanTempDir && (currentFile = [directoryEnum nextObject])) {
        success = [fileManager removeItemAtPath:[self.baseFilePath stringByAppendingPathComponent:currentFile]
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
