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
    weak var delegate: VideoConverterDelegate?
    
    var baseFilePath: String
    var httpFilePath: String?
    var duration: Double? {
        let len = inputMedia?.length
        let intVal = len?.intValue
        return intVal.map({ Double($0) / 1000 })
    }
    
    /// `true` to indicate that the converter may output HLS instead of a single video file.
    var useHTTPLiveStreaming: Bool = false
    
    let httpServer: HTTPServer
    let httpAddress: String
    var sessionRandom: UInt32 = 0
    
    /// `false` to force outputting a single video file, even with conversion to HLS
    /// would be possible without transcoding
    private let useHLS: Bool = true
    
    var inputMedia: VLCMedia?
    var session: VLCStreamSession?
    var outputStreamPath: String?
    var outputStreamFilename: String?
    var m3u8Filename: String?
    
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
        var baseHTTPAddress: String?
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
                baseHTTPAddress = String(UTF8String: inet_ntoa(ifa_addr_sockaddr_in.sin_addr))
                break
            }
        }
        
        guard let foundBaseHTTPAddress = baseHTTPAddress else {
            fatalError("Error, could not find a non-loopback IPv4 address for myself.")
        }
        
        httpAddress = "http://\(foundBaseHTTPAddress):\(httpServer.port())"
        
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
        
        let workingPath: String
        if let _ = path.rangeOfString("file://localhost") {
            let nonURL = path.stringByReplacingOccurrencesOfString("file://localhost", withString: "")
            guard let unencoded = nonURL.stringByRemovingPercentEncoding else {
                print("Couldn't remove percent encodes from path \(path)")
                return
            }
            
            workingPath = unencoded
        } else {
            workingPath = path
        }
        
        if useHLS {
            outputStreamFilename = "\(sessionRandom)-#####.\(kOVCHLSOutputFiletype)"
            m3u8Filename = "\(sessionRandom).m3u8"
            httpFilePath = httpAddress.stringByAppendingString(m3u8Filename!)
        } else {
            outputStreamFilename = "\(sessionRandom).\(kOVCNormalOutputFiletype)"
            httpFilePath = httpAddress.stringByAppendingString(outputStreamFilename!)
        }
        
        let inputMedia = VLCMedia(path: workingPath)
        self.inputMedia = inputMedia
        inputMedia.delegate = self
        inputMedia.parse()
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
        session?.stopStreaming()
    }
}

extension VideoConverter: VLCMediaDelegate {
    func mediaDidFinishParsing(aMedia: VLCMedia!) {
        convertMedia(aMedia)
        
        //  give VLCKit at least one segment duration before checking
        //  for the playlist file
        NSTimer.scheduledTimerWithTimeInterval(NSTimeInterval(kOVCSegmentDuration), target: self, selector: #selector(VideoConverter.waitForOutputStream), userInfo: nil, repeats: false)
    }
}

private extension VideoConverter {
    func convertMedia(inputMedia: VLCMedia) {
        stop()
        
        var videoNeedsTranscode = false
        var audioNeedsTranscode = false
        
        // Maybe the wrong initializer?
        let session = VLCStreamSession()
        self.session = session
        session.media = inputMedia
        
        //  AAC is 1630826605
        //  MP3 is 1634168941
        //  AC3 is 540161377
        //  AirPlay devices need not support AC3 audio, so this may need adjusting
        //  VLCKit doesn't support AC3 in MP4, so don't allow it unless we are
        //  using TS, i.e. we are using HTTP Live Streaming
        var audioCodecs: [String] = [
            "1630826605",
            "1634168941",
            ]
        
        if useHLS {
            // AC3
            audioCodecs.append("540161377")
        }
        
        var streamOutputOptions: [String:AnyObject] = [:]
        
        //  TODO: intelligently choose bitrates and channels
        var audioChannels: String?
        var width: String?
        var subs: String?
        
        let tracksInformation = inputMedia.tracksInformation as! [[String:AnyObject]]
        for properties in tracksInformation {
            guard let type = properties["type"] as? String else {
                continue
            }
            
            switch type {
            case "video":
                // If we get a 0 value bitrate, transcode to produce a CBR video.
                if !videoNeedsTranscode && properties["bitrate"] as? Int == 0 {
                    videoNeedsTranscode = true
                }
                
                if width == nil {
                    width = properties["width"] as? String
                    
                    if width.flatMap({ Int($0) }) > 1920 {
                        width = "1920"
                        videoNeedsTranscode = true
                    }
                    
                    //  h264 is 875967080
                    //  other video codecs may be supported, further investigation
                    //  is required
                    if (properties["codec"] as? String).flatMap({ Int($0) }) != 875967080 {
                        videoNeedsTranscode = true
                    }
                }
            case "audio":
                if audioChannels == nil {
                    
                    //  AirPlay devices need not support higher than stereo audio, so
                    //  this may need adjusting
                    audioChannels = properties["channelsNumber"] as? String
                    if audioChannels.flatMap({ Int($0) }) > 6 {
                        audioChannels = "6"
                        audioNeedsTranscode = true
                    }
                    
                    //  transcode if the audio codec is not supported by the intended container
                    let codec = properties["codec"] as? String ?? ""
                    if !audioCodecs.contains(codec) {
                        audioChannels = "2"
                        audioNeedsTranscode = true
                    }
                }
            case "text":
                if subs == nil {
                    subs = "tx3g"
//                    subs = "subt"
                }
            case let other:
                print("Unhandled type: \(other)")
            }
        }
        
        //  TODO: intelligently choose bitrates and channels
        var videoBitrate: String
        var audioBitrate: String
        
        let intWidth = width.flatMap({ Int($0) }) ?? 400
        let intAudioChannels = audioChannels.flatMap({ Int($0) }) ?? 2
        videoBitrate = "\(intWidth * 3)"
        audioBitrate = "\(intAudioChannels * 128)"
        
        let videoFilesPath: String
        let videoFilesUrl: String
        
        let access: String
        
        var transcodingOptions: [String:AnyObject] = [:]
        var outputOptions: [String:AnyObject] = [:]
        
        if kOVCIncludeSubs, let _ = subs {
            //  VLCKit can't encode subs for MP4, so if we are using HLS then we have
            //  to burn the subs into the video
            if useHLS {
                transcodingOptions["subtitleOverlay"] = true
                videoNeedsTranscode = true
            } else {
                transcodingOptions["subtitleEncoder"] = "dvbsub"
            }
        }
        
        let videoCodec: String = "h264"
        let audioCodec: String = "mp3"
        
        if videoNeedsTranscode {
            let newOptions = [
                "videoCodec" : videoCodec,
                "videoBitrate" : videoBitrate,
                "width" : width,
                ]
            
            for (key, value) in newOptions {
                transcodingOptions[key] = value
            }
        }
        
        if audioNeedsTranscode {
            let newOptions = [
                "audioCodec" : audioCodec,
                "audioBitrate" : audioBitrate,
                "channels" : audioChannels,
                "audio-sync" : "yes",
                ]
            
            for (key, value) in newOptions {
                transcodingOptions[key] = value
            }
        }
        
        if !transcodingOptions.isEmpty {
            streamOutputOptions["transcodingOptions"] = transcodingOptions
        }
        
        videoFilesPath = baseFilePath.stringByAppendingString(outputStreamFilename!)
        videoFilesUrl = httpAddress.stringByAppendingString(outputStreamFilename!)
        
        let outputStreamPath: String
        //  use part of an mrl to set our options all at once
        if useHLS {
            outputStreamPath = baseFilePath.stringByAppendingString(m3u8Filename!)
            
            access = "livehttp{seglen=\(kOVCSegmentDuration),delsegs=false,index=\(outputStreamPath),index-url=\(videoFilesUrl)}"
            outputOptions = [
                "access" :  access,
                "muxer" : "\(kOVCHLSOutputFiletype){use-key-frames}",
                "destination" : videoFilesPath,
            ]
        } else {
            outputStreamPath = videoFilesPath
            
            access = "file"
            outputOptions = [
                "access" : access,
                "muxer" : kOVCNormalOutputFiletype,
                "destination" : outputStreamPath,
            ]
        }
        
        self.outputStreamPath = outputStreamPath
        
        streamOutputOptions["outputOptions"] = outputOptions
        
        let output = VLCStreamOutput(optionDictionary: streamOutputOptions)
        
        session.streamOutput = output
        session.startStreaming()
    }
    
    //  wait for the output file for this session to be created,
    //  i.e. the .m3u8 file for HLS (or the actual video file otherwise) has
    //  been created for the input video
    @objc func waitForOutputStream() {
        let makeTimer = { () -> Void in
            NSTimer.scheduledTimerWithTimeInterval(2, target: self, selector: #selector(VideoConverter.waitForOutputStream), userInfo: nil, repeats: false)
        }
        
        guard let session = self.session, outputStreamPath = self.outputStreamPath else {
            makeTimer()
            return
        }
        
        let isReady = (useHLS && NSFileManager.defaultManager().fileExistsAtPath(outputStreamPath)) || session.isComplete
        
        guard isReady else {
            makeTimer()
            return
        }
        
        if let session = self.session where session.isComplete {
            session.stopStreaming()
        }
        
        delegate?.outputReady(self)
    }
}

protocol VideoConverterDelegate: class {
    func outputReady(videoConverter: VideoConverter)
}
