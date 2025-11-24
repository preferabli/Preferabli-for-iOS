// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Preferabli",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "PreferabliDataSDK",
            targets: ["PreferabliDataSDK"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/Alamofire/Alamofire.git",
            from: "5.9.0"
        ),
        .package(
            url: "https://github.com/mixpanel/mixpanel-swift.git",
            from: "4.2.0"
        )
    ],
    targets: [
        .target(
            name: "PreferabliDataSDK",
            dependencies: [
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "Mixpanel", package: "mixpanel-swift")
            ],
            path: "PreferabliDataSDK",
            resources: [
                .process("assets"),
                .process("tools/PreferabliConfig.plist")
            ]
        )
    ]
)
