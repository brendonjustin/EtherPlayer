//
//  AirplayHandler.m
//  EtherPlayer
//
//  Created by Brendon Justin on 5/31/12.
//  Copyright (c) 2012 Brendon Justin. All rights reserved.
//

#import "AirplayHandler.h"

#import "HTTPServer.h"

#import <VLCKit/VLCMedia.h>
#import <VLCKit/VLCStreamOutput.h>
#import <VLCKit/VLCStreamSession.h>

#import <arpa/inet.h>
#import <ifaddrs.h>

const BOOL ENABLE_DEBUG_OUTPUT = NO;

@interface AirplayHandler ()

- (void)transcodeInput;
- (void)airplayWhenReady;
- (void)playRequest;
- (void)scrubRequest;
- (void)playbackInfoRequest;
- (void)stop;
- (void)changePlaybackStatus;

@property (strong, nonatomic) VLCMedia          *m_inputVideo;
@property (strong, nonatomic) VLCStreamOutput   *m_output;
@property (strong, nonatomic) VLCStreamSession  *m_session;
@property (strong, nonatomic) NSString          *m_baseOutputPath;
@property (strong, nonatomic) NSString          *m_outputFilename;
@property (strong, nonatomic) NSString          *m_currentRequest;
@property (strong, nonatomic) NSString          *m_baseServerPath;
@property (strong, nonatomic) NSString          *m_httpAddress;
@property (strong, nonatomic) NSURL             *m_baseUrl;
@property (strong, nonatomic) NSMutableData     *m_responseData;
@property (strong, nonatomic) HTTPServer        *m_httpServer;
@property (nonatomic) BOOL                      m_playing;
@property (nonatomic) double                    m_playbackPosition;
@property (nonatomic) NSUInteger                m_sessionRandom;

@end

@implementation AirplayHandler

//  public properties
@synthesize inputFilePath = m_inputFilePath;
@synthesize targetService = m_targetService;

//  private properties
@synthesize m_inputVideo;
@synthesize m_output;
@synthesize m_session;
@synthesize m_baseOutputPath;
@synthesize m_outputFilename;
@synthesize m_currentRequest;
@synthesize m_baseServerPath;
@synthesize m_httpAddress;
@synthesize m_baseUrl;
@synthesize m_responseData;
@synthesize m_httpServer;
@synthesize m_playing;
@synthesize m_playbackPosition;
@synthesize m_sessionRandom;

//  temporary directory code thanks to a Stack Overflow post
//  http://stackoverflow.com/questions/374431/how-do-i-get-the-default-temporary-directory-on-mac-os-x
//  ip address retrieval code also thanks to a Stack Overflow post
//  http://stackoverflow.com/questions/7072989/iphone-ipad-how-to-get-my-ip-address-programmatically
- (id)init
{
    if ((self = [super init])) {
        NSString        *tempDir = nil;
        NSString        *template = nil;
        NSMutableData   *bufferData = nil;
        NSError         *error = nil;
        char            *buffer;
        char            *result;
        struct ifaddrs  *ifap;
        struct ifaddrs  *ifap0;
        
        m_httpAddress = nil;
        m_session = nil;
        m_playing = YES;
        m_playbackPosition = 0;
        
        tempDir = NSTemporaryDirectory();
        if (tempDir == nil)
            tempDir = @"/tmp";
        
        template = [tempDir stringByAppendingPathComponent:@"temp.XXXXXX"];
        if (ENABLE_DEBUG_OUTPUT) {
            NSLog(@"Template: %@", template);
        }
        const char *fsTemplate = [template fileSystemRepresentation];
        bufferData = [NSMutableData dataWithBytes:fsTemplate
                                           length:strlen(fsTemplate)+1];
        buffer = [bufferData mutableBytes];
        if (ENABLE_DEBUG_OUTPUT) {
            NSLog(@"FS Template: %s", buffer);
        }
        result = mkdtemp(buffer);
        if (ENABLE_DEBUG_OUTPUT) {
            NSLog(@"mkdtemp result: %s", result);
        }
        m_baseOutputPath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:result
                                                                                       length:strlen(result)];
        m_baseOutputPath = [m_baseOutputPath stringByAppendingString:@"/"];
        
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
            m_httpAddress = [@"http://" stringByAppendingFormat:@"%@:%u/", m_httpAddress, m_httpServer.port];
        }
    }
    
    return self;
}

//  play the current video via AirPlay
//  only the /reverse handshake is performed in this function,
//  other work is done in connectionDidFinishLoading:
- (void)airplay
{
    NSArray             *sockArray = nil;
    NSData              *sockData = nil;
    char                addressBuffer[100];
    struct sockaddr_in  *sockAddress;
    
    [self stop];
    
    sockArray = m_targetService.addresses;
    sockData = [sockArray objectAtIndex:0];
    
    sockAddress = (struct sockaddr_in*) [sockData bytes];
    if (sockAddress == NULL) {
        return;
    }
    
    int sockFamily = sockAddress->sin_family;
    if (sockFamily == AF_INET || sockFamily == AF_INET6) {
        const char* addressStr = inet_ntop(sockFamily,
                                           &(sockAddress->sin_addr), addressBuffer,
                                           sizeof(addressBuffer));
        int port = ntohs(sockAddress->sin_port);
        if (addressStr && port) {
            NSString *address = [NSString stringWithFormat:@"http://%s:%d", addressStr, port];
            
            if (ENABLE_DEBUG_OUTPUT) {
                NSLog(@"Found service at %@", address);
            }
            m_baseUrl = [NSURL URLWithString:address];
        }
    }
    
    [self transcodeInput];
    
    [self airplayWhenReady];
}

//  TODO: intelligently choose bitrates and channels
- (void)transcodeInput
{
    NSString    *videoCodec = @"h264";
    NSString    *audioCodec = @"mp4a";
    NSString    *videoBitrate = @"1024";
    NSString    *audioBitrate = @"128";
    NSString    *audioChannels = @"2";
    NSString    *width = @"640";
    NSString    *filetype = @"mp4";
    NSString    *outputPath = nil;
    
    m_sessionRandom = arc4random();
    
    m_inputVideo = [VLCMedia mediaWithPath:m_inputFilePath];
    
    m_outputFilename = [NSString stringWithFormat:@"%u.%@", m_sessionRandom, filetype];
    outputPath = [m_baseOutputPath stringByAppendingFormat:@"%u.%@", m_sessionRandom, filetype];
    
    m_output = [VLCStreamOutput streamOutputWithOptionDictionary:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                  [NSDictionary dictionaryWithObjectsAndKeys:
                                                                   videoCodec, @"videoCodec",
                                                                   videoBitrate, @"videoBitrate",
                                                                   audioCodec, @"audioCodec",
                                                                   audioBitrate, @"audioBitrate",
                                                                   audioChannels, @"channels",
                                                                   width, @"width",
                                                                   @"Yes", @"audio-sync",
                                                                   nil
                                                                   ], @"transcodingOptions",
                                                                  [NSDictionary dictionaryWithObjectsAndKeys:
                                                                   filetype, @"muxer",
                                                                   @"file", @"access",
                                                                   outputPath, @"destination",
                                                                   nil
                                                                   ], @"outputOptions",
                                                                  nil
                                                                  ]];
    //  the iPod settings for testing
//    m_output = [VLCStreamOutput ipodStreamOutputWithFilePath:outputPath];
    
    m_session = [VLCStreamSession streamSession];
    m_session.media = m_inputVideo;
    m_session.streamOutput = m_output;
    
    [m_session startStreaming];
}

- (void)airplayWhenReady
{
    NSMutableURLRequest *request = nil;
    NSURLConnection     *connection = nil;
    
    if (!m_session.isComplete) {
        [NSTimer scheduledTimerWithTimeInterval:1
                                         target:self
                                       selector:@selector(airplayWhenReady)
                                       userInfo:nil
                                        repeats:NO];
    } else {
        //  make a request to /reverse on the target and start the AirPlay process
        request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"/server-info" relativeToURL:m_baseUrl]];
        connection = [NSURLConnection connectionWithRequest:request delegate:self];
        [connection start];
        m_currentRequest = @"/server-info";
    }
}

- (void)playRequest
{
    NSMutableURLRequest     *request = nil;
    NSURLConnection         *nextConnection = nil;
    NSDictionary            *dict = nil;
    NSData                  *data = nil;
    NSError                 *err = nil;
    NSString                *filePath = nil;
    NSPropertyListFormat    format;
    
    filePath = [m_httpAddress stringByAppendingString:m_outputFilename];
    
    dict = [NSDictionary dictionaryWithObjectsAndKeys:filePath, @"Content-Location",
            [NSString stringWithFormat:@"%f", m_playbackPosition], @"Start-Position", nil];
    [dict writeToFile:[m_baseOutputPath stringByAppendingFormat:@"%u.plist", m_sessionRandom] atomically:YES];
    data = [NSData dataWithContentsOfFile:[m_baseOutputPath stringByAppendingFormat:@"%u.plist", m_sessionRandom]];
    
    [NSPropertyListSerialization propertyListWithData:data
                                              options:NSPropertyListImmutable
                                               format:&format
                                                error:&err];
    
    if (err != nil) {
        NSLog(@"Error preparing PLIST for /play request, %ld", err.code);
    }
    
    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"/play"
                                                         relativeToURL:m_baseUrl]];
    request.HTTPMethod = @"POST";
    
    if (format == NSPropertyListBinaryFormat_v1_0) {
        [request addValue:@"application/x-apple-binary-plist" forHTTPHeaderField:@"Content-Type"];
    } else if (format == NSPropertyListXMLFormat_v1_0) {
        [request addValue:@"text/x-apple-plist+xml" forHTTPHeaderField:@"Content-Type"];
    } else {
        //  format == NSPropertyListOpenStepFormat
        //  should never get here, Apple doesn't write out PLISTs in this format any more
    }
    
    request.HTTPBody = data;
    
    nextConnection = [NSURLConnection connectionWithRequest:request delegate:self];
    [nextConnection start];
    m_currentRequest = @"/play";
}

- (void)scrubRequest
{
    NSURLRequest    *request = nil;
    NSURLConnection *nextConnection = nil;
    
    request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"/scrub" relativeToURL:m_baseUrl]];
    nextConnection = [NSURLConnection connectionWithRequest:request delegate:self];
    [nextConnection start];
    m_currentRequest = @"/scrub";
}

- (void)playbackInfoRequest
{
    NSURLRequest    *request = nil;
    NSURLConnection *nextConnection = nil;
    
    request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"/playback-info" relativeToURL:m_baseUrl]];
    nextConnection = [NSURLConnection connectionWithRequest:request delegate:self];
    [nextConnection start];
    m_currentRequest = @"/playback-info";
}

//  TODO: consider doing more in this function
- (void)stop
{
    //  if m_session exists, it must be stopped
    //  if not, this is still OK since m_session was initialized to nil
    [m_session stopStreaming];
}

- (void)changePlaybackStatus
{
    NSMutableURLRequest *request = nil;
    NSURLConnection     *nextConnection = nil;
    NSString *rateString = @"/rate?value=0.00000";
    
    if (m_playing) {
        rateString = @"/rate?value=1.00000";
    }
    
    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:rateString relativeToURL:m_baseUrl]];
    request.HTTPMethod = @"POST";
    
    nextConnection = [NSURLConnection connectionWithRequest:request delegate:self];
    [nextConnection start];
    m_currentRequest = @"/rate";
}

#pragma mark -
#pragma mark NSURLConnectionDelegate methods

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection
                  willCacheResponse:(NSCachedURLResponse *)cachedResponse
{
    return cachedResponse;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    if (ENABLE_DEBUG_OUTPUT) {
        if ([response isKindOfClass: [NSHTTPURLResponse class]])
            NSLog(@"Response type: %ld, %@", [(NSHTTPURLResponse *)response statusCode],
                  [NSHTTPURLResponse localizedStringForStatusCode:[(NSHTTPURLResponse *)response statusCode]]);
    }
    
    m_responseData = [[NSMutableData alloc] init];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [m_responseData appendData:data];
}

- (void)connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten
 totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
{
    
}

- (NSURLRequest *)connection:(NSURLConnection *)connection 
             willSendRequest:(NSURLRequest *)request 
            redirectResponse:(NSURLResponse *)response
{
    return  request;
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    NSLog(@"Connection failed with error code %ld", error.code);
}

//  TDOO: finish our responses to successful requests for 
//  /play, /scrub, /playback-info
- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    NSMutableURLRequest *request = nil;
    NSURLConnection     *nextConnection = nil;
    NSString            *response = [[NSString alloc] initWithData:m_responseData
                                                          encoding:NSASCIIStringEncoding];
    
    if (ENABLE_DEBUG_OUTPUT) {
        NSLog(@"current request: %@, response string: %@", m_currentRequest, response);
    }
    
    
    if ([m_currentRequest isEqualToString:@"/server-info"]) {
        //  /reverse is a handshake before starting
        //  the next request is /reverse
        BOOL workaroundMissingResponse = YES;
        request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"/reverse"
                                                             relativeToURL:m_baseUrl]];
        [request setHTTPMethod:@"POST"];
        [request addValue:@"PTTH/1.0" forHTTPHeaderField:@"Upgrade"];
        [request addValue:@"event" forHTTPHeaderField:@"X-Apple-Purpose"];
        
        nextConnection = [NSURLConnection connectionWithRequest:request delegate:self];
        [nextConnection start];
        m_currentRequest = @"/reverse";
        
        //  /reverse always seems to time out, so just move on to /play
        if (workaroundMissingResponse) {
            [self playRequest];
        }
    } else if ([m_currentRequest isEqualToString:@"/reverse"]) {
        //  give the signal to play the file after /reverse
        //  the next request is /play
        
        [self playRequest];
    } else if ([m_currentRequest isEqualToString:@"/play"]) {
        //  check if playing successful after /play
        //  the next request is /playback-info
        
        [self playbackInfoRequest];
    } else if ([m_currentRequest isEqualToString:@"/rate"]) {
        //  nothing to do for /rate
        //  no set next request
    } else if ([m_currentRequest isEqualToString:@"/scrub"]) {
        //  update our position in the file after /scrub
        NSRange     durationRange = [response rangeOfString:@"position: "];
        NSUInteger  durationEnd;
        
        if (durationRange.location != NSNotFound) {
            durationEnd = durationRange.location + durationRange.length;
            m_playbackPosition = [[response substringFromIndex:durationEnd] doubleValue];
        }
        
        //  the next request is /playback-info
        //  call it after a short delay to keep the polling rate reasonable
        [NSTimer scheduledTimerWithTimeInterval:0.5
                                         target:self
                                       selector:@selector(playbackInfoRequest)
                                       userInfo:nil
                                        repeats:NO];
    } else if ([m_currentRequest isEqualToString:@"/playback-info"]) {
        //  update our playback status and position after /playback-info
        //  TODO: update our playing status based on m_playing
        NSDictionary            *playbackInfo = nil;
        NSString                *errDesc = nil;
        NSPropertyListFormat    format;
        
        playbackInfo = [NSPropertyListSerialization propertyListFromData:m_responseData
                                                        mutabilityOption:NSPropertyListImmutable
                                                                  format:&format
                                                        errorDescription:&errDesc];
        
        m_playbackPosition = [[playbackInfo objectForKey:@"position"] doubleValue];
        m_playing = [[playbackInfo objectForKey:@"rate"] doubleValue] > 0.5f ? YES : NO;
        
        //  the next request is /scrub
        //  call it after a short delay to keep the polling rate reasonable
        [NSTimer scheduledTimerWithTimeInterval:0.5
                                         target:self
                                       selector:@selector(scrubRequest)
                                       userInfo:nil
                                        repeats:NO];
    } else if ([m_currentRequest isEqualToString:@"/stop"]) {
        //  no next request
    }
}

@end
