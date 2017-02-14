//
//  Loca.swift
//  Loca
//
//  Created by Ian Dundas on 05/01/2017.
//  Copyright © 2017 Tacks. All rights reserved.
//

import Foundation
import CoreLocation
import ReactiveKit

let LocaQueue = DispatchQueue(label: "com.iandundas.loca")

public protocol GeocodingProvider{
    static func geocodeStreetnameOperation(location: CLLocation) -> ReactiveKit.Signal<String?, NSError>
    static func geocodeShortAddressOperation(location: CLLocation) -> ReactiveKit.Signal<String?, NSError>
    static func reverseGeocodeOperation(location: CLLocation) -> ReactiveKit.Signal<[CLPlacemark], NSError>
}

extension CLGeocoder: GeocodingProvider {} // implemented in Loca

