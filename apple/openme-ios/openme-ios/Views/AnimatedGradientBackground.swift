//
//  AnimatedGradientBackground.swift
//  Open Ping
//
//  Created by Merlos on 12/27/24.
//

import SwiftUI

struct AnimatedGradientBackground: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var animateGradient = false
    
    var body: some View {
        LinearGradient(
            colors: gradientColors,
            startPoint: animateGradient ? .topLeading : .bottomLeading,
            endPoint: animateGradient ? .bottomTrailing : .topTrailing
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(
                .easeInOut(duration: 6)
                .repeatForever(autoreverses: true)
            ) {
                animateGradient = true
            }
        }
    }
    
    private var gradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.1, green: 0.2, blue: 0.4),
                Color(red: 0.2, green: 0.1, blue: 0.3),
                Color(red: 0.1, green: 0.15, blue: 0.35)
            ]
        } else {
            return [
                Color(red: 0.7, green: 0.85, blue: 1.0),
                Color(red: 0.85, green: 0.75, blue: 1.0),
                Color(red: 0.75, green: 0.9, blue: 1.0)
            ]
        }
    }
}

struct GlassmorphicCard<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        colorScheme == .dark
                        ? Color.white.opacity(0.08)
                        : Color.white.opacity(0.3)
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                colorScheme == .dark
                                ? Color.white.opacity(0.15)
                                : Color.white.opacity(0.5),
                                lineWidth: 1
                            )
                    )
                    .shadow(
                        color: colorScheme == .dark
                        ? Color.black.opacity(0.3)
                        : Color.black.opacity(0.1),
                        radius: 10,
                        x: 0,
                        y: 5
                    )
            )
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    ZStack {
        AnimatedGradientBackground()
        
        VStack(spacing: 20) {
            GlassmorphicCard {
                Text("Glassmorphic Card")
                    .padding()
            }
            
            GlassmorphicCard {
                VStack {
                    Text("Another Card")
                    Text("With multiple elements")
                }
                .padding()
            }
        }
        .padding()
    }
}
