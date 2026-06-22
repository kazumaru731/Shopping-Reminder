import SwiftUI

struct OnboardingView: View {
    @State private var displayName = ""
    @State private var errorMessage = ""
    @State private var isProcessing = false

    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                Image(systemName: "cart.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.blue)

                Text("買い物リマインダー")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                TextField("表示名", text: $displayName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button(action: start) {
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("始める")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isProcessing ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(isProcessing)
            }
            .padding()

            if isProcessing {
                Color.black.opacity(0.2)
                    .edgesIgnoringSafeArea(.all)
                ProgressView("処理中...")
                    .padding()
                    .background(Color.white)
                    .cornerRadius(10)
                    .shadow(radius: 10)
            }
        }
    }

    private func start() {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "表示名を入力してください。"
            return
        }

        Task {
            await MainActor.run {
                isProcessing = true
                errorMessage = ""
            }

            do {
                try await SupabaseService.shared.startAppAccount(displayName: trimmedName)
            } catch {
                await MainActor.run {
                    errorMessage = "開始できませんでした。時間をおいてもう一度お試しください。"
                }
            }

            await MainActor.run {
                isProcessing = false
            }
        }
    }
}
