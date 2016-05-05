//
//  ReverseRequester.swift
//  EtherPlayer
//
//  Created by Brendon Justin on 5/5/16.
//  Copyright © 2016 Brendon Justin. All rights reserved.
//

import Foundation

class ReverseRequester:  AirplayRequester {
    let socket: GCDAsyncSocket
    let targetAddress: NSData
    
    weak var delegate: ReverseRequesterDelegate?
    
    init(socket: GCDAsyncSocket, targetAddress: NSData) {
        self.socket = socket
        self.targetAddress = targetAddress
    }
    
    func performRequest(baseURL: NSURL, sessionID: String, urlSession: NSURLSession) {
        NSLog("/reverse")
        
        // Manually put together an HTTP request. We can't just make a request
        // using `urlSession` because we don't want the `keep-alive` header that
        // the OS would automatically add.
        let bodyString: CFString = ""
        let requestMethod: CFString = "POST"
        let myURL = baseURL.URLByAppendingPathComponent("reverse") as CFURLRef
        let myRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, requestMethod, myURL, kCFHTTPVersion1_1).takeUnretainedValue()
        let bodyDataExt = CFStringCreateExternalRepresentation(kCFAllocatorDefault, bodyString, CFStringBuiltInEncodings.UTF8.rawValue, 0)
        CFHTTPMessageSetBody(myRequest, bodyDataExt)
        CFHTTPMessageSetHeaderFieldValue(myRequest, "Upgrade", "PTTH/1.0")
        CFHTTPMessageSetHeaderFieldValue(myRequest, "Connection", "Upgrade")
        CFHTTPMessageSetHeaderFieldValue(myRequest, "X-Apple-Purpose", "event")
        CFHTTPMessageSetHeaderFieldValue(myRequest, "User-Agent", "MediaControl/1.0")
        CFHTTPMessageSetHeaderFieldValue(myRequest, "X-Apple-Session-ID", sessionID as CFStringRef)
        let mySerializedRequest = CFHTTPMessageCopySerializedMessage(myRequest)?.takeUnretainedValue()
        let data = NSData(data: mySerializedRequest!)
        
        print("Request:\r\n \(NSString(data: data, encoding: NSUTF8StringEncoding))")
        do {
            try socket.connectToAddress(targetAddress)
            
            socket.writeData(data, withTimeout: 1, tag: Int(kAHRequestTagReverse))
            socket.readDataToData("\r\n\r\n".dataUsingEncoding(NSUTF8StringEncoding), withTimeout: 2, tag: Int(kAHRequestTagReverse))
        } catch {
            print ("Error connecting to socket for /reverse: \(error)")
        }
    }
    
    func cancelRequest() {
        // empty
    }
}

protocol ReverseRequesterDelegate: class {
    func requester(requester: ReverseRequester, didErrorConnectingToSocket: NSError)
}
