import SwiftUI

struct PasswordUpdateView: View {
    @Environment(\.dismiss) var dismiss
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    @State private var errorMessage = ""
    @State private var isSuccess = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("新しいパスワードを設定")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("新しいパスワードを入力してください。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                HStack {
                    if isPasswordVisible {
                        TextField("新しいパスワード", text: $password)
                    } else {
                        SecureField("新しいパスワード", text: $password)
                    }
                    Button(action: { isPasswordVisible.toggle() }) {
                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.2)))
                
                HStack {
                    if isConfirmPasswordVisible {
                        TextField("パスワード（確認用）", text: $confirmPassword)
                    } else {
                        SecureField("パスワード（確認用）", text: $confirmPassword)
                    }
                    Button(action: { isConfirmPasswordVisible.toggle() }) {
                        Image(systemName: isConfirmPasswordVisible ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.2)))
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                Button(action: handleUpdate) {
                    Text("パスワードを更新")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(password.isEmpty || password != confirmPassword)
                
                Spacer()
            }
            .padding()
            .navigationTitle("パスワード再設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        SupabaseService.shared.resetPasswordRecoveryStatus()
                        dismiss()
                    }
                }
            }
            .alert("完了", isPresented: $isSuccess) {
                Button("OK") {
                    SupabaseService.shared.resetPasswordRecoveryStatus()
                    dismiss()
                }
            } message: {
                Text("パスワードを更新しました。新しいパスワードでログインしてください。")
            }
        }
    }
    
    private func handleUpdate() {
        guard password == confirmPassword else {
            errorMessage = "パスワードが一致しません。"
            return
        }
        
        Task {
            do {
                try await SupabaseService.shared.updatePassword(password: password)
                await MainActor.run {
                    isSuccess = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
