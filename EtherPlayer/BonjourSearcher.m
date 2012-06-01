//
//  BonjourSearcher.m
//  EtherPlayer
//
//  Created by Brendon Justin on 5/31/12.
//  Copyright (c) 2012 Naga Softworks, LLC. All rights reserved.
//

#import "BonjourSearcher.h"

@interface BonjourSearcher ()

- (void)handleError:(NSNumber *)error;

@end

@implementation BonjourSearcher

@synthesize services = m_services;

- (id)init
{
    if ((self = [super init])) {
        NSNetServiceBrowser *serviceBrowser;
        
        serviceBrowser = [[NSNetServiceBrowser alloc] init];
        [serviceBrowser setDelegate:self];
        [serviceBrowser searchForServicesOfType:@"_airplay._tcp" inDomain:@""];
    }
    
    return self;
}

#pragma mark -
#pragma mark NSNetServiceDelegate

// Sent when browsing begins
- (void)netServiceBrowserWillSearch:(NSNetServiceBrowser *)browser
{
}

// Sent when browsing stops
- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)browser
{
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
    [m_services addObject:aNetService];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser 
         didRemoveService:(NSNetService *)aNetService 
               moreComing:(BOOL)moreComing
{
    if ([m_services containsObject:aNetService]) {
        [m_services removeObject:aNetService];
    }
}

// Error handling code
- (void)handleError:(NSNumber *)error
{
    NSLog(@"An error occurred. Error code = %d", [error intValue]);
    // Handle error here    
}

@end
