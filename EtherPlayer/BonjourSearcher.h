//
//  BonjourSearcher.h
//  EtherPlayer
//
//  Created by Brendon Justin on 5/31/12.
//  Copyright (c) 2012 Brendon Justin. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface BonjourSearcher : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate>

- (void)beginSearching;

@end
