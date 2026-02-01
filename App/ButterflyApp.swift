//
//  Momenta
//  Developed by ZHOU Jing
//  Designed by GONG Shengao and LIN Yang

import SwiftUI
import GoogleSignIn

@main
struct ButterflyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}

