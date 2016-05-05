//
//  AirplayStateMachine.swift
//  EtherPlayer
//
//  Created by Brendon Justin on 5/5/16.
//  Copyright © 2016 Brendon Justin. All rights reserved.
//

import Cocoa
import GameplayKit

class AirplayStateMachine: GKStateMachine {
    typealias ReverseState = AirplayState<ReverseRequester>
    typealias PlayingState = AirplayState<PlayingRequester>
    
    enum State {
        case reverse(ReverseState)
        case playing(PlayingState)
        
        init?(state: GKState) {
            switch state {
            case let reverse as ReverseState:
                self = .reverse(reverse)
            case let playing as PlayingState:
                self = .playing(playing)
            default:
                return nil
            }
        }
        
        static func validTransition(leavingStateOfClass: AnyClass?, forStateOfClass: AnyClass) -> Bool {
            guard let leavingClass = leavingStateOfClass else {
                return forStateOfClass == ReverseState.self
            }
            
            switch (leavingClass, forStateOfClass) {
            case (_,_) as (ReverseState.Type, PlayingState.Type):
                return true
            default:
                return false
            }
        }
    }
    
    override func canEnterState(stateClass: AnyClass) -> Bool {
        return State.validTransition(currentState?.dynamicType, forStateOfClass: stateClass)
    }
}

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
}

protocol AirplayRequester {
    func performRequest(baseURL: NSURL, sessionID: String, urlSession: NSURLSession)
    func cancelRequest()
}

protocol AirplayRequestCustomizer: class {
    func requester(requester: AirplayRequester, willPerformRequest request: NSMutableURLRequest)
}
