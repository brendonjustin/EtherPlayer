//
//  AirplayHandler_Socket.swift
//  EtherPlayer
//
//  Created by Brendon Justin on 5/3/16.
//  Copyright © 2016 Brendon Justin. All rights reserved.
//

import Cocoa

extension AirplayHandler: GCDAsyncSocketDelegate {
    public func socket(sock: GCDAsyncSocket!, didConnectToHost host: String!, port: UInt16) {
        print("socket:didConnectToHost:port: called")
    }
    
    public func socket(sock: GCDAsyncSocket!, didWritePartialDataOfLength partialLength: UInt, tag: Int) {
        print("socket:didWritePartialDataOfLength:tag: called")
    }
    
    public func socket(sock: GCDAsyncSocket!, didWriteDataWithTag tag: Int) {
        switch UInt(tag) {
        case kAHRequestTagReverse:
            //  /reverse request data written
            break
        case kAHRequestTagPlay:
            //  /play request data written
            airplaying = true
        default:
            break
        }
    }
    
    public func socket(sock: GCDAsyncSocket!, didReadData data: NSData!, withTag tag: Int) {
        let replyString = String(data: data, encoding: NSUTF8StringEncoding)!
    
        print("socket:didReadData:withTag: data:\r\n%@", replyString);
        
        let range: Range<String.Index>?
        
        switch UInt(tag) {
        case kAHRequestTagReverse:
            //  /reverse request reply received and read
            range = replyString.rangeOfString("HTTP/1.1 101 Switching Protocols")
            
            if range == nil {
                //  a /reverse reply after we started playback, this should contain
                //  any playback info that the server wants to send
                
                //  TODO: does this ever occur?
                print("later /reverse data");
            } else {
                //  the first /reverse reply, now we should start playback
                playRequest()
                reverseSocket.readDataWithTimeout(100, tag: Int(kAHRequestTagReverse))
            }
            
            print("read data for /reverse reply")
        case kAHRequestTagPlay:
            //  /play request reply received and read
            range = replyString.rangeOfString("HTTP/1.1 200 OK")
    
            if let _ = range {
                airplaying = true
                paused = false
                delegate.setPaused(paused)
                delegate.durationUpdated(Float(videoManager.duration))

                infoTimer = NSTimer.scheduledTimerWithTimeInterval(3,
                                                                   target: self,
                                                                   selector: #selector(AirplayHandler.infoRequest),
                                                                   userInfo: nil,
                                                                   repeats: true)
            }
            
            print("read data for /play reply")
        default:
            print("read data for unknown reply")
        }
    }
}
