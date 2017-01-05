//
//  CLLocationManager+proxy.swift
//  Tacks
//
//  Created by Ian Dundas on 27/05/2016.
//  Copyright © 2016 Ian Dundas. All rights reserved.
//

import Foundation
import CoreLocation
import ReactiveKit
import Bond

extension CLLocationManager {
    public var rDelegate: ProtocolProxy {
        return protocolProxyFor(CLLocationManagerDelegate.self, setter: NSSelectorFromString("setDelegate:"))
    }
    
    public static func statusStream() -> Signal1<CLAuthorizationStatus>{
        return Signal1 { observer in
            let bag = DisposeBag()
            let locationManager = CLLocationManager()
            let delegateProxy = locationManager.rDelegate
            
            let didChangeAuthStatusSelector = #selector(CLLocationManagerDelegate.locationManager(_:didChangeAuthorizationStatus:))
            delegateProxy.streamFor(didChangeAuthStatusSelector, map: { (manager: CLLocationManager, status: CLAuthorizationStatus) -> CLAuthorizationStatus in
                return status
            })
            .observeNext { status in
                observer.next(status)
            }.disposeIn(bag)

            BlockDisposable{locationManager}.disposeIn(bag) // retain locationManager in block
            return bag
        }
    }
}
