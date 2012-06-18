//
//  OutputVideoCreator.h
//  EtherPlayer
//
//  Created by Brendon Justin on 6/6/12.
//  Copyright (c) 2012 Brendon Justin. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol VideoManagerDelegate <NSObject>

- (void)outputReady:(id)sender;

@end

@interface VideoManager : NSObject

- (void)transcodeMediaForPath:(NSString *)mediaPath;
- (void)cleanup;

@property (strong, nonatomic) id<VideoManagerDelegate>    delegate;
@property (strong, nonatomic) NSString  *httpFilePath;
@property (nonatomic, readonly) double  duration;
@property (nonatomic) BOOL              useHttpLiveStreaming;

@end
