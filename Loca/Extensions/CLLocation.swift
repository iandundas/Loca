//
//  CLLocation.swift
//  Tacks
//
//  Created by Ian Dundas on 20/07/2016.
//  Copyright © 2016 Ian Dundas. All rights reserved.
//

import Foundation
import CoreLocation

public extension CLLocation{
    public convenience init(coordinate: CLLocationCoordinate2D){
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
