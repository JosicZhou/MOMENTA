//
//  Momenta
//  Developed by ZHOU Jing
//  Designed by GONG Shengao and LIN Yang

import SwiftUI
import GoogleSignIn

@main
struct ButterflyApp: App {
    @StateObject private var deepLinkRouter = DeepLinkRouter()

    var body: some Scene {
        WindowGroup {
            ContentView(deepLinkRouter: deepLinkRouter)
                .onOpenURL { url in
                    if !GIDSignIn.sharedInstance.handle(url) {
                        _ = deepLinkRouter.handle(url)
                    }
                }
        }
    }
}
