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

@property (assign) IBOutlet NSWindow *window;

@end
