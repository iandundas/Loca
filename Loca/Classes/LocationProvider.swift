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
    case known(CLLocation)
    case error(LocationProviderError)
}

public enum LocationProviderError: Error{
    // "If the location service is unable to retrieve a location right away, it
    // reports a kCLErrorLocationUnknown error and keeps trying. In such a
    // situation, you can simply ignore the error and wait for a new event.
    case unknown
    
    // "If a heading could not be determined because of strong interference
    // from nearby magnetic fields, this method returns kCLErrorHeadingFailure.
    case cannotLocate
    
    // "If the user denies your application’s use of the location service,
    // this method reports a kCLErrorDenied error. Upon receiving such an error, 
    // you should stop the location service.
    // @id - this should not generally happen because we ensure permissions before trying. Maybe it happens if enabling airplane mode?
    case denied
    
    // Too much time passed, and any retries were unsuccessful (either we never received any results or never hit the accuracy we wanted)
    case timeout
    
    public var message: String{
        switch self{
        case .timeout: return "Timed out whilst finding your location"
        case .denied: return "GPS is denied for this app"
        case .cannotLocate: fallthrough
        case .unknown: return "Could not determine your location"
        }
    }
}

public enum Accuracy {
    case accurate(to: CLLocationAccuracy, at: CLLocation)
    case inaccurate(to: CLLocationAccuracy, at: CLLocation)
}

extension Accuracy: CustomDebugStringConvertible{
    public var debugDescription: String{
        switch self{
        case let .accurate(to: accuracy, at: location):
            return "✅ accurate to \(accuracy) meters: \(location)"
        case let .inaccurate(to: accuracy, at: location):
            return "❌ accurate only to \(accuracy) meters: \(location)"
        }
    }
}

public protocol LocationProviderType{
    func locationsStream(meterAccuracy desiredAccuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance) -> Stream
    func locationStateStream(meterAccuracy desiredAccuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance) -> Stream
    func accurateLocationOperation(meterAccuracy desiredAccuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance, maximumAge: TimeInterval?) -> Operation
    func accurateLocationOnlyOperation(meterAccuracy desiredAccuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance, maximumAge: TimeInterval?) -> Operation
}


/* TODO: Add a Stream which finds location, then stops but without completing, and periodically updates  */

public final class LocationProvider: LocationProviderType{
    
    fileprivate let bag = DisposeBag()
    public init?(){
        let authorized = CLLocationManager.authorizationStatus()
        guard authorized == .authorizedWhenInUse || authorized == .authorizedAlways else {
            print("Warning: can't start LocationProvider as we do not have permission from the User yet")
            return nil
        }
    }
    
    
    public func locationsStream(meterAccuracy desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyNearestTenMeters, distanceFilter: CLLocationDistance = kCLDistanceFilterNone) -> Signal1<CLLocation?>{
        return self.locationStateStream(meterAccuracy: kCLLocationAccuracyBest, distanceFilter: distanceFilter)
            .map { (state: LocationState) -> CLLocation? in
                guard case .known(let location) = state else { return nil }
                return location
            }
    }
    
    
    /*
     When observed, the Signal starts Location tracking
     When disposed, location tracking is ended.
     */
    
    public func locationStateStream(meterAccuracy desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyNearestTenMeters, distanceFilter: CLLocationDistance = kCLDistanceFilterNone) -> Signal1<LocationState>{
        return Signal1 { observer in
            let bag = DisposeBag()
            let locationManager = CLLocationManager()
            
            // Updating Locations:
            let didUpdateLocationsSelector = #selector(CLLocationManagerDelegate.locationManager(_:didUpdateLocations:))
            locationManager.rDelegate
                .streamFor(didUpdateLocationsSelector, map: { (manager: CLLocationManager, locations: NSArray) -> [CLLocation] in
                    return locations as! [CLLocation]
                })
                .observeIn(LocaQueue.context)
                .map {$0.last}
                .observeNext {location in
                    guard let location = location else {return}
                    observer.next(LocationState.known(location))
                }.disposeIn(bag)
            
            
            // Catching Errors:
            let didSendErrorSelector = #selector(CLLocationManagerDelegate.locationManager(_:didFailWithError:))
            locationManager.rDelegate
                .streamFor(didSendErrorSelector, map: { (manager: CLLocationManager, error: NSError) -> NSError in
                    return error
                })
                .observeIn(LocaQueue.context)
                .observeNext {error in
                    switch(error.code){
                    case CLError.LocationUnknown.rawValue:
                        observer.next(LocationState.Error(LocationProviderError.Unknown))
                    case CLError.HeadingFailure.rawValue:
                        observer.next(LocationState.Error(LocationProviderError.CannotLocate))
                    case CLError.Denied.rawValue:
                        observer.next(LocationState.Error(LocationProviderError.denied))
                    default:
                        observer.next(LocationState.Error(LocationProviderError.CannotLocate))
                    }
                }.disposeIn(bag)
            
            
            locationManager.desiredAccuracy = desiredAccuracy
            
            if distanceFilter > 0{
                locationManager.distanceFilter = distanceFilter
            }else{
                locationManager.distanceFilter = kCLDistanceFilterNone
            }
            
            // Starting Location Tracking:
            locationManager.startUpdatingLocation()
            
            // if a location update has already been delivered, you can query the locationManager for it immediately
            if let location = locationManager.location{
                // NB this first one could be very old. Observers should check the timestamp and see if they're happy with it or not.
                observer.next(LocationState.known(location))
            }
            
            // Cleaning up:
            bag.addDisposable(BlockDisposable{
                Queue.main.async(locationManager.stopUpdatingLocation)
            })
            
            return bag
        }
    }

    
    
    /* 
        - Starts Location tracking. Fetches the current Location as an Operation
        - Completes when Location is found to required accuracy
        - Fails when there was an error 
        - posts intermediate inaccurate results (.Inaccurate) which can be filtered if required.
     
        NB ideally you'd use something this with the following appended:
         .timeout(10, with: .CannotLocate, on: Queue.main)
         .retry(3)
     */
    
    
    public func accurateLocationOperation(meterAccuracy desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyNearestTenMeters, distanceFilter: CLLocationDistance = kCLDistanceFilterNone, maximumAge: TimeInterval? = 30) -> Signal<Accuracy, LocationProviderError>{
        return Operation { observer in
            let bag = DisposeBag()
            
            self.locationStateStream(meterAccuracy: desiredAccuracy, distanceFilter: distanceFilter)
                .observeIn(LocaQueue.context)
                .observeNext { state in
                    
                    guard case let .known(location) = state,  (0 ... desiredAccuracy) ~= location.horizontalAccuracy && location.age < maximumAge
                    else {
                        switch(state){
                        case .known(let location):
                            if let maximumAge = maximumAge, location.age > maximumAge{
                                print("Location received was too old (\(location.age) seconds) - dumping")
                                return
                            }
                            
                            // Known location with insufficient accuracy. Report this and keep trying:
                            print("Found location but not accurate enough (meters: \(location.horizontalAccuracy)). Still scanning..")
                            observer.next(Accuracy.Inaccurate(to: location.horizontalAccuracy, at: location))
                            
                        case .Error(let error):
                            if case .Unknown = error{
                                /* > If the location service is unable to retrieve a location right away, it
                                 reports a kCLErrorLocationUnknown error and keeps trying. In such a
                                 situation, you can simply ignore the error and wait for a new event. */
                            }
                            else {
                                observer.failed(error)
                            }
                        }
                        return
                    }
                
                    // We've got a location within desired accuracy range. 🎉
                    observer.next(Accuracy.accurate(to: location.horizontalAccuracy, at: location))
                    observer.completed()
                    
            }.disposeIn(bag)
            
            return bag
        }
    }
    
    // Same as above but filters the intermediate Inaccurate results
    public func accurateLocationOnlyOperation(meterAccuracy desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyNearestTenMeters, distanceFilter: CLLocationDistance = kCLDistanceFilterNone, maximumAge: TimeInterval? = 30) -> Signal<CLLocation, LocationProviderError>{
        return accurateLocationOperation(meterAccuracy: desiredAccuracy, distanceFilter: distanceFilter, maximumAge: maximumAge)
            .filter { (accuracy: Accuracy) -> Bool in
                guard case .accurate(_,_) = accuracy else {return false}
                return true
            }
            .map { accuracy in
                guard case let .accurate(_,location) = accuracy else {fatalError()}
                return location
            }
    }
}
