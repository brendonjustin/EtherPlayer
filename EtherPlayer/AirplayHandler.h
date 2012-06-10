//
//  AirplayHandler.h
//  EtherPlayer
//
//  Created by Brendon Justin on 5/31/12.
//  Copyright (c) 2012 Brendon Justin. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol AirplayHandlerDelegate <NSObject>

- (void)isPaused:(BOOL)paused;
- (void)positionUpdated:(float)position;
- (void)durationUpdated:(float)duration;

@end

@interface AirplayHandler : NSObject <NSURLConnectionDelegate>

- (void)airplayMediaForPath:(NSString *)mediaPath;
- (void)togglePaused;
- (void)stopPlayback;

@property (strong, nonatomic) id<AirplayHandlerDelegate> delegate;
@property (strong, nonatomic) NSNetService  *targetService;

@end
