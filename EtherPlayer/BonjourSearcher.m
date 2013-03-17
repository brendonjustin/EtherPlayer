//
//  BonjourSearcher.m
//  EtherPlayer
//
//  Created by Brendon Justin on 5/31/12.
//  Copyright (c) 2012 Brendon Justin. All rights reserved.
//

#import "BonjourSearcher.h"

@interface BonjourSearcher () <NSNetServiceBrowserDelegate>

- (void)handleError:(NSNumber *)error;
- (void)postNotificationWithServices:(NSArray *)services;

@property (strong, nonatomic) NSNetServiceBrowser   *browser;
@property (strong, nonatomic) NSMutableArray        *unresolvedServices;
@property (strong, nonatomic) NSMutableArray        *services;

@end

@implementation BonjourSearcher

- (id)init
{
    if ((self = [super init])) {
        self.unresolvedServices = [NSMutableArray array];
        self.services = [NSMutableArray array];
    }
    
    return self;
}
- (void)beginSearching
{
    self.browser = [[NSNetServiceBrowser alloc] init];
    self.browser.delegate = self;
    [self.browser searchForServicesOfType:@"_airplay._tcp." inDomain:@""];
}

- (void)postNotificationWithServices:(NSArray *)services;
{
    NSNotification  *notification;
    NSDictionary    *userInfo = @{ @"targets" : services };
    notification = [NSNotification notificationWithName:@"AirplayTargets" 
                                                 object:self 
                                               userInfo:userInfo];
    [[NSNotificationCenter defaultCenter] postNotification:notification];
}

#pragma mark -
#pragma mark NSNetServiceDelegate methods

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
    aNetService.delegate = self;
    [aNetService resolveWithTimeout:1000];
    
    [self.unresolvedServices addObject:aNetService];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser 
         didRemoveService:(NSNetService *)aNetService 
               moreComing:(BOOL)moreComing
{
    NSLog(@"didRemoveService");
    if ([self.unresolvedServices containsObject:aNetService]) {
        [self.unresolvedServices removeObject:aNetService];
    } else if ([self.services containsObject:aNetService]) {
        [self.services removeObject:aNetService];
        [self postNotificationWithServices:[self.services copy]];
    }
    
}

// Error handling code
- (void)handleError:(NSNumber *)error
{
    NSLog(@"An error occurred. Error code = %d", [error intValue]);
    // Handle error here    
}

#pragma mark -
#pragma NSNetServiceDelegate methods

- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
    [self.services addObject:sender];
    
    if ([self.unresolvedServices containsObject:sender]) {
        [self.unresolvedServices removeObject:sender];
    }
    
    [self postNotificationWithServices:[self.services copy]];
}

@end
