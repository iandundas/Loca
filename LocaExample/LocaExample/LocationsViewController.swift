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
        
        let operation = locationProvider.accurateLocation(meterAccuracy: 10, distanceFilter: 5, maximumAge: 10)
            .timeout(after: 15, with: LocationProviderError.timeout, on: DispatchQueue.main)
            .observeIn(DispatchQueue.main.context)
            .shareReplay()
            
        operation.observe { [weak self] event in
            switch event {
            case let .next(accuracy):
                self?.addMessage(accuracy.debugDescription)
                
            case let .failed(error):
                self?.addMessage("💔 Failure: \(error)")
                
            case .completed:
                self?.addMessage("Completed.")
            }
            }.dispose(in: reactive.bag)
        
        operation.suppressError(logging: true)
            .map { accuracy -> String in
                switch accuracy {
                case let .accurate(to: _, at: location):
                    return location.timestamp.description
                case let .inaccurate(to: _, at: location):
                    return location.timestamp.description
                }
            }
            .map { (date: String) -> String in
                return "Last updated: \(date)"
            }
            .combineLatest(with: SafeSignal<UILabel>.just(lastKnownLabel))
            .observeNext { (string: String, label: UILabel) in
                label.text = string
            }.dispose(in: reactive.bag)
    }
    
    func addMessage(_ message: String) {
        let label = UILabel()
        label.text = message
        label.numberOfLines = 0
        label.sizeToFit()
        
        stackView.insertArrangedSubview(label, at: 0)
    }
    
    
}
