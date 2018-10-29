//
//  ViewController.swift
//  kilolo
//
//  Created by Masatoshi SEKI on 2018/10/26.
//  Copyright © 2018 Masatoshi SEKI. All rights reserved.
//

import UIKit
import HealthKit

class ViewController: UIViewController {
    @IBOutlet weak var lastUpdatedText: UILabel!
    @IBOutlet weak var statusText: UILabel!
    
    @IBAction func doReset(_ sender: Any) {
        lastUpdatedText.text = "not yet"
        statusText.text = "rewound anchor"
        myAnchor = HKQueryAnchor.init(fromValue: 0)
        saveAnchor()
    }
    
    @IBAction func doCorrect(_ sender: Any) {
        let authStatus:HKAuthorizationStatus = healthStore.authorizationStatus(for: activeEnergyBurnedType)
        if authStatus == .sharingAuthorized {
            findAndSave()
        } else {
            let types: NSSet! = NSSet(object: activeEnergyBurnedType)
            healthStore.requestAuthorization(toShare: types as? Set<HKSampleType>, read: types as? Set<HKObjectType>) {
                success, error in
                
                if error != nil {
                    NSLog(error.debugDescription);
                    return
                }
                
                if success {
                    self.findAndSave()
                }
            }
        }
    }
    
    var activeEnergyBurnedType: HKQuantityType!
    var myAnchor: HKQueryAnchor!
    private let healthStore = HKHealthStore()

    func initText() {
        
    }
    
    func initHK() {
        activeEnergyBurnedType = HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.activeEnergyBurned)
        guard (activeEnergyBurnedType != nil) else {
            fatalError("*** Unable to get the step count type ***")
        }
        myAnchor = HKQueryAnchor.init(fromValue: 0)
        let defaults = UserDefaults.standard
        guard let it = defaults.data(forKey: "anchor") else { return }
        do {
            myAnchor = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(it) as? HKQueryAnchor
        } catch {
            // nop
        }
    }
    
    func saveAnchor() {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: self.myAnchor, requiringSecureCoding: true)
            let defaults = UserDefaults.standard
            defaults.set(data, forKey: "anchor")
        } catch {
            NSLog("encode failed")
        }
    }
    
    func saveDataFromFossil(fossil: HKQuantitySample) -> HKQuantitySample? {
        let acUnit: HKUnit = HKUnit.smallCalorie()
        let acQuantity: HKQuantity! = fossil.quantity
        let acResult: Double = acQuantity.doubleValue(for: acUnit)
        
        if acResult > 1000 {
            return nil
        }
        
        let acType: HKQuantityType = HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.activeEnergyBurned)!
        
        let quantity: HKQuantity = HKQuantity(unit: HKUnit.kilocalorie(), doubleValue: acResult)
        return HKQuantitySample(type: acType, quantity: quantity, start: fossil.startDate, end: fossil.endDate)
    }
    
    func saveActiveEnergyBurned(sample: [HKQuantitySample], completion: @escaping (Bool, Error?) -> Void) {
        let authStatus:HKAuthorizationStatus = healthStore.authorizationStatus(for: activeEnergyBurnedType)
        
        if authStatus == .sharingAuthorized {
            healthStore.save(sample, withCompletion:completion)
        }
    }
    
    func findAndSave() {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: "HKDeviceName", allowedValues: ["Fossil device"])
        
        let query = HKAnchoredObjectQuery(type: activeEnergyBurnedType,
                                          predicate: predicate,
                                          anchor: myAnchor,
                                          limit: HKObjectQueryNoLimit)
        { (query, samplesOrNil, deletedObjectsOrNil, newAnchor, errorOrNil) in
            
            guard let samples = samplesOrNil, let _ = deletedObjectsOrNil else {
                fatalError("*** An error occurred during the initial query: \(errorOrNil!.localizedDescription) ***")
            }
            
            if newAnchor != nil {
                self.myAnchor = newAnchor!
            }
            
            var saveData: [HKQuantitySample] = []
            for activeEnergyBurned: HKQuantitySample in samples as! [HKQuantitySample] {
                guard let it = self.saveDataFromFossil(fossil: activeEnergyBurned) else { continue }
                saveData.append(it)
            }
            NSLog("saveData.count \(saveData.count)" )
            if saveData.isEmpty {
                DispatchQueue.main.async {
                    self.statusText.text = "no news is good news"
                }
                return
            }
            DispatchQueue.main.async {
                self.statusText.text = "writing"
            }
                
            self.saveActiveEnergyBurned(sample: saveData, completion: {
                success, error in
                if error != nil {
                    NSLog(error.debugDescription)
                    return
                }
                if success {
                    self.saveAnchor()
                    
                    NSLog("success \(String(describing: self.myAnchor))")
                    DispatchQueue.main.async {
                        self.statusText.text = String(format: "corrected: %d items", saveData.count)
                        guard let date = saveData.last?.endDate else { return }
                        let df = DateFormatter()
                        df.dateStyle = .short
                        df.timeStyle = .short
                        self.lastUpdatedText.text = df.string(from: date)
                    }
                }
            })
        }
        statusText.text = "reading"
        healthStore.execute(query)
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        initHK()
        initText()
    }
}

