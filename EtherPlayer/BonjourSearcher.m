//
//  BonjourSearcher.m
//  EtherPlayer
//
//  Created by Brendon Justin on 5/31/12.
//  Copyright (c) 2012 Naga Softworks, LLC. All rights reserved.
//

#import "BonjourSearcher.h"

@interface BonjourSearcher () <NSNetServiceBrowserDelegate>

- (void)handleError:(NSNumber *)error;
- (void)postNotificationWithServices:(NSArray *)services;

@property (strong, nonatomic) NSNetServiceBrowser   *m_browser;
@property (strong, nonatomic) NSMutableArray        *m_services;

@end

@implementation BonjourSearcher

@synthesize m_services;
@synthesize m_browser;

- (id)init
{
    if ((self = [super init])) {
        m_services = [NSMutableArray array];
    }
    
    return self;
}
- (void)beginSearching
{
    m_browser = [[NSNetServiceBrowser alloc] init];
    m_browser.delegate = self;
    [m_browser searchForServicesOfType:@"_airplay._tcp." inDomain:@""];
}

- (void)postNotificationWithServices:(NSArray *)services;
{
    NSNotification  *notification;
    NSDictionary    *userInfo = [NSDictionary dictionaryWithObject:services forKey:@"targets"];
    notification = [NSNotification notificationWithName:@"AirplayTargets" 
                                                 object:self 
                                               userInfo:userInfo];
    [[NSNotificationCenter defaultCenter] postNotification:notification];
}

#pragma mark -
#pragma mark NSNetServiceDelegate

// Sent when browsing begins
- (void)netServiceBrowserWillSearch:(NSNetServiceBrowser *)browser
{
    NSLog(@"netServiceBrowserWillSearch");
}

// Sent when browsing stops
- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)browser
{
    NSLog(@"netServiceBrowserDidStopSearch");
}

// Sent if browsing fails
- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
             didNotSearch:(NSDictionary *)errorDict
{
    [self handleError:[errorDict objectForKey:NSNetServicesErrorCode]];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser 
           didFindService:(NSNetService *)aNetService 
               moreComing:(BOOL)moreComing
{
    NSLog(@"didFindService");
    [m_services addObject:aNetService];
    
    [self postNotificationWithServices:[m_services copy]];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser 
         didRemoveService:(NSNetService *)aNetService 
               moreComing:(BOOL)moreComing
{
    NSLog(@"didRemoveService");
    if ([m_services containsObject:aNetService]) {
        [m_services removeObject:aNetService];
        [self postNotificationWithServices:[m_services copy]];
    }
}

// Error handling code
- (void)handleError:(NSNumber *)error
{
    NSLog(@"An error occurred. Error code = %d", [error intValue]);
    // Handle error here    
}

@end
