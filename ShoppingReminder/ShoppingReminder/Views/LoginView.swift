import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var displayName = ""
    @State private var isSignUp = false
    @State private var errorMessage = ""
    @State private var showingSignUpSuccess = false
    @State private var showingResetAlert = false
    @State private var resetEmail = ""
    @State private var showingResetSuccess = false
    @State private var isProcessing = false
    
    var body: some View {
        ZStack {
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
            
            HStack {
                if isPasswordVisible {
                    TextField("パスワード", text: $password)
                } else {
                    SecureField("パスワード", text: $password)
                }
                
                Button(action: { isPasswordVisible.toggle() }) {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.2)))
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button(action: handleAuth) {
                if isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text(isSignUp ? "登録する" : "ログインする")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isProcessing ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .disabled(isProcessing)
            
            Button(action: { 
                isSignUp.toggle() 
                errorMessage = ""
            }) {
                Text(isSignUp ? "すでにアカウントをお持ちですか？ ログイン" : "アカウントをお持ちでないですか？ 新規登録")
                    .font(.caption)
            }
            .disabled(isProcessing)
            
            if !isSignUp {
                Button("パスワードをお忘れですか？") {
                    resetEmail = email
                    showingResetAlert = true
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .disabled(isProcessing)
            }
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
        .onAppear {
            // 保存されたメールアドレスを読み込み
            if let savedEmail = UserDefaults.standard.string(forKey: "saved_email") {
                email = savedEmail
            }
        }
        .alert("パスワードリセット", isPresented: $showingResetAlert) {
            TextField("メールアドレス", text: $resetEmail)
            Button("キャンセル", role: .cancel) { }
            Button("送信") {
                Task {
                    isProcessing = true
                    do {
                        try await SupabaseService.shared.resetPassword(email: resetEmail)
                        showingResetSuccess = true
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    isProcessing = false
                }
            }
        } message: {
            Text("パスワードリセット用のリンクをメールで送信します。")
        }
        .alert("送信完了", isPresented: $showingResetSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\(resetEmail) 宛にパスワードリセットの案内を送信しました。")
        }
        .alert("登録完了", isPresented: $showingSignUpSuccess) {
            Button("OK") { 
                isSignUp = false // ログイン画面に切り替え
                errorMessage = ""
            }
        } message: {
            Text("\(email) 宛に確認メールを送信しました。メール内のリンクをクリックしてアカウントを有効化してください。")
        }
    }
    
    private func handleAuth() {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "メールアドレスとパスワードを入力してください。"
            return
        }
        
        if isSignUp && displayName.isEmpty {
            errorMessage = "表示名を入力してください。"
            return
        }

        Task {
            isProcessing = true
            do {
                if isSignUp {
                    try await SupabaseService.shared.signUp(email: email, password: password, displayName: displayName)
                    await MainActor.run {
                        showingSignUpSuccess = true
                    }
                } else {
                    try await SupabaseService.shared.signIn(email: email, password: password)
                    // ログイン成功時にメールアドレスを保存
                    UserDefaults.standard.set(email, forKey: "saved_email")
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
            isProcessing = false
        }
    }
}
