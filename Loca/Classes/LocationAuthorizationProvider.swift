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
    case noDecisionYet
    case userNotPermitted
    case userDisabled
    case authorized(always: Bool)
    
    public static func fromClAuthorizationStatus(_ status: CLAuthorizationStatus) -> LocationAuthorizationState{
        switch(status){
        case .authorizedAlways: return .authorized(always: true)
        case .authorizedWhenInUse: return .authorized(always: false)
        case .restricted: return .userNotPermitted
        case .denied: return .userDisabled
        case .notDetermined: fallthrough
        default: return .noDecisionYet
        }
    }
    
    public static var currentState: LocationAuthorizationState{
        return fromClAuthorizationStatus(CLLocationManager.authorizationStatus())
    }
}

public enum LocationAuthorizationError: Error{
    case denied, restricted
}

public protocol LocationAuthorizationProviderType{
    var state: Property<LocationAuthorizationState> {get}
    static var stateStream: Signal1<LocationAuthorizationState> {get}
    
    func authorize() -> Signal<LocationAuthorizationState, LocationAuthorizationError>
}


public final class LocationAuthorizationProvider: LocationAuthorizationProviderType{
    
    public let state = Property<LocationAuthorizationState>(LocationAuthorizationState.currentState)
    fileprivate let bag = DisposeBag()
    
    public init(){
        LocationAuthorizationProvider.stateStream
            .bind(to:state)
            .dispose(in: bag)
    }
    
    public static var stateStream: Signal1<LocationAuthorizationState>{
        return CLLocationManager.statusStream().map { LocationAuthorizationState.fromClAuthorizationStatus($0) }
    }
    
    public func authorize() -> Signal<LocationAuthorizationState, LocationAuthorizationError>{
        
        return Signal { observer in
            
            let startingState = LocationAuthorizationState.currentState
            guard case .noDecisionYet = startingState else {
                switch(startingState){
                case .authorized(always: _):
                    observer.next(startingState)
                    observer.completed()
                case .userNotPermitted:
                    observer.failed(LocationAuthorizationError.restricted)
                case .userDisabled:fallthrough
                default:
                    observer.failed(LocationAuthorizationError.denied)
                }
                return SimpleDisposable()
            }
            
            
            let bag = DisposeBag()
            let locationManager = CLLocationManager()
            
            locationManager.reactive.authorizationStatus
                .map {LocationAuthorizationState.fromClAuthorizationStatus($0)}
                .observeNext { status in
                    switch(status){
                    case .authorized(_):
                        observer.next(status)
                        observer.completed()

                    case .userNotPermitted:
                        observer.failed(LocationAuthorizationError.restricted)
                        
                    case .userDisabled:
                        observer.failed(LocationAuthorizationError.denied)
                    
                    default:
                        observer.next(.noDecisionYet)
                    }
                }.dispose(in: bag)
            
            locationManager.requestWhenInUseAuthorization()
            
            BlockDisposable{
                _ = locationManager // hold reference to it in the disposable block otherwise it's deallocated.
            }.dispose(in: bag)

            return bag
        }
    }
}
