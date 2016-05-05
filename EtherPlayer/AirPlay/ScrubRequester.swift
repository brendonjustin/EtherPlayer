//
//  ScrubRequester.swift
//  EtherPlayer
//
//  Created by Brendon Justin on 5/5/16.
//  Copyright © 2016 Brendon Justin. All rights reserved.
//

import Cocoa

class ScrubRequester: AirplayRequester {
    let relativeURL = "/scrub"
    
    var delegate: ScrubRequesterDelegate?
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
            //  update our position in the file after /scrub
            guard let strongSelf = self else {
                return
            }
            
            defer {
                strongSelf.requestTask = nil
            }
            
            guard let data = data, responseString = NSString(data: data, encoding: NSUTF8StringEncoding) else {
                print("No response data, or data was not a valid string, for /scrub request")
                return
            }
            
            if case let cachedDurationRange = responseString.rangeOfString("position") where cachedDurationRange.location != NSNotFound {
                let cachedDurationEnd = cachedDurationRange.location + cachedDurationRange.length
                let playbackPosition = Double(responseString.substringFromIndex(cachedDurationEnd)) ?? 0
                strongSelf.delegate?.playbackPositionUpdated(playbackPosition)
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

protocol ScrubRequesterDelegate: class {
    func playbackPositionUpdated(playbackPosition: Double)
}
