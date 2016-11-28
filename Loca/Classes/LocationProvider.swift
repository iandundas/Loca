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
    
    // Too much time passed, and any retries were unsuccessful (either we never received any results or never hit the accuracy we wanted)
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

public enum Accuracy {
    case Accurate(to: CLLocationAccuracy, at: CLLocation)
    case Inaccurate(to: CLLocationAccuracy, at: CLLocation)
}

extension Accuracy: CustomDebugStringConvertible{
    public var debugDescription: String{
        switch self{
        case let .Accurate(to: accuracy, at: location):
            return "✅ accurate to \(accuracy) meters: \(location)"
        case let .Inaccurate(to: accuracy, at: location):
            return "❌ accurate only to \(accuracy) meters: \(location)"
        }
    }
}

public protocol LocationProviderType{
    func locationsStream(meterAccuracy desiredAccuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance) -> Stream<CLLocation?>
    func locationStateStream(meterAccuracy desiredAccuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance) -> Stream<LocationState>
    func accurateLocationOperation(meterAccuracy desiredAccuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance, maximumAge: NSTimeInterval?) -> Operation<Accuracy, LocationProviderError>
    func accurateLocationOnlyOperation(meterAccuracy desiredAccuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance, maximumAge: NSTimeInterval?) -> Operation<CLLocation, LocationProviderError>
}


/* TODO: Add a Stream which finds location, then stops but without completing, and periodically updates  */

public final class LocationProvider: LocationProviderType{
    
    private let bag = DisposeBag()
    public init?(){
        let authorized = CLLocationManager.authorizationStatus()
        guard authorized == .AuthorizedWhenInUse || authorized == .AuthorizedAlways else {
            print("Warning: can't start LocationProvider as we do not have permission from the User yet")
            return nil
        }
    }
    
    
    public func locationsStream(meterAccuracy desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyNearestTenMeters, distanceFilter: CLLocationDistance = kCLDistanceFilterNone) -> Stream<CLLocation?>{
        return self.locationStateStream(meterAccuracy: kCLLocationAccuracyBest, distanceFilter: distanceFilter)
            .map { (state: LocationState) -> CLLocation? in
                guard case .Known(let location) = state else { return nil }
                return location
            }
    }
    
    
    /*
     When observed, the Signal starts Location tracking
     When disposed, location tracking is ended.
     */
    
    public func locationStateStream(meterAccuracy desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyNearestTenMeters, distanceFilter: CLLocationDistance = kCLDistanceFilterNone) -> Stream<LocationState>{
        return Stream<LocationState> { observer in
            let bag = DisposeBag()
            let locationManager = CLLocationManager()
            
            // Updating Locations:
            let didUpdateLocationsSelector = #selector(CLLocationManagerDelegate.locationManager(_:didUpdateLocations:))
            locationManager.rDelegate
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
            locationManager.rDelegate
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
            
            
            locationManager.desiredAccuracy = desiredAccuracy
            locationManager.distanceFilter = distanceFilter
            
            // Starting Location Tracking:
            locationManager.startUpdatingLocation()
            
            // if a location update has already been delivered, you can query the locationManager for it immediately
            if let location = locationManager.location{
                // NB this first one could be very old. Observers should check the timestamp and see if they're happy with it or not.
                observer.next(LocationState.Known(location))
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
    
    
    public func accurateLocationOperation(meterAccuracy desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyNearestTenMeters, distanceFilter: CLLocationDistance = kCLDistanceFilterNone, maximumAge: NSTimeInterval? = 30) -> Operation<Accuracy, LocationProviderError>{
        return Operation { observer in
            let bag = DisposeBag()
            
            self.locationStateStream(meterAccuracy: desiredAccuracy, distanceFilter: distanceFilter)
                .observeIn(Queue.background.context)
                .observeNext { state in
                    
                    guard case let .Known(location) = state where  (0 ... desiredAccuracy) ~= location.horizontalAccuracy && location.age < maximumAge
                    else {
                        switch(state){
                        case .Known(let location):
                            if let maximumAge = maximumAge where location.age > maximumAge{
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
                                observer.failure(error)
                            }
                        }
                        return
                    }
                
                    // We've got a location within desired accuracy range. 🎉
                    observer.next(Accuracy.Accurate(to: location.horizontalAccuracy, at: location))
                    observer.completed()
                    
            }.disposeIn(bag)
            
            return bag
        }
    }
    
    // Same as above but filters the intermediate Inaccurate results
    public func accurateLocationOnlyOperation(meterAccuracy desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyNearestTenMeters, distanceFilter: CLLocationDistance = kCLDistanceFilterNone, maximumAge: NSTimeInterval? = 30) -> Operation<CLLocation, LocationProviderError>{
        return accurateLocationOperation().filter({ (accuracy: Accuracy) -> Bool in
            guard case .Accurate(_,_) = accuracy else {return false}
            return true
        })
        .map { accuracy in
            guard case let .Accurate(_,location) = accuracy else {fatalError()}
            return location
        }
        
    }
}
