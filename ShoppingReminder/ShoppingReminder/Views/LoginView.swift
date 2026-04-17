import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isSignUp = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text(isSignUp ? "アカウント作成" : "ログイン")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            if isSignUp {
                TextField("名前（表示名）", text: $displayName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            TextField("メールアドレス", text: $email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                #endif
            
            SecureField("パスワード", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            Button(action: handleAuth) {
                Text(isSignUp ? "登録する" : "ログインする")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            
            Button(action: { isSignUp.toggle() }) {
                Text(isSignUp ? "すでにアカウントをお持ちですか？ ログイン" : "アカウントをお持ちでないですか？ 新規登録")
                    .font(.caption)
            }
        }
        .padding()
    }
    
    private func handleAuth() {
        Task {
            do {
                if isSignUp {
                    try await SupabaseService.shared.signUp(email: email, password: password, displayName: displayName)
                } else {
                    try await SupabaseService.shared.signIn(email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
