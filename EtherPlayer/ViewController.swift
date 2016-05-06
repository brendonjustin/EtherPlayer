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
    let videoConverter: VideoConverter = VideoConverter()
    var services: [NSNetService] = []
    
    @IBOutlet var targetSelector: NSPopUpButton!
    @IBOutlet var playButton: NSButton!
    @IBOutlet var positionFieldCell: NSTextFieldCell!
    @IBOutlet var durationFieldCell: NSTextFieldCell!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(airplayTargetsNotificationReceived(_:)), name: "AirplayTargets", object: searcher)
        
        videoConverter.delegate = self
        
        handler.delegate = self
        handler.videoConverter = videoConverter
        
        searcher.beginSearching()
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
        
        handler.targetService = selectedService
    }
    
    @IBAction func showWorkingDirectory(sender: AnyObject?) {
        let fileURL = NSURL(fileURLWithPath: videoConverter.baseFilePath)

        NSWorkspace.sharedWorkspace().activateFileViewerSelectingURLs([fileURL])
    }
}

extension ViewController {
    func airplayTargetsNotificationReceived(notification: NSNotification) {
        guard let newServices = notification.userInfo?["targets"] as? [NSNetService] else {
            assertionFailure("Expected array of NSNetService")
            return
        }
        
        print("Found services: \(newServices)")
        
        for service in newServices {
            guard !services.contains(service) else {
                continue
            }
            
            services.append(service)
            targetSelector.addItemWithTitle(service.hostName!)
            
            if targetSelector.itemArray.count == 1 {
                targetSelector.selectItem(targetSelector.lastItem!)
                updateTarget(self)
            }
        }
        
        let servicesToRemove = Set(services).subtract(Set(newServices))
        
        let indices = servicesToRemove.flatMap { service -> Int? in
            services.indexOf(service)
        }
        
        for service in servicesToRemove {
            targetSelector.removeItemWithTitle(service.hostName!)
        }
        
        for index in indices {
            services.removeAtIndex(index)
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
    
    func positionUpdated(position: Double) {
        positionFieldCell.title = "\(Int(position) / 3600):\((Int(position) / 60) % 60)\(Int(position) % 60)"
    }
    
    func durationUpdated(duration: Double) {
        durationFieldCell.title = "\(Int(duration) / 3600):\((Int(duration) / 60) % 60)\(Int(duration) % 60)"
    }
    
    func airplayStoppedWithError(error: NSError?) {
        if let error = error {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
        
        playButton.image = NSImage(named: "play.png")
    }
}

extension ViewController: VideoConverterDelegate {
    func videoConverter(videoConverter: VideoConverter, outputReadyWithHTTPAddress httpAddress: String, metadata: VideoConverter.Metadata) {
        handler.startAirplay(httpAddress, playbackDuration: metadata.duration)
    }
}
