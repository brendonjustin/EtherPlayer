//
//  AirplayHandler.h
//  EtherPlayer
//
//  Created by Brendon Justin on 5/31/12.
//  Copyright (c) 2012 Brendon Justin. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol AirplayHandlerDelegate <NSObject>

- (void)playStateChanged:(BOOL)playing;

@end

@interface AirplayHandler : NSObject <NSURLConnectionDelegate>

- (void)airplayMediaForPath:(NSString *)mediaPath;
- (void)togglePlaying:(BOOL)playing;
- (void)stopPlayback;

@property (strong, nonatomic) id<AirplayHandlerDelegate> delegate;
@property (strong, nonatomic) NSNetService  *targetService;

@end
