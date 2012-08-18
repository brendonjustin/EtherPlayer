//
//  AirplayHandler.m
//  EtherPlayer
//
//  Created by Brendon Justin on 5/31/12.
//  Copyright (c) 2012 Brendon Justin. All rights reserved.
//

#import "AirplayHandler.h"

#import "VideoManager.h"

#import "GCDAsyncSocket.h"

#import <CFNetwork/CFHTTPStream.h>

#import <arpa/inet.h>
#import <ifaddrs.h>

const BOOL kAHEnableDebugOutput = YES;
const BOOL kAHAssumeReverseTimesOut = YES;
const NSUInteger    kAHVideo = 0,
                    kAHPhoto = 1,
                    kAHVideoFairPlay = 2,
                    kAHVideoVolumeControl = 3,
                    kAHVideoHTTPLiveStreams = 4,
                    kAHSlideshow = 5,
                    kAHScreen = 7,
                    kAHScreenRotate = 8,
                    kAHAudio = 9,
                    kAHAudioRedundant = 11,
                    kAHFPSAPv2pt5_AES_GCM = 12,
                    kAHPhotoCaching = 13;
const NSUInteger    kAHRequestTagReverse = 1,
                    kAHRequestTagPlay = 2;
const NSUInteger    kAHPropertyRequestPlaybackAccess = 1,
                    kAHPropertyRequestPlaybackError = 2;

@interface AirplayHandler () <GCDAsyncSocketDelegate>

- (void)setCommonHeadersForRequest:(NSMutableURLRequest *)request;
- (void)reverseRequest;
- (void)playRequest;
- (void)infoRequest;
- (void)getPropertyRequest:(NSUInteger)property;
- (void)stopRequest;
- (void)changePlaybackStatus;
- (void)stoppedWithError:(NSError *)error;

@property (strong, nonatomic) NSURL                 *m_baseUrl;
@property (strong, nonatomic) NSString              *m_sessionID;
@property (strong, nonatomic) NSString              *m_prevInfoRequest;
@property (strong, nonatomic) NSMutableData         *m_responseData;
@property (strong, nonatomic) NSMutableData         *m_data;
@property (strong, nonatomic) NSTimer               *m_infoTimer;
@property (strong, nonatomic) NSNetService          *m_targetService;
@property (strong, nonatomic) NSDictionary          *m_serverInfo;
@property (strong, nonatomic) GCDAsyncSocket        *m_reverseSocket;
@property (strong, nonatomic) GCDAsyncSocket        *m_mainSocket;
@property (strong, nonatomic) NSOperationQueue      *m_operationQueue;
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
@synthesize m_baseUrl;
@synthesize m_sessionID;
@synthesize m_prevInfoRequest;
@synthesize m_responseData;
@synthesize m_data;
@synthesize m_infoTimer;
@synthesize m_targetService;
@synthesize m_reverseSocket;
@synthesize m_mainSocket;
@synthesize m_operationQueue;
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
        m_prevInfoRequest = @"/scrub";
        m_operationQueue = [NSOperationQueue mainQueue];
        m_operationQueue.name = @"Connection Queue";
        m_airplaying = NO;
        m_paused = YES;
        m_playbackPosition = 0;
    }
    
    return self;
}

- (void)setTargetService:(NSNetService *)targetService
{
    NSMutableURLRequest *request = nil;
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
                                           &(sockAddress->sin_addr),
                                           addressBuffer,
                                           sizeof(addressBuffer));
        int port = ntohs(sockAddress->sin_port);
        if (addressStr && port) {
            NSString *address = [NSString stringWithFormat:@"http://%s:%d",
                addressStr, port];
            
            if (kAHEnableDebugOutput) {
                NSLog(@"Found service at %@", address);
            }
            m_baseUrl = [NSURL URLWithString:address];
        }
    }
    
    m_sessionID = @"09080524-2e51-457e-9bf5-bef9847f34ff";
    
    //  make a request to /server-info on the target to get some info before
    //  we do anything else
    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"/server-info"
                                                         relativeToURL:m_baseUrl]];
    [self setCommonHeadersForRequest:request];
    [NSURLConnection sendAsynchronousRequest:request
                                       queue:m_operationQueue
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                               NSString                *errDesc = nil;
                               NSPropertyListFormat    format;
                               BOOL                    useHLS = NO;
                               
                               if (error != nil) {
                                   NSLog(@"Error getting /server-info");
                                   return;
                               }
                               
                               m_serverInfo = [NSPropertyListSerialization propertyListFromData:data
                                                                               mutabilityOption:NSPropertyListImmutable
                                                                                         format:&format
                                                                               errorDescription:&errDesc];
                               
                               if (m_serverInfo != nil) {
                                   useHLS = ([[m_serverInfo objectForKey:@"features"] integerValue]
                                             & kAHVideoHTTPLiveStreams) != 0;
//                                   useHLS = NO;
                                   m_videoManager.useHttpLiveStreaming = useHLS;
                                   
                                   m_serverCapabilities = [[m_serverInfo objectForKey:@"features"] integerValue];
                               } else {
                                   NSLog(@"Error parsing /server-info response: %@", errDesc);
                               }
                           }];
}

- (void)togglePaused
{
    if (m_airplaying) {
        m_paused = !m_paused;
        [self changePlaybackStatus];
        [delegate setPaused:m_paused];
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
    [request addValue:m_sessionID forHTTPHeaderField:@"X-Apple-Session-ID"];
}

- (void)reverseRequest
{
    NSData              *data = nil;
    NSError             *error = nil;
    CFURLRef            myURL;
    CFStringRef         bodyString;
    CFStringRef         requestMethod;
    CFHTTPMessageRef    myRequest;
    CFDataRef           bodyDataExt;
    CFDataRef           mySerializedRequest;
    
    NSLog(@"/reverse");
    
    bodyString = CFSTR("");
    requestMethod = CFSTR("POST");
    myURL = (__bridge CFURLRef)[m_baseUrl URLByAppendingPathComponent:@"reverse"];
    myRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, requestMethod,
                                           myURL, kCFHTTPVersion1_1);
    bodyDataExt = CFStringCreateExternalRepresentation(kCFAllocatorDefault,
                                                       bodyString,
                                                       kCFStringEncodingUTF8,
                                                       0);
    CFHTTPMessageSetBody(myRequest, bodyDataExt);
    CFHTTPMessageSetHeaderFieldValue(myRequest, CFSTR("Upgrade"),
                                     CFSTR("PTTH/1.0"));
    CFHTTPMessageSetHeaderFieldValue(myRequest, CFSTR("Connection"),
                                     CFSTR("Upgrade"));
    CFHTTPMessageSetHeaderFieldValue(myRequest, CFSTR("X-Apple-Purpose"),
                                     CFSTR("event"));
    CFHTTPMessageSetHeaderFieldValue(myRequest, CFSTR("User-Agent"),
                                     CFSTR("MediaControl/1.0"));
    CFHTTPMessageSetHeaderFieldValue(myRequest, CFSTR("X-Apple-Session-ID"),
                                     (__bridge CFStringRef)m_sessionID);
    mySerializedRequest = CFHTTPMessageCopySerializedMessage(myRequest);
    data = (__bridge NSData *)mySerializedRequest;
    
    NSLog(@"Request:\r\n%@", [[NSString alloc] initWithData:data
                                                   encoding:NSUTF8StringEncoding]);
    m_reverseSocket = [[GCDAsyncSocket alloc] initWithDelegate:self
                                                 delegateQueue:dispatch_get_main_queue()];
    [m_reverseSocket connectToAddress:[[m_targetService addresses] objectAtIndex:0]
                                error:&error];
    
    if (error != nil) {
        NSLog(@"Error connecting socket for /reverse: %@", error);
    } else {
        [m_reverseSocket writeData:data
                       withTimeout:1.0f
                               tag:kAHRequestTagReverse];
        [m_reverseSocket readDataToData:[@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]
                            withTimeout:2.0f
                                    tag:kAHRequestTagReverse];
    }
    
    if (kAHAssumeReverseTimesOut) {
        [self playRequest];
    }
}

- (void)playRequest
{
    NSDictionary        *plist = nil;
    NSString            *httpFilePath = nil;
    NSString            *errDesc = nil;
    NSString            *appName = nil;
    NSError             *error = nil;
    NSData              *outData = nil;
    NSString            *dataLength = nil;
    CFURLRef            myURL;
    CFStringRef         bodyString;
    CFStringRef         requestMethod;
    CFHTTPMessageRef    myRequest;
    CFDataRef           mySerializedRequest;
    
    NSLog(@"/play");
    
    httpFilePath = m_videoManager.httpFilePath;
    appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];

    plist = @{ @"Content-Location" : httpFilePath,
               @"Start-Position" : @0.0f };
    
    outData = [NSPropertyListSerialization dataFromPropertyList:plist
                                                         format:NSPropertyListBinaryFormat_v1_0
                                               errorDescription:&errDesc];
    
    if (outData == nil && errDesc != nil) {
        NSLog(@"Error creating /play info plist: %@", errDesc);
        return;
    }

    dataLength = [NSString stringWithFormat:@"%lu", [outData length]];

    bodyString = CFSTR("");
    requestMethod = CFSTR("POST");
    myURL = (__bridge CFURLRef)[m_baseUrl URLByAppendingPathComponent:@"play"];
    myRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, requestMethod,
                                           myURL, kCFHTTPVersion1_1);

    CFHTTPMessageSetHeaderFieldValue(myRequest, CFSTR("User-Agent"),
                                     (__bridge CFStringRef)appName);
    CFHTTPMessageSetHeaderFieldValue(myRequest, CFSTR("Content-Length"),
                                     (__bridge CFStringRef)dataLength);
    CFHTTPMessageSetHeaderFieldValue(myRequest, CFSTR("Content-Type"),
                                     CFSTR("application/x-apple-binary-plist"));
    CFHTTPMessageSetHeaderFieldValue(myRequest, CFSTR("X-Apple-Session-ID"),
                                     (__bridge CFStringRef)m_sessionID);
    mySerializedRequest = CFHTTPMessageCopySerializedMessage(myRequest);
    m_data = [(__bridge NSData *)mySerializedRequest mutableCopy];
    [m_data appendData:outData];

    m_mainSocket = [[GCDAsyncSocket alloc] initWithDelegate:self
                                              delegateQueue:dispatch_get_main_queue()];
    [m_mainSocket connectToAddress:[[m_targetService addresses] objectAtIndex:0]
                             error:&error];
    
    if (m_mainSocket != nil) {
        [m_mainSocket writeData:m_data
                    withTimeout:1.0f
                            tag:kAHRequestTagPlay];
        [m_mainSocket readDataToData:[@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]
                         withTimeout:2.0f
                                 tag:kAHRequestTagPlay];
    } else {
        NSLog(@"Error connecting socket for /play: %@", error);
    }
}

//  alternates /scrub and /playback-info
- (void)infoRequest
{
    NSString                *nextRequest = @"/playback-info";
    NSMutableURLRequest     *request = nil;
    
    if (m_airplaying) {
        if ([m_prevInfoRequest isEqualToString:@"/playback-info"]) {
            nextRequest = @"/scrub";
            m_prevInfoRequest = @"/scrub";
            
            request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:nextRequest
                                                                 relativeToURL:m_baseUrl]];
            [self setCommonHeadersForRequest:request];
            [NSURLConnection sendAsynchronousRequest:request
                                               queue:m_operationQueue
                                   completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                                       //  update our position in the file after /scrub
                                       NSString    *responseString = [NSString stringWithUTF8String:[data bytes]];
                                       NSRange     cachedDurationRange = [responseString rangeOfString:@"position: "];
                                       NSUInteger  cachedDurationEnd;
                                       
                                       if (cachedDurationRange.location != NSNotFound) {
                                           cachedDurationEnd = cachedDurationRange.location + cachedDurationRange.length;
                                           m_playbackPosition = [[responseString substringFromIndex:cachedDurationEnd] doubleValue];
                                           [delegate positionUpdated:m_playbackPosition];
                                       }
                                   }];
        } else {
            nextRequest = @"/playback-info";
            m_prevInfoRequest = @"/playback-info";
            
            request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:nextRequest
                                                                 relativeToURL:m_baseUrl]];
            [self setCommonHeadersForRequest:request];
            [NSURLConnection sendAsynchronousRequest:request
                                               queue:m_operationQueue
                                   completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                                       //  update our playback status and position after /playback-info
                                       NSDictionary            *playbackInfo = nil;
                                       NSString                *errDesc = nil;
                                       NSNumber                *readyToPlay = nil;
                                       NSPropertyListFormat    format;
                                       
                                       if (!m_airplaying) {
                                           return;
                                       }
                                       
                                       playbackInfo = [NSPropertyListSerialization propertyListFromData:data
                                                                                       mutabilityOption:NSPropertyListImmutable
                                                                                                 format:&format
                                                                                       errorDescription:&errDesc];
                                       
                                       if ((readyToPlay = [playbackInfo objectForKey:@"readyToPlay"])
                                           && ([readyToPlay boolValue] == NO)) {
                                           NSDictionary    *userInfo = nil;
                                           NSString        *bundleIdentifier = nil;
                                           NSError         *error = nil;
                                           
                                           userInfo = @{ NSLocalizedDescriptionKey : @"Target AirPlay server not ready.  "
                                                                                      "Check if it is on and idle." };
                                           
                                           bundleIdentifier = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"];
                                           error = [NSError errorWithDomain:bundleIdentifier
                                                                       code:100
                                                                   userInfo:userInfo];
                                           
                                           NSLog(@"Error: %@", [error description]);
                                           //  [self stoppedWithError:error];
                                       } else if ([playbackInfo objectForKey:@"position"]) {
                                           m_playbackPosition = [[playbackInfo objectForKey:@"position"] doubleValue];
                                           m_paused = [[playbackInfo objectForKey:@"rate"] doubleValue] < 0.5f ? YES : NO;
                                           
                                           [delegate setPaused:m_paused];
                                           [delegate positionUpdated:m_playbackPosition];
                                       } else if (playbackInfo != nil) {
                                           [self getPropertyRequest:kAHPropertyRequestPlaybackError];
                                       } else {
                                           NSLog(@"Error parsing /playback-info response: %@", errDesc);
                                       }
                                   }];
        }
    }
}

- (void)getPropertyRequest:(NSUInteger)property
{
    NSMutableURLRequest *request = nil;
    if (property == kAHPropertyRequestPlaybackAccess) {
        request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"/getProperty?playbackAccessLog"
                                                             relativeToURL:m_baseUrl]];
    } else {
        request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"/getProperty?playbackErrorLog"
                                                             relativeToURL:m_baseUrl]];
    }

    [self setCommonHeadersForRequest:request];
    [request setValue:@"application/x-apple-binary-plist" forHTTPHeaderField:@"Content-Type"];

    [NSURLConnection sendAsynchronousRequest:request
                                       queue:m_operationQueue
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                               //  update our playback status and position after /playback-info
                               NSDictionary            *propertyPlist = nil;
                               NSString                *errDesc = nil;
                               NSPropertyListFormat    format;
                               
                               if (!m_airplaying) {
                                   return;
                               }
                               
                               propertyPlist = [NSPropertyListSerialization propertyListFromData:data
                                                                                mutabilityOption:NSPropertyListImmutable
                                                                                          format:&format
                                                                                errorDescription:&errDesc];
                           }];
}

- (void)stopRequest
{
    NSMutableURLRequest *request = nil;
    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"/stop"
                                                         relativeToURL:m_baseUrl]];
    
    [self setCommonHeadersForRequest:request];
    [NSURLConnection sendAsynchronousRequest:request
                                       queue:m_operationQueue
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                               [self stoppedWithError:nil];
                           }];
}

- (void)stopPlayback
{
    if (m_airplaying) {
        [self stopRequest];
        [m_videoManager stop];
    }
}

- (void)changePlaybackStatus
{
    NSMutableURLRequest *request = nil;
    NSString            *rateString = @"/rate?value=1.00000";
    
    if (m_paused) {
        rateString = @"/rate?value=0.00000";
    }
    
    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:rateString
                                                         relativeToURL:m_baseUrl]];
    request.HTTPMethod = @"POST";
    [self setCommonHeadersForRequest:request];
    
    [NSURLConnection sendAsynchronousRequest:request
                                       queue:m_operationQueue
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                               //   Do nothing on completion
                           }];
}

- (void)stoppedWithError:(NSError *)error
{
    m_paused = NO;
    m_airplaying = NO;
    [m_infoTimer invalidate];
    
    m_playbackPosition = 0;
    [delegate positionUpdated:m_playbackPosition];
    [delegate durationUpdated:0];
    [delegate airplayStoppedWithError:error];
}

#pragma mark -
#pragma mark GCDAsyncSocket methods

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port
{
    NSLog(@"socket:didConnectToHost:port: called");
}

- (void)socket:(GCDAsyncSocket *)sock didWritePartialDataOfLength:(NSUInteger)partialLength
           tag:(long)tag
{
    NSLog(@"socket:didWritePartialDataOfLength:tag: called");
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag
{
    if (tag == kAHRequestTagReverse) {
        //  /reverse request data written
    } else if (tag == kAHRequestTagPlay) {
        //  /play request data written
    }
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
    NSString    *replyString = nil;
    NSRange     range;
    
    replyString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSLog(@"socket:didReadData:withTag: data:\r\n%@", replyString);
    
    if (tag == kAHRequestTagReverse) {
        //  /reverse request reply received and read
        range = [replyString rangeOfString:@"HTTP/1.1 101 Switching Protocols"];
        
        if (range.location == NSNotFound) {
            //  a /reverse reply after we started playback, this should contain
            //  any playback info that the server wants to send
            
            //  TODO: does this ever occur?
            NSLog(@"later /reverse data");
        } else {
            //  the first /reverse reply, now we should start playback
            [self playRequest];
            [m_reverseSocket readDataWithTimeout:100.0f tag:kAHRequestTagReverse];
            [NSTimer scheduledTimerWithTimeInterval:10.0f
                                             target:self
                                           selector:@selector(writestuff)
                                           userInfo:nil
                                            repeats:YES];
        }
        
    } else if (tag == kAHRequestTagPlay) {
        //  /play request reply received and read
        range = [replyString rangeOfString:@"HTTP/1.1 200 OK"];
        
        if (range.location != NSNotFound) {
            m_airplaying = YES;
            m_paused = NO;
            [delegate setPaused:m_paused];
            [delegate durationUpdated:m_videoManager.duration];
            
            m_infoTimer = [NSTimer scheduledTimerWithTimeInterval:3.0f
                                                           target:self
                                                         selector:@selector(infoRequest)
                                                         userInfo:nil
                                                          repeats:YES];
        }
    }
}

- (void)writestuff {
    NSData              *data = nil;
    CFURLRef            myURL;
    CFStringRef         bodyString;
    CFStringRef         requestMethod;
    CFHTTPMessageRef    myRequest;
    CFDataRef           bodyDataExt;
    CFDataRef           mySerializedRequest;
    
    bodyString = CFSTR("");
    requestMethod = CFSTR("POST");
    myURL = (__bridge CFURLRef)[m_baseUrl URLByAppendingPathComponent:@"stuff"];
    myRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, requestMethod,
                                           myURL, kCFHTTPVersion1_1);
    bodyDataExt = CFStringCreateExternalRepresentation(kCFAllocatorDefault,
                                                       bodyString,
                                                       kCFStringEncodingUTF8,
                                                       0);
    CFHTTPMessageSetBody(myRequest, bodyDataExt);
    CFHTTPMessageSetHeaderFieldValue(myRequest, CFSTR("X-Apple-Purpose"),
                                     CFSTR("event"));
    CFHTTPMessageSetHeaderFieldValue(myRequest, CFSTR("User-Agent"),
                                     CFSTR("MediaControl/1.0"));
    CFHTTPMessageSetHeaderFieldValue(myRequest, CFSTR("X-Apple-Session-ID"),
                                     (__bridge CFStringRef)m_sessionID);
    mySerializedRequest = CFHTTPMessageCopySerializedMessage(myRequest);
    data = (__bridge NSData *)mySerializedRequest;
    [m_reverseSocket writeData:data
                   withTimeout:1.0f
                           tag:kAHRequestTagReverse];
}

@end
