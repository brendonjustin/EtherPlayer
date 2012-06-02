//
//  AirplayHandler.h
//  EtherPlayer
//
//  Created by Brendon Justin on 5/31/12.
//  Copyright (c) 2012 Brendon Justin. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AirplayHandler : NSObject

- (void)airplay;

@property (strong, nonatomic) NSString      *inputPath;
@property (strong, nonatomic) NSNetService  *targetService;

@end
