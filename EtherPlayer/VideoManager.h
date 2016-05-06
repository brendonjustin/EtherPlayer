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
- (void)stop;

@property (strong, nonatomic) id<VideoManagerDelegate> delegate;
/**
 The location on disk to store converted video files.
 */
@property (strong, nonatomic) NSString  *baseFilePath;
/**
 The main URL for the converted file, either an m3u8 playlist or a video.
 */
@property (strong, nonatomic) NSString  *httpFilePath;
@property (nonatomic, readonly) double  duration;
@property (nonatomic) BOOL              useHttpLiveStreaming;

@end
