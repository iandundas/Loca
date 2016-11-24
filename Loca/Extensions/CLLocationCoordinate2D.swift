//
//  CLLocationCoordinate2D.swift
//  Tacks
//
//  Created by Ian Dundas on 20/07/2016.
//  Copyright © 2016 Ian Dundas. All rights reserved.
//

import MapKit

extension CLLocationCoordinate2D: Equatable{}
public func ==(a:CLLocationCoordinate2D, b:CLLocationCoordinate2D) -> Bool{
    return a.latitude == b.latitude && b.longitude == b.longitude
}

public extension CLLocationCoordinate2D{
    public var location: CLLocation {
        return CLLocation(latitude: latitude, longitude: longitude)
    }
    public func googleMapsURL(zoomLevel zoomLevel: Int) -> NSURL?{
        return NSURL(string:"comgooglemaps://?center=\(self.latitude),\(self.longitude)&zoom=\(zoomLevel)")
    }
}

