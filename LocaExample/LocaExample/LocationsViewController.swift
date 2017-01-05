//
//  LocationsViewController.swift
//  LocaExample
//
//  Created by Ian Dundas on 24/11/2016.
//  Copyright © 2016 Tacks. All rights reserved.
//

import UIKit
import Loca
import ReactiveKit


class LocationsViewController: UIViewController{
    
    var locationProvider: LocationProvider? = nil
    
    @IBOutlet var lastKnownLabel: UILabel!
    @IBOutlet var stackView: UIStackView!
    
    @IBAction func didTapStart(_ sender: AnyObject) {
        start()
    }
    
    func start() {
        guard let locationProvider = locationProvider else {return}
        
        let operation = locationProvider.accurateLocationOperation(meterAccuracy: 10, distanceFilter: 5, maximumAge: 10)
            .timeout(15, with: LocationProviderError.Timeout, on: Queue.main)
            .observeIn(Queue.main.context)
            .shareReplay()
            
        operation.observe { [weak self] event in
            switch event {
            case let .Next(accuracy):
                self?.addMessage(accuracy.debugDescription)
                
            case let .Failure(error):
                self?.addMessage("💔 Failure: \(error)")
                
            case .Completed:
                self?.addMessage("Completed.")
            }
        }.disposeIn(rBag)
        
        operation
            .toStream(justLogError: false)
            .map { accuracy -> String in
                switch accuracy {
                case let .Accurate(to: _, at: location):
                    return location.timestamp.description
                case let .Inaccurate(to: _, at: location):
                    return location.timestamp.description
                }
            }
            .map {"Last updated: \($0)"}
            .combineLatestWith(Stream<UILabel>.just(lastKnownLabel))
            .observeNext { (string, label) in
                label.text = string
            }.disposeIn(rBag)
    }
    
    func addMessage(_ message: String) {
        let label = UILabel()
        label.text = message
        label.numberOfLines = 0
        label.sizeToFit()
        
        stackView.insertArrangedSubview(label, at: 0)
    }
    
    
}
