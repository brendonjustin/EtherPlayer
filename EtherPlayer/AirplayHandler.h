//
//  AirplayHandler.h
//  EtherPlayer
//
//  Created by Brendon Justin on 5/31/12.
//  Copyright (c) 2012 Brendon Justin. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "AirplayConstants.h"

@protocol AirplayHandlerDelegate <NSObject>

- (void)setPaused:(BOOL)paused;
- (void)positionUpdated:(float)position;
- (void)durationUpdated:(float)duration;
- (void)airplayStoppedWithError:(NSError *)error;

@end

@class GCDAsyncSocket;
@class VideoManager;

@interface AirplayHandler : NSObject

- (void)setTargetService:(NSNetService *)targetService;
- (void)startAirplay;
- (void)togglePaused;
- (void)stopPlayback;

@property (strong, nonatomic) id<AirplayHandlerDelegate>    delegate;
@property (strong, nonatomic) VideoManager                  *videoManager;

// Keep everything in the header for easy piecemeal migration to Swift
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
