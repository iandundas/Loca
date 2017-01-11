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
    
    func locationsStream(meterAccuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance) -> SafeSignal<CLLocation?>
    func locationStateStream(meterAccuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance) -> SafeSignal<LocationState>
    func accurateLocation(meterAccuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance, maximumAge: TimeInterval) -> Signal<Accuracy, LocationProviderError>
    func accurateLocationOnly(meterAccuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance, maximumAge: TimeInterval) -> Signal<CLLocation, LocationProviderError>
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
    
    
    public func locationsStream(meterAccuracy desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyNearestTenMeters, distanceFilter: CLLocationDistance = kCLDistanceFilterNone) -> SafeSignal<CLLocation?>{
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
    
    public func locationStateStream(meterAccuracy desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyNearestTenMeters, distanceFilter: CLLocationDistance = kCLDistanceFilterNone) -> SafeSignal<LocationState>{
        return SafeSignal { observer in
            let bag = DisposeBag()
            let locationManager = CLLocationManager()
            
            // Updating Locations:
            locationManager.reactive.didUpdateLocations
                .observeIn(LocaQueue.context)
                .map {$0.last}
                .observeNext {location in
                    guard let location = location else {return}
                    observer.next(LocationState.known(location))
                }.dispose(in: bag)
            
            // Catching Errors:
            locationManager.reactive.didSendError
                .map {$0 as NSError}
                .observeIn(LocaQueue.context)
                .observeNext {error in
                    switch(error.code){
                    case CLError.locationUnknown.rawValue:
                        observer.next(LocationState.error(LocationProviderError.unknown))
                    case CLError.headingFailure.rawValue:
                        observer.next(LocationState.error(LocationProviderError.cannotLocate))
                    case CLError.denied.rawValue:
                        observer.next(LocationState.error(LocationProviderError.denied))
                    default:
                        observer.next(LocationState.error(LocationProviderError.cannotLocate))
                    }
                }.dispose(in: bag)
            
            
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
            bag.add(disposable: BlockDisposable{
                DispatchQueue.main.async(execute: locationManager.stopUpdatingLocation)
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
    
    
    public func accurateLocation(meterAccuracy desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyNearestTenMeters, distanceFilter: CLLocationDistance = kCLDistanceFilterNone, maximumAge: TimeInterval = 30) -> Signal<Accuracy, LocationProviderError>{
        return Signal { observer in
            let bag = DisposeBag()
            
            self.locationStateStream(meterAccuracy: desiredAccuracy, distanceFilter: distanceFilter)
                .observeIn(LocaQueue.context)
                .observeNext { state in
                    
                    guard case let .known(location) = state,  (0 ... desiredAccuracy) ~= location.horizontalAccuracy && location.age < maximumAge
                    else {
                        switch(state){
                        case .known(let location):
                            if location.age > maximumAge{
                                print("Location received was too old (\(location.age) seconds) - dumping")
                                return
                            }
                            
                            // Known location with insufficient accuracy. Report this and keep trying:
                            print("Found location but not accurate enough (meters: \(location.horizontalAccuracy)). Still scanning..")
                            observer.next(Accuracy.inaccurate(to: location.horizontalAccuracy, at: location))
                            
                        case .error(let error):
                            if case .unknown = error{
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
                    
            }.dispose(in: bag)
            
            return bag
        }
    }
    
    // Same as above but filters the intermediate Inaccurate results
    public func accurateLocationOnly(meterAccuracy desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyNearestTenMeters, distanceFilter: CLLocationDistance = kCLDistanceFilterNone, maximumAge: TimeInterval = 30) -> Signal<CLLocation, LocationProviderError>{
        return accurateLocation(meterAccuracy: desiredAccuracy, distanceFilter: distanceFilter, maximumAge: maximumAge)
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
