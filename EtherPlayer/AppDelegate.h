//
//  EtherPlayerAppDelegate.h
//  EtherPlayer
//
//  Created by Brendon Justin on 5/31/12.
//  Copyright (c) 2012 Brendon Justin. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>

- (IBAction)openFile:(id)sender;
- (IBAction)pausePlayback:(id)sender;
- (IBAction)stopPlaying:(id)sender;

@property (assign) IBOutlet NSWindow *window;
@property (assign) IBOutlet NSPopUpButton *targetSelector;
@property (assign) IBOutlet NSButton *playButton;
@property (assign) IBOutlet NSTextFieldCell *positionFieldCell;
@property (assign) IBOutlet NSTextFieldCell *durationFieldCell;

@end
