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

@interface AppDelegate () <AirplayHandlerDelegate>

- (void)targetChanged;
- (void)airplayTargetsNotificationReceived:(NSNotification *)notification;

@property (strong, nonatomic) AirplayHandler    *m_handler;
@property (strong, nonatomic) BonjourSearcher   *m_searcher;
@property (strong, nonatomic) NSMutableArray    *m_services;

@end

@implementation AppDelegate

@synthesize window = _window;
@synthesize targetSelector = m_targetSelector;
@synthesize playButton = m_playButton;
@synthesize positionFieldCell = m_positionFieldCell;
@synthesize durationFieldCell = m_durationFieldCell;
@synthesize m_handler;
@synthesize m_searcher;
@synthesize m_services;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
    m_handler = [[AirplayHandler alloc] init];
    m_handler.delegate = self;
    
    m_searcher = [[BonjourSearcher alloc] init];
    m_services = [NSMutableArray array];
    
    m_targetSelector.autoenablesItems = YES;
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(airplayTargetsNotificationReceived:) 
                                                 name:@"AirplayTargets" 
                                               object:m_searcher];
    
    [m_searcher beginSearching];
}

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
    
    [m_handler setTargetService:selectedService];
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename
{
    [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL URLWithString:filename]];
    [m_handler airplayMediaForPath:filename];
    
    return YES;
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
            [[m_targetSelector lastItem] setTarget:self];
            [[m_targetSelector lastItem] setAction:@selector(targetChanged)];
            
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

- (IBAction)pausePlayback:(id)sender
{
    [m_handler togglePaused];
}

- (IBAction)stopPlaying:(id)sender
{
    [m_handler stopPlayback];
    [m_playButton setImage:[NSImage imageNamed:@"play.png"]];
}

#pragma mark - 
#pragma mark AirplayHandlerDelegate functions

- (void)isPaused:(BOOL)paused
{
    if (paused) {
        [m_playButton setImage:[NSImage imageNamed:@"play.png"]];
    } else {
        [m_playButton setImage:[NSImage imageNamed:@"pause.png"]];
    }
}

- (void)positionUpdated:(float)position
{
    self.positionFieldCell.title = [NSString stringWithFormat:@"%u:%.2u:%.2u",
                                    (int)position / 3600, ((int)position / 60) % 60,
                                    (int)position % 60];
}

- (void)durationUpdated:(float)duration
{
    self.durationFieldCell.title = [NSString stringWithFormat:@"%u:%.2u:%.2u",
                                    (int)duration / 3600, ((int)duration / 60) % 60,
                                    (int)duration % 60];
}

@end
