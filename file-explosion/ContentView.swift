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
    
    // --- 選択・書き出し関連 ---
    @State private var isSelectionMode = false
    @State private var selectedFileIDs: Set<UUID> = []
    @State private var showingMultiDeleteConfirm = false
    @State private var filesToShare: [URL] = []
    @State private var showShareSheet = false
    
    // --- 認証関連 ---
    @State private var inputPasscode = ""
    @State private var faceIDFailCount = 0
    @State private var showPasscodeEntry = false
    @State private var showingPasscodeSetup = false
    @State private var isFirstSetupMode = false
    @State private var showingTimerSetup = false
    
    // --- ギャラリー関連 ---
    @State private var showingGallery = false
    @State private var galleryFiles: [SecretFile] = []
    @State private var galleryIndex: Int = 0
    
    // --- 表示・タブ関連 ---
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    // 🗑️ timeRemainingString を削除して軽量化！
    @State private var selectedFolder = 0
    @State private var selectedMainTab = 0
    @Environment(\.scenePhase) var scenePhase
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ▼ 🆕 変更：1秒ごとに描画されるタイマー部分を「独立した専用ビュー」に分離しました！
                VStack(spacing: 5) {
                    if isDestroyed { Text("【警告】システム停止").font(.subheadline).foregroundColor(.red) }
                    else if isUnlocked { Text("ロック解除中").font(.subheadline).foregroundColor(.green) }
                    else { Text(statusMessage).font(.subheadline).foregroundColor(.primary) }
                    
                    if !isDestroyed && lastAccessDate != 0 {
                        TimerDisplayView(isUnlocked: isUnlocked)
                    }
                }.padding(.vertical, 12).frame(maxWidth: .infinity).background(Color.secondary.opacity(0.05))
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
                } else if !isUnlocked { lockScreenView }
                else {
                    TabView(selection: $selectedMainTab) {
                        controlPanelView.tabItem { Label("操作", systemImage: "slider.horizontal.3") }.tag(0)
                        folderView.tabItem { Label("ファイル", systemImage: "folder.fill") }.tag(1)
                    }
                }
            }
            .navigationTitle("Deadman Switch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isUnlocked {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if isSelectionMode {
                            Button(action: { withAnimation { isSelectionMode = false; selectedFileIDs.removeAll() } }) { Image(systemName: "xmark").font(.title3).fontWeight(.bold) }
                        } else {
                            Menu {
                                if selectedMainTab == 1 {
                                    Button(action: { withAnimation { isSelectionMode = true; selectedFileIDs.removeAll() } }) { Label("選択", systemImage: "checkmark.circle") }
                                    Divider()
                                }
                                Button(action: { showingTimerSetup = true }) { Label("自爆タイマー", systemImage: "timer") }
                                Button(role: .destructive, action: { showingResetConfirmation = true }) { Label("システムを初期化", systemImage: "trash") }
                            } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                        }
                    }
                }
            }
            .onChange(of: selectedMainTab) { newValue in if newValue == 0 { isSelectionMode = false; selectedFileIDs.removeAll() } }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image, .movie, .pdf, .item], allowsMultipleSelection: true) { result in processImportedFiles(result: result) }
            .onChange(of: selectedItems) { _ in processSelectedPhotos() }
            .onChange(of: timerLimitSeconds) { _ in lastAccessDate = Date().timeIntervalSince1970 }
            .fullScreenCover(isPresented: $showingPasscodeSetup) { PasscodeSetupView(isUnlocked: $isUnlocked, isFirstSetup: isFirstSetupMode) }
            .fullScreenCover(isPresented: $showingGallery) { GalleryView(files: galleryFiles, currentIndex: galleryIndex) }
            .sheet(isPresented: $showShareSheet, onDismiss: { cleanupExportedFiles() }) { ShareSheet(activityItems: filesToShare) }
            .fullScreenCover(isPresented: $showingTimerSetup) { TimerSetupView() }
            .alert("【警告】システムの初期化", isPresented: $showingResetConfirmation) { Button("キャンセル", role: .cancel) { }; Button("初期化を実行", role: .destructive) { resetApp() } } message: { Text("全てのデータが完全に消去されます。よろしいですか？\n※パスコード設定は維持されます。") }
            .alert("削除の確認", isPresented: $showingMultiDeleteConfirm) { Button("キャンセル", role: .cancel) { }; Button("削除", role: .destructive) { deleteSelectedFiles() } } message: { Text("選択したファイルを完全に削除しますか？") }
        }
        .overlay {
            if isProcessing {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 20) { ProgressView().scaleEffect(1.5).tint(.white); Text(processingMessage).font(.callout).fontWeight(.bold).foregroundColor(.white).multilineTextAlignment(.center) }.padding(30).background(Color.black.opacity(0.8)).cornerRadius(15)
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
    
    // MARK: - メインUIコンポーネント
    
    var lockScreenView: some View {
        VStack(spacing: 30) {
            Spacer()
            Image(systemName: showPasscodeEntry ? "lock.shield.fill" : "faceid").font(.system(size: 60)).foregroundColor(showPasscodeEntry ? .orange : .blue)
            if showPasscodeEntry {
                VStack(spacing: 20) {
                    Text("パスコードを入力").font(.headline)
                    PasscodeField(title: "4桁の数字", text: $inputPasscode)
                    Button(action: { if inputPasscode == appPasscode { unlockSystem() } else { statusMessage = "❌ パスコード不一致"; inputPasscode = "" } }) { Text("解除する").font(.headline).foregroundColor(.white).padding().frame(width: 200).background(Color.orange).cornerRadius(10) }.disabled(inputPasscode.count < 4)
                    Button("Face IDに戻る") { showPasscodeEntry = false }.font(.caption).foregroundColor(.gray)
                }
            } else {
                Button(action: { authenticate() }) { HStack { Image(systemName: "faceid"); Text("Face ID でロック解除") }.font(.headline).foregroundColor(.white).padding().frame(width: 250).background(Color.blue).cornerRadius(10) }
                Button("パスコードを使う") { showPasscodeEntry = true }.font(.subheadline).foregroundColor(.secondary).underline()
            }
            Spacer()
        }
    }
    
    var controlPanelView: some View {
        ScrollView {
            VStack(spacing: 25) {
                SectionHeader(title: "セキュリティ管理")
                Button(action: { isFirstSetupMode = false; showingPasscodeSetup = true }) { Label("パスコードを変更する", systemImage: "lock.rotation").frame(maxWidth: .infinity).padding().background(Color.orange).foregroundColor(.white).cornerRadius(10) }.padding(.horizontal)
                SectionHeader(title: "パフォーマンス")
                Button(action: { batchDecryptAll() }) { Label("全ファイルを一括事前解読", systemImage: "bolt.fill").frame(maxWidth: .infinity).padding().background(Color.blue).foregroundColor(.white).cornerRadius(10) }.padding(.horizontal)
                SectionHeader(title: "極秘データの追加")
                HStack(spacing: 15) {
                    PhotosPicker(selection: $selectedItems, matching: .any(of: [.images, .videos])) { VStack { Image(systemName: "photo.fill"); Text("写真/動画").font(.caption2) }.frame(maxWidth: .infinity).padding().background(Color.green).foregroundColor(.white).cornerRadius(10) }
                    Button(action: { showFileImporter = true }) { VStack { Image(systemName: "doc.badge.plus"); Text("ファイル").font(.caption2) }.frame(maxWidth: .infinity).padding().background(Color.indigo).foregroundColor(.white).cornerRadius(10) }
                }.padding(.horizontal)
            }.padding(.vertical)
        }
    }
    
    var folderView: some View {
        VStack(spacing: 0) {
            Picker("フォルダ", selection: $selectedFolder) { Text("写真").tag(0); Text("動画").tag(1); Text("PDF").tag(2); Text("他").tag(3) }.pickerStyle(.segmented).padding()
            
            TabView(selection: $selectedFolder) {
                fileGrid(for: 0).tag(0)
                fileGrid(for: 1).tag(1)
                fileGrid(for: 2).tag(2)
                fileGrid(for: 3).tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never)).animation(.easeInOut, value: selectedFolder)
            
            if isSelectionMode {
                Divider()
                HStack {
                    Button(action: { exportSelectedFiles() }) { VStack { Image(systemName: "square.and.arrow.up").font(.title2); Text("書き出し").font(.caption) } }.disabled(selectedFileIDs.isEmpty)
                    Spacer()
                    let countFormat = String(localized: "%lld項目を選択")
                    Text(String(format: countFormat, selectedFileIDs.count)).font(.subheadline).bold()
                    Spacer()
                    Button(action: { showingMultiDeleteConfirm = true }) { VStack { Image(systemName: "trash").font(.title2); Text("削除").font(.caption) } }.foregroundColor(selectedFileIDs.isEmpty ? .gray : .red).disabled(selectedFileIDs.isEmpty)
                }
                .padding(.horizontal, 30).padding(.vertical, 10).background(Color.secondary.opacity(0.1))
                .transition(.move(edge: .bottom))
            }
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
                        ZStack(alignment: .bottomTrailing) {
                            FileThumbnailView(file: file) {
                                if isSelectionMode {
                                    if selectedFileIDs.contains(file.id) { selectedFileIDs.remove(file.id) }
                                    else { selectedFileIDs.insert(file.id) }
                                } else {
                                    self.galleryFiles = filtered
                                    self.galleryIndex = index
                                    self.showingGallery = true
                                }
                            }
                            if isSelectionMode { Image(systemName: selectedFileIDs.contains(file.id) ? "checkmark.circle.fill" : "circle").font(.title2).foregroundColor(selectedFileIDs.contains(file.id) ? .blue : .white).background(Circle().fill(Color.black.opacity(0.3))).padding(6).allowsHitTesting(false) }
                        }
                    }
                }.padding()
            }
        }
    }
    
    // MARK: - メインロジック群
    func deleteSelectedFiles() { let targets = secretFiles.filter { selectedFileIDs.contains($0.id) }; for file in targets { try? FileManager.default.removeItem(at: file.url); try? FileManager.default.removeItem(at: FileManagerHelper.getCacheURL(for: file)) }; withAnimation { isSelectionMode = false; selectedFileIDs.removeAll() }; refreshFiles() }
    func exportSelectedFiles() { isProcessing = true; processingMessage = "復号中..."; let targets = secretFiles.filter { selectedFileIDs.contains($0.id) }; DispatchQueue.global(qos: .userInitiated).async { var tempURLs: [URL] = []; for file in targets { let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Export_" + file.url.lastPathComponent); if KeyManager.decryptFile(inputURL: file.url, outputURL: tempURL) { tempURLs.append(tempURL) } }; DispatchQueue.main.async { isProcessing = false; if !tempURLs.isEmpty { self.filesToShare = tempURLs; self.showShareSheet = true } } } }
    func cleanupExportedFiles() { for url in filesToShare { try? FileManager.default.removeItem(at: url) }; filesToShare.removeAll(); withAnimation { isSelectionMode = false; selectedFileIDs.removeAll() } }
    func checkInitialSetup() { if appPasscode.isEmpty || lastAccessDate == 0 { isFirstSetupMode = true; showingPasscodeSetup = true } else { checkTimeLimit() } }
    func authenticate() { let context = LAContext(); if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) { context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "システムを解除します") { success, _ in DispatchQueue.main.async { if success { unlockSystem() } else { faceIDFailCount += 1; if faceIDFailCount >= 3 { showPasscodeEntry = true; statusMessage = "パスコードを入力してください" } else { statusMessage = "認証失敗 (\(faceIDFailCount)/3)" } } } } } else { showPasscodeEntry = true } }
    func unlockSystem() { lastAccessDate = Date().timeIntervalSince1970; KeyManager.createAndSaveKey(); isUnlocked = true; faceIDFailCount = 0; showPasscodeEntry = false; inputPasscode = ""; refreshFiles() }
    func lockApp() { isUnlocked = false; secretFiles = []; FileManagerHelper.clearTempCache(); isSelectionMode = false; selectedFileIDs.removeAll(); showPasscodeEntry = false; inputPasscode = ""; faceIDFailCount = 0; statusMessage = "認証してください"; showingGallery = false }
    func refreshFiles() { secretFiles = FileManagerHelper.getAllSecretFiles() }
    
    // ▼ 🆕 変更：状態を監視し、時間が過ぎた時「だけ」システムを破壊する（UIの更新はしない）
    func checkTimeLimit() {
        if lastAccessDate == 0 || isDestroyed { return }
        let passed = Date().timeIntervalSince1970 - lastAccessDate
        if passed > timerLimitSeconds {
            isDestroyed = true
            KeyManager.destroyKey(); FileManagerHelper.deleteAllFiles(); FileManagerHelper.clearTempCache()
        }
    }
    
    func batchDecryptAll() { let targets = secretFiles.filter { !FileManager.default.fileExists(atPath: FileManagerHelper.getCacheURL(for: $0).path) }; if targets.isEmpty { return }; isProcessing = true; var count = 0; processingMessage = "一括解読中... (0/\(targets.count))"; DispatchQueue.global(qos: .userInitiated).async { for file in targets { autoreleasepool { _ = KeyManager.decryptFile(inputURL: file.url, outputURL: FileManagerHelper.getCacheURL(for: file)) }; DispatchQueue.main.async { count += 1; processingMessage = "一括解読中... (\(count)/\(targets.count))" } }; DispatchQueue.main.async { isProcessing = false; refreshFiles() } } }
    func processSelectedPhotos() { guard !selectedItems.isEmpty else { return }; isProcessing = true; processingMessage = "極秘処理中...\n（そのままお待ちください）"; let items = selectedItems; selectedItems = []; DispatchQueue.global(qos: .userInitiated).async { for (index, item) in items.enumerated() { DispatchQueue.main.async { processingMessage = "極秘処理中... (\(index + 1)/\(items.count))" }; let semaphore = DispatchSemaphore(value: 0); let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "data"; item.loadTransferable(type: TempMediaFile.self) { result in if case .success(let media?) = result { autoreleasepool { KeyManager.createAndSaveKey(); _ = KeyManager.encryptFile(inputURL: media.url, outputURL: FileManagerHelper.generateNewFileURL(originalExtension: ext)); try? FileManager.default.removeItem(at: media.url) } }; semaphore.signal() }; semaphore.wait() }; DispatchQueue.main.async { refreshFiles(); isProcessing = false } } }
    func processImportedFiles(result: Result<[URL], Error>) { if case .success(let urls) = result { isProcessing = true; processingMessage = "極秘処理中..."; DispatchQueue.global(qos: .userInitiated).async { for (index, url) in urls.enumerated() { DispatchQueue.main.async { processingMessage = "極秘処理中... (\(index + 1)/\(urls.count))" }; autoreleasepool { if url.startAccessingSecurityScopedResource() { KeyManager.createAndSaveKey(); _ = KeyManager.encryptFile(inputURL: url, outputURL: FileManagerHelper.generateNewFileURL(originalExtension: url.pathExtension)); url.stopAccessingSecurityScopedResource() } } }; DispatchQueue.main.async { refreshFiles(); isProcessing = false } } } }
    func resetApp() { lastAccessDate = 0; isDestroyed = false; isUnlocked = false; secretFiles = []; KeyManager.destroyKey(); FileManagerHelper.deleteAllFiles(); FileManagerHelper.clearTempCache(); checkInitialSetup() }
}

// MARK: - 小さなUIパーツ
struct SectionHeader: View { let title: LocalizedStringKey; var body: some View { Text(title).font(.caption).fontWeight(.bold).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal) } }
struct TempMediaFile: Transferable { let url: URL; static var transferRepresentation: some TransferRepresentation { FileRepresentation(importedContentType: .item) { received in let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + received.file.lastPathComponent); try FileManager.default.copyItem(at: received.file, to: tempURL); return TempMediaFile(url: tempURL) } } }
struct ShareSheet: UIViewControllerRepresentable { var activityItems: [Any]; func makeUIViewController(context: Context) -> UIActivityViewController { return UIActivityViewController(activityItems: activityItems, applicationActivities: nil) }; func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {} }

// ▼ 🆕 追加：1秒ごとに更新される「文字だけ」を独立させた専用ビュー
struct TimerDisplayView: View {
    var isUnlocked: Bool
    @AppStorage("lastAccessDate") private var lastAccessDate: Double = 0
    @AppStorage("timerLimitSeconds") private var timerLimitSeconds: Double = 604800
    @State private var timeRemainingString: String = ""
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        Text(timeRemainingString)
            .font(.system(.title2, design: .monospaced))
            .fontWeight(.bold)
            .foregroundColor(isUnlocked ? .green : .red)
            .onReceive(timer) { _ in updateTime() }
            .onAppear { updateTime() }
    }
    
    func updateTime() {
        if lastAccessDate == 0 { return }
        let passed = Date().timeIntervalSince1970 - lastAccessDate
        if passed > timerLimitSeconds {
            timeRemainingString = "00日 00:00:00"
        } else {
            let rem = max(0, timerLimitSeconds - passed)
            let format = String(localized: "%02d日 %02d:%02d:%02d")
            timeRemainingString = String(format: format, Int(rem)/86400, (Int(rem)%86400)/3600, (Int(rem)%3600)/60, Int(rem)%60)
        }
    }
}

// MARK: - 自爆タイマー設定専用画面
struct TimerSetupView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("timerLimitSeconds") private var timerLimitSeconds: Double = 604800
    @AppStorage("lastAccessDate") private var lastAccessDate: Double = 0
    @State private var tempTimerLimit: Double = 604800
    
    let options: [(title: LocalizedStringKey, value: Double)] = [
        ("10分", 600), ("30分", 1800), ("1時間", 3600), ("1日", 86400),
        ("3日", 259200), ("1週間", 604800), ("1ヶ月", 2592000)
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 25) {
                Image(systemName: "timer").font(.system(size: 70)).foregroundColor(.red).padding(.top, 30)
                Text("自爆タイマー設定").font(.title2).bold()
                Text("設定した期間アプリを開かなかった場合、\nすべての極秘データが自動的に消去されます。").font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(options, id: \.value) { option in
                            Button(action: { tempTimerLimit = option.value }) {
                                HStack {
                                    Text(option.title).font(.headline).foregroundColor(tempTimerLimit == option.value ? .white : .primary)
                                    Spacer()
                                    if tempTimerLimit == option.value { Image(systemName: "checkmark.circle.fill").foregroundColor(.white) }
                                }
                                .padding().background(tempTimerLimit == option.value ? Color.red : Color.secondary.opacity(0.1)).cornerRadius(12)
                            }
                        }
                    }.padding(.horizontal, 30).padding(.top, 10)
                }
                
                Button(action: {
                    timerLimitSeconds = tempTimerLimit
                    lastAccessDate = Date().timeIntervalSince1970
                    dismiss()
                }) { Text("保存して閉じる").font(.headline).foregroundColor(.white).padding().frame(maxWidth: .infinity).background(Color.blue).cornerRadius(12) }.padding(.horizontal, 30).padding(.bottom, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("閉じる") { dismiss() } } }
            .onAppear { tempTimerLimit = timerLimitSeconds }
        }
    }
}
