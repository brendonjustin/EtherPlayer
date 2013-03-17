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
#import "VideoManager.h"

@interface AppDelegate () <AirplayHandlerDelegate, VideoManagerDelegate>

- (void)airplayTargetsNotificationReceived:(NSNotification *)notification;

@property (strong, nonatomic) AirplayHandler    *handler;
@property (strong, nonatomic) BonjourSearcher   *searcher;
@property (strong, nonatomic) NSMutableArray    *services;
@property (strong, nonatomic) VideoManager      *manager;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
    self.searcher = [[BonjourSearcher alloc] init];
    self.services = [NSMutableArray array];

    self.targetSelector.autoenablesItems = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(airplayTargetsNotificationReceived:) 
                                                 name:@"AirplayTargets" 
                                               object:self.searcher];

    self.manager =  [[VideoManager alloc] init];
    self.manager.delegate = self;
    
    self.handler = [[AirplayHandler alloc] init];
    self.handler.delegate = self;
    self.handler.videoManager = self.manager;

    [self.searcher beginSearching];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [self.manager cleanup];
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

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename
{
    [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL URLWithString:filename]];
    [self.manager transcodeMediaForPath:filename];
    
    return YES;
}

- (void)airplayTargetsNotificationReceived:(NSNotification *)notification
{
    NSMutableArray *servicesToRemove = [NSMutableArray array];
    NSArray *services = [[notification userInfo] objectForKey:@"targets"];
    NSLog(@"Found services: %@", services);
    
    for (NSNetService *service in services) {
        if (![self.services containsObject:service]) {
            [self.services addObject:service];
            [self.targetSelector addItemWithTitle:service.hostName];
            
            if ([[self.targetSelector itemArray] count] == 1) {
                [self.targetSelector selectItem:[self.targetSelector lastItem]];
                [self updateTarget:self];
            }
        }
    }
    
    for (NSNetService *service in self.services) {
        if (![services containsObject:service]) {
            [servicesToRemove addObject:service];
            [self.targetSelector removeItemWithTitle:service.hostName];
        }
    }
    
    for (NSNetService *service in servicesToRemove) {
        [self.services removeObject:service];
    }
}

- (IBAction)pausePlayback:(id)sender
{
    [self.handler togglePaused];
}

- (IBAction)stopPlaying:(id)sender
{
    [self.handler stopPlayback];
    [self.playButton setImage:[NSImage imageNamed:@"play.png"]];
}

- (IBAction)updateTarget:(id)sender
{
    NSString *newHostName = [[self.targetSelector selectedItem] title];
    NSNetService *selectedService = nil;
    for (NSNetService *service in self.services) {
        if ([service.hostName isEqualToString:newHostName]) {
            selectedService = service;
        }
    }
    
    [self.handler setTargetService:selectedService];
}

#pragma mark -
#pragma mark AirplayHandlerDelegate functions

- (void)setPaused:(BOOL)paused
{
    if (paused) {
        [self.playButton setImage:[NSImage imageNamed:@"play.png"]];
    } else {
        [self.playButton setImage:[NSImage imageNamed:@"pause.png"]];
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

- (void)airplayStoppedWithError:(NSError *)error
{
    if (error != nil) {
        NSAlert *alert = [NSAlert alertWithError:error];
        [alert runModal];
    }
    
    [self.playButton setImage:[NSImage imageNamed:@"play.png"]];
}

#pragma mark -
#pragma mark VideoManagerDelegate functions

- (void)outputReady:(id)sender
{
    [self.handler startAirplay];
}

@end
