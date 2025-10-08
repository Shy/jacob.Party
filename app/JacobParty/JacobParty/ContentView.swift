import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = PartyViewModel()

    var body: some View {
        ZStack {
            // Background with gradient when party mode is active
            BackgroundView(isPartyMode: viewModel.isPartyMode)

            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 60)

                // Title
                Text("jacob.Party")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

                Spacer()

                // 3D Party Button
                PartyButton3DView(
                    isPartyMode: viewModel.isPartyMode,
                    isPressed: viewModel.isPressed
                )
                .onTapGesture {
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()

                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        viewModel.setPressed(true)
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            viewModel.setPressed(false)
                            viewModel.togglePartyMode()
                        }
                    }
                }

                // Instruction text
                Text(viewModel.isPartyMode ? "Press to stop the party" : "Press to start the party!")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .padding(.top, 16)

                Spacer()
            }
        }
        .ignoresSafeArea()
        .task {
            await viewModel.fetchInitialState()
        }
    }
}

struct BackgroundView: View {
    let isPartyMode: Bool
    @State private var animatedGradient = false

    var body: some View {
        LinearGradient(
            colors: isPartyMode ? [
                Color(red: 1.0, green: 0.4, blue: 0.8),
                Color(red: 0.5, green: 0.2, blue: 1.0),
                Color(red: 0.2, green: 0.8, blue: 1.0)
            ] : [
                Color(red: 0.1, green: 0.1, blue: 0.2),
                Color(red: 0.2, green: 0.1, blue: 0.3)
            ],
            startPoint: animatedGradient ? .topLeading : .bottomTrailing,
            endPoint: animatedGradient ? .bottomTrailing : .topLeading
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 2), value: isPartyMode)
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                animatedGradient = true
            }
        }
    }
}

#Preview {
    ContentView()
}
