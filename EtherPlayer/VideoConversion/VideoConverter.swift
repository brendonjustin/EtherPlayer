//
//  VideoConverter.swift
//  EtherPlayer
//
//  Created by Brendon Justin on 5/6/16.
//  Copyright © 2016 Brendon Justin. All rights reserved.
//

import Cocoa

import Foundation

import VLCKit
    
let kOVCNormalOutputFiletype: String = "mp4"
let kOVCHLSOutputFiletype: String = "ts"
let kOVCSegmentDuration: UInt = 15
let kOVCIncludeSubs: Bool = false
let kOVCCleanTempDir: Bool = false

class VideoConverter: NSObject {
    typealias Metadata = VideoConversionStateMachine.Metadata
    
    weak var delegate: VideoConverterDelegate?
    
    var baseFilePath: String
    
    /// `true` to indicate that the converter may output HLS instead of a single video file.
    var useHTTPLiveStreaming: Bool = false
    
    let httpServer: HTTPServer
    let baseHTTPAddress: String
    var sessionRandom: UInt32 = 0
    
    var currentConversionHTTPFilePath: String?
    
    private var stateMachine: VideoConversionStateMachine = VideoConversionStateMachine(states: [])
    
    /// `false` to force outputting a single video file, even with conversion to HLS
    /// would be possible without transcoding
    private let useHLS: Bool = true
    
    //  temporary directory code thanks to a Stack Overflow post
    //  http://stackoverflow.com/questions/374431/how-do-i-get-the-default-temporary-directory-on-mac-os-x
    //  ip address retrieval code also thanks to a Stack Overflow post
    //  http://stackoverflow.com/questions/7072989/iphone-ipad-how-to-get-my-ip-address-programmatically
    override init() {
        let bundleIdentifier = NSBundle.mainBundle().bundleIdentifier!
        let tempDir = NSTemporaryDirectory()
        let fileManager = NSFileManager.defaultManager()
        let error: NSError
        
        var ifap0: UnsafeMutablePointer<ifaddrs> = nil
        
        baseFilePath = "\(tempDir)\(bundleIdentifier)/"
        
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExistsAtPath(baseFilePath, isDirectory: &isDirectory)
        if exists {
            assert(isDirectory.boolValue, "File (not a directory) exists where we'd like to make our temporary directory.")
        } else {
            do {
                try fileManager.createDirectoryAtPath(baseFilePath, withIntermediateDirectories: false, attributes: nil)
            } catch {
                fatalError("Couldn't create temporary directory")
            }
        }
        
        httpServer = HTTPServer()
        httpServer.setDocumentRoot(baseFilePath)
        httpServer.setPort(6004)
        
        do {
            try httpServer.start()
        } catch {
            fatalError("Couldn't start HTTP server to serve converted videos")
        }
        
        //  get our IPv4 address
        var ipv4Address: String?
        do {
            let success = getifaddrs(&ifap0)
            defer {
                freeifaddrs(ifap0)
            }
            
            guard success == 0 else {
                fatalError("Couldn't get our IPv4 addresses")
            }
            
            var ifapPtr = ifap0
            
            while ifapPtr != nil {
                let ifap = ifapPtr.memory
                
                defer {
                    ifapPtr = ifap.ifa_next
                }
                
                guard case let ifa_addrPtr = ifap.ifa_addr where ifa_addrPtr != nil, case let ifa_addr = ifa_addrPtr.memory, case let sa_family = ifa_addr.sa_family where Int32(sa_family) == AF_INET else {
                    continue
                }
                
                let adapterName = String(UTF8String: ifap.ifa_name)
                
                // Skip the loopback adapter
                guard adapterName != "lo0" else {
                    continue
                }
                
                // Get String from C string
                let ifa_addr_sockaddr_in = unsafeBitCast(ifa_addr, sockaddr_in.self)
                ipv4Address = String(UTF8String: inet_ntoa(ifa_addr_sockaddr_in.sin_addr))
                break
            }
        }
        
        guard let foundIPv4Address = ipv4Address else {
            fatalError("Error, could not find a non-loopback IPv4 address for myself.")
        }
        
        baseHTTPAddress = "http://\(foundIPv4Address):\(httpServer.port())/"
        
        //  settings for VLCKit, copied from VLCKit's VLCLibrary.m and slightly modified
        let defaultParams = [
            "--no-color",                                // Don't use color in output (Xcode doesn't show it)
            "--no-video-title-show",                     // Don't show the title on overlay when starting to play
            "--verbose=4",                               // Let's not wreck the logs
            "--no-sout-keep",
            "--vout=macosx",                             // Select Mac OS X video output
            "--text-renderer=quartztext",                // our CoreText-based renderer
            "--extraintf=macosx_dialog_provider",        // Some extra dialog (login, progress) may come up from here
            "--sub-track=0",
        ]
        
        NSUserDefaults.standardUserDefaults().setObject(defaultParams, forKey: "VLCParams")
    }

    func convertMedia(path: String) {
        sessionRandom = arc4random()
        
        let ready = VideoConversionStateMachine.ReadyState(sessionID: sessionRandom, mediaPath: path, allowHLS: useHLS)
        let parsing = VideoConversionStateMachine.ParsingState(metadata: ready.metadata) { [unowned self] in
            self.stateMachine.enterState(VideoConversionStateMachine.ConvertingState.self)
        }
        
        let metadata = ready.metadata
        let converting = VideoConversionStateMachine.ConvertingState(metadata: metadata, baseHTTPAddress: baseHTTPAddress, baseFilePath: baseFilePath)
        converting.delegate = self
        
        let stopped = VideoConversionStateMachine.StoppedState(session: converting.session)
        
        let states = [
            ready,
            parsing,
            converting,
            stopped,
            ]
        stateMachine = VideoConversionStateMachine(states: states)
        stateMachine.enterState(VideoConversionStateMachine.ReadyState.self)
        
        let filenameToServe: String
        switch ready.conversionType {
        case let .httpLiveStreaming(m3u8Filename: m3u8Filename, filenameTemplate: _):
            filenameToServe = m3u8Filename
        case let .video(filename: filename):
            filenameToServe = filename
        }
        
        currentConversionHTTPFilePath = baseHTTPAddress.stringByAppendingString(filenameToServe)
        stateMachine.enterState(VideoConversionStateMachine.ParsingState.self)
    }
    
    func cleanup() {
        guard kOVCCleanTempDir else {
            return
        }
        
        let fileManager = NSFileManager.defaultManager()
        
        guard let directoryEnumerator = fileManager.enumeratorAtPath(baseFilePath) else {
            assertionFailure("Couldn't get file enumerator for cleaning up \(baseFilePath)")
            return
        }
        
        for currentFilePathAny in directoryEnumerator {
            let currentFilePath = currentFilePathAny as! String
            
            do {
                try fileManager.removeItemAtPath(currentFilePath)
            } catch {
                print("Error deleting temporary file: \(currentFilePath), \(error)")
            }
        }
    }
    
    func stop() {
        let stopped = stateMachine.enterState(VideoConversionStateMachine.StoppedState.self)
        assert(stopped)
    }
}

extension VideoConverter: ConvertingStateDelegate {
    func convertingStateOutputReady(convertingState: VideoConversionStateMachine.ConvertingState) {
        let httpAddress = convertingState.mainFileURL
        let metadata = convertingState.metadata
        delegate?.videoConverter(self, outputReadyWithHTTPAddress: httpAddress, metadata: metadata)
    }
}

private extension VideoConverter {
    func convertMedia(inputMedia: VLCMedia) {
        // TODO: work out how to stop the state-machine based conversion
        stop()
        stateMachine.enterState(VideoConversionStateMachine.ConvertingState.self)
    }
}

protocol VideoConverterDelegate: class {
    func videoConverter(videoConverter: VideoConverter, outputReadyWithHTTPAddress httpAddress: String, metadata: VideoConverter.Metadata)
}
