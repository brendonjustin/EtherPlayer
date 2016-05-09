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
    
    weak var delegate: ScrubRequesterDelegate?
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
            
            // Expect a string like "duration: xxx.xxxxx\nposition: yyy.yyyyy\n"
            if case let positionRange = responseString.rangeOfString("position: ") where positionRange.location != NSNotFound {
                let playbackPositionStart = positionRange.location + positionRange.length
                let playbackPositionEndRange = responseString.rangeOfString("\n", options: [.BackwardsSearch])
                let playbackPositionEnd = playbackPositionEndRange.location
                let playbackPositionNumberRange = NSRange(location: playbackPositionStart, length: playbackPositionEnd - playbackPositionStart)
                let playbackPosition = Double(responseString.substringWithRange(playbackPositionNumberRange)) ?? 0
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
