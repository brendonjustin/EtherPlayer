//
//  AppDelegate.swift
//  EtherPlayer
//
//  Created by Brendon Justin on 5/3/16.
//  Copyright © 2016 Brendon Justin. All rights reserved.
//

import AppKit

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    private var viewController: ViewController!
    
    func applicationDidFinishLaunching(notification: NSNotification) {
        viewController = NSApplication.sharedApplication().windows.first?.contentViewController as! ViewController
    }
    
    @IBAction func openFile(sender: AnyObject?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        
        panel.beginWithCompletionHandler { (result) in
            guard result == NSFileHandlingPanelOKButton else {
                return
            }
            
            self.application(NSApplication.sharedApplication(), openFile: panel.URL!.absoluteString)
        }
    }
    
    func application(sender: NSApplication, openFile filename: String) -> Bool {
        let controller = NSDocumentController.sharedDocumentController()
        controller.noteNewRecentDocumentURL(NSURL(fileURLWithPath: filename))
        viewController.videoConverter.convertMedia(filename)
        
        return true
    }
}
