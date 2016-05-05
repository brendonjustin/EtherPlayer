//
//  PlaybackInfoRequester.swift
//  EtherPlayer
//
//  Created by Brendon Justin on 5/5/16.
//  Copyright © 2016 Brendon Justin. All rights reserved.
//

import Cocoa

class PlaybackInfoRequester: AirplayRequester {
    let relativeURL = "/playback-info"
    
    weak var delegate: PlaybackInfoRequesterDelegate?
    var requestCustomizer: AirplayRequestCustomizer?
    var requestTask: NSURLSessionTask?
    
    func performRequest(baseURL: NSURL, sessionID: String, urlSession: NSURLSession) {
        guard requestTask == nil else {
            print("\(relativeURL) request already in flight, not performing another one.")
            return
        }
        
        let url = NSURL(string: relativeURL, relativeToURL: baseURL)!
        let request = NSMutableURLRequest(URL: url)
        requestCustomizer?.requester(self, willPerformRequest: request)
        
        let task = urlSession.dataTaskWithRequest(request, completionHandler: { [weak self] (data, response, error) in
            //  update our playback status and position after /playback-info
            
            guard let strongSelf = self else {
                return
            }
            
            defer {
                strongSelf.requestTask = nil
            }
            
            guard let data = data else {
                print("No response data for /playback-info request")
                return
            }
            
            var format: NSPropertyListFormat = .BinaryFormat_v1_0
            let playbackInfo: [String:AnyObject]
            
            do {
                let playbackInfoAny = try NSPropertyListSerialization.propertyListWithData(data, options: [], format: &format)
                print("/playback-info plist: \(playbackInfoAny)")
                
                guard let playbackInfoDictionary = playbackInfoAny as? [String:AnyObject] else {
                    print("Error parsing /playback-info response into a dictionary")
                    assertionFailure()
                    return
                }
                
                playbackInfo = playbackInfoDictionary
            } catch {
                print("Error parsing /playback-info response: \(error)")
                return
            }
            
            guard let readyToPlay = playbackInfo["readyToPlay"] as? Bool else {
                print("readyToPlay key in plist not found or not corresponding to a bool")
                assertionFailure()
                return
            }
            
            if !readyToPlay {
                let userInfo = [NSLocalizedDescriptionKey : "Target AirPlay server not ready.  " +
                    "Check if it is on and idle." ]
                
                let bundleIdentifier = NSBundle.mainBundle().bundleIdentifier!
                let error = NSError(domain: bundleIdentifier, code: 100, userInfo: userInfo)
                
                print("Error: \(error.description)")
                //  [self stoppedWithError:error]
            } else if let position = playbackInfo["position"] as? String {
                let playbackPosition = Double(position) ?? 0
                let rateString = playbackInfo["rate"] as? String
                let rate = rateString.map { Double($0) } ?? 0
                let paused = rate < 0.5 ? true : false
                
                strongSelf.delegate?.didUpdatePlaybackStatus(paused: paused, playbackPosition: playbackPosition)
            } else {
                strongSelf.delegate?.didErrorGettingPlaybackStatus()
            }
            })
        
        requestTask = task
        task.resume()
    }
    
    func cancelRequest() {
        requestTask?.cancel()
        requestTask = nil
    }
}

protocol PlaybackInfoRequesterDelegate: class {
    func didUpdatePlaybackStatus(paused paused: Bool, playbackPosition: Double)
    func didErrorGettingPlaybackStatus()
}
