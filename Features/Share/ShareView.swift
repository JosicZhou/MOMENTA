//
//  ShareView.swift
//  Butterfly
//

import SwiftUI

struct ShareView: View {
    var body: some View {
        ZStack {
            IridescentBackground()
            
            VStack(spacing: 30) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(.primary.opacity(0.6))
                
                Text("SHARE")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                
                Text("Share your musical creations with friends")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .ignoresSafeArea()
    }
}

