//
//  CLLocationManager+proxy.swift
//  Tacks
//
//  Created by Ian Dundas on 27/05/2016.
//  Copyright © 2016 Ian Dundas. All rights reserved.
//

import UIKit
import CoreLocation
import ReactiveKit
import Bond

public extension ReactiveExtensions where Base: CLLocationManager {

    public var delegate: ProtocolProxy {
        return base.protocolProxy(for: CLLocationManagerDelegate.self, setter: NSSelectorFromString("setDelegate:"))
    }
    
    public var authorizationStatus: Signal<CLAuthorizationStatus, NoError>{
        let didChangeAuthStatus = #selector(CLLocationManagerDelegate.locationManager(_:didChangeAuthorization:))
        
        return delegate.signal(for: didChangeAuthStatus) { (subject: PublishSubject<CLAuthorizationStatus, NoError>, _: CLLocationManager, status: CLAuthorizationStatus) in
            subject.next(status)
        }
    }
    
    public var didUpdateLocations: Signal<[CLLocation], NoError> {
        let didUpdateLocations = #selector(CLLocationManagerDelegate.locationManager(_:didUpdateLocations:))
        
        return delegate.signal(for: didUpdateLocations) { (subject: PublishSubject<[CLLocation], NoError>, _: CLLocationManager, locations: NSArray) in
            subject.next(locations as! [CLLocation])
        }
    }
    
    public var didSendError: Signal<Error, NoError> {
        let didFailWithError = #selector(CLLocationManagerDelegate.locationManager(_:didFailWithError:))
        
        return delegate.signal(for: didFailWithError) { (subject: PublishSubject<Error, NoError>, _: CLLocationManager, error: NSError) in
            subject.next(error)
        }
    }
}

extension CLLocationManager {
    
    public static func statusStream() -> SafeSignal<CLAuthorizationStatus>{
        return SafeSignal { observer in
            let bag = DisposeBag()
            let locationManager = CLLocationManager()
            
            locationManager.reactive.authorizationStatus.observeNext { status in
                observer.next(status)
            }.dispose(in: bag)
            
            BlockDisposable{_ = locationManager}.dispose(in: bag) // retain locationManager in block
            return bag
        }
    }
}
