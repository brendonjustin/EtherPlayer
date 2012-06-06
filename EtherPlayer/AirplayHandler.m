//
//  AirplayHandler.m
//  EtherPlayer
//
//  Created by Brendon Justin on 5/31/12.
//  Copyright (c) 2012 Brendon Justin. All rights reserved.
//

#import "AirplayHandler.h"

#import "OutputVideoCreator.h"

#import <arpa/inet.h>
#import <ifaddrs.h>

const BOOL kAHEnableDebugOutput = NO;

@interface AirplayHandler () <OutputVideoCreatorDelegate>

- (void)startAirplay;
- (void)playRequest;
- (void)infoRequest;
- (void)stopRequest;
- (void)stopPlayback;
- (void)changePlaybackStatus;

@property (strong, nonatomic) OutputVideoCreator    *m_outputVideoCreator;
@property (strong, nonatomic) NSString              *m_currentRequest;
@property (strong, nonatomic) NSURL                 *m_baseUrl;
@property (strong, nonatomic) NSMutableData         *m_responseData;
@property (strong, nonatomic) NSTimer               *m_infoTimer;
@property (nonatomic) BOOL                          m_playing;
@property (nonatomic) double                        m_playbackPosition;

@end

@implementation AirplayHandler

//  public properties
@synthesize delegate;
@synthesize targetService = m_targetService;

//  private properties
@synthesize m_outputVideoCreator;
@synthesize m_currentRequest;
@synthesize m_baseUrl;
@synthesize m_responseData;
@synthesize m_infoTimer;
@synthesize m_playing;
@synthesize m_playbackPosition;

//  temporary directory code thanks to a Stack Overflow post
//  http://stackoverflow.com/questions/374431/how-do-i-get-the-default-temporary-directory-on-mac-os-x
//  ip address retrieval code also thanks to a Stack Overflow post
//  http://stackoverflow.com/questions/7072989/iphone-ipad-how-to-get-my-ip-address-programmatically
- (id)init
{
    if ((self = [super init])) {
        m_playing = YES;
        m_playbackPosition = 0;
        
        m_outputVideoCreator = [[OutputVideoCreator alloc] init];
        m_outputVideoCreator.delegate = self;
    }
    
    return self;
}

//  play the current video via AirPlay
//  only the /reverse handshake is performed in this function,
//  other work is done in connectionDidFinishLoading:
- (void)airplayMediaForPath:(NSString *)mediaPath
{
    NSArray             *sockArray = nil;
    NSData              *sockData = nil;
    char                addressBuffer[100];
    struct sockaddr_in  *sockAddress;
    
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
            
            if (kAHEnableDebugOutput) {
                NSLog(@"Found service at %@", address);
            }
            m_baseUrl = [NSURL URLWithString:address];
        }
    }
    
    [m_outputVideoCreator transcodeMediaForPath:mediaPath];
}

- (void)startAirplay
{
    NSMutableURLRequest *request = nil;
    NSURLConnection     *connection = nil;
    
    //  make a request to /reverse on the target and start the AirPlay process
    request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"/server-info" 
                                                  relativeToURL:m_baseUrl]];
    connection = [NSURLConnection connectionWithRequest:request delegate:self];
    [connection start];
    m_currentRequest = @"/server-info";
}

- (void)playRequest
{
    NSMutableURLRequest     *request = nil;
    NSURLConnection         *nextConnection = nil;
    
    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"/play"
                                                         relativeToURL:m_baseUrl]];
    request.HTTPMethod = @"POST";
    
    [request addValue:m_outputVideoCreator.playRequestDataType forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = m_outputVideoCreator.playRequestData;
    
    nextConnection = [NSURLConnection connectionWithRequest:request delegate:self];
    [nextConnection start];
    m_currentRequest = @"/play";
}

- (void)infoRequest
{
    NSString        *nextRequest = nil;
    NSURLRequest    *request = nil;
    NSURLConnection *nextConnection = nil;
    
    if ([m_currentRequest isEqualToString:@"/playback-info"]) {
        nextRequest = @"/scrub";
    } else {
        nextRequest = @"/playback-info";
    }
    
    request = [NSURLRequest requestWithURL:[NSURL URLWithString:nextRequest
                                                  relativeToURL:m_baseUrl]];
    nextConnection = [NSURLConnection connectionWithRequest:request delegate:self];
    [nextConnection start];
    m_currentRequest = nextRequest;
}

- (void)stopRequest
{
    NSURLRequest    *request = nil;
    NSURLConnection *nextConnection = nil;
    
    request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"/stop"
                                                  relativeToURL:m_baseUrl]];
    nextConnection = [NSURLConnection connectionWithRequest:request delegate:self];
    [nextConnection start];
    m_currentRequest = @"/stop";
}

//  TODO: more in this function?
- (void)stopPlayback
{
    [self stopRequest];
}


- (void)changePlaybackStatus
{
    NSMutableURLRequest *request = nil;
    NSURLConnection     *nextConnection = nil;
    NSString            *rateString = @"/rate?value=0.00000";
    
    if (m_playing) {
        rateString = @"/rate?value=1.00000";
    }
    
    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:rateString
                                                         relativeToURL:m_baseUrl]];
    request.HTTPMethod = @"POST";
    
    nextConnection = [NSURLConnection connectionWithRequest:request delegate:self];
    [nextConnection start];
    m_currentRequest = @"/rate";
}

- (void)togglePlaying:(BOOL)playing
{
    m_playing = playing;
    [self changePlaybackStatus];
    [delegate playStateChanged:m_playing];
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
    
    if (kAHEnableDebugOutput) {
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
        
        m_playing = YES;
        [delegate playStateChanged:m_playing];
        
        m_infoTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                       target:self
                                                     selector:@selector(playbackInfoRequest)
                                                     userInfo:nil
                                                      repeats:YES];
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
        
        //  nothing else to do
    } else if ([m_currentRequest isEqualToString:@"/playback-info"]) {
        //  update our playback status and position after /playback-info
        NSDictionary            *playbackInfo = nil;
        NSString                *errDesc = nil;
        NSPropertyListFormat    format;
        
        playbackInfo = [NSPropertyListSerialization propertyListFromData:m_responseData
                                                        mutabilityOption:NSPropertyListImmutable
                                                                  format:&format
                                                        errorDescription:&errDesc];
        
        m_playbackPosition = [[playbackInfo objectForKey:@"position"] doubleValue];
        m_playing = [[playbackInfo objectForKey:@"rate"] doubleValue] > 0.5f ? YES : NO;
        
        [delegate playStateChanged:m_playing];
        
        //  nothing else to do
    } else if ([m_currentRequest isEqualToString:@"/stop"]) {
        //  no next request
        
        [m_infoTimer invalidate];
    }
}

#pragma mark - 
#pragma mark OutputVideoCreatorDelegate functions

- (void)outputReady:(id)sender
{
    [self startAirplay];
}

@end
