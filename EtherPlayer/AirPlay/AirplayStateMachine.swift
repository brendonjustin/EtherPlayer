//
//  AirplayStateMachine.swift
//  EtherPlayer
//
//  Created by Brendon Justin on 5/5/16.
//  Copyright © 2016 Brendon Justin. All rights reserved.
//

import Cocoa
import GameplayKit

typealias AirplayReverseState = AirplayState<ReverseRequester>
typealias AirplayPlayingState = AirplayState<PlayingRequester>
typealias AirplayPlaybackInfoState = AirplayState<PlaybackInfoRequester>
typealias AirplayScrubState = AirplayState<ScrubRequester>
typealias AirplayStopState = AirplayState<StopRequester>

private enum State {
    case reverse(AirplayReverseState)
    case playing(AirplayPlayingState)
    case playbackInfo(AirplayPlaybackInfoState)
    case scrub(AirplayScrubState)
    case stop(AirplayStopState)
    
    init?(state: GKState) {
        switch state {
        case let reverse as AirplayReverseState:
            self = .reverse(reverse)
        case let playing as AirplayPlayingState:
            self = .playing(playing)
        case let playbackInfo as AirplayPlaybackInfoState:
            self = .playbackInfo(playbackInfo)
        case let scrub as AirplayScrubState:
            self = .scrub(scrub)
        case let stop as AirplayStopState:
            self = .stop(stop)
        default:
            return nil
        }
    }
    
    static func validTransition(leavingStateOfClass: AnyClass?, forStateOfClass: AnyClass) -> Bool {
        guard let leavingClass = leavingStateOfClass else {
            return forStateOfClass == AirplayReverseState.self
        }
        
        let targetStateIsStop = forStateOfClass == AirplayStopState.self
        let nonStopTransitionAllowed: Bool
        let stopTransitionAllowed: Bool
        
        switch leavingClass {
        case _ as AirplayReverseState.Type:
            nonStopTransitionAllowed = forStateOfClass is AirplayPlayingState.Type
            stopTransitionAllowed = false
        case _ as AirplayPlayingState.Type:
            nonStopTransitionAllowed = forStateOfClass is AirplayPlaybackInfoState.Type
            stopTransitionAllowed = true
        case _ as AirplayPlaybackInfoState.Type:
            nonStopTransitionAllowed = forStateOfClass is AirplayScrubState.Type
            stopTransitionAllowed = true
        case _ as AirplayScrubState.Type:
            nonStopTransitionAllowed = forStateOfClass is AirplayPlaybackInfoState.Type
            stopTransitionAllowed = true
        case _ as AirplayStopState.Type:
            nonStopTransitionAllowed = true
            stopTransitionAllowed = false
        default:
            nonStopTransitionAllowed = false
            stopTransitionAllowed = true
        }
        
        return (!targetStateIsStop && nonStopTransitionAllowed) || (targetStateIsStop && stopTransitionAllowed)
    }
}

typealias AirplayStateMachine = GKStateMachine

class AirplayState<Requester: AirplayRequester>: GKState {
    let baseURL: NSURL
    let sessionID: String
    let requester: Requester
    var urlSession: NSURLSession = NSURLSession.sharedSession()
    
    init(baseURL: NSURL, sessionID: String, requester: Requester) {
        self.baseURL = baseURL
        self.sessionID = sessionID
        self.requester = requester
    }
    
    override func didEnterWithPreviousState(previousState: GKState?) {
        requester.performRequest(baseURL, sessionID: sessionID, urlSession: urlSession)
    }
    
    override func isValidNextState(stateClass: AnyClass) -> Bool {
        return State.validTransition(self.dynamicType, forStateOfClass: stateClass)
    }
}

protocol AirplayRequester {
    func performRequest(baseURL: NSURL, sessionID: String, urlSession: NSURLSession)
    func cancelRequest()
}

protocol AirplayRequestCustomizer: class {
    func requester(requester: AirplayRequester, willPerformRequest request: NSMutableURLRequest)
}
