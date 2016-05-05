//
//  PlayingRequester.swift
//  EtherPlayer
//
//  Created by Brendon Justin on 5/5/16.
//  Copyright © 2016 Brendon Justin. All rights reserved.
//

import Cocoa

class PlayingRequester: AirplayRequester {
    let httpFilePath: String
    let socket: GCDAsyncSocket
    let targetAddress: NSData
    
    init(httpFilePath: String, socket: GCDAsyncSocket, targetAddress: NSData) {
        self.httpFilePath = httpFilePath
        self.socket = socket
        self.targetAddress = targetAddress
    }
    
    func performRequest(baseURL: NSURL, sessionID: String, urlSession: NSURLSession) {
        NSLog("/play")
        
        let appName = NSBundle.mainBundle().objectForInfoDictionaryKey("CFBundleName") as! String
        
        let plist = ["Content-Location" : httpFilePath,
                     "Start-Position" : 0]
        
        let outData: NSData
        do {
            outData = try NSPropertyListSerialization.dataWithPropertyList(plist, format: .BinaryFormat_v1_0, options: .allZeros)
        } catch {
            print("Error creating data from property list: \(error)")
            assertionFailure("Must be able to make plist data for /play request.")
            return
        }
        
        let dataLength = "\(outData.length)"
        
        let bodyString: CFString = ""
        let requestMethod: CFString = "POST"
        let myURL = baseURL.URLByAppendingPathComponent("play") as CFURLRef
        let myRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, requestMethod, myURL, kCFHTTPVersion1_1).takeUnretainedValue()
        
        CFHTTPMessageSetHeaderFieldValue(myRequest, "User-Agent", appName)
        CFHTTPMessageSetHeaderFieldValue(myRequest, "Content-Length", dataLength)
        CFHTTPMessageSetHeaderFieldValue(myRequest, "Content-Type", "application/x-apple-binary-plist")
        CFHTTPMessageSetHeaderFieldValue(myRequest, "X-Apple-Session-ID", sessionID)
        let mySerializedRequest = CFHTTPMessageCopySerializedMessage(myRequest)?.takeUnretainedValue()
        let data = NSMutableData(data: mySerializedRequest!)
        data.appendData(outData)
        
        do {
            try socket.connectToAddress(targetAddress)
            socket.writeData(data, withTimeout: 1, tag: Int(kAHRequestTagPlay))
            socket.readDataToData("\r\n\r\n".dataUsingEncoding(NSUTF8StringEncoding), withTimeout: 2, tag: Int(kAHRequestTagPlay))
        } catch {
            print("Error connecting main socket for /play request: \(error)")
        }
    }
    
    func cancelRequest() {
        // empty
    }
}
