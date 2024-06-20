import CoreBluetooth
import Foundation

public protocol CentralBluetoothInteractorConfigurable {
  var centralManagerInitializationOptions: [String : Any]? { get }
  var peripheralScanningOptions: [String : Any]? { get }
  var peripheralScanningRequiredServices: [CBUUID]? { get }
  var autoReconnectTimeout: DispatchQueue.SchedulerTimeType.Stride { get }
  var initialDiscoveryTimeout: DispatchQueue.SchedulerTimeType.Stride { get }
}

public struct DefaultBluetoothInteractorOptions: CentralBluetoothInteractorConfigurable {
  public let centralManagerInitializationOptions: [String : Any]?
  public let peripheralScanningOptions: [String : Any]?
  public let peripheralScanningRequiredServices: [CBUUID]?
  public let autoReconnectTimeout: DispatchQueue.SchedulerTimeType.Stride
  public let initialDiscoveryTimeout: DispatchQueue.SchedulerTimeType.Stride
  
  public init(centralManagerInitializationOptions: [String : Any]? = nil,
              peripheralScanningOptions: [String : Any]? = nil,
              peripheralScanningRequiredServices: [CBUUID]? = nil,
              autoReconnectTimeout: DispatchQueue.SchedulerTimeType.Stride = 30.0,
              initialDiscoveryTimeout: DispatchQueue.SchedulerTimeType.Stride = 30.0) {
    self.centralManagerInitializationOptions = centralManagerInitializationOptions
    self.peripheralScanningOptions = peripheralScanningOptions
    self.peripheralScanningRequiredServices = peripheralScanningRequiredServices
    self.autoReconnectTimeout = autoReconnectTimeout
    self.initialDiscoveryTimeout = initialDiscoveryTimeout
  }
}
