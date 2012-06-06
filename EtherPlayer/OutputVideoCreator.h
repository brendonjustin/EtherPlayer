//
//  OutputVideoCreator.h
//  EtherPlayer
//
//  Created by Brendon Justin on 6/6/12.
//  Copyright (c) 2012 Brendon Justin. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol OutputVideoCreatorDelegate <NSObject>

- (void)outputReady:(id)sender;

@end

@interface OutputVideoCreator : NSObject

- (void)transcodeMediaForPath:(NSString *)mediaPath;

@property (strong, nonatomic) id<OutputVideoCreatorDelegate>    delegate;
@property (strong, nonatomic) NSData    *playRequestData;
@property (strong, nonatomic) NSString  *playRequestDataType;
@property (strong, nonatomic) NSString  *outputSegsFilename;
@property (strong, nonatomic) NSString  *outputM3u8Filename;

@end
