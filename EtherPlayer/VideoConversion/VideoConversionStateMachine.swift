//
//  VideoConversion.swift
//  EtherPlayer
//
//  Created by Brendon Justin on 5/6/16.
//  Copyright © 2016 Brendon Justin. All rights reserved.
//

import Cocoa
import GameplayKit
import VLCKit

class VideoConversionStateMachine: GKStateMachine {
    enum VideoConversionState {
        case ready(ReadyState)
        case parsing(ParsingState)
        case converting(ConvertingState)
        case stopped(StoppedState)
    }
    
    enum ConversionType {
        case httpLiveStreaming(m3u8Filename: String, filenameTemplate: String)
        case video(filename: String)
    }
    
    struct Metadata {
        var duration: Double {
            let len = inputMedia.length
            let intVal = len.intValue
            return Double(intVal) / 1000
        }
        
        let conversionType: ConversionType
        let inputMedia: VLCMedia
        
        var outputVideoFilenameOrTemplate: String {
            switch conversionType {
            case let .httpLiveStreaming(m3u8Filename: _, filenameTemplate: template):
                return template
            case let .video(filename: filename):
                return filename
            }
        }
    }
    
    class ReadyState: GKState {
        let sessionID: UInt32
        let metadata: Metadata
        let allowHLS: Bool
        let conversionType: ConversionType
        
        init(sessionID: UInt32, mediaPath: String, allowHLS: Bool) {
            self.sessionID = sessionID
            self.allowHLS = allowHLS
            
            let workingPath: String
            if let _ = mediaPath.rangeOfString("file://localhost") {
                let nonURL = mediaPath.stringByReplacingOccurrencesOfString("file://localhost", withString: "")
                guard let unencoded = nonURL.stringByRemovingPercentEncoding else {
                    fatalError("Couldn't remove percent encodes from path \(mediaPath)")
                }
                
                workingPath = unencoded
            } else {
                workingPath = mediaPath
            }
            
            if allowHLS {
                let outputStreamFilename = "\(sessionID)-#####.\(kOVCHLSOutputFiletype)"
                let m3u8Filename = "\(sessionID).m3u8"
                conversionType = .httpLiveStreaming(m3u8Filename: m3u8Filename, filenameTemplate: outputStreamFilename)
            } else {
                let outputStreamFilename = "\(sessionID).\(kOVCNormalOutputFiletype)"
                conversionType = .video(filename: outputStreamFilename)
            }
            
            let inputMedia = VLCMedia(path: workingPath)
            metadata = Metadata(conversionType: conversionType, inputMedia: inputMedia)
        }
        
        override func isValidNextState(stateClass: AnyClass) -> Bool {
            return stateClass is ParsingState.Type || stateClass is StoppedState.Type
        }
    }
    
    class ParsingState: GKState, VLCMediaDelegate {
        let metadata: Metadata
        let completion: () -> Void
        
        private var alreadyParsed: Bool {
            return metadata.inputMedia.isParsed
        }
        private var isCancelled = false
        
        init(metadata: Metadata, completion: () -> Void) {
            self.metadata = metadata
            self.completion = completion
            
            super.init()
            
            metadata.inputMedia.delegate = self
        }
        
        override func didEnterWithPreviousState(previousState: GKState?) {
            guard !alreadyParsed else {
                print("Our VLCMedia object is already parsed.")
                completion()
                return
            }
            
            metadata.inputMedia.parse()
        }
        
        override func willExitWithNextState(nextState: GKState) {
            isCancelled = true
        }
        
        override func isValidNextState(stateClass: AnyClass) -> Bool {
            return stateClass is ConvertingState.Type || stateClass is StoppedState.Type
        }
        
        func mediaDidFinishParsing(aMedia: VLCMedia!) {
            guard !isCancelled else {
                return
            }
            completion()
        }
    }
    
    class ConvertingState: GKState {
        let metadata: Metadata
        
        let session: VLCStreamSession
        let outputStreamPath: String
        
        /**
         The URL of the HLS playlist file, or if not using HLS, the converted video file itself.
         */
        let mainFileURL: String
        
        let usingHLS: Bool
        
        weak var delegate: ConvertingStateDelegate?
        
        init(metadata: Metadata, baseHTTPAddress: String, baseFilePath: String) {
            self.metadata = metadata
            
            let inputMedia = metadata.inputMedia
            
            // Maybe the wrong initializer for VLCStreamSession?
            session = VLCStreamSession()
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
            
            let conversionType = metadata.conversionType
            let useHLS: Bool
            if case .httpLiveStreaming = conversionType {
                useHLS = true
            } else {
                useHLS = false
            }
            usingHLS = useHLS
            
            if useHLS {
                // AC3
                audioCodecs.append("540161377")
            }
            
            var videoNeedsTranscode = false
            var audioNeedsTranscode = false
            
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
            
            var streamOutputOptions: [String:AnyObject] = [:]
            
            if !transcodingOptions.isEmpty {
                streamOutputOptions["transcodingOptions"] = transcodingOptions
            }
            
            let outFilenameOrTemplate = metadata.outputVideoFilenameOrTemplate
            let mainFilePath = baseFilePath.stringByAppendingString(outFilenameOrTemplate)
            
            //  use part of an mrl to set our options all at once
            switch conversionType {
            case let .httpLiveStreaming(m3u8Filename: m3u8Filename, filenameTemplate: _):
                outputStreamPath = baseFilePath.stringByAppendingString(m3u8Filename)
                mainFileURL = baseHTTPAddress.stringByAppendingString(m3u8Filename)
                
                let videoFileURL = baseHTTPAddress.stringByAppendingString(outFilenameOrTemplate)
                access = "livehttp{seglen=\(kOVCSegmentDuration),delsegs=false,index=\(outputStreamPath),index-url=\(videoFileURL)}"
                outputOptions = [
                    "access" :  access,
                    "muxer" : "\(kOVCHLSOutputFiletype){use-key-frames}",
                    "destination" : mainFilePath,
                ]
            case let .video(filename: filename):
                outputStreamPath = mainFilePath
                mainFileURL = baseHTTPAddress.stringByAppendingString(filename)
                
                access = "file"
                outputOptions = [
                    "access" : access,
                    "muxer" : kOVCNormalOutputFiletype,
                    "destination" : outputStreamPath,
                ]
            }
            
            streamOutputOptions["outputOptions"] = outputOptions
            
            let output = VLCStreamOutput(optionDictionary: streamOutputOptions)
            session.streamOutput = output
            
            super.init()
            
            //  give VLCKit at least one segment duration before checking
            //  for the playlist file
            NSTimer.scheduledTimerWithTimeInterval(NSTimeInterval(kOVCSegmentDuration), target: self, selector: #selector(ConvertingState.waitForOutputStream), userInfo: nil, repeats: false)
        }
        
        override func didEnterWithPreviousState(previousState: GKState?) {
            session.startStreaming()
        }
        
        override func isValidNextState(stateClass: AnyClass) -> Bool {
            // From here, we can only stop
            return stateClass is StoppedState.Type
        }
        
        //  wait for the output file for this session to be created,
        //  i.e. the .m3u8 file for HLS (or the actual video file otherwise) has
        //  been created for the input video
        @objc private func waitForOutputStream() {
            let makeTimer = { () -> Void in
                NSTimer.scheduledTimerWithTimeInterval(2, target: self, selector: #selector(ConvertingState.waitForOutputStream), userInfo: nil, repeats: false)
            }
            
            let isReady = (usingHLS && NSFileManager.defaultManager().fileExistsAtPath(outputStreamPath)) || session.isComplete
            
            guard isReady else {
                makeTimer()
                return
            }
            
            if session.isComplete {
                session.stopStreaming()
            }
            
            delegate?.convertingStateOutputReady(self)
        }
    }
    
    class StoppedState: GKState {
        let session: VLCStreamSession
        
        init(session: VLCStreamSession) {
            self.session = session
        }
        
        override func didEnterWithPreviousState(previousState: GKState?) {
            session.stopStreaming()
        }
        
        override func isValidNextState(stateClass: AnyClass) -> Bool {
            // Don't allow transitions to any other states
            return false
        }
    }
}

protocol ConvertingStateDelegate: class {
    func convertingStateOutputReady(convertingState: VideoConversionStateMachine.ConvertingState)
}
