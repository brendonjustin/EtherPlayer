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
- (void)scrubRequest;
- (void)playbackInfoRequest;

@property (strong, nonatomic) VLCMedia          *m_inputVideo;
@property (strong, nonatomic) VLCStreamOutput   *m_output;
@property (strong, nonatomic) VLCStreamSession  *m_session;
@property (strong, nonatomic) NSString          *m_baseOutputPath;
@property (strong, nonatomic) NSString          *m_outputPath;
@property (strong, nonatomic) NSURL             *m_baseUrl;
@property (strong, nonatomic) NSString          *m_currentRequest;
@property (strong, nonatomic) NSMutableData     *m_responseData;
@property (nonatomic) BOOL                      m_playing;

@end

@implementation AirplayHandler

//  public properties
@synthesize inputPath = m_inputPath;
@synthesize targetService = m_targetService;

//  private properties
@synthesize m_inputVideo;
@synthesize m_output;
@synthesize m_session;
@synthesize m_baseOutputPath;
@synthesize m_outputPath;
@synthesize m_baseUrl;
@synthesize m_currentRequest;
@synthesize m_responseData;
@synthesize m_playing;

//  temporary directory code thanks to a Stack Overflow post
//  http://stackoverflow.com/questions/374431/how-do-i-get-the-default-temporary-directory-on-mac-os-x
- (id)init
{
    if ((self = [super init])) {
        m_playing = YES;
        
        NSString * tempDir = NSTemporaryDirectory();
        if (tempDir == nil)
            tempDir = @"/tmp";
        
        NSString *template = [tempDir stringByAppendingPathComponent:@"temp.XXXXXX"];
        NSLog(@"Template: %@", template);
        const char *fsTemplate = [template fileSystemRepresentation];
        NSMutableData *bufferData = [NSMutableData dataWithBytes:fsTemplate
                                                           length:strlen(fsTemplate)+1];
        char *buffer = [bufferData mutableBytes];
        NSLog(@"FS Template: %s", buffer);
        char *result = mkdtemp(buffer);
        NSLog(@"mkdtemp result: %s", result);
        m_baseOutputPath = [[NSFileManager defaultManager]  stringWithFileSystemRepresentation:buffer
                                                                                        length:strlen(buffer)];
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
    NSMutableURLRequest *request = nil;
    NSURLConnection     *connection = nil;
    char                addressBuffer[100];
    struct sockaddr_in  *sockAddress;
    
//    [self transcodeInput];
    
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
            m_baseUrl = [NSURL URLWithString:address];
        }
    }
    
    //  /reverse
    request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"/server-info" relativeToURL:m_baseUrl]];
    connection = [NSURLConnection connectionWithRequest:request delegate:self];
    [connection start];
    m_currentRequest = @"/server-info";
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
    NSString    *height = @"480";
    NSUInteger  randomInt = arc4random();
    
    m_inputVideo = [VLCMedia mediaWithPath:m_inputPath];
    
    m_outputPath = [m_baseOutputPath stringByAppendingFormat:@"%d.mp4", randomInt];
    
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
    m_session.media = m_inputVideo;
    m_session.streamOutput = m_output;
    
    [m_session startStreaming];
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

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse
{
    return cachedResponse;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    if ([response isKindOfClass: [NSHTTPURLResponse class]])
        NSLog(@"Response type: %ld, %@", [(NSHTTPURLResponse *)response statusCode],
              [NSHTTPURLResponse localizedStringForStatusCode:[(NSHTTPURLResponse *)response statusCode]]);
    
    m_responseData = [[NSMutableData alloc] init];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [m_responseData appendData:data];
}

- (void)connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
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
    NSLog(@"current request: %@, response string: %@", m_currentRequest, response);
    
    if ([m_currentRequest isEqualToString:@"/server-info"]) {
        //  /reverse is a handshake before starting
        //  the next request is /reverse
        request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"/reverse" 
                                                             relativeToURL:m_baseUrl]];
        [request setHTTPMethod:@"POST"];
        [request addValue:@"PTTH/1.0" forHTTPHeaderField:@"Upgrade"];
        [request addValue:@"event" forHTTPHeaderField:@"X-Apple-Purpose"];
        
        nextConnection = [NSURLConnection connectionWithRequest:request delegate:self];
        [nextConnection start];
        m_currentRequest = @"/reverse";
    } else if ([m_currentRequest isEqualToString:@"/reverse"]) {
        //  give the signal to play the file after /reverse
        //  the next request is /play
        request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"/play" 
                                                      relativeToURL:m_baseUrl]];
        
        nextConnection = [NSURLConnection connectionWithRequest:request delegate:self];
        [nextConnection start];
        m_currentRequest = @"/play";
    } else if ([m_currentRequest isEqualToString:@"/play"]) {
        //  check if playing successful after /play
        //  the next request is /playback-info
        
        [self playbackInfoRequest];
    } else if ([m_currentRequest isEqualToString:@"/rate"]) {
        //  nothing to do for /rate
        //  no set next request
    } else if ([m_currentRequest isEqualToString:@"/scrub"]) {
        //  update our position in the file after /scrub
        
        //  the next request is /playback-info
        //  call it after a short delay to keep the polling rate reasonable
        [NSTimer scheduledTimerWithTimeInterval:0.25 
                                         target:self 
                                       selector:@selector(playbackInfoRequest) 
                                       userInfo:nil 
                                        repeats:NO];
    } else if ([m_currentRequest isEqualToString:@"/playback-info"]) {
        //  update our playback status and position after /playback-info
        
        //  the next request is /scrub
        //  call it after a short delay to keep the polling rate reasonable
        [NSTimer scheduledTimerWithTimeInterval:0.25 
                                         target:self 
                                       selector:@selector(scrubRequest) 
                                       userInfo:nil 
                                        repeats:NO];
    } else if ([m_currentRequest isEqualToString:@"/stop"]) {
        //  no next request
    }
}

@end
