//
//  ProfileView.swift
//  Butterfly
//

import SwiftUI

struct ProfileView: View {
    @ObservedObject var viewModel: LightViewModel
    
    var body: some View {
        ZStack {
            IridescentBackground()
            
            VStack(spacing: 30) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(.primary.opacity(0.75))
                
                Text("PROFILE")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                
                Text("Your personal profile")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .ignoresSafeArea()
    }
}

