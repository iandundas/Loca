//
//  LocationAuthorizationProvider.swift
//  Tacks
//
//  Created by Ian Dundas on 27/05/2016.
//  Copyright © 2016 Ian Dundas. All rights reserved.
//

import Foundation
import CoreLocation
import ReactiveKit

public enum LocationAuthorizationState{
    case NoDecisionYet
    case UserNotPermitted
    case UserDisabled
    case Authorized(always: Bool)
    
    public static func fromClAuthorizationStatus(status: CLAuthorizationStatus) -> LocationAuthorizationState{
        switch(status){
        case .AuthorizedAlways: return .Authorized(always: true)
        case .AuthorizedWhenInUse: return .Authorized(always: false)
        case .Restricted: return .UserNotPermitted
        case .Denied: return .UserDisabled
        case .NotDetermined: fallthrough
        default: return .NoDecisionYet
        }
    }
    
    public static var currentState: LocationAuthorizationState{
        return fromClAuthorizationStatus(CLLocationManager.authorizationStatus())
    }
}

public enum LocationAuthorizationError: ErrorType{
    case Denied, Restricted
}

public protocol LocationAuthorizationProviderType{
    var state: Property<LocationAuthorizationState> {get}
    static var stateStream: Stream<LocationAuthorizationState> {get}
    
    func authorize() -> Operation<LocationAuthorizationState, LocationAuthorizationError>
}


public final class LocationAuthorizationProvider: LocationAuthorizationProviderType{
    
    public let state = Property<LocationAuthorizationState>(LocationAuthorizationState.currentState)
    private let bag = DisposeBag()
    
    public init(){
        LocationAuthorizationProvider.stateStream
            .bindTo(state)
            .disposeIn(bag)
    }
    
    public static var stateStream: Stream<LocationAuthorizationState>{
        return CLLocationManager.statusStream().map { LocationAuthorizationState.fromClAuthorizationStatus($0) }
    }
    
    public func authorize() -> Operation<LocationAuthorizationState, LocationAuthorizationError>{
        
        return Operation<LocationAuthorizationState, LocationAuthorizationError> { observer in
            
            let startingState = LocationAuthorizationState.currentState
            guard case .NoDecisionYet = startingState else {
                switch(startingState){
                case .Authorized(always: _):
                    observer.next(startingState)
                    observer.completed()
                case .UserNotPermitted:
                    observer.failure(LocationAuthorizationError.Restricted)
                case .UserDisabled:fallthrough
                default:
                    observer.failure(LocationAuthorizationError.Denied)
                }
                return SimpleDisposable()
            }
            
            
            let bag = DisposeBag()
            let locationManager = CLLocationManager()
            let delegateProxy = locationManager.rDelegate
            
            let didChangeAuthStatusSelector = #selector(CLLocationManagerDelegate.locationManager(_:didChangeAuthorizationStatus:))
            delegateProxy.streamFor(didChangeAuthStatusSelector, map: { (manager: CLLocationManager, status: CLAuthorizationStatus) -> LocationAuthorizationState in
                return LocationAuthorizationState.fromClAuthorizationStatus(status)
            })
            .observeNext { status in
                switch(status){
                case .Authorized(_):
                    observer.next(status)
                    observer.completed()

                case .UserNotPermitted:
                    observer.failure(LocationAuthorizationError.Restricted)
                    
                case .UserDisabled:
                    observer.failure(LocationAuthorizationError.Denied)
                
                default:
                    observer.next(.NoDecisionYet)
                }
            }.disposeIn(bag)
            
            locationManager.requestWhenInUseAuthorization()
            
            BlockDisposable{
                locationManager // hold reference to it in the disposable block otherwise it's deallocated.
            }.disposeIn(bag)

            return bag
        }
    }
}
