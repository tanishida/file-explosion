import SwiftUI
import LocalAuthentication
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {
    // --- 状態管理 ---
    @State private var statusMessage: LocalizedStringKey = "認証してください"
    @State private var isDestroyed = false
    @AppStorage("lastAccessDate") private var lastAccessDate: Double = 0
    @AppStorage("timerLimitSeconds") private var timerLimitSeconds: Double = 604800
    @AppStorage("appPasscode") private var appPasscode: String = ""
    
    @State private var isUnlocked = false
    @State private var secretFiles: [SecretFile] = []
    
    // --- UI/インポート関連 ---
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var showingResetConfirmation = false
    @State private var isProcessing = false
    @State private var processingMessage: LocalizedStringKey = ""
    
    // --- 認証関連 ---
    @State private var inputPasscode = ""
    @State private var faceIDFailCount = 0
    @State private var showPasscodeEntry = false
    @State private var showingPasscodeSetup = false
    @State private var isFirstSetupMode = false
    
    // --- ギャラリー（スワイプ閲覧）関連 ---
    @State private var showingGallery = false
    @State private var galleryFiles: [SecretFile] = []
    @State private var galleryIndex: Int = 0
    
    // --- 表示関連 ---
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var timeRemainingString: String = ""
    @State private var selectedFolder = 0
    @Environment(\.scenePhase) var scenePhase
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 上部ステータス
                VStack(spacing: 5) {
                    if isDestroyed {
                        Text("【警告】システム停止").font(.subheadline).foregroundColor(.red)
                    } else if isUnlocked {
                        Text("ロック解除中").font(.subheadline).foregroundColor(.green)
                    } else {
                        Text(statusMessage).font(.subheadline).foregroundColor(.primary)
                    }
                    
                    if !isDestroyed && lastAccessDate != 0 {
                        Text(timeRemainingString)
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(isUnlocked ? .green : .red)
                    }
                }
                .padding(.vertical, 12).frame(maxWidth: .infinity).background(Color.secondary.opacity(0.05))
                Divider()
                
                if isDestroyed {
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: "bolt.slash.fill").font(.system(size: 60)).foregroundColor(.gray)
                        Text("データは完全に消去されました。\n再構築が必要です。").multilineTextAlignment(.center).foregroundColor(.gray)
                        Button(action: { showingResetConfirmation = true }) {
                            Text("システムを再構築").font(.headline).foregroundColor(.red).padding().frame(maxWidth: .infinity).background(Color.red.opacity(0.1)).cornerRadius(10).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red, lineWidth: 1))
                        }.padding(.horizontal)
                        Spacer()
                    }
                } else if !isUnlocked {
                    lockScreenView
                } else {
                    TabView {
                        controlPanelView.tabItem { Label("操作", systemImage: "slider.horizontal.3") }
                        folderView.tabItem { Label("ファイル", systemImage: "folder.fill") }
                    }
                }
            }
            .navigationTitle("Deadman Switch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isUnlocked {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Menu {
                                Picker("自爆タイマー", selection: $timerLimitSeconds) {
                                    Text("1時間").tag(3600.0)
                                    Text("1日").tag(86400.0)
                                    Text("3日").tag(259200.0)
                                    Text("1週間").tag(604800.0)
                                }
                            } label: { Label("自爆タイマー", systemImage: "timer") }
                            
                            Button(role: .destructive, action: { showingResetConfirmation = true }) {
                                Label("システムを初期化", systemImage: "trash")
                            }
                        } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                    }
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image, .movie, .pdf, .item], allowsMultipleSelection: true) { result in
                processImportedFiles(result: result)
            }
            .onChange(of: selectedItems) { _ in processSelectedPhotos() }
            .onChange(of: timerLimitSeconds) { _ in lastAccessDate = Date().timeIntervalSince1970 }
            .fullScreenCover(isPresented: $showingPasscodeSetup) {
                PasscodeSetupView(isUnlocked: $isUnlocked, isFirstSetup: isFirstSetupMode)
            }
            .fullScreenCover(isPresented: $showingGallery) {
                GalleryView(files: galleryFiles, currentIndex: galleryIndex)
            }
            .alert("【警告】システムの初期化", isPresented: $showingResetConfirmation) {
                Button("キャンセル", role: .cancel) { }; Button("初期化を実行", role: .destructive) { resetApp() }
            } message: { Text("全てのデータが完全に消去されます。よろしいですか？\n※パスコード設定は維持されます。") }
        }
        .overlay {
            if isProcessing {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 20) {
                        ProgressView().scaleEffect(1.5).tint(.white)
                        Text(processingMessage).font(.callout).fontWeight(.bold).foregroundColor(.white).multilineTextAlignment(.center)
                    }.padding(30).background(Color.black.opacity(0.8)).cornerRadius(15)
                }
            }
        }
        .disabled(isProcessing)
        .onReceive(timer) { _ in checkTimeLimit() }
        .onAppear { checkInitialSetup() }
        .onChange(of: scenePhase) { phase in
            if (phase == .background || phase == .inactive) && isUnlocked { lockApp() } else if phase == .active { checkTimeLimit() }
        }
    }
    
    var lockScreenView: some View {
        VStack(spacing: 30) {
            Spacer()
            Image(systemName: showPasscodeEntry ? "lock.shield.fill" : "faceid").font(.system(size: 60)).foregroundColor(showPasscodeEntry ? .orange : .blue)
            if showPasscodeEntry {
                VStack(spacing: 20) {
                    Text("パスコードを入力").font(.headline)
                    PasscodeField(title: "4桁の数字", text: $inputPasscode)
                    Button(action: {
                        if inputPasscode == appPasscode { unlockSystem() } else { statusMessage = "❌ パスコード不一致"; inputPasscode = "" }
                    }) {
                        Text("解除する").font(.headline).foregroundColor(.white).padding().frame(width: 200).background(Color.orange).cornerRadius(10)
                    }.disabled(inputPasscode.count < 4)
                    Button("Face IDに戻る") { showPasscodeEntry = false }.font(.caption).foregroundColor(.gray)
                }
            } else {
                Button(action: { authenticate() }) {
                    HStack { Image(systemName: "faceid"); Text("Face ID でロック解除") }.font(.headline).foregroundColor(.white).padding().frame(width: 250).background(Color.blue).cornerRadius(10)
                }
                Button("パスコードを使う") { showPasscodeEntry = true }.font(.subheadline).foregroundColor(.secondary).underline()
            }
            Spacer()
        }
    }
    
    var controlPanelView: some View {
        ScrollView {
            VStack(spacing: 25) {
                SectionHeader(title: "セキュリティ管理")
                Button(action: { isFirstSetupMode = false; showingPasscodeSetup = true }) {
                    Label("パスコードを変更する", systemImage: "lock.rotation").frame(maxWidth: .infinity).padding().background(Color.orange).foregroundColor(.white).cornerRadius(10)
                }.padding(.horizontal)
                
                SectionHeader(title: "パフォーマンス")
                Button(action: { batchDecryptAll() }) {
                    Label("全ファイルを一括事前解読", systemImage: "bolt.fill").frame(maxWidth: .infinity).padding().background(Color.blue).foregroundColor(.white).cornerRadius(10)
                }.padding(.horizontal)
                
                SectionHeader(title: "極秘データの追加")
                HStack(spacing: 15) {
                    PhotosPicker(selection: $selectedItems, matching: .any(of: [.images, .videos])) {
                        VStack { Image(systemName: "photo.fill"); Text("写真/動画").font(.caption2) }.frame(maxWidth: .infinity).padding().background(Color.green).foregroundColor(.white).cornerRadius(10)
                    }
                    Button(action: { showFileImporter = true }) {
                        VStack { Image(systemName: "doc.badge.plus"); Text("ファイル").font(.caption2) }.frame(maxWidth: .infinity).padding().background(Color.indigo).foregroundColor(.white).cornerRadius(10)
                    }
                }.padding(.horizontal)
                
            }.padding(.vertical)
        }
    }
    
    var folderView: some View {
        VStack(spacing: 0) {
            Picker("フォルダ", selection: $selectedFolder) {
                Text("写真").tag(0); Text("動画").tag(1); Text("PDF").tag(2); Text("他").tag(3)
            }.pickerStyle(.segmented).padding()
            
            TabView(selection: $selectedFolder) {
                fileGrid(for: 0).tag(0)
                fileGrid(for: 1).tag(1)
                fileGrid(for: 2).tag(2)
                fileGrid(for: 3).tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: selectedFolder)
        }
    }
    
    @ViewBuilder
    func fileGrid(for folderIndex: Int) -> some View {
        let filtered = secretFiles.filter { f in
            if folderIndex == 0 { return f.isImage }
            else if folderIndex == 1 { return f.isVideo }
            else if folderIndex == 2 { return f.isPDF }
            else { return !f.isImage && !f.isVideo && !f.isPDF }
        }
        
        if filtered.isEmpty {
            VStack { Spacer(); Text("このフォルダは空です").foregroundColor(.gray); Spacer() }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, file in
                        FileThumbnailView(file: file) {
                            self.galleryFiles = filtered
                            self.galleryIndex = index
                            self.showingGallery = true
                        }
                    }
                }.padding()
            }
        }
    }
    
    func checkInitialSetup() {
        if appPasscode.isEmpty || lastAccessDate == 0 { isFirstSetupMode = true; showingPasscodeSetup = true } else { checkTimeLimit() }
    }
    
    func authenticate() {
        let context = LAContext()
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "システムを解除します") { success, _ in
                DispatchQueue.main.async {
                    if success { unlockSystem() }
                    else {
                        faceIDFailCount += 1
                        if faceIDFailCount >= 3 { showPasscodeEntry = true; statusMessage = "パスコードを入力してください" }
                        else { statusMessage = "認証失敗 (\(faceIDFailCount)/3)" }
                    }
                }
            }
        } else { showPasscodeEntry = true }
    }
    
    func unlockSystem() {
        lastAccessDate = Date().timeIntervalSince1970; KeyManager.createAndSaveKey(); isUnlocked = true
        faceIDFailCount = 0; showPasscodeEntry = false; inputPasscode = ""; refreshFiles()
    }
    
    func lockApp() {
        isUnlocked = false; secretFiles = []; FileManagerHelper.clearTempCache()
        showPasscodeEntry = false; inputPasscode = ""; faceIDFailCount = 0; statusMessage = "認証してください"
        showingGallery = false
    }
    
    func refreshFiles() { secretFiles = FileManagerHelper.getAllSecretFiles() }
    
    func checkTimeLimit() {
        if lastAccessDate == 0 || isDestroyed { return }
        let passed = Date().timeIntervalSince1970 - lastAccessDate
        if passed > timerLimitSeconds {
            isDestroyed = true; KeyManager.destroyKey(); FileManagerHelper.deleteAllFiles(); FileManagerHelper.clearTempCache()
        } else {
            let rem = max(0, timerLimitSeconds - passed)
            let format = String(localized: "%02d日 %02d:%02d:%02d")
            timeRemainingString = String(format: format, Int(rem)/86400, (Int(rem)%86400)/3600, (Int(rem)%3600)/60, Int(rem)%60)
        }
    }
    
    func batchDecryptAll() {
        let targets = secretFiles.filter { !FileManager.default.fileExists(atPath: FileManagerHelper.getCacheURL(for: $0).path) }
        if targets.isEmpty { return }
        isProcessing = true; var count = 0; processingMessage = "一括解読中... (0/\(targets.count))"
        
        DispatchQueue.global(qos: .userInitiated).async {
            for file in targets {
                autoreleasepool {
                    _ = KeyManager.decryptFile(inputURL: file.url, outputURL: FileManagerHelper.getCacheURL(for: file))
                }
                DispatchQueue.main.async { count += 1; processingMessage = "一括解読中... (\(count)/\(targets.count))" }
            }
            DispatchQueue.main.async { isProcessing = false; refreshFiles() }
        }
    }
    
    func processSelectedPhotos() {
        guard !selectedItems.isEmpty else { return }
        isProcessing = true; processingMessage = "極秘処理中...\n（そのままお待ちください）"
        let items = selectedItems
        selectedItems = []
        
        DispatchQueue.global(qos: .userInitiated).async {
            for (index, item) in items.enumerated() {
                DispatchQueue.main.async { processingMessage = "極秘処理中... (\(index + 1)/\(items.count))" }
                
                let semaphore = DispatchSemaphore(value: 0)
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "data"
                
                item.loadTransferable(type: TempMediaFile.self) { result in
                    if case .success(let media?) = result {
                        autoreleasepool {
                            KeyManager.createAndSaveKey()
                            _ = KeyManager.encryptFile(inputURL: media.url, outputURL: FileManagerHelper.generateNewFileURL(originalExtension: ext))
                            try? FileManager.default.removeItem(at: media.url)
                        }
                    }
                    semaphore.signal()
                }
                semaphore.wait()
            }
            DispatchQueue.main.async { refreshFiles(); isProcessing = false }
        }
    }
    
    func processImportedFiles(result: Result<[URL], Error>) {
        if case .success(let urls) = result {
            isProcessing = true; processingMessage = "極秘処理中..."
            
            DispatchQueue.global(qos: .userInitiated).async {
                for (index, url) in urls.enumerated() {
                    DispatchQueue.main.async { processingMessage = "極秘処理中... (\(index + 1)/\(urls.count))" }
                    
                    autoreleasepool {
                        if url.startAccessingSecurityScopedResource() {
                            KeyManager.createAndSaveKey()
                            _ = KeyManager.encryptFile(inputURL: url, outputURL: FileManagerHelper.generateNewFileURL(originalExtension: url.pathExtension))
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                }
                DispatchQueue.main.async { refreshFiles(); isProcessing = false }
            }
        }
    }
    
    func resetApp() {
        lastAccessDate = 0; isDestroyed = false; isUnlocked = false; secretFiles = []
        KeyManager.destroyKey(); FileManagerHelper.deleteAllFiles(); FileManagerHelper.clearTempCache()
        checkInitialSetup()
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey
    var body: some View { Text(title).font(.caption).fontWeight(.bold).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal) }
}

struct TempMediaFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .item) { received in
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            return TempMediaFile(url: tempURL)
        }
    }
}
