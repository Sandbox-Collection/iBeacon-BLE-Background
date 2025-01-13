//
//  CentralView.swift
//  BLEBackground
//
//  Created by Importants on 1/9/25.
//

import SwiftUI
import CoreBluetooth
import CoreLocation

struct CentralView: View {
    @StateObject var viewModel: CentralViewModel = .init()
    
    var body: some View {
        VStack(spacing: 32) {
            Text(viewModel.isInside ? "In" : "Out")
            Group {
                if viewModel.isScanning {
                    Text("Scanning")
                }
                else if viewModel.isConnected {
                    Text("Connected")
                }
            }
            .foregroundStyle(.white)

            Button("scan") {
                viewModel.startMonitoring()
            }
        }
    }
}

final class CentralViewModel: NSObject, ObservableObject, CBCentralManagerDelegate {
    var locationManager = CLLocationManager()
    var beaconConstraints = [CLBeaconIdentityConstraint: [CLBeacon]]()
    var beacons = [CLProximity: [CLBeacon]]()
    var centralManager: CBCentralManager!
    @Published var isInside: Bool = false
    @Published var isCanScanning: Bool = false
    @Published var isConnected: Bool = false
    @Published var isScanning: Bool = false
    private var connectedPeripheral: CBPeripheral? = nil
    var characteristic: CBCharacteristic!
    
    override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: .global(qos: .default))
        locationManager.delegate = self
    }
    
    func startMonitoring() {
        self.locationManager.requestAlwaysAuthorization()
        
        // Create a new constraint and add it to the dictionary.
        let uuid = Const.iBeaconUUID.uuidString
        let constraint = CLBeaconIdentityConstraint(uuid: UUID(uuidString: uuid)!)
        let beaconRegion = CLBeaconRegion(beaconIdentityConstraint: constraint, identifier: uuid)
        self.locationManager.startMonitoring(for: beaconRegion)
        print("Start")
    }
    
    func scanning() {
        guard isCanScanning, isScanning == false else { return }
        isScanning = true
        centralManager.scanForPeripherals(
            withServices: [Const.ServiceUUID],
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true // 중복 검색 가능
            ]
        )
        print("Start Scanning")
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task {
            await MainActor.run {
                isCanScanning = central.state == .poweredOn
            }
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("name: \(String(describing: peripheral.name))")
        print("rssi: \(RSSI)")
        
        if -40..<0 ~= RSSI.intValue {
            connectedPeripheral = peripheral
            central.connect(peripheral)
            central.stopScan()
            Task {
                await MainActor.run {
                    isCanScanning = false
                }
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        connectedPeripheral = nil
        Task { @MainActor in
            isConnected = false
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        print("didDisconnectPeripheral")
        connectedPeripheral = nil
        Task { @MainActor in
            isConnected = false
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task {
            await MainActor.run {
                isConnected = true
            }
        }
        print("Connecting")
        peripheral.delegate = self
        peripheral.discoverServices([Const.ServiceUUID])
    }
}

extension CentralViewModel: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didFailRangingFor beaconConstraint: CLBeaconIdentityConstraint, error: any Error) {
        print("didFailRangingFor")
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        print("didFailWithError")
    }
    
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: any Error) {
        print("monitoringDidFailFor")
    }
    
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        let beaconRegion = region as? CLBeaconRegion
        Task {
            await MainActor.run {
                isInside = state == .inside
            }
        }
        
        if state == .inside {
            // Start ranging when inside a region.
            
            print("inside")
            manager.startRangingBeacons(satisfying: beaconRegion!.beaconIdentityConstraint)
        } else {
            // Stop ranging when not inside a region.
            print("outside")
            manager.stopRangingBeacons(satisfying: beaconRegion!.beaconIdentityConstraint)
        }
    }
    
    /// - Tag: didRange
    func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying beaconConstraint: CLBeaconIdentityConstraint) {
        /*
         Beacons are categorized by proximity. A beacon can satisfy
         multiple constraints and can be displayed multiple times.
         */
        
        for beacon in beacons {
            if beacon.proximity == .immediate {
                scanning()
            }
        }
    }
    
    
    // 이것으로 구분하기
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print("exit")
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print("enter")
    }
}

extension CentralViewModel: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else { return }
        if let service = services.first {
            print("Discovered service: \(service.uuid)")
            peripheral.discoverCharacteristics(
                [Const.peripheralUUID],
                for: service
            )
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        if let error = error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        
        guard let foundCharacteristics = service.characteristics else { return }
        
        for foundCharacteristic in foundCharacteristics {
            if foundCharacteristic.uuid == Const.peripheralUUID,
               foundCharacteristic.properties.contains(.write) {
                // 연결 후 Write > Response > Disconnected
                characteristic = foundCharacteristic
                let data = "WritingData".data(using: .utf8)!
                peripheral.writeValue(data, for: characteristic, type: .withResponse)
                print("writing")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard error == nil
        else {
            print("Failed to send Data, waiting for ready signal \(String(describing: error))")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        print("Successfully sent Data")
        centralManager.cancelPeripheralConnection(peripheral)
    }
}
