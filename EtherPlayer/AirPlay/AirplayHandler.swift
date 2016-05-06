//
//  AirplayHandler_Socket.swift
//  EtherPlayer
//
//  Created by Brendon Justin on 5/3/16.
//  Copyright © 2016 Brendon Justin. All rights reserved.
//

import Cocoa


private typealias ServerInfoState = AirplayState<ServerInfoRequester>

class AirplayHandler: NSObject {
    var delegate: AirplayHandlerDelegate?
    var videoConverter: VideoConverter!
    var urlSession: NSURLSession = NSURLSession.sharedSession()
    
    // Initialize and update these together
    var sessionID: String = NSUUID().UUIDString
    var baseURL: NSURL?
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
    
	private var prevInfoRequest = "/scrub"
	private var responseData = NSMutableData()
    private var infoTimer: NSTimer?
    private var serverCapabilities: AirplayServerInfo?
    
    private let reverseSocket = GCDAsyncSocket(delegate: nil, delegateQueue: dispatch_get_main_queue())
    private let mainSocket = GCDAsyncSocket(delegate: nil, delegateQueue: dispatch_get_main_queue())
    
	var operationQueue = NSOperationQueue.mainQueue()
	private var airplaying = false
	private var paused = true
	private var playbackPosition: Double = 0
    
    /**
     Keep a strong reference to the server info state, since it makes network
     requests for us, and we're using it outside of our state machine.
     */
    private var serverInfoState: ServerInfoState?
    private var stateMachine = AirplayStateMachine(states: [])
    
    override init() {
        super.init()
        
        reverseSocket.setDelegate(self)
        mainSocket.setDelegate(self)
        
//        operationQueue.name = "Connection Queue"
    }
    
    private func createAfterServerInfoStateMachine(baseURL: NSURL) {
        let playbackInfoRequester = PlaybackInfoRequester()
        playbackInfoRequester.delegate = self
        playbackInfoRequester.requestCustomizer = self
        
        let playingRequester = PlayingRequester(httpFilePath: videoConverter.httpFilePath!, socket: mainSocket, targetAddress: targetServiceAddress)
        let reverseRequester = ReverseRequester(socket: reverseSocket, targetAddress: targetServiceAddress)
        
        let scrubRequester = ScrubRequester()
        scrubRequester.delegate = self
        scrubRequester.requestCustomizer = self
        
        let stopRequester = StopRequester()
        stopRequester.delegate = self
        stopRequester.requestCustomizer = self
        
        let states = [
            generateState(playbackInfoRequester),
            generateState(playingRequester),
            generateState(reverseRequester),
            generateState(scrubRequester),
            generateState(stopRequester),
        ]
        
        stateMachine = AirplayStateMachine(states: states)
    }
    
    private func generateState<RequesterType: AirplayRequester>(requester: RequesterType) -> AirplayState<RequesterType> {
        let baseURL = self.baseURL!
        return AirplayState(baseURL: baseURL, sessionID: sessionID, requester: requester)
    }
    
    private func internalSetTargetService(targetService: NSNetService?) {
        internalTargetService = targetService
        
        stateMachine.enterState(AirplayStopState.self)
        
        guard let targetService = targetService else {
            return
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
        
        var successGettingInfo = false
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
                
                successGettingInfo = true
                baseURL = NSURL(string: address)
            }
        }
        
        guard successGettingInfo, let baseURL = self.baseURL else {
            print("Couldn't get target service info, not trying to AirPlay")
            return
        }
        
        let requester = ServerInfoRequester()
        requester.delegate = self
        requester.requestCustomizer = self
        let serverInfoState = AirplayState(baseURL: baseURL, sessionID: sessionID, requester: requester)
        serverInfoState.didEnterWithPreviousState(nil)
        self.serverInfoState = serverInfoState
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
        
        createAfterServerInfoStateMachine(baseURL!)
        sessionID = NSUUID().UUIDString
        stateMachine.enterState(AirplayReverseState.self)
    }
    
    func setCommonHeadersForRequest(request: NSMutableURLRequest) {
        request.addValue("MediaControl/1.0", forHTTPHeaderField: "User-Agent")
        request.addValue(sessionID, forHTTPHeaderField: "X-Apple-Session-ID")
    }
    
    func stopPlayback() {
        guard airplaying else {
            return
        }
        
        stateMachine.enterState(AirplayStopState.self)
        videoConverter.stop()
    }
    
    func changePlaybackStatus() {
        let rateString: String
        
        if paused {
            rateString = "/rate?value=0.00000"
        } else {
            rateString = "/rate?value=1.00000"
        }
        
        let url = NSURL(string: rateString, relativeToURL: baseURL)!
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "POST"
        
        setCommonHeadersForRequest(request)
        
        let task = urlSession.dataTaskWithRequest(request) { (data, response, error) in
            // empty
        }
        
        task.resume()
    }
}

private extension AirplayHandler {
    ///  alternates /scrub and /playback-info
    @objc func infoTimerFired() {
        guard airplaying else {
            return
        }
        
        if !stateMachine.enterState(AirplayPlaybackInfoState.self) {
            stateMachine.enterState(AirplayScrubState.self)
        }
    }
}

// Network requests
private extension AirplayHandler {
    func getPropertyRequest(property: UInt) {
        let requestType: String
        if property == kAHPropertyRequestPlaybackAccess {
            requestType = "playbackAccessLog"
        } else {
            requestType = "playbackErrorLog"
        }
        
        let urlString = "/getProperty?\(requestType)"
        
        let url = NSURL(string: urlString, relativeToURL: baseURL)!
        let request = NSMutableURLRequest(URL: url)
        
        setCommonHeadersForRequest(request)
        request.setValue("application/x-apple-binary-plist", forHTTPHeaderField: "Content-Type")
        
        let task = urlSession.dataTaskWithRequest(request) { (data, response, error) in
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
        
        task.resume()
    }
}

// Testing methods
private extension AirplayHandler {
    func writeStuff() {
        let bodyString: CFString = ""
        let requestMethod: CFString = "POST"
        let myURL = baseURL?.URLByAppendingPathComponent("stuff") as CFURLRef?
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
                stateMachine.enterState(AirplayPlayingState.self)
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
                delegate?.durationUpdated(videoConverter.duration!)
                
                infoTimer = NSTimer.scheduledTimerWithTimeInterval(3,
                                                                   target: self,
                                                                   selector: #selector(AirplayHandler.infoTimerFired),
                                                                   userInfo: nil,
                                                                   repeats: true)
            }
            
            print("read data for /play reply")
        default:
            print("read data for unknown reply")
        }
    }
}

extension AirplayHandler: AirplayRequestCustomizer {
    func requester(requester: AirplayRequester, willPerformRequest request: NSMutableURLRequest) {
        setCommonHeadersForRequest(request)
    }
}

extension AirplayHandler: PlaybackInfoRequesterDelegate {
    func didUpdatePlaybackStatus(paused paused: Bool, playbackPosition: Double) {
        self.paused = paused
        self.playbackPosition = playbackPosition
        
        delegate?.positionUpdated(playbackPosition)
        delegate?.setPaused(paused)
    }
    
    func didErrorGettingPlaybackStatus() {
        getPropertyRequest(kAHPropertyRequestPlaybackError)
    }
}

extension AirplayHandler: ScrubRequesterDelegate {
    func playbackPositionUpdated(playbackPosition: Double) {
        self.playbackPosition = playbackPosition
        delegate?.positionUpdated(playbackPosition)
    }
}

extension AirplayHandler: ServerInfoRequesterDelegate {
    func didReceiveServerInfo(serverInfo: AirplayServerInfo) {
        let useHLS = serverInfo.supportsHTTPLiveStreaming
        
        videoConverter.useHTTPLiveStreaming = useHLS
        serverCapabilities = serverInfo
        
        serverInfoState = nil
    }
}

extension AirplayHandler: StopRequesterDelegate {
    func stoppedWithError(error: NSError?) {
        paused = false
        airplaying = false
        infoTimer?.invalidate()
        
        playbackPosition = 0
        delegate?.positionUpdated(playbackPosition)
        delegate?.durationUpdated(0)
        delegate?.airplayStoppedWithError(error)
    }
}

protocol AirplayHandlerDelegate: NSObjectProtocol {
    func setPaused(paused: Bool)
    func positionUpdated(position: Double)
    func durationUpdated(duration: Double)
    func airplayStoppedWithError(error: NSError?)
}
