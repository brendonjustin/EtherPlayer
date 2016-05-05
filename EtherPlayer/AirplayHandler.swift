//
//  AirplayHandler_Socket.swift
//  EtherPlayer
//
//  Created by Brendon Justin on 5/3/16.
//  Copyright © 2016 Brendon Justin. All rights reserved.
//

import Cocoa

class AirplayHandler: NSObject {
    var delegate: AirplayHandlerDelegate?
    var videoManager: VideoManager!
    
    // Initialize these together
    var baseUrl: NSURL?
    var targetService: NSNetService? {
        get {
            return internalTargetService
        }
        set {
            internalSetTargetService(newValue)
        }
    }
    private var internalTargetService: NSNetService?
    private var targetServiceAddress: NSData {
        return (targetService?.addresses?.first)!
    }
	var sessionID: String = NSUUID().UUIDString
    
	private var prevInfoRequest = "/scrub"
	private var responseData = NSMutableData()
	private var data = NSMutableData()
	private var infoTimer: NSTimer?
    private var serverInfo: [String:AnyObject] = [:]
    private let reverseSocket = GCDAsyncSocket(delegate: nil, delegateQueue: dispatch_get_main_queue())
    private let mainSocket = GCDAsyncSocket(delegate: nil, delegateQueue: dispatch_get_main_queue())
	private var operationQueue = NSOperationQueue.mainQueue()
	private var airplaying = false
	private var paused = true
	private var playbackPosition: Double = 0
	private var serverCapabilities: Int = 0
    
    override init() {
        super.init()
        
        reverseSocket.setDelegate(self)
        mainSocket.setDelegate(self)
        
//        operationQueue.name = "Connection Queue"
    }
    
    private func internalSetTargetService(targetService: NSNetService?) {
        internalTargetService = targetService;
        
        guard let targetService = targetService else {
            return;
        }

        let addressBufferSize = 100
        let addressBuffer = UnsafeMutablePointer<Int8>.alloc(addressBufferSize)
        
        guard let sockArray = targetService.addresses where sockArray.count > 0 else {
            print("Target service didn't have any addresses.")
            self.targetService = nil
            return
        }
        
        guard let sockData = sockArray.first as NSData? else {
            print("Target service socket array didn't contain NSData.")
            return
        }
        
        let sockAddrSize = sizeof(sockaddr_in)
        guard sockData.length == sockAddrSize else {
            if kAHEnableDebugOutput {
                print("No AirPlay targets found, taking no action")
            }
            
            return
        }
        
        let sockAddrPtr = UnsafeMutablePointer<sockaddr_in>.alloc(sockAddrSize)
        sockData.getBytes(sockAddrPtr, length: sockAddrSize)
        
        var sockAddress = sockAddrPtr.memory
        let sockFamily = Int32(sockAddress.sin_family)
        
        if sockFamily == AF_INET || sockFamily == AF_INET6 {
            let addressStringPointer = inet_ntop(sockFamily,
                                                 &(sockAddress.sin_addr),
                                                 addressBuffer,
                                                 socklen_t(addressBufferSize))
            let maybeAddressString = String.fromCString(addressStringPointer)
            let port = CFSwapInt16(sockAddress.sin_port)
            if port != 0, let addressString = maybeAddressString {
                let address = "http://\(addressString):\(port)"
                
                if (kAHEnableDebugOutput) {
                    print("Found service at \(address)")
                }
                
                baseUrl = NSURL(string: address)
            }
        }
        
        //  make a request to /server-info on the target to get some info before
        //  we do anything else
        let url = NSURL(string: "/server-info", relativeToURL: baseUrl)!
        let request = NSMutableURLRequest(URL: url)
        setCommonHeadersForRequest(request)
        
        NSURLConnection.sendAsynchronousRequest(request, queue: operationQueue) { [weak self] (response, data, error) in
            guard let strongSelf = self else {
                return
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
            
            strongSelf.serverInfo = serverInfo
            
            var useHLS = false
            
            let features = serverInfo["features"] as? Int ?? 0
            if features & Int(kAHVideoHTTPLiveStreams) != 0 {
                useHLS = true
            }
            
            strongSelf.videoManager.useHttpLiveStreaming = useHLS
            strongSelf.serverCapabilities = features
        }
    }
    
}

extension AirplayHandler {
    func togglePaused() {
        guard airplaying else {
            return
        }
        
        paused = !paused
        changePlaybackStatus()
        delegate?.setPaused(paused)
    }
    
    func startAirplay() {
        guard let _ = targetService else {
            return
        }
        
        sessionID = NSUUID().UUIDString
        reverseRequest()
    }
    
    func setCommonHeadersForRequest(request: NSMutableURLRequest) {
        request.addValue("MediaControl/1.0", forHTTPHeaderField: "User-Agent")
        request.addValue(sessionID, forHTTPHeaderField: "X-Apple-Session-ID")
    }
    
    func stopPlayback() {
        guard airplaying else {
            return
        }
        
        stopRequest()
        videoManager.stop()
    }
    
    func changePlaybackStatus() {
        let rateString: String
        
        if paused {
            rateString = "rate?value=0.00000"
        } else {
            rateString = "/rate?value=1.00000"
        }
        
        let url = NSURL(string: rateString, relativeToURL: baseUrl)!
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "POST"
        
        setCommonHeadersForRequest(request)
        
        NSURLConnection.sendAsynchronousRequest(request, queue: operationQueue) { (response, data, error) in
            // empty
        }
    }
    
    func stoppedWithError(error: NSError?) {
        paused = false
        airplaying = false
        infoTimer?.invalidate()
        
        playbackPosition = 0
        delegate?.positionUpdated(Float(playbackPosition))
        delegate?.durationUpdated(0)
        delegate?.airplayStoppedWithError(error)
    }
}

// Network requests
private extension AirplayHandler {
    func reverseRequest() {
        NSLog("/reverse")
        
        let bodyString: CFString = ""
        let requestMethod: CFString = "POST"
        let myURL = baseUrl?.URLByAppendingPathComponent("reverse") as CFURLRef?
        let myRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, requestMethod, myURL!, kCFHTTPVersion1_1).takeUnretainedValue()
        let bodyDataExt = CFStringCreateExternalRepresentation(kCFAllocatorDefault, bodyString, CFStringBuiltInEncodings.UTF8.rawValue, 0)
        CFHTTPMessageSetBody(myRequest, bodyDataExt)
        CFHTTPMessageSetHeaderFieldValue(myRequest, "Upgrade", "PTTH/1.0")
        CFHTTPMessageSetHeaderFieldValue(myRequest, "Connection", "Upgrade")
        CFHTTPMessageSetHeaderFieldValue(myRequest, "X-Apple-Purpose", "event")
        CFHTTPMessageSetHeaderFieldValue(myRequest, "User-Agent", "MediaControl/1.0")
        CFHTTPMessageSetHeaderFieldValue(myRequest, "X-Apple-Session-ID", sessionID as CFStringRef)
        let mySerializedRequest = CFHTTPMessageCopySerializedMessage(myRequest)?.takeUnretainedValue()
        data = NSMutableData(data: mySerializedRequest!)
        
        print("Request:\r\n \(NSString(data: data, encoding: NSUTF8StringEncoding))")
        do {
            try reverseSocket.connectToAddress(targetServiceAddress)
            
            reverseSocket.writeData(data, withTimeout: 1, tag: Int(kAHRequestTagReverse))
            reverseSocket.readDataToData("\r\n\r\n".dataUsingEncoding(NSUTF8StringEncoding), withTimeout: 2, tag: Int(kAHRequestTagReverse))
        } catch {
            print ("Error connecting to socket for /reverse: \(error)")
        }
        
        if (kAHAssumeReverseTimesOut) {
            playRequest()
        }
    }
    
    func playRequest() {
        NSLog("/play")
        
        let httpFilePath = videoManager.httpFilePath
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
        let myURL = baseUrl?.URLByAppendingPathComponent("play") as CFURLRef?
        let myRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, requestMethod, myURL!, kCFHTTPVersion1_1).takeUnretainedValue()
        
        CFHTTPMessageSetHeaderFieldValue(myRequest, "User-Agent", appName)
        CFHTTPMessageSetHeaderFieldValue(myRequest, "Content-Length", dataLength)
        CFHTTPMessageSetHeaderFieldValue(myRequest, "Content-Type", "application/x-apple-binary-plist")
        CFHTTPMessageSetHeaderFieldValue(myRequest, "X-Apple-Session-ID", sessionID)
        let mySerializedRequest = CFHTTPMessageCopySerializedMessage(myRequest)?.takeUnretainedValue()
        data = NSMutableData(data: mySerializedRequest!)
        data.appendData(outData)
        
        do {
            try mainSocket.connectToAddress(targetServiceAddress)
            mainSocket.writeData(data, withTimeout: 1, tag: Int(kAHRequestTagPlay))
            mainSocket.readDataToData("\r\n\r\n".dataUsingEncoding(NSUTF8StringEncoding), withTimeout: 2, tag: Int(kAHRequestTagPlay))
        } catch {
            print("Error connecting main socket for /play request: \(error)")
        }
    }
    
    ///  alternates /scrub and /playback-info
    @objc func infoRequest() {
        guard airplaying else {
            return
        }
        
        let nextRequest: String
        
        if prevInfoRequest == "/playback-info" {
            nextRequest = "/scrub"
            
            defer {
                prevInfoRequest = "/scrub"
            }
            
            let url = NSURL(string: nextRequest, relativeToURL: baseUrl)!
            let request = NSMutableURLRequest(URL: url)
            setCommonHeadersForRequest(request)
            
            NSURLConnection.sendAsynchronousRequest(request, queue: operationQueue, completionHandler: { [weak self] (response, data, error) in
                //  update our position in the file after /scrub
                guard let strongSelf = self else {
                    return
                }
                
                guard let data = data, responseString = NSString(data: data, encoding: NSUTF8StringEncoding) else {
                    print("No response data, or data was not a valid string, for /scrub request")
                    return
                }
                
                if case let cachedDurationRange = responseString.rangeOfString("position") where cachedDurationRange.location != NSNotFound {
                    let cachedDurationEnd = cachedDurationRange.location + cachedDurationRange.length
                    strongSelf.playbackPosition = Double(responseString.substringFromIndex(cachedDurationEnd)) ?? 0
                    strongSelf.delegate?.positionUpdated(Float(strongSelf.playbackPosition))
                }
            })
        } else {
            nextRequest = "/playback-info"
            
            defer {
                prevInfoRequest = "/playback-info"
            }
            
            let url = NSURL(string: nextRequest, relativeToURL: baseUrl)!
            let request = NSMutableURLRequest(URL: url)
            setCommonHeadersForRequest(request)
            
            NSURLConnection.sendAsynchronousRequest(request, queue: operationQueue, completionHandler: { [weak self] (response, data, error) in
                //  update our playback status and position after /playback-info
                
                guard let strongSelf = self where strongSelf.airplaying else {
                    return
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
                    strongSelf.playbackPosition = Double(position) ?? 0
                    let rateString = playbackInfo["rate"] as? String
                    let rate = rateString.map { Double($0) } ?? 0
                    strongSelf.paused = rate < 0.5 ? true : false
                    
                    strongSelf.delegate?.setPaused(strongSelf.paused)
                    strongSelf.delegate?.positionUpdated(Float(strongSelf.playbackPosition))
                } else {
                    strongSelf.getPropertyRequest(kAHPropertyRequestPlaybackError)
                }
            })
        }
    }

    func getPropertyRequest(property: UInt) {
        let requestType: String
        if property == kAHPropertyRequestPlaybackAccess {
            requestType = "playbackAccessLog"
        } else {
            requestType = "playbackErrorLog"
        }
        
        let urlString = "/getProperty?\(requestType)"
        
        let url = NSURL(string: urlString, relativeToURL: baseUrl)!
        let request = NSMutableURLRequest(URL: url)
        
        setCommonHeadersForRequest(request)
        request.setValue("application/x-apple-binary-plist", forHTTPHeaderField: "Content-Type")
        
        NSURLConnection.sendAsynchronousRequest(request, queue: operationQueue) { (response, data, error) in
            //  get the PLIST from the response and log it
            guard let data = data else {
                return
            }
            
            var format: NSPropertyListFormat = .BinaryFormat_v1_0
            let propertyPlist: [String:AnyObject]
            do {
                let propertyPlistAny = try NSPropertyListSerialization.propertyListWithData(data, options: [], format: &format)
                print("\(urlString) plist: \(propertyPlistAny)")
                
                guard let propertyPlistDictionary = propertyPlistAny as? [String:AnyObject] else {
                    print("Error parsing \(urlString) response into a dictionary")
                    assertionFailure()
                    return
                }
                
                propertyPlist = propertyPlistDictionary
            } catch {
                print("Error parsing \(urlString) response: \(error)")
                return
            }
            
            print("\(requestType): \(propertyPlist)")
        }
    }
    
    func stopRequest() {
        let url = NSURL(string: "/stop", relativeToURL: baseUrl)!
        let request = NSMutableURLRequest(URL: url)
        
        setCommonHeadersForRequest(request)
        
        NSURLConnection.sendAsynchronousRequest(request, queue: operationQueue) { (response, data, error) in
            self.stoppedWithError(nil)
        }
    }
}

// Testing methods
private extension AirplayHandler {
    func writeStuff() {
        let bodyString: CFString = ""
        let requestMethod: CFString = "POST"
        let myURL = baseUrl?.URLByAppendingPathComponent("stuff") as CFURLRef?
        let myRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, requestMethod, myURL!, kCFHTTPVersion1_1).takeUnretainedValue()
        let bodyDataExt = CFStringCreateExternalRepresentation(kCFAllocatorDefault, bodyString, CFStringBuiltInEncodings.UTF8.rawValue, 0)
        CFHTTPMessageSetBody(myRequest, bodyDataExt)
        CFHTTPMessageSetHeaderFieldValue(myRequest, "X-Apple-Purpose", "event")
        CFHTTPMessageSetHeaderFieldValue(myRequest, "User-Agent", "MediaControl/1.0")
        CFHTTPMessageSetHeaderFieldValue(myRequest, "X-Apple-Session-ID", sessionID as CFStringRef)
        let mySerializedRequest = CFHTTPMessageCopySerializedMessage(myRequest)?.takeUnretainedValue()
        let data = mySerializedRequest as? NSData
        reverseSocket.writeData(data, withTimeout: 1, tag: Int(kAHRequestTagReverse))
    }
}

extension AirplayHandler: GCDAsyncSocketDelegate {
    func socket(sock: GCDAsyncSocket!, didConnectToHost host: String!, port: UInt16) {
        print("socket:didConnectToHost:port: called")
    }
    
    func socket(sock: GCDAsyncSocket!, didWritePartialDataOfLength partialLength: UInt, tag: Int) {
        print("socket:didWritePartialDataOfLength:tag: called")
    }
    
    func socket(sock: GCDAsyncSocket!, didWriteDataWithTag tag: Int) {
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
    
    func socket(sock: GCDAsyncSocket!, didReadData data: NSData!, withTag tag: Int) {
        let replyString = String(data: data, encoding: NSUTF8StringEncoding)!
        
        print("socket:didReadData:withTag: data:\r\n%@", replyString)
        
        let range: Range<String.Index>?
        
        switch UInt(tag) {
        case kAHRequestTagReverse:
            //  /reverse request reply received and read
            range = replyString.rangeOfString("HTTP/1.1 101 Switching Protocols")
            
            if range == nil {
                //  a /reverse reply after we started playback, this should contain
                //  any playback info that the server wants to send
                
                //  TODO: does this ever occur?
                print("later /reverse data")
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
                delegate?.setPaused(paused)
                delegate?.durationUpdated(Float(videoManager.duration))
                
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

protocol AirplayHandlerDelegate: NSObjectProtocol {
    func setPaused(paused: Bool)
    func positionUpdated(position: Float)
    func durationUpdated(duration: Float)
    func airplayStoppedWithError(error: NSError?)
}
