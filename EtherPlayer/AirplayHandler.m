//
//  AirplayHandler.m
//  EtherPlayer
//
//  Created by Brendon Justin on 5/31/12.
//  Copyright (c) 2012 Brendon Justin. All rights reserved.
//

#import "AirplayHandler.h"

#import "VideoManager.h"

#import <arpa/inet.h>
#import <ifaddrs.h>

const BOOL kAHEnableDebugOutput = YES;
const BOOL kAHAssumeReverseTimesOut = NO;
const NSUInteger kVideo = 0,
kPhoto = 1,
kVideoFairPlay = 2,
kVideoVolumeControl = 3,
kVideoHTTPLiveStreams = 4,
kSlideshow = 5,
kScreen = 7,
kScreenRotate = 8,
kAudio = 9,
kAudioRedundant = 11,
kFPSAPv2pt5_AES_GCM = 12,
kPhotoCaching = 13;

@interface AirplayHandler ()

- (void)setCommonHeadersForRequest:(NSMutableURLRequest *)request;
- (void)reverseRequest;
- (void)playRequest;
- (void)infoRequest;
- (void)stopRequest;
- (void)changePlaybackStatus;
- (void)setStopped;

@property (strong, nonatomic) NSURL                 *m_baseUrl;
@property (strong, nonatomic) NSString              *m_currentRequest;
@property (strong, nonatomic) NSMutableData         *m_responseData;
@property (strong, nonatomic) NSTimer               *m_infoTimer;
@property (strong, nonatomic) NSNetService          *m_targetService;
@property (strong, nonatomic) NSDictionary          *m_serverInfo;
@property (nonatomic) BOOL                          m_airplaying;
@property (nonatomic) BOOL                          m_paused;
@property (nonatomic) double                        m_playbackPosition;
@property (nonatomic) uint8_t                       m_serverCapabilities;

@end

@implementation AirplayHandler

//  public properties
@synthesize delegate;
@synthesize videoManager = m_videoManager;

//  private properties
@synthesize m_currentRequest;
@synthesize m_baseUrl;
@synthesize m_responseData;
@synthesize m_infoTimer;
@synthesize m_targetService;
@synthesize m_airplaying;
@synthesize m_paused;
@synthesize m_playbackPosition;
@synthesize m_serverCapabilities;
@synthesize m_serverInfo;

//  temporary directory code thanks to a Stack Overflow post
//  http://stackoverflow.com/questions/374431/how-do-i-get-the-default-temporary-directory-on-mac-os-x
//  ip address retrieval code also thanks to a Stack Overflow post
//  http://stackoverflow.com/questions/7072989/iphone-ipad-how-to-get-my-ip-address-programmatically
- (id)init
{
    if ((self = [super init])) {
        m_airplaying = NO;
        m_paused = YES;
        m_playbackPosition = 0;
    }
    
    return self;
}

- (void)setTargetService:(NSNetService *)targetService
{
    NSMutableURLRequest *request = nil;
    NSURLConnection     *connection = nil;
    NSArray             *sockArray = nil;
    NSData              *sockData = nil;
    char                addressBuffer[100];
    struct sockaddr_in  *sockAddress;
    
    m_targetService = targetService;
    
    if (m_targetService == nil) {
        return;
    }
    
    sockArray = m_targetService.addresses;
    
    if ([sockArray count] < 1) {
        m_targetService = nil;
        return;
    }
    
    sockData = [sockArray objectAtIndex:0];
    
    sockAddress = (struct sockaddr_in*) [sockData bytes];
    if (sockAddress == NULL) {
        if (kAHEnableDebugOutput) {
            NSLog(@"No AirPlay targets found, taking no action.");
        }
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
            
            if (kAHEnableDebugOutput) {
                NSLog(@"Found service at %@", address);
            }
            m_baseUrl = [NSURL URLWithString:address];
        }
    }
    
    //  make a request to /server-info on the target to get some info before
    //  we do anything else
    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"/server-info"
                                                         relativeToURL:m_baseUrl]];
    [self setCommonHeadersForRequest:request];
    connection = [NSURLConnection connectionWithRequest:request delegate:self];
    [connection start];
    m_currentRequest = @"/server-info";
}

- (void)togglePaused
{
    if (m_airplaying) {
        m_paused = !m_paused;
        [self changePlaybackStatus];
        [delegate isPaused:m_paused];
    }
}

- (void)startAirplay
{
    //  we must have a target service to AirPlay to
    if (m_targetService == nil) {
        return;
    }
    
    [self reverseRequest];
}

- (void)setCommonHeadersForRequest:(NSMutableURLRequest *)request
{
    [request addValue:@"MediaControl/1.0" forHTTPHeaderField:@"User-Agent"];
    [request addValue:@"09080524-2e51-457e-9bf5-bef9847f34ff" forHTTPHeaderField:@"X-Apple-Session-ID"];
}

- (void)reverseRequest
{
    NSMutableURLRequest     *request = nil;
    NSURLConnection         *connection = nil;
    
    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"/reverse"
                                                         relativeToURL:m_baseUrl]];
    [request setHTTPMethod:@"POST"];
    [request addValue:@"PTTH/1.0" forHTTPHeaderField:@"Upgrade"];
    [request addValue:@"Upgrade" forHTTPHeaderField:@"Connection"];
    [request addValue:@"event" forHTTPHeaderField:@"X-Apple-Purpose"];
    [request addValue:@"0" forHTTPHeaderField:@"Content-Length"];
    [self setCommonHeadersForRequest:request];
    
    connection = [NSURLConnection connectionWithRequest:request delegate:self];
    [connection start];
    m_currentRequest = @"/reverse";
    
    //  /reverse always times out in my airplay server, so just move on to /play
    if (kAHAssumeReverseTimesOut) {
        [self playRequest];
    }
}

- (void)playRequest
{
    NSMutableURLRequest     *request = nil;
    NSURLConnection         *nextConnection = nil;

    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"/play"
                                                         relativeToURL:m_baseUrl]];
    request.HTTPMethod = @"POST";

    [request addValue:m_videoManager.playRequestDataType forHTTPHeaderField:@"Content-Type"];
    [self setCommonHeadersForRequest:request];
    request.HTTPBody = m_videoManager.playRequestData;

    nextConnection = [NSURLConnection connectionWithRequest:request delegate:self];
    [nextConnection start];
    m_currentRequest = @"/play";
    m_airplaying = YES;
}

//  alternates /scrub and /playback-info
- (void)infoRequest
{
    NSString                *nextRequest = nil;
    NSMutableURLRequest     *request = nil;
    NSURLConnection         *nextConnection = nil;

    if ([m_currentRequest isEqualToString:@"/playback-info"]) {
        nextRequest = @"/scrub";
    } else {
        nextRequest = @"/playback-info";
    }

    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:nextRequest
                                                         relativeToURL:m_baseUrl]];
    
    [self setCommonHeadersForRequest:request];
    nextConnection = [NSURLConnection connectionWithRequest:request delegate:self];
    [nextConnection start];
    m_currentRequest = nextRequest;
}

- (void)stopRequest
{
    NSMutableURLRequest *request = nil;
    NSURLConnection     *nextConnection = nil;

    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"/stop"
                                                         relativeToURL:m_baseUrl]];
    
    [self setCommonHeadersForRequest:request];
    nextConnection = [NSURLConnection connectionWithRequest:request delegate:self];
    [nextConnection start];
    m_currentRequest = @"/stop";
    m_airplaying = NO;
    [delegate isPaused:NO];
}

- (void)stopPlayback
{
    if (m_airplaying) {
        [self stopRequest];
    }
}

- (void)changePlaybackStatus
{
    NSMutableURLRequest *request = nil;
    NSURLConnection     *nextConnection = nil;
    NSString            *rateString = @"/rate?value=1.00000";
    
    if (m_paused) {
        rateString = @"/rate?value=0.00000";
    }
    
    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:rateString
                                                         relativeToURL:m_baseUrl]];
    [self setCommonHeadersForRequest:request];
    request.HTTPMethod = @"POST";
    
    nextConnection = [NSURLConnection connectionWithRequest:request delegate:self];
    [nextConnection start];
    m_currentRequest = @"/rate";
}

- (void)setStopped
{
    m_paused = NO;
    m_airplaying = NO;
    [m_infoTimer invalidate];
    
    m_playbackPosition = 0;
    [delegate isPaused:m_paused];
    [delegate positionUpdated:m_playbackPosition];
    [delegate durationUpdated:0];
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
    if (kAHEnableDebugOutput) {
        if ([response isKindOfClass: [NSHTTPURLResponse class]])
            NSLog(@"Response code: %ld %@; request URL: %@",
                  [(NSHTTPURLResponse *)response statusCode],
                  [NSHTTPURLResponse localizedStringForStatusCode:[(NSHTTPURLResponse *)response statusCode]],
                  [m_baseUrl URLByAppendingPathComponent:m_currentRequest]);
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
    return;
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

    [self setStopped];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    NSString            *response = [[NSString alloc] initWithData:m_responseData
                                                          encoding:NSASCIIStringEncoding];
    
    if (kAHEnableDebugOutput) {
        NSLog(@"current request: %@, response string: %@", m_currentRequest, response);
    }
    
    if ([m_currentRequest isEqualToString:@"/server-info"]) {
        NSString                *errDesc = nil;
        NSPropertyListFormat    format;
        BOOL                    useHLS = NO;
        
        m_serverInfo = [NSPropertyListSerialization propertyListFromData:m_responseData
                                                        mutabilityOption:NSPropertyListImmutable
                                                                  format:&format
                                                        errorDescription:&errDesc];
        
        useHLS = ([[m_serverInfo objectForKey:@"features"] integerValue] & kVideoHTTPLiveStreams) != 0;
        m_videoManager.useHttpLiveStreaming = useHLS;
        
        m_serverCapabilities = [[m_serverInfo objectForKey:@"features"] integerValue];
    } else if ([m_currentRequest isEqualToString:@"/reverse"]) {
        //  give the signal to play the file after /reverse
        //  the next request is /play
        
        [self playRequest];
    } else if ([m_currentRequest isEqualToString:@"/play"]) {
        //  check if playing successful after /play
        //  the next request is /playback-info
        
        m_paused = NO;
        [delegate isPaused:m_paused];
        [delegate durationUpdated:m_videoManager.duration];
        
        m_infoTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                       target:self
                                                     selector:@selector(infoRequest)
                                                     userInfo:nil
                                                      repeats:YES];
    } else if ([m_currentRequest isEqualToString:@"/rate"]) {
        //  nothing to do for /rate
        //  no set next request
    } else if ([m_currentRequest isEqualToString:@"/scrub"]) {
        //  update our position in the file after /scrub
        NSRange     cachedDurationRange = [response rangeOfString:@"position: "];
        NSUInteger  cachedDurationEnd;
        
        if (cachedDurationRange.location != NSNotFound) {
            cachedDurationEnd = cachedDurationRange.location + cachedDurationRange.length;
            m_playbackPosition = [[response substringFromIndex:cachedDurationEnd] doubleValue];
            [delegate positionUpdated:m_playbackPosition];
        }
        
        //  nothing else to do
    } else if ([m_currentRequest isEqualToString:@"/playback-info"]) {
        //  update our playback status and position after /playback-info
        NSDictionary            *playbackInfo = nil;
        NSString                *errDesc = nil;
        NSPropertyListFormat    format;
        
        if (!m_airplaying) {
            return;
        }
        
        playbackInfo = [NSPropertyListSerialization propertyListFromData:m_responseData
                                                        mutabilityOption:NSPropertyListImmutable
                                                                  format:&format
                                                        errorDescription:&errDesc];
        
        m_playbackPosition = [[playbackInfo objectForKey:@"position"] doubleValue];
        m_paused = [[playbackInfo objectForKey:@"rate"] doubleValue] < 0.5f ? YES : NO;
        
        [delegate isPaused:m_paused];
        [delegate positionUpdated:m_playbackPosition];
        
        //  nothing else to do
    } else if ([m_currentRequest isEqualToString:@"/stop"]) {
        //  no next request
        
        [self setStopped];
    }
}

@end
