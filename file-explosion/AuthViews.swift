import SwiftUI

struct PasscodeSetupView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("appPasscode") private var appPasscode: String = ""
    @AppStorage("lastAccessDate") private var lastAccessDate: Double = 0
    @Binding var isUnlocked: Bool
    let isFirstSetup: Bool
    
    @State private var step = 1
    @State private var first = ""
    @State private var second = ""
    @State private var error: LocalizedStringKey = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Image(systemName: "lock.shield.fill").font(.system(size: 60)).foregroundColor(.orange).padding(.top, 40)
                Text(step == 1 ? "新しいパスコード(4桁)" : "確認のためもう一度").font(.title3).bold()
                if error != "" { Text(error).foregroundColor(.red).font(.caption).bold() }
                
                PasscodeField(title: "数字4桁", text: step == 1 ? $first : $second)
                
                Button(action: {
                    if step == 1 { step = 2 }
                    else {
                        if first == second {
                            appPasscode = first
                            if isFirstSetup { lastAccessDate = Date().timeIntervalSince1970; KeyManager.createAndSaveKey(); isUnlocked = true }
                            dismiss()
                        } else { error = "不一致です。最初からやり直し。"; step = 1; first = ""; second = "" }
                    }
                }) {
                    Text(step == 1 ? "次へ" : "設定を完了").font(.headline).foregroundColor(.white).padding().frame(width: 200).background(Color.blue).cornerRadius(10)
                }.disabled((step == 1 ? first : second).count < 4)
                Spacer()
            }
            .navigationTitle(isFirstSetup ? "初期設定" : "変更")
            .toolbar { if !isFirstSetup { ToolbarItem(placement: .cancellationAction) { Button("戻る") { dismiss() } } } }
        }.interactiveDismissDisabled(isFirstSetup)
    }
}

struct PasscodeField: View {
    var title: LocalizedStringKey
    @Binding var text: String
    @State private var isVisible = false
    
    var body: some View {
        ZStack(alignment: .trailing) {
            if isVisible {
                visibleField
            } else {
                hiddenField
            }
            Button(action: { isVisible.toggle() }) {
                Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill").foregroundColor(.gray).padding(.trailing, 10)
            }
        }.frame(width: 180)
            .onChange(of: text) { _, newValue in
                let numericString = newValue.filter { "0123456789".contains($0) }
                if numericString.count > 4 { text = String(numericString.prefix(4)) } else if numericString != newValue { text = numericString }
            }
    }
    
    @ViewBuilder
    private var visibleField: some View {
#if os(iOS)
        TextField(title, text: $text)
            .keyboardType(.numberPad)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .multilineTextAlignment(.center)
#else
        TextField(title, text: $text)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .multilineTextAlignment(.center)
#endif
    }
    
    @ViewBuilder
    private var hiddenField: some View {
#if os(iOS)
        SecureField(title, text: $text)
            .keyboardType(.numberPad)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .multilineTextAlignment(.center)
#else
        SecureField(title, text: $text)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .multilineTextAlignment(.center)
#endif
    }
}
