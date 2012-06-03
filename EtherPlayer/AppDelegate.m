//
//  EtherPlayerAppDelegate.m
//  EtherPlayer
//
//  Created by Brendon Justin on 5/31/12.
//  Copyright (c) 2012 Brendon Justin. All rights reserved.
//

#import "AppDelegate.h"
#import "AirplayHandler.h"
#import "BonjourSearcher.h"

@interface AppDelegate ()

- (void)targetChanged;
- (void)airplayTargetsNotificationReceived:(NSNotification *)notification;

@property (strong, nonatomic) AirplayHandler    *m_handler;
@property (strong, nonatomic) BonjourSearcher   *m_searcher;
@property (strong, nonatomic) NSMutableArray    *m_services;

@end

@implementation AppDelegate

@synthesize window = _window;
@synthesize targetSelector = m_targetSelector;
@synthesize m_handler;
@synthesize m_searcher;
@synthesize m_services;

- (IBAction)openFile:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.allowsMultipleSelection = NO;
    
    [panel beginWithCompletionHandler:^(NSInteger result) {
        if (result == NSFileHandlingPanelOKButton) {
            [self application:[NSApplication sharedApplication] openFile:[panel.URL absoluteString]];
        }
    }];
}

//  set the target device to airplay to
- (void)targetChanged
{
    NSNetService *selectedService = nil;
    for (NSNetService *service in m_services) {
        if ([service.hostName isEqualToString:[[m_targetSelector selectedItem] title]]) {
            selectedService = service;
        }
    }
    
    m_handler.targetService = selectedService;
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename
{
    [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL URLWithString:filename]];
    m_handler.inputFilePath = filename;
    [m_handler airplay];
    
    return YES;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
    m_handler = [[AirplayHandler alloc] init];
    m_searcher = [[BonjourSearcher alloc] init];
    m_services = [NSMutableArray array];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(airplayTargetsNotificationReceived:) 
                                                 name:@"AirplayTargets" 
                                               object:m_searcher];
    
    [m_searcher beginSearching];
}

- (void)airplayTargetsNotificationReceived:(NSNotification *)notification
{
    NSMutableArray *servicesToRemove = [NSMutableArray array];
    NSArray *services = [[notification userInfo] objectForKey:@"targets"];
    NSLog(@"Found services: %@", services);
    
    for (NSNetService *service in services) {
        if (![m_services containsObject:service]) {
            [m_services addObject:service];
            [m_targetSelector addItemWithTitle:service.hostName];
            [[m_targetSelector lastItem] setAction:@selector(targetChanged:)];
            
            if ([[m_targetSelector itemArray] count] == 1) {
                [m_targetSelector selectItem:[m_targetSelector lastItem]];
                [self targetChanged];
            }
        }
    }
    
    for (NSNetService *service in m_services) {
        if (![services containsObject:service]) {
            [servicesToRemove addObject:service];
            [m_targetSelector removeItemWithTitle:service.hostName];
        }
    }
    
    for (NSNetService *service in servicesToRemove) {
        [m_services removeObject:service];
    }
}

@end
