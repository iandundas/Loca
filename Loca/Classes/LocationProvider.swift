//
//  LocationManager.swift
//  LocationManager
//
//  Created by Ian Dundas on 22/08/2015.
//  Copyright (c) 2015 Ian Dundas. All rights reserved.
//

import Foundation
import CoreLocation
import ReactiveKit

public enum LocationState{
    case Known(CLLocation)
    case Error(LocationProviderError)
}

public enum LocationProviderError: ErrorType{
    // "If the location service is unable to retrieve a location right away, it
    // reports a kCLErrorLocationUnknown error and keeps trying. In such a
    // situation, you can simply ignore the error and wait for a new event.
    case Unknown
    
    // "If a heading could not be determined because of strong interference
    // from nearby magnetic fields, this method returns kCLErrorHeadingFailure.
    case CannotLocate
    
    // "If the user denies your application’s use of the location service,
    // this method reports a kCLErrorDenied error. Upon receiving such an error, 
    // you should stop the location service.
    // @id - this should not generally happen because we ensure permissions before trying. Maybe it happens if enabling airplane mode?
    case Denied
    
    // Too much time passed, and any retries were unsuccessful
    case Timeout
    
    public var message: String{
        switch self{
        case .Timeout: return "Timed out whilst finding your location"
        case .Denied: return "GPS is denied for this app"
        case .CannotLocate: fallthrough
        case .Unknown: return "Could not determine your location"
        }
    }
}

public protocol LocationProviderType{
    var locationsStream: Stream<CLLocation?> {get}
    var locationStateStream: Stream<LocationState> {get}
    
    func accurateLocationOperation(meterAccuracy accuracy: CLLocationAccuracy) -> Operation<CLLocation, LocationProviderError>
}


public final class LocationProvider: LocationProviderType{
    
    private let bag = DisposeBag()
    public init?(){
        let authorized = CLLocationManager.authorizationStatus()
        guard authorized == .AuthorizedWhenInUse || authorized == .AuthorizedAlways else {
            print("Warning: can't start LocationProvider as we do not have permission from the User yet")
            return nil
        }
    }
    
    public var locationsStream: Stream<CLLocation?>{
        return self.locationStateStream
            .map { (state: LocationState) -> CLLocation? in
                guard case .Known(let location) = state else { return nil }
                return location
            }
    }
    
    /*
     When observed, the Signal starts Location tracking
     When disposed, location tracking is ended.
     */
    public var locationStateStream: Stream<LocationState>{
        return Stream<LocationState> { observer in
            let bag = DisposeBag()
            
            let locationManager = CLLocationManager()
            let delegateProxy = locationManager.rDelegate
            
            // Updating Locations:
            let didUpdateLocationsSelector = #selector(CLLocationManagerDelegate.locationManager(_:didUpdateLocations:))
            delegateProxy
                .streamFor(didUpdateLocationsSelector, map: { (manager: CLLocationManager, locations: NSArray) -> [CLLocation] in
                    return locations as! [CLLocation]
                })
                .observeIn(Queue.background.context)
                .map {$0.last}
                .observeNext {location in
                    guard let location = location else {return}
                    observer.next(LocationState.Known(location))
                }.disposeIn(bag)
            
            
            // Catching Errors:
            let didSendErrorSelector = #selector(CLLocationManagerDelegate.locationManager(_:didFailWithError:))
            delegateProxy
                .streamFor(didSendErrorSelector, map: { (manager: CLLocationManager, error: NSError) -> NSError in
                    return error
                })
                .observeIn(Queue.background.context)
                .observeNext {error in
                    switch(error.code){
                    case CLError.LocationUnknown.rawValue:
                        observer.next(LocationState.Error(LocationProviderError.Unknown))
                    case CLError.HeadingFailure.rawValue:
                        observer.next(LocationState.Error(LocationProviderError.CannotLocate))
                    case CLError.Denied.rawValue:
                        observer.next(LocationState.Error(LocationProviderError.Denied))
                    default:
                        observer.next(LocationState.Error(LocationProviderError.CannotLocate))
                    }
                }.disposeIn(bag)
            
            
            // Starting Location Tracking:
            locationManager.startUpdatingLocation()
            
            
            // Cleaning up:
            bag.addDisposable(BlockDisposable{
                Queue.main.async(locationManager.stopUpdatingLocation)
            })
            
            return bag
        }
    }

    
    
    /* 
        - Starts Location tracking. Fetches the current Location as an Operation
        - Completes when Location is found
        - Fails when there was an error 
     
        NB ideally you'd use something this with the following appended:
         .timeout(10, with: .CannotLocate, on: Queue.main)
         .retry(3)
     */
    public func accurateLocationOperation(meterAccuracy accuracy: CLLocationAccuracy) -> Operation<CLLocation, LocationProviderError>{
        return Operation { observer in
            let bag = DisposeBag()
            
            self.locationStateStream
                .observeIn(Queue.background.context)
                .observeNext { state in
                    guard case let .Known(location) = state where  (0 ... accuracy) ~= location.horizontalAccuracy else {
                    
                    switch(state){
                    case .Known(let location):
                        print("Found location but not accurate enough (\(location.horizontalAccuracy). Skipping..")
                        // Known location with insufficient accuracy. Just wait for the next location.
                        break
                        
                    case .Error(let error):
                        if case .Unknown = error{
                            /* > If the location service is unable to retrieve a location right away, it
                             reports a kCLErrorLocationUnknown error and keeps trying. In such a
                             situation, you can simply ignore the error and wait for a new event. */
                        }
                        else {
                            observer.failure(error)
                        }
                    }
                    return
                }
                
                // We've got a location within desired accuracy range. 🎉
                observer.next(location)
                observer.completed()
            }.disposeIn(bag)
            
            return bag
        }
    }
    
    
    }
