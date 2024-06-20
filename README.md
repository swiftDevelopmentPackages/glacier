![CI](https://github.com/swiftDevelopmentPackages/glacier/actions/workflows/swift.yml/badge.svg?branch=main)
![iOS](https://img.shields.io/badge/iOS-14.0+-blue)

# glacier
Reactive CoreBluetooth Abstraction Layer written in Swift, using Combine publishers.

BLE peripheral interactions are messy. It often requires using low-level APIs and big state machines. While trying to send/receive byte level data between/to peripherals, connectivity health, resilience and security are essential.

While glacier is not a magic pill to solve them all, it eases the pain of keeping track of observables, reacting to necessary changes by encapsulating and abstracting low level iOS CoreBluetooth APIs.

## Installation

### Swift Package Manager

You can install Wheel using the [Swift Package Manager](https://swift.org/package-manager/) by adding the following line to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/swiftDevelopmentPackages/glacier.git", from: "1.0.0")
]
```
Then, add wheel to your target's dependencies:
```
targets: [
    .target(name: "YourTarget", dependencies: ["glacier"]),
]
```

Or, simply add using XCode's package dependencies tab.

## Usage
TBD

