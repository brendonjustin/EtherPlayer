//
//  BonjourSearcher.h
//  EtherPlayer
//
//  Created by Brendon Justin on 5/31/12.
//  Copyright (c) 2012 Naga Softworks, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface BonjourSearcher : NSObject <NSNetServiceBrowserDelegate>

- (void)beginSearching;

@end
