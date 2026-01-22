//
//  MemoriesView.swift
//  Butterfly
//

import SwiftUI

struct MemoriesView: View {
    var body: some View {
        ZStack {
            IridescentBackground()
            
            VStack(spacing: 30) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(.primary.opacity(0.6))
                
                Text("MEMORIES")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                
                Text("Your musical memories will appear here")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .ignoresSafeArea()
    }
}

