//
//  ServerInfoRequester.swift
//  EtherPlayer
//
//  Created by Brendon Justin on 5/5/16.
//  Copyright © 2016 Brendon Justin. All rights reserved.
//

import Cocoa

class ServerInfoRequester: AirplayRequester {
    let relativeURL = "/server-info"
    
    var delegate: ServerInfoRequesterDelegate?
    var requestCustomizer: AirplayRequestCustomizer?
    
    private var requestTask: NSURLSessionTask?
    
    func performRequest(baseURL: NSURL, sessionID: String, urlSession: NSURLSession) {
        //  make a request to /server-info on the target to get some info before
        let url = NSURL(string: relativeURL, relativeToURL: baseURL)!
        let request = NSMutableURLRequest(URL: url)
        requestCustomizer?.requester(self, willPerformRequest: request)
        
        let task = urlSession.dataTaskWithRequest(request) { [weak self] (data, response, error) in
            guard let strongSelf = self else {
                return
            }
            
            defer {
                strongSelf.requestTask = nil
            }
            
            guard let data = data else {
                print("Error getting /server-info")
                return
            }
            
            var format = NSPropertyListFormat.BinaryFormat_v1_0
            
            let serverInfo: [String:AnyObject]
            
            do {
                let serverInfoAny = try NSPropertyListSerialization.propertyListWithData(data, options: [], format: &format)
                print("/server-info plist: \(serverInfoAny)")
                
                guard let serverInfoDictionary = serverInfoAny as? [String:AnyObject] else {
                    print("Error parsing /server-info response into a dictionary")
                    return
                }
                
                serverInfo = serverInfoDictionary
            } catch {
                print("Error parsing /server-info response: \(error)")
                return
            }
            
            let airplayServerInfo = AirplayServerInfo(infoDictionary: serverInfo)
            strongSelf.delegate?.didReceiveServerInfo(airplayServerInfo)
        }
        
        requestTask = task
        task.resume()
    }
    
    func cancelRequest() {
        requestTask?.cancel()
        requestTask = nil
    }
}

protocol ServerInfoRequesterDelegate {
    func didReceiveServerInfo(serverInfo: AirplayServerInfo)
}

struct AirplayServerInfo {
    private let infoDictionary: [String:AnyObject]
    
    var supportsHTTPLiveStreaming: Bool {
        let features = infoDictionary["features"] as? Int ?? 0
        if features & Int(kAHVideoHTTPLiveStreams) != 0 {
            return true
        }
        
        return false
    }
}
