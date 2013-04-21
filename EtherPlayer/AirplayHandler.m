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

@property (strong, nonatomic) NSURL                 *baseUrl;
@property (strong, nonatomic) NSString              *sessionID;
@property (strong, nonatomic) NSString              *prevInfoRequest;
@property (strong, nonatomic) NSMutableData         *responseData;
@property (strong, nonatomic) NSMutableData         *data;
@property (strong, nonatomic) NSTimer               *infoTimer;
@property (strong, nonatomic) NSNetService          *targetService;
@property (strong, nonatomic) NSDictionary          *serverInfo;
@property (strong, nonatomic) GCDAsyncSocket        *reverseSocket;
@property (strong, nonatomic) GCDAsyncSocket        *mainSocket;
@property (strong, nonatomic) NSOperationQueue      *operationQueue;
@property (nonatomic) BOOL                          airplaying;
@property (nonatomic) BOOL                          paused;
@property (nonatomic) double                        playbackPosition;
@property (nonatomic) uint8_t                       serverCapabilities;

@end

@implementation AirplayHandler

//  temporary directory code thanks to a Stack Overflow post
//  http://stackoverflow.com/questions/374431/how-do-i-get-the-default-temporary-directory-on-mac-os-x
//  ip address retrieval code also thanks to a Stack Overflow post
//  http://stackoverflow.com/questions/7072989/iphone-ipad-how-to-get-my-ip-address-programmatically
- (id)init
{
    if ((self = [super init])) {
        self.prevInfoRequest = @"/scrub";
        self.operationQueue = [NSOperationQueue mainQueue];
        self.operationQueue.name = @"Connection Queue";
        self.airplaying = NO;
        self.paused = YES;
        self.playbackPosition = 0;
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
    
    _targetService = targetService;
    
    if (self.targetService == nil) {
        return;
    }
    
    sockArray = self.targetService.addresses;
    
    if ([sockArray count] < 1) {
        self.targetService = nil;
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
            self.baseUrl = [NSURL URLWithString:address];
        }
    }
    
    //  make a request to /server-info on the target to get some info before
    //  we do anything else
    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"/server-info"
                                                         relativeToURL:self.baseUrl]];
    [self setCommonHeadersForRequest:request];
    __weak typeof(&*self) weakSelf = self;
    [NSURLConnection sendAsynchronousRequest:request
                                       queue:self.operationQueue
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                               NSString                *errDesc = nil;
                               NSPropertyListFormat    format;
                               BOOL                    useHLS = NO;
                               
                               if (error != nil) {
                                   NSLog(@"Error getting /server-info");
                                   return;
                               }
                               
                               weakSelf.serverInfo = [NSPropertyListSerialization propertyListFromData:data
                                                                                      mutabilityOption:NSPropertyListImmutable
                                                                                                format:&format
                                                                                      errorDescription:&errDesc];
                               
                               if (weakSelf.serverInfo != nil) {
                                   useHLS = ([[weakSelf.serverInfo objectForKey:@"features"] integerValue]
                                             & kAHVideoHTTPLiveStreams) != 0;
                                   weakSelf.videoManager.useHttpLiveStreaming = useHLS;
                                   
                                   weakSelf.serverCapabilities = [[weakSelf.serverInfo objectForKey:@"features"] integerValue];
                               } else {
                                   NSLog(@"Error parsing /server-info response: %@", errDesc);
                               }
                           }];
}

- (void)togglePaused
{
    if (self.airplaying) {
        self.paused = !self.paused;
        [self changePlaybackStatus];
        [self.delegate setPaused:self.paused];
    }
}

- (void)startAirplay
{
    //  we must have a target service to AirPlay to
    if (self.targetService == nil) {
        return;
    }
    
    [self reverseRequest];
}

- (void)setCommonHeadersForRequest:(NSMutableURLRequest *)request
{
    [request addValue:@"MediaControl/1.0" forHTTPHeaderField:@"User-Agent"];
    [request addValue:self.sessionID forHTTPHeaderField:@"X-Apple-Session-ID"];
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
    
    // generate a UUID for the session
    CFUUIDRef UUID = CFUUIDCreate(kCFAllocatorDefault);
    CFStringRef UUIDString = CFUUIDCreateString(kCFAllocatorDefault,UUID);
    self.sessionID = (__bridge NSString *)UUIDString;
    
    CFRelease(UUID);
    CFRelease(UUIDString);
    
    bodyString = CFSTR("");
    requestMethod = CFSTR("POST");
    myURL = (__bridge CFURLRef)[self.baseUrl URLByAppendingPathComponent:@"reverse"];
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
                                     (__bridge CFStringRef)self.sessionID);
    mySerializedRequest = CFHTTPMessageCopySerializedMessage(myRequest);
    data = (__bridge NSData *)mySerializedRequest;
    
    NSLog(@"Request:\r\n%@", [[NSString alloc] initWithData:data
                                                   encoding:NSUTF8StringEncoding]);
    self.reverseSocket = [[GCDAsyncSocket alloc] initWithDelegate:self
                                                    delegateQueue:dispatch_get_main_queue()];
    [self.reverseSocket connectToAddress:[[self.targetService addresses] objectAtIndex:0]
                                   error:&error];
    
    if (error != nil) {
        NSLog(@"Error connecting socket for /reverse: %@", error);
    } else {
        [self.reverseSocket writeData:data
                          withTimeout:1.0f
                                  tag:kAHRequestTagReverse];
        [self.reverseSocket readDataToData:[@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]
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
    
    httpFilePath = self.videoManager.httpFilePath;
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
    myURL = (__bridge CFURLRef)[self.baseUrl URLByAppendingPathComponent:@"play"];
    myRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, requestMethod,
                                           myURL, kCFHTTPVersion1_1);
    
    CFHTTPMessageSetHeaderFieldValue(myRequest, CFSTR("User-Agent"),
                                     (__bridge CFStringRef)appName);
    CFHTTPMessageSetHeaderFieldValue(myRequest, CFSTR("Content-Length"),
                                     (__bridge CFStringRef)dataLength);
    CFHTTPMessageSetHeaderFieldValue(myRequest, CFSTR("Content-Type"),
                                     CFSTR("application/x-apple-binary-plist"));
    CFHTTPMessageSetHeaderFieldValue(myRequest, CFSTR("X-Apple-Session-ID"),
                                     (__bridge CFStringRef)self.sessionID);
    mySerializedRequest = CFHTTPMessageCopySerializedMessage(myRequest);
    self.data = [(__bridge NSData *)mySerializedRequest mutableCopy];
    [self.data appendData:outData];
    
    self.mainSocket = [[GCDAsyncSocket alloc] initWithDelegate:self
                                                 delegateQueue:dispatch_get_main_queue()];
    [self.mainSocket connectToAddress:[[self.targetService addresses] objectAtIndex:0]
                                error:&error];
    
    if (self.mainSocket != nil) {
        [self.mainSocket writeData:self.data
                       withTimeout:1.0f
                               tag:kAHRequestTagPlay];
        [self.mainSocket readDataToData:[@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]
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
    
    if (self.airplaying) {
        if ([self.prevInfoRequest isEqualToString:@"/playback-info"]) {
            nextRequest = @"/scrub";
            self.prevInfoRequest = @"/scrub";
            
            request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:nextRequest
                                                                 relativeToURL:self.baseUrl]];
            [self setCommonHeadersForRequest:request];
            [NSURLConnection sendAsynchronousRequest:request
                                               queue:self.operationQueue
                                   completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                                       //  update our position in the file after /scrub
                                       NSString    *responseString = [NSString stringWithUTF8String:[data bytes]];
                                       NSRange     cachedDurationRange = [responseString rangeOfString:@"position: "];
                                       NSUInteger  cachedDurationEnd;
                                       
                                       if (cachedDurationRange.location != NSNotFound) {
                                           cachedDurationEnd = cachedDurationRange.location + cachedDurationRange.length;
                                           self.playbackPosition = [[responseString substringFromIndex:cachedDurationEnd] doubleValue];
                                           [self.delegate positionUpdated:self.playbackPosition];
                                       }
                                   }];
        } else {
            nextRequest = @"/playback-info";
            self.prevInfoRequest = @"/playback-info";
            
            request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:nextRequest
                                                                 relativeToURL:self.baseUrl]];
            [self setCommonHeadersForRequest:request];
            [NSURLConnection sendAsynchronousRequest:request
                                               queue:self.operationQueue
                                   completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                                       //  update our playback status and position after /playback-info
                                       NSDictionary            *playbackInfo = nil;
                                       NSString                *errDesc = nil;
                                       NSNumber                *readyToPlay = nil;
                                       NSPropertyListFormat    format;
                                       
                                       if (!self.airplaying) {
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
                                           self.playbackPosition = [[playbackInfo objectForKey:@"position"] doubleValue];
                                           self.paused = [[playbackInfo objectForKey:@"rate"] doubleValue] < 0.5f ? YES : NO;
                                           
                                           [self.delegate setPaused:self.paused];
                                           [self.delegate positionUpdated:self.playbackPosition];
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
    NSString *reqType = nil;
    NSString *urlString = @"/getProperty?%@";
    if (property == kAHPropertyRequestPlaybackAccess) {
        reqType = @"playbackAccessLog";
    } else {
        reqType = @"playbackErrorLog";
    }
    
    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:urlString, reqType]
                                                         relativeToURL:self.baseUrl]];
    
    [self setCommonHeadersForRequest:request];
    [request setValue:@"application/x-apple-binary-plist" forHTTPHeaderField:@"Content-Type"];
    
    [NSURLConnection sendAsynchronousRequest:request
                                       queue:self.operationQueue
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                               //  get the PLIST from the response and log it
                               NSDictionary            *propertyPlist = nil;
                               NSString                *errDesc = nil;
                               NSPropertyListFormat    format;
                               
                               propertyPlist = [NSPropertyListSerialization propertyListFromData:data
                                                                                mutabilityOption:NSPropertyListImmutable
                                                                                          format:&format
                                                                                errorDescription:&errDesc];
                               
                               [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                                   NSLog(@"%@: %@", reqType, propertyPlist);
                               }];
                           }];
}

- (void)stopRequest
{
    NSMutableURLRequest *request = nil;
    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"/stop"
                                                         relativeToURL:self.baseUrl]];
    
    [self setCommonHeadersForRequest:request];
    [NSURLConnection sendAsynchronousRequest:request
                                       queue:self.operationQueue
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                               [self stoppedWithError:nil];
                           }];
}

- (void)stopPlayback
{
    if (self.airplaying) {
        [self stopRequest];
        [self.videoManager stop];
    }
}

- (void)changePlaybackStatus
{
    NSMutableURLRequest *request = nil;
    NSString            *rateString = @"/rate?value=1.00000";
    
    if (self.paused) {
        rateString = @"/rate?value=0.00000";
    }
    
    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:rateString
                                                         relativeToURL:self.baseUrl]];
    request.HTTPMethod = @"POST";
    [self setCommonHeadersForRequest:request];
    
    [NSURLConnection sendAsynchronousRequest:request
                                       queue:self.operationQueue
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                               //   Do nothing on completion
                           }];
}

- (void)stoppedWithError:(NSError *)error
{
    self.paused = NO;
    self.airplaying = NO;
    [self.infoTimer invalidate];
    
    self.playbackPosition = 0;
    [self.delegate positionUpdated:self.playbackPosition];
    [self.delegate durationUpdated:0];
    [self.delegate airplayStoppedWithError:error];
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
        self.airplaying = YES;
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
            [self.reverseSocket readDataWithTimeout:100.0f tag:kAHRequestTagReverse];
        }
        
        NSLog(@"read data for /reverse reply");
        
    } else if (tag == kAHRequestTagPlay) {
        //  /play request reply received and read
        range = [replyString rangeOfString:@"HTTP/1.1 200 OK"];
        
        if (range.location != NSNotFound) {
            self.airplaying = YES;
            self.paused = NO;
            [self.delegate setPaused:self.paused];
            [self.delegate durationUpdated:self.videoManager.duration];
            
            self.infoTimer = [NSTimer scheduledTimerWithTimeInterval:3.0f
                                                              target:self
                                                            selector:@selector(infoRequest)
                                                            userInfo:nil
                                                             repeats:YES];
        }
        
        NSLog(@"read data for /play reply");
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
    myURL = (__bridge CFURLRef)[self.baseUrl URLByAppendingPathComponent:@"stuff"];
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
                                     (__bridge CFStringRef)self.sessionID);
    mySerializedRequest = CFHTTPMessageCopySerializedMessage(myRequest);
    data = (__bridge NSData *)mySerializedRequest;
    [self.reverseSocket writeData:data
                      withTimeout:1.0f
                              tag:kAHRequestTagReverse];
}

@end
