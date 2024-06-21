@testable import glacier
import XCTest
import CoreBluetooth
import Combine


class CentralBluetoothInteractorTests: XCTestCase {
  private var centralManager: MockCBCentralManager!
  private var centralBluetoothInteractor: CentralBluetoothInteractor!
  private var cancellables: Set<AnyCancellable>!
  
  override func setUp() {
    super.setUp()
    cancellables = Set<AnyCancellable>()
    centralManager = MockCBCentralManager()
    centralBluetoothInteractor = CentralBluetoothInteractor(centralManager: centralManager,
                                                            peripheralCommunication: MockPeripheralInitialCommunicator())
  }
  
  // MARK: serverState
  func test_givenCBManager_whenUnderlyingServerStateChanges_shouldBeReflected() throws {
    let expectation = self.expectation(description: "serverState changes are not updated accordingly")
    expectation.expectedFulfillmentCount = 2
    
    let mockPeripheral = MockPeripheral.dummyPeripheral(identifier: "00000000-0000-0000-0000-000000000000")

    centralBluetoothInteractor.serverState
      .combineLatest(centralBluetoothInteractor.advertisingPeripherals.dropFirst())
      .collect(3)
      .sink(receiveValue: { result in
        let advertisingPeripheralIds = result.map { $0.1.map { $0.cbPeripheral.identifier }}
        
        // Emission #1 Result
        XCTAssertEqual(result[0].0, .poweredOn)
        XCTAssertEqual(advertisingPeripheralIds[0], [mockPeripheral.cbPeripheral.identifier])
        
        // Emission #2 Result
        XCTAssertEqual(result[1].0, .resetting)
        XCTAssertEqual(advertisingPeripheralIds[1], [mockPeripheral.cbPeripheral.identifier])
        
        // Clearing the peripherals is only done as a side effect of .resetting state,
        // which updates advertisingPeripherals after serverState is updated.
        // Therefore those two streams are emitting at a different time
        XCTAssertEqual(result[2].0, .resetting)
        XCTAssertEqual(advertisingPeripheralIds[2], [])
        
        expectation.fulfill()
      })
      .store(in: &cancellables)
    
    centralBluetoothInteractor.serverState
      .combineLatest(centralBluetoothInteractor.allPeripherals.dropFirst())
      .collect(3)
      .sink(receiveValue: { result in
        let allPeripheralIds = result.map { $0.1.values.map { $0.0.cbPeripheral.identifier }}
        
        // Emission #1 Result
        XCTAssertEqual(result[0].0, .poweredOn)
        XCTAssertEqual(allPeripheralIds[0], [mockPeripheral.cbPeripheral.identifier])
        
        // Emission #2 Result
        XCTAssertEqual(result[1].0, .resetting)
        XCTAssertEqual(allPeripheralIds[1], [mockPeripheral.cbPeripheral.identifier])
        
        // Clearing the peripherals is only done as a side effect of .resetting state,
        // which updates allPeripherals after serverState is updated.
        // Therefore those two streams are emitting at a different time
        XCTAssertEqual(result[2].0, .resetting)
        XCTAssertEqual(allPeripheralIds[2], [])
        
        expectation.fulfill()
      })
      .store(in: &cancellables)
    
    // Emission #1 - Adding a dummy peripheral to have at least one advertising peripheral
    centralBluetoothInteractor.reactPeripheralDiscovery(peripheral: mockPeripheral)
    // Emission #2 - Sending any other state then .poweredOn, should clear the peripherals
    centralBluetoothInteractor.updateServerState(state: .resetting)
    
    waitForExpectations(timeout: 10)
  }
  
  // MARK: isScanning
  func test_givenInteractor_thenShouldReflectUnderlyingInitialScanningState() {
    let expectation = self.expectation(description: "isScanning observable is not updated accordingly")
    
    centralManager.isScanning = true
    
    centralBluetoothInteractor.isScanning
      .sink(receiveValue: {
        XCTAssertTrue($0)
        expectation.fulfill()
      })
      .store(in: &cancellables)
    
    waitForExpectations(timeout: 10)
  }
  
  // MARK: scanForPeripherals
  func test_givenInteractor_whenUnderlyingNotScanning_andPoweredOn_andStartsScanning_thenShouldUpdateScanningAccordingly() {
    let expectation = self.expectation(description: "scanning for peripherals test failed")
    
    centralBluetoothInteractor.isScanning
      .collect(2)
      .sink(receiveValue: {
        XCTAssertEqual($0, [false, true])
        XCTAssertEqual(self.centralManager.calledMethods, ["scanForPeripherals(withServices:options:)"])
        
        expectation.fulfill()
      })
      .store(in: &cancellables)
    
    centralBluetoothInteractor.scanForPeripherals()
    
    waitForExpectations(timeout: 10)
  }
  
  func test_givenInteractor_whenUnderlyingNotScanning_andPoweredOff_andStartsScanning_thenShouldUpdateScanningAccordingly() {
    let expectation = self.expectation(description: "scanning for peripherals test failed")
    
    centralManager.serverState = .poweredOff
    
    centralBluetoothInteractor.isScanning
      .collect(1)
      .sink(receiveValue: {
        XCTAssertEqual($0, [false])
        XCTAssertEqual(self.centralManager.calledMethods, [])
        expectation.fulfill()
      })
      .store(in: &cancellables)
    
    // Underlying is .poweredOff, should not start scanning
    centralBluetoothInteractor.scanForPeripherals()
    
    waitForExpectations(timeout: 10)
  }
  
  func test_givenInteractor_whenUnderlyingAlreadyScanning_andPoweredOn_andStartsScanning_thenShouldUpdateScanningAccordingly() {
    let expectation = self.expectation(description: "scanning for peripherals test failed")
    
    centralManager.isScanning = true
    
    centralBluetoothInteractor.isScanning
      .collect(1)
      .sink(receiveValue: {
        // Already scanning before, therefore no new calls to the underlying layer to initiate scan
        XCTAssertEqual($0, [true])
        XCTAssertEqual(self.centralManager.calledMethods, [])
        expectation.fulfill()
      })
      .store(in: &cancellables)
    
    centralBluetoothInteractor.scanForPeripherals()
    
    waitForExpectations(timeout: 10)
  }
  
  // MARK: stopScan
  func test_givenInteractor_whenUnderlyingAlreadyScanning_thenShouldUpdateScanningAccordingly() {
    let expectation = self.expectation(description: "stopscan test failed")
    expectation.expectedFulfillmentCount = 2
    
    centralManager.isScanning = true
    
    centralBluetoothInteractor.isScanning
      .collect(2)
      .sink(receiveValue: {
        XCTAssertEqual($0, [true, false])
        expectation.fulfill()
      })
      .store(in: &cancellables)
    
    centralBluetoothInteractor.advertisingPeripherals
      .collect(3)
      .sink(receiveValue: {
        let advertisingPeripheralCounts = $0.map { $0.count }
        XCTAssertEqual(advertisingPeripheralCounts, [0, 1, 0])
        expectation.fulfill()
      })
      .store(in: &cancellables)
    
    centralBluetoothInteractor.reactPeripheralDiscovery(peripheral: MockPeripheral.dummyPeripheral())
    centralBluetoothInteractor.stopScan()
    XCTAssertEqual(self.centralManager.calledMethods, ["stopScan()"])
    
    waitForExpectations(timeout: 10)
  }
  
  // MARK: didDiscoverPeripheral
  func test_givenUnderlyingManager_whenDiscoversNewPeripherals_thenShouldUpdateAdvertisingPeripherals() {
    let expectation = self.expectation(description: "reacting peripheral discovery test failed")
    expectation.expectedFulfillmentCount = 2
    let mockPeripheral = MockPeripheral.dummyPeripheral(identifier: "00000000-0000-0000-0000-000000000000")

    centralBluetoothInteractor.advertisingPeripherals
      .map { $0.map{ $0.cbPeripheral.identifier} }
      .collect(2)
      .sink(receiveValue: { advertisingPeripheralIds in
        XCTAssertEqual(advertisingPeripheralIds, [[], [mockPeripheral.cbPeripheral.identifier]])
        expectation.fulfill()
      })
      .store(in: &cancellables)
    
    centralBluetoothInteractor.readyToControlPeripherals
      .map { $0.map{ $0.cbPeripheral.identifier} }
      .collect(1)
      .sink(receiveValue: { readyToControlPeripheralIds in
        // readyToControlPeripherals shouldn't be affected once a peripheral is discovered
        XCTAssertEqual(readyToControlPeripheralIds, [[]])
        expectation.fulfill()
      })
      .store(in: &cancellables)
    
    centralBluetoothInteractor.reactPeripheralDiscovery(peripheral: mockPeripheral)
    
    waitForExpectations(timeout: 10)
  }
  
  // MARK: connect
  func test_givenPeripheral_whenConnectionInitiated_andAlreadyPaired_thenShouldReturnImmediately() {
    let expectation = self.expectation(description: "connection to already paired preipheral test has failed")
    expectation.expectedFulfillmentCount = 2
    
    let peripheral = MockPeripheral.dummyPeripheral(identifier: "00000000-0000-0000-0000-000000000000")
    peripheral.pairingState = .paired
    
    centralBluetoothInteractor.connect(peripheral, options: [:])
      .sink {
        if case .failure = $0 {
          XCTFail("should not finish with failure")
        } else {
          expectation.fulfill()
        }
      }
  receiveValue: { peripheral in
    XCTAssertEqual(peripheral.cbPeripheral.identifier.uuidString, "00000000-0000-0000-0000-000000000000")
    // No connection request should be sent to the underlying manager
    XCTAssertEqual(self.centralManager.calledMethods, [])
  }
  .store(in: &cancellables)
    
    centralBluetoothInteractor.readyToControlPeripherals
      .map { $0.map{ $0.cbPeripheral.identifier } }
      .collect(1)
      .sink(receiveValue: { readyToControlPeripheralIds in
        XCTAssertEqual(readyToControlPeripheralIds, [[peripheral.cbPeripheral.identifier]])
        expectation.fulfill()
      })
      .store(in: &cancellables)
    
    waitForExpectations(timeout: 10)
  }
  
  func test_givenPeripheral_whenConnectionInitiated_andWaitingForResponse_andAlsoAnotherPeripheralResponds_thenOnlyIntendedPeripheralShouldBeSubscribed() {
    let expectation = self.expectation(description: "connection to a specific peripheral while getting response for another one fails")
    expectation.expectedFulfillmentCount = 3
    
    let peripheral1 = MockPeripheral.dummyPeripheral(identifier: "00000000-0000-0000-0000-000000000000")
    let peripheral2 = MockPeripheral.dummyPeripheral(identifier: "10000000-0000-0000-0000-000000000000")

    // ------- Subscriptions --------
    
    centralBluetoothInteractor.advertisingPeripherals
      .map { $0.count }
      .collect(5)
      .sink(receiveValue: { advertisingPeripheralCount in
        XCTAssertEqual(advertisingPeripheralCount, [0, 1, 2, 1, 0])
        expectation.fulfill()
      })
      .store(in: &cancellables)
    
    centralBluetoothInteractor.connect(peripheral1, options: [:])
      .sink {
        if case .failure = $0 {
          XCTFail("should not fail with an error")
        }
      }
  receiveValue: { peripheral in
    XCTAssertEqual(peripheral.cbPeripheral.identifier, peripheral1.cbPeripheral.identifier)
    expectation.fulfill()
  }
  .store(in: &cancellables)
    
    // successful peripheral connection should move peripherals from .advertising to .readyToControl one by one
    centralBluetoothInteractor.readyToControlPeripherals
      .map { $0.count }
      .collect(3)
      .sink(receiveValue: { readyToControlPeripheralCount in
        XCTAssertEqual(readyToControlPeripheralCount, [0, 1, 2])
        expectation.fulfill()
      })
      .store(in: &cancellables)
    
    // ---------- Test input -----------
    
    // Add both peripherals to advertising toys first. Which should increase the count from 0 to 2 step by step
    centralBluetoothInteractor.reactPeripheralDiscovery(peripheral: peripheral1)
    centralBluetoothInteractor.reactPeripheralDiscovery(peripheral: peripheral2)
    
    // connecting to peripheral2 should not trigger subscription for peripheral1 above
    centralBluetoothInteractor.reactPeripheralConnection(peripheral: peripheral2.cbPeripheral)
    // Simulating successful pairing validation for peripheral2
    peripheral2.pairingValidationStream.send(peripheral2)
    
    // This should be the actual trigger for peripheral1 subscription
    centralBluetoothInteractor.reactPeripheralConnection(peripheral: peripheral1.cbPeripheral)
    // Simulating successful pairing validation for peripheral1
    peripheral1.pairingValidationStream.send(peripheral1)
    
    waitForExpectations(timeout: 10)
  }
  
  func test_givenPeripheral_whenConnectionInitiated_thenOnlyTheFirstInputInThePipelineShouldReport() {
    let expectation = self.expectation(description: "connection to a specific peripheral while getting response for another one fails")
    
    let peripheral1 = MockPeripheral.dummyPeripheral(identifier: "00000000-0000-0000-0000-000000000000")

    // ------- Subscriptions --------
    
    centralBluetoothInteractor.connect(peripheral1, options: [:])
      .handleEvents(receiveCompletion: { _ in
        expectation.fulfill()
      })
      .sink {
        if case .failure = $0 {
          XCTFail("should not fail with an error")
        }
      }
  receiveValue: { peripheral in
    XCTAssertEqual(peripheral.cbPeripheral.identifier, peripheral1.cbPeripheral.identifier)
    // Sending another pairing validation input shouldn't matter. `.first()` should terminate the subscription
    peripheral1.pairingValidationStream.send(peripheral1)
  }
  .store(in: &cancellables)
    
    // ---------- Test input -----------
    
    centralBluetoothInteractor.reactPeripheralDiscovery(peripheral: peripheral1)
    
    // Sending multiple pairing validation results
    centralBluetoothInteractor.reactPeripheralConnection(peripheral: peripheral1.cbPeripheral)
    peripheral1.pairingValidationStream.send(peripheral1)
    
    waitForExpectations(timeout: 10)
  }
  
  func test_givenPeripheral_whenConnectionInitiated_andWaitingForResponse_andOnlyAnotherPeripheralResponds_thenIntendedPeripheralShoudTimeoutWhileWaiting() {
    let expectation = self.expectation(description: "connection to a specific peripheral while expecting a timeout, test fails")
    expectation.expectedFulfillmentCount = 3
    
    centralBluetoothInteractor = CentralBluetoothInteractor(
      centralManager: centralManager,
      peripheralCommunication: MockPeripheralInitialCommunicator(),
      options: MockInteractorOptions(autoReconnectTimeout: 30, initialDiscoveryTimeout: 1) //Test timeout has to be greater than this!
    )
    let peripheral1 = MockPeripheral.dummyPeripheral(identifier: "00000000-0000-0000-0000-000000000000")
    let peripheral2 = MockPeripheral.dummyPeripheral(identifier: "10000000-0000-0000-0000-000000000000")

    // ------- Subscriptions --------
    
    // Connection subscription for peripheral1
    centralBluetoothInteractor.connect(peripheral1, options: [:])
      .sink {
        if case let .failure(error) = $0,
           case GlacierError.peripheralInitialDiscoveryTimeout = error {
          XCTAssertEqual(peripheral1.calledMethods, [])
          expectation.fulfill()
        } else {
          XCTFail("should not complete succesfully")
        }
      }
  receiveValue: { peripheral in
    XCTFail("should not succesfully pair to given peripheral")
  }
  .store(in: &cancellables)
    
    // Connection subscription for peripheral2
    centralBluetoothInteractor.connect(peripheral2, options: [:])
      .sink {
        if case .failure = $0 {
          XCTFail("should not fail with an error")
        }
      }
  receiveValue: { peripheral in
    XCTAssertEqual(peripheral2.calledMethods, ["validatePairing()"])
    XCTAssertEqual(peripheral.cbPeripheral.identifier, peripheral2.cbPeripheral.identifier)
  }
  .store(in: &cancellables)
    
    centralBluetoothInteractor.advertisingPeripherals
      .map { $0.count }
      .collect(4)
      .sink(receiveValue: { advertisingPeripheralCount in
        XCTAssertEqual(advertisingPeripheralCount, [0, 1, 2, 1])
        expectation.fulfill()
      })
      .store(in: &cancellables)
    
    centralBluetoothInteractor.readyToControlPeripherals
      .map { $0.count }
      .collect(2)
      .sink(receiveValue: { readyToControlPeripheralCount in
        XCTAssertEqual(readyToControlPeripheralCount, [0, 1])
        expectation.fulfill()
      })
      .store(in: &cancellables)
    
    // --------- Test input ---------
    
    // Add both peripherals to advertising toys first
    centralBluetoothInteractor.reactPeripheralDiscovery(peripheral: peripheral1)
    centralBluetoothInteractor.reactPeripheralDiscovery(peripheral: peripheral2)
    
    // connecting to peripheral2 should not interfere with the subscription above
    centralBluetoothInteractor.reactPeripheralConnection(peripheral: peripheral2.cbPeripheral)
    // Simulating successful pairing validation for peripheral2 not peripheral1
    peripheral2.pairingValidationStream.send(peripheral2)
    
    waitForExpectations(timeout: 10)
  }
  
  func test_givenPeripheral_whenConnectionInitiated_andValidationFailsWithKnownError_thenConnectionShouldFailWithSameError() {
    let expectation = self.expectation(description: "connection to a specific peripheral while expecting a filed pairing validation test fails")
    expectation.expectedFulfillmentCount = 3
    
    let peripheral1 = MockPeripheral.dummyPeripheral(identifier: "00000000-0000-0000-0000-000000000000")
    let peripheral2 = MockPeripheral.dummyPeripheral(identifier: "10000000-0000-0000-0000-000000000000")

    // ------- Subscriptions --------
    
    centralBluetoothInteractor.advertisingPeripherals
      .map { $0.count }
      .collect(3)
      .sink(receiveValue: { advertisingPeripheralCount in
        // None of the peripherals should be readyToControl
        XCTAssertEqual(advertisingPeripheralCount, [0, 1, 2])
        expectation.fulfill()
      })
      .store(in: &cancellables)
    
    centralBluetoothInteractor.connect(peripheral1, options: [:])
      .sink {
        XCTAssertEqual(self.centralManager.calledMethods, ["connect(_:options:)", "cancelConnection(peripheral:)"])
        XCTAssertEqual(peripheral1.calledMethods, ["validatePairing()", "resetPairingState()"])
        
        if case let .failure(error) = $0,
           case GlacierError.peripheralConnectionLossDuringPairing = error {
          expectation.fulfill()
        } else {
          XCTFail("should not fail with another error or finish")
        }
      }
  receiveValue: { peripheral in
    XCTFail("should not connect succesfully")
  }
  .store(in: &cancellables)
    
    // successful peripheral connection should move peripherals from .advertising to .readyToControl one by one
    centralBluetoothInteractor.readyToControlPeripherals
      .map { $0.count }
      .collect(1)
      .sink(receiveValue: { readyToControlPeripheralCount in
        XCTAssertEqual(readyToControlPeripheralCount, [0])
        expectation.fulfill()
      })
      .store(in: &cancellables)
    
    // ---------- Test input -----------
    
    centralBluetoothInteractor.reactPeripheralDiscovery(peripheral: peripheral1)
    centralBluetoothInteractor.reactPeripheralDiscovery(peripheral: peripheral2)
    
    centralBluetoothInteractor.reactPeripheralConnection(peripheral: peripheral1.cbPeripheral)
    // Simulating successful pairing validation for peripheral1
    peripheral1.pairingValidationStream.send(completion: .failure(GlacierError.peripheralConnectionLossDuringPairing))
    
    waitForExpectations(timeout: 10)
  }
  
  func test_givenPeripheral_whenConnectionInitiated_andValidationFailsWithUnknownError_thenConnectionShouldFailWithSameError() {
    let expectation = self.expectation(description: "connection to a specific peripheral while expecting a failed pairing validation  with unknown error, test fails")
    expectation.expectedFulfillmentCount = 3
    
    let peripheral1 = MockPeripheral.dummyPeripheral(identifier: "00000000-0000-0000-0000-000000000000")
    let peripheral2 = MockPeripheral.dummyPeripheral(identifier: "10000000-0000-0000-0000-000000000000")

    // ------- Subscriptions --------
    
    centralBluetoothInteractor.advertisingPeripherals
      .map { $0.count }
      .collect(3)
      .sink(receiveValue: { advertisingPeripheralCount in
        // None of the peripherals should be readyToControl
        XCTAssertEqual(advertisingPeripheralCount, [0, 1, 2])
        expectation.fulfill()
      })
      .store(in: &cancellables)
    
    centralBluetoothInteractor.connect(peripheral1, options: [:])
      .sink {
        XCTAssertEqual(self.centralManager.calledMethods, ["connect(_:options:)", "cancelConnection(peripheral:)"])
        XCTAssertEqual(peripheral1.calledMethods, ["validatePairing()", "resetPairingState()"])
        
        if case let .failure(error) = $0,
           case let GlacierError.unknown(underlyingError) = error,
           underlyingError is MockError {
          expectation.fulfill()
        } else {
          XCTFail("should not fail with another error or finish")
        }
      }
  receiveValue: { peripheral in
    XCTFail("should not connect succesfully")
  }
  .store(in: &cancellables)
    
    centralBluetoothInteractor.readyToControlPeripherals
      .map { $0.count }
      .collect(1)
      .sink(receiveValue: { readyToControlPeripheralCount in
        XCTAssertEqual(readyToControlPeripheralCount, [0])
        expectation.fulfill()
      })
      .store(in: &cancellables)
    
    // ---------- Test input -----------
    
    // Add both peripherals to advertising toys first. Which should increase the count from 0 to 2 step by step
    centralBluetoothInteractor.reactPeripheralDiscovery(peripheral: peripheral1)
    centralBluetoothInteractor.reactPeripheralDiscovery(peripheral: peripheral2)
    
    centralBluetoothInteractor.reactPeripheralConnection(peripheral: peripheral1.cbPeripheral)
    // Simulating successful pairing validation for peripheral1
    peripheral1.pairingValidationStream.send(completion: .failure(MockError.dummy))
    
    waitForExpectations(timeout: 10)
  }
  
  func test_givenPeripheral_whenConnectionInitiated_andFailsToConnectWithUnderlyingError_thenConnectionShouldFail_andNoPairingValidationShouldbePerformed() {
    let expectation = self.expectation(description: "connection to a specific peripheral while expecting a failed pairing validation  with unknown error, test fails")
    expectation.expectedFulfillmentCount = 3
    
    let peripheral = MockPeripheral.dummyPeripheral(identifier: "00000000-0000-0000-0000-000000000000")

    // ------- Subscriptions --------
    
    centralBluetoothInteractor.advertisingPeripherals
      .map { $0.count }
      .collect(2)
      .sink(receiveValue: { advertisingPeripheralCount in
        // No peripheral should be readyToControl
        XCTAssertEqual(advertisingPeripheralCount, [0, 1])
        expectation.fulfill()
      })
      .store(in: &cancellables)
    
    centralBluetoothInteractor.connect(peripheral, options: [:])
      .dropFirst(1)
      .sink {
        XCTAssertEqual(self.centralManager.calledMethods, ["connect(_:options:)", "cancelConnection(peripheral:)"])
        XCTAssertEqual(peripheral.calledMethods, ["resetPairingState()"])
        
        if case let .failure(error) = $0,
           case let GlacierError.unknown(underlyingError) = error,
           underlyingError is MockError {
          expectation.fulfill()
        } else {
          XCTFail("should not fail with another error or finish")
        }
      }
  receiveValue: { peripheral in
    XCTFail("should not connect succesfully")
  }
  .store(in: &cancellables)
    
    centralBluetoothInteractor.readyToControlPeripherals
      .map { $0.count }
      .collect(1)
      .sink(receiveValue: { readyToControlPeripheralCount in
        XCTAssertEqual(readyToControlPeripheralCount, [0])
        expectation.fulfill()
      })
      .store(in: &cancellables)
    
    // ---------- Test input -----------
    
    // Add both peripherals to advertising toys first. Which should increase the count from 0 to 2 step by step
    centralBluetoothInteractor.reactPeripheralDiscovery(peripheral: peripheral)
    
    centralBluetoothInteractor.reactPeripheralFailedConnection(peripheral: peripheral.cbPeripheral, error: MockError.dummy)
    
    waitForExpectations(timeout: 10)
  }
  
  // MARK: autoReconnect
  func test_givenPeripheral_whenDisconnectsWithUnexpectedError_thenShouldNotTriggerAutoReconnect() {
    let expectation = expectation(description: "autoReconnect test fails with unexpeted error")
    
    let peripheral1 = MockPeripheral.dummyPeripheral(identifier: "00000000-0000-0000-0000-000000000000")
    
    // ------- Subscriptions --------
    
    centralBluetoothInteractor.advertisingPeripherals
      .map { $0.count }
      .collect(3)
      .sink(receiveValue: { advertisingPeripheralCount in
        // Autoreconnect shouldn't be triggered therefore the peripheral should not go back to .advertising after being .readyToControl.
        XCTAssertEqual(advertisingPeripheralCount, [0, 1, 0])
        expectation.fulfill()
      })
      .store(in: &cancellables)
    
    centralBluetoothInteractor.connect(peripheral1, options: [:])
      .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
      .store(in: &cancellables)
    
    // ---------- Test input -----------
    
    // Add peripheral to advertising toys first.
    centralBluetoothInteractor.reactPeripheralDiscovery(peripheral: peripheral1)
    
    centralBluetoothInteractor.reactPeripheralConnection(peripheral: peripheral1.cbPeripheral)
    // Simulating successful pairing validation for peripheral1 to put it into .readyToControl state
    peripheral1.pairingValidationStream.send(peripheral1)
    
    // After disconnection with an unknown error the peripheral shouldn't go back into .advertising
    centralBluetoothInteractor.reactPeripheralDisconnection(peripheral: peripheral1.cbPeripheral, error: nil)
    
    waitForExpectations(timeout: 10)
  }
}

private class MockPeripheralInitialCommunicator: MockBase, PeripheralInitialCommunicationProtocol {
  var servicesToDiscover: [CBUUID]?
  var characteristicsToDiscover: [CBUUID]?
  var writeCharacteristicIdentifier: CBUUID = CBUUID(string: "00000000-0000-0000-0000-000000000000")
  var readCharacteristicIdentifier: CBUUID = CBUUID(string: "00000000-0000-0000-0000-000000000000")
  var readCharacteristicPollingInterval: DispatchQueue.SchedulerTimeType.Stride { 10 }
  var pairingRequestPayload: Data = Data()
  var pairingConfirmationPayload: Data = Data()
}

private class MockInteractorOptions: CentralBluetoothInteractorConfigurable {
  var centralManagerInitializationOptions: [String : Any]?
  var peripheralScanningOptions: [String : Any]?
  var peripheralScanningRequiredServices: [CBUUID]?
  var autoReconnectTimeout: DispatchQueue.SchedulerTimeType.Stride
  var initialDiscoveryTimeout: DispatchQueue.SchedulerTimeType.Stride
  
  internal init(centralManagerInitializationOptions: [String : Any]? = nil,
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
