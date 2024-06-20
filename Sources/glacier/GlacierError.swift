import Foundation

public enum GlacierError: Error {
  case peripheralStoppedAdvertising
  case peripheralPairingPermissonFailure
  case peripheralInitialDiscoveryTimeout
  case peripheralConnectionLossDuringPairing
  case peripheralAutoReconnectTimeout
  case unknown(Error?)
}
