//
//  PeripheralView.swift
//  BLEBackground
//
//  Created by Importants on 1/9/25.
//

import SwiftUI
import CoreBluetooth
import CoreLocation

struct PeripheralView: View {
    @StateObject var viewModel: PeripheralViewModel = .init()
    var body: some View {
        VStack(spacing: 32) {
            Group {
                if viewModel.isAdvertising {
                    Text("Advertising")
                }
                else if viewModel.isConnected {
                    Text("Connected")
                }
            }

            Button("AD") {
                viewModel.buttonTapped()
            }
            
            Button("broadcast") {
                viewModel.monitorBeacon()
            }
        }
    }
}

final class PeripheralViewModel: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    var locationManager: CLLocationManager!
    var region: CLBeaconRegion!
    var peripheralManager: CBPeripheralManager!
    @Published var isCanAdvertising: Bool = false
    @Published var isConnected: Bool = false
    @Published var isAdvertising: Bool = false
    var characteristic: CBMutableCharacteristic!
    
    override init() {
        super.init()
        self.locationManager = CLLocationManager()
        self.peripheralManager = CBPeripheralManager(delegate: self, queue: .global())
    }
    
    func monitorBeacon() {
        peripheralManager.add(makeService())
        
        let bundleURL = Bundle.main.bundleIdentifier!
        
        // Defines the beacon identity characteristics the device broadcasts.
        let uuid = Const.iBeaconUUID.uuidString
        let constraint = CLBeaconIdentityConstraint(uuid: UUID(uuidString: uuid)!, major: 0, minor: 0)
        region = CLBeaconRegion(beaconIdentityConstraint: constraint, identifier: bundleURL)
        
        var peripheralData = region.peripheralData(withMeasuredPower: nil) as? [String: Any]
        peripheralData?[CBAdvertisementDataServiceUUIDsKey] = [Const.ServiceUUID]
        peripheralData?[CBAdvertisementDataLocalNameKey] = "iBeacon"
        print(peripheralData)
        
        // Start broadcasting the beacon identity characteristics.
        peripheralManager.startAdvertising(peripheralData)
    }
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        Task {
            await MainActor.run {
                isCanAdvertising = peripheral.state == .poweredOn
            }
        }
    }
    
    // 데이터를 담을 Characteristics
    func makeCharacteristics() -> [CBMutableCharacteristic] {
        let characteristic = CBMutableCharacteristic(
            type: Const.peripheralUUID,
            properties: [.notify, .write, .read],
            value: nil,
            permissions: [.writeable]
        )
        
        self.characteristic = characteristic
     
        return [characteristic]
    }
    
    // Characteristics를 담을 Service
    func makeService() -> CBMutableService {
        let transferService = CBMutableService(type: Const.ServiceUUID, primary: true)
        transferService.characteristics = makeCharacteristics()
        
        return transferService
    }
    
    // startAdvertising
    func buttonTapped() {
        peripheralManager.stopAdvertising()
        guard isCanAdvertising else { return }
        
        peripheralManager.add(makeService())
        
        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "ButtonTapped",
            CBAdvertisementDataServiceUUIDsKey: [Const.ServiceUUID]
        ])
        print("Start Scanning")
        
        Task {
            await MainActor.run {
                isAdvertising = true
            }
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard let value = request.value,
                  let stringFromData = String(data: value, encoding: .utf8)
            else { continue }
            print("response = \(stringFromData)!")
            
            peripheral.respond(to: request, withResult: .success)
            peripheral.stopAdvertising()
            Task {
                await MainActor.run {
                    isAdvertising = false
                }
            }
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: (any Error)?) {
        print("didAdd")
    }
}
