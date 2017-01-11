//
//  GeoCalculations.swift
//  Tacks
//
//  Created by Ian Dundas on 20/07/2016.
//  Copyright © 2016 Ian Dundas. All rights reserved.
//

import MapKit

// credit: http://stackoverflow.com/a/31423828
public func fittingRegionForCoordinates(_ coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
    
    guard coordinates.count > 0 else { return nil }
    
    var topLeftCoord: CLLocationCoordinate2D = CLLocationCoordinate2D()
    topLeftCoord.latitude = -90
    topLeftCoord.longitude = 180
    var bottomRightCoord: CLLocationCoordinate2D = CLLocationCoordinate2D()
    bottomRightCoord.latitude = 90
    bottomRightCoord.longitude = -180
    
    coordinates.forEach { coordinate in
        topLeftCoord.longitude = fmin(topLeftCoord.longitude, coordinate.longitude)
        topLeftCoord.latitude = fmax(topLeftCoord.latitude, coordinate.latitude)
        bottomRightCoord.longitude = fmax(bottomRightCoord.longitude, coordinate.longitude)
        bottomRightCoord.latitude = fmin(bottomRightCoord.latitude, coordinate.latitude)
    }
    
    var region: MKCoordinateRegion = MKCoordinateRegion()
    region.center.latitude = topLeftCoord.latitude - (topLeftCoord.latitude - bottomRightCoord.latitude) * 0.5
    region.center.longitude = topLeftCoord.longitude + (bottomRightCoord.longitude - topLeftCoord.longitude) * 0.5
    region.span.latitudeDelta = fabs(topLeftCoord.latitude - bottomRightCoord.latitude) * 1.4
    region.span.longitudeDelta = fabs(bottomRightCoord.longitude - topLeftCoord.longitude) * 1.4
    return region
}
