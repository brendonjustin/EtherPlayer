//
//  ViewController.swift
//  EtherPlayer
//
//  Created by Brendon Justin on 5/3/16.
//  Copyright © 2016 Brendon Justin. All rights reserved.
//

import Cocoa

class ViewController: NSViewController {
    
    let handler: AirplayHandler = AirplayHandler()
    let searcher: BonjourSearcher = BonjourSearcher()
    let manager: VideoManager = VideoManager()
    var services: [NSNetService] = []
    
    @IBOutlet var targetSelector: NSPopUpButton!
    @IBOutlet var playButton: NSButton!
    @IBOutlet var positionFieldCell: NSTextFieldCell!
    @IBOutlet var durationFieldCell: NSTextFieldCell!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(airplayTargetsNotificationReceived(_:)), name: "AirplayTargets", object: searcher)
        
        manager.delegate = self
        
        handler.delegate = self
        handler.videoManager = manager
        
        searcher.beginSearching()
    }
    
    deinit {
        manager.cleanup()
    }
}

extension ViewController {
    @IBAction func pausePlayback(sender: AnyObject?) {
        handler.togglePaused()
    }
    
    @IBAction func stopPlaying(sender: AnyObject?) {
        handler.stopPlayback()
        playButton.image = NSImage(named: "play.png")
    }
    
    @IBAction func updateTarget(sender: AnyObject?) {
        let newHostName = targetSelector.selectedItem!.title
        let selectedService: NSNetService = services.filter { $0.hostName == newHostName }.first!
        
        handler.setTargetService(selectedService)
    }
}

extension ViewController {
    func airplayTargetsNotificationReceived(notification: NSNotification) {
        var servicesToRemove: [NSNetService] = []
        guard let services = notification.userInfo?["targets"] as? [NSNetService] else {
            assertionFailure("Expected array of NSNetService")
            return
        }
        
        debugPrint("Found services: %@", services as NSArray?)
        
        for service in services {
            guard !self.services.contains(service) else {
                continue
            }
            
            self.services.append(service)
            targetSelector.addItemWithTitle(service.hostName!)
            
            if targetSelector.itemArray.count == 1 {
                targetSelector.selectItem(targetSelector.lastItem!)
                updateTarget(self)
            }
        }
        
        for service in self.services {
            guard !services.contains(service) else {
                continue
            }
            
            servicesToRemove.append(service)
            targetSelector.removeItemWithTitle(service.hostName!)
        }
        
        for service in servicesToRemove {
            if let idx = services.indexOf(service) {
                self.services.removeAtIndex(idx)
            }
        }
    }
}

extension ViewController: AirplayHandlerDelegate {
    func setPaused(paused: Bool) {
        let image: NSImage?
        if paused {
            image = NSImage(named: "play.png")
        } else {
            image = NSImage(named: "pause.png")
        }
        
        playButton.image = image
    }
    
    func positionUpdated(position: Float) {
        positionFieldCell.title = "\(Int(position) / 3600):\((Int(position) / 60) % 60)\(Int(position) % 60)"
    }
    
    func durationUpdated(duration: Float) {
        durationFieldCell.title = "\(Int(duration) / 3600):\((Int(duration) / 60) % 60)\(Int(duration) % 60)"
    }
    
    func airplayStoppedWithError(error: NSError!) {
        if let error = error {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
        
        playButton.image = NSImage(named: "play.png")
    }
}

extension ViewController: VideoManagerDelegate {
    func outputReady(sender: AnyObject!) {
        handler.startAirplay()
    }
}
