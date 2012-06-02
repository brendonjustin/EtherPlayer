//
//  EtherPlayerAppDelegate.m
//  EtherPlayer
//
//  Created by Brendon Justin on 5/31/12.
//  Copyright (c) 2012 Naga Softworks, LLC. All rights reserved.
//

#import "AppDelegate.h"
#import "AirplayHandler.h"
#import "BonjourSearcher.h"

@interface AppDelegate ()

- (void)airplayTargetsNotificationReceived:(NSNotification *)notification;

@property (strong, nonatomic) AirplayHandler    *m_handler;
@property (strong, nonatomic) BonjourSearcher   *m_searcher;

@end

@implementation AppDelegate

@synthesize window = _window;
@synthesize m_handler;
@synthesize m_searcher;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
    m_handler = [[AirplayHandler alloc] init];
    m_searcher = [[BonjourSearcher alloc] init];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(airplayTargetsNotificationReceived:) 
                                                 name:@"AirplayTargets" 
                                               object:m_searcher];
    
    [m_searcher beginSearching];
}

- (void)airplayTargetsNotificationReceived:(NSNotification *)notification
{
    NSArray *services = [[notification userInfo] objectForKey:@"targets"];
    NSLog(@"Found services: %@", services);
    
    if (m_handler.targetService == nil && [services count] > 0) {
        m_handler.targetService = [services objectAtIndex:0];
        [m_handler airplay];
    }
}

@end
