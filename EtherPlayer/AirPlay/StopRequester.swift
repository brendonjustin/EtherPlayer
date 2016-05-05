//
//  StopRequester.swift
//  EtherPlayer
//
//  Created by Brendon Justin on 5/5/16.
//  Copyright © 2016 Brendon Justin. All rights reserved.
//

import Cocoa

class StopRequester: AirplayRequester {
    let relativeURL = "/stop"
    
    weak var delegate: StopRequesterDelegate?
    weak var requestCustomizer: AirplayRequestCustomizer?
    
    private var requestTask: NSURLSessionTask?
    
    func performRequest(baseURL: NSURL, sessionID: String, urlSession: NSURLSession) {
        guard requestTask == nil else {
            print("\(relativeURL) request already in flight, not performing another one.")
            return
        }
        
        let url = NSURL(string: relativeURL, relativeToURL: baseURL)!
        let request = NSMutableURLRequest(URL: url)
        
        requestCustomizer?.requester(self, willPerformRequest: request)
        
        let task = urlSession.dataTaskWithRequest(request) { [weak self] (data, response, error) in
            defer {
                self?.requestTask = nil
            }
            
            self?.delegate?.stoppedWithError(nil)
        }
        
        requestTask = task
        task.resume()
    }
    
    func cancelRequest() {
        requestTask?.cancel()
        requestTask = nil
    }
}

protocol StopRequesterDelegate: class {
    func stoppedWithError(error: NSError?)
}
