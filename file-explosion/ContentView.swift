import SwiftUI
import LocalAuthentication
import PhotosUI
import UniformTypeIdentifiers

struct AppFolder: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var category: Int
}
enum FolderAlertMode { case create, rename }

enum FolderSelection: Hashable {
    case favorites
    case unclassified
    case folder(UUID)
}

struct ContentView: View {
    // MARK: - 状態管理
    @State var statusMessage: LocalizedStringKey = "認証してください"
    @State var isDestroyed = false
    @AppStorage("lastAccessDate") var lastAccessDate: Double = 0
    @AppStorage("timerLimitSeconds") var timerLimitSeconds: Double = 604800
    @AppStorage("appPasscode") var appPasscode: String = ""
    
    @State var isUnlocked = false
    @State var secretFiles: [SecretFile] = []
    
    // MARK: - フォルダ・お気に入り
    @State var appFolders: [AppFolder] = []
    @State var fileFolderMap: [UUID: UUID] = [:]
    @State var favoriteFileIDs: Set<UUID> = []
    
    @State var selectedAppFolderID: UUID? = nil
    @State var showingFavoritesOnly = false
    
    @State var showingFolderAlert = false
    @State var folderAlertMode: FolderAlertMode = .create
    @State var editingFolderName = ""
    @State var editingFolder: AppFolder? = nil
    @State var showingMoveDialog = false
    
    // MARK: - UI・インポート
    @State var selectedItems: [PhotosPickerItem] = []
    @State var showFileImporter = false
    @State var showingResetConfirmation = false
    @State var isProcessing = false
    @State var processingMessage: LocalizedStringKey = ""
    
    // MARK: - 選択・書き出し
    @State var isSelectionMode = false
    @State var selectedFileIDs: Set<UUID> = []
    @State var showingMultiDeleteConfirm = false
    @State var filesToShare: [URL] = []
    @State var showShareSheet = false
    
    // MARK: - 認証
    @State var inputPasscode = ""
    @State var faceIDFailCount = 0
    @State var showPasscodeEntry = false
    @State var showingPasscodeSetup = false
    @State var isFirstSetupMode = false
    @State var showingTimerSetup = false
    
    // MARK: - ギャラリー連携
    @State var showingGallery = false
    @State var galleryIndex: Int = 0
    @State var selectedFileForGallery: SecretFile? = nil
    
    // MARK: - 表示・タブ
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State var selectedFolder = 0
    @State var selectedMainTab = 0
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    private var isMacOrPad: Bool {
#if os(macOS)
        true
#else
        horizontalSizeClass == .regular
#endif
    }
    
    // MARK: - Mac/iPad用
    enum ViewMode { case grid, list }
    @State var viewMode: ViewMode = .grid
    @State var searchText = ""
    @State var sortOrder: [KeyPathComparator<SecretFile>] = [KeyPathComparator(\.creationDate, order: .reverse)]
    @State var folderSelection: FolderSelection? = .unclassified
    @State var macShowHome: Bool = true
    @State var isDropTargetedHome: Bool = false
    @State var isDropTargetedFiles: Bool = false
    @State var sidebarDropTarget: FolderSelection? = nil
    @State var macToastMessages: [MacToast] = []
    @State var gridItemFrames: [UUID: CGRect] = [:]
    @State var dragStartPos: CGPoint? = nil
    @State var dragCurrentPos: CGPoint? = nil
    
    // MARK: - Body
    /// 共通モディファイアはここに1か所にまとめる。
    /// プラットフォーム固有の実装は ContentView+iPhone.swift / ContentView+Mac.swift に分離。
    var body: some View {
        bodyContent
    }
    
    @ViewBuilder
    private var platformRootView: some View {
        if isMacOrPad {
            finderBody   // → ContentView+Mac.swift
        } else {
            iPhoneBody   // → ContentView+iPhone.swift
        }
    }
    
    private var baseBodyContent: some View {
        platformRootView
            .overlay { processingOverlay }
            .disabled(isProcessing)
            .onReceive(timer) { _ in checkTimeLimit() }
            .onAppear {
                FileManagerHelper.clearAllPlaintextResiduals()
                checkInitialSetup()
                loadFolders()
            }
            .onChange(of: scenePhase) { _, phase in
#if os(macOS)
                if (phase == .background || phase == .inactive) && isUnlocked { lockApp() }
                else if phase == .active { checkTimeLimit() }
#else
                if phase == .background && isUnlocked { lockApp() }
                else if phase == .active { checkTimeLimit() }
#endif
            }
            .onChange(of: selectedItems) { _, _ in processSelectedPhotos() }
            .onChange(of: timerLimitSeconds) { _, _ in lastAccessDate = Date().timeIntervalSince1970 }
    }
    
    private var bodyContent: some View {
        baseBodyContent
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.image, .movie, .pdf, .item],
                allowsMultipleSelection: true
            ) { result in processImportedFiles(result: result) }
#if os(iOS)
            .fullScreenCover(isPresented: $showingPasscodeSetup) {
                PasscodeSetupView(isUnlocked: $isUnlocked, isFirstSetup: isFirstSetupMode)
            }
            .fullScreenCover(isPresented: $showingGallery, onDismiss: {
                StorageCleaner.clearAllTempAndCacheData()
            }) { gallerySheetContent }
#else
            .sheet(isPresented: $showingPasscodeSetup) {
                PasscodeSetupView(isUnlocked: $isUnlocked, isFirstSetup: isFirstSetupMode)
            }
            .sheet(isPresented: $showingGallery, onDismiss: {
                StorageCleaner.clearAllTempAndCacheData()
            }) { gallerySheetContent }
#endif
            .sheet(isPresented: $showShareSheet, onDismiss: { cleanupExportedFiles() }) {
#if os(iOS)
                ShareSheet(activityItems: filesToShare)
#else
                Text("共有シートはMacではサポートされていません")
#endif
            }
#if os(iOS)
            .fullScreenCover(isPresented: $showingTimerSetup) { TimerSetupView() }
#else
            .sheet(isPresented: $showingTimerSetup) { TimerSetupView() }
#endif
            .alert(folderAlertMode == .create ? "新規フォルダ" : "名前を変更", isPresented: $showingFolderAlert) {
                TextField("フォルダ名", text: $editingFolderName)
                Button("キャンセル", role: .cancel) { editingFolderName = "" }
                Button(folderAlertMode == .create ? "作成" : "保存") {
                    if folderAlertMode == .create { createFolder() } else { renameFolder() }
                }
            }
            .confirmationDialog("移動先を選択", isPresented: $showingMoveDialog, titleVisibility: .visible) {
                Button("未分類に戻す") { moveSelectedFiles(to: nil) }
                ForEach(appFolders.filter { $0.category == selectedFolder }) { folder in
                    Button(folder.name) { moveSelectedFiles(to: folder) }
                }
                Button("キャンセル", role: .cancel) {}
            }
            .alert("【警告】システムの初期化", isPresented: $showingResetConfirmation) {
                Button("キャンセル", role: .cancel) { }
                Button("初期化を実行", role: .destructive) { resetApp() }
            } message: {
                Text("全てのデータが完全に消去されます。よろしいですか？\n※パスコード設定は維持されます。")
            }
            .alert("削除の確認", isPresented: $showingMultiDeleteConfirm) {
                Button("キャンセル", role: .cancel) { }
                Button("削除", role: .destructive) { deleteSelectedFiles() }
            } message: { Text("選択したファイルを完全に削除しますか？") }
    }
}

// MARK: - 共通UIパーツ
extension ContentView {
    
    @ViewBuilder
    var processingOverlay: some View {
        if isProcessing {
            ZStack {
                Color.black.opacity(0.4).ignoresSafeArea()
                VStack(spacing: 20) {
                    ProgressView().scaleEffect(1.5).tint(.white)
                    Text(processingMessage)
                        .font(.callout).fontWeight(.bold).foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
                .padding(30).background(Color.black.opacity(0.8)).cornerRadius(15)
            }
        }
    }
    
    var destroyedView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "bolt.slash.fill").font(.system(size: 60)).foregroundColor(.gray)
            Text("データは完全に消去されました。\n再構築が必要です。")
                .multilineTextAlignment(.center).foregroundColor(.gray)
            Button(action: { showingResetConfirmation = true }) {
                Text("システムを再構築")
                    .font(.headline).foregroundColor(.red).padding()
                    .frame(maxWidth: .infinity).background(Color.red.opacity(0.1)).cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red, lineWidth: 1))
            }.padding(.horizontal)
            Spacer()
        }
    }
    
    var gallerySheetContent: some View {
        GalleryView(
            files: currentFilteredFiles(for: selectedFolder),
            currentIndex: $galleryIndex,
            appFolders: appFolders,
            currentCategory: selectedFolder,
            isFavorite: { f in favoriteFileIDs.contains(f.id) },
            onToggleFavorite: { f in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    if favoriteFileIDs.contains(f.id) { favoriteFileIDs.remove(f.id) }
                    else { favoriteFileIDs.insert(f.id) }
                    saveFolders()
                }
            },
            onMove: { targetFile, folder in
                if let folder = folder { fileFolderMap[targetFile.id] = folder.id }
                else { fileFolderMap.removeValue(forKey: targetFile.id) }
                saveFolders(); adjustGalleryIndexAfterRemoval()
            },
            onDelete: { targetFile in
                fileFolderMap.removeValue(forKey: targetFile.id)
                favoriteFileIDs.remove(targetFile.id)
                try? FileManager.default.removeItem(at: targetFile.url)
                try? FileManager.default.removeItem(at: FileManagerHelper.getCacheURL(for: targetFile))
                saveFolders(); refreshFiles(); adjustGalleryIndexAfterRemoval()
            }
        )
        .toolbar(.hidden)
    }
    
    func adjustGalleryIndexAfterRemoval() {
        DispatchQueue.main.async {
            let newCount = currentFilteredFiles(for: selectedFolder).count
            if newCount == 0 { showingGallery = false }
            else if galleryIndex >= newCount { galleryIndex = newCount - 1 }
        }
    }
}

// MARK: - ビジネスロジック
extension ContentView {
    
    func loadFolders() {
        if let data = UserDefaults.standard.data(forKey: "appFolders"),
           let decoded = try? JSONDecoder().decode([AppFolder].self, from: data) { appFolders = decoded }
        if let data = UserDefaults.standard.data(forKey: "fileFolderMap"),
           let decoded = try? JSONDecoder().decode([UUID: UUID].self, from: data) { fileFolderMap = decoded }
        if let data = UserDefaults.standard.data(forKey: "favoriteFileIDs"),
           let decoded = try? JSONDecoder().decode(Set<UUID>.self, from: data) { favoriteFileIDs = decoded }
    }
    
    func saveFolders() {
        if let data = try? JSONEncoder().encode(appFolders) { UserDefaults.standard.set(data, forKey: "appFolders") }
        if let data = try? JSONEncoder().encode(fileFolderMap) { UserDefaults.standard.set(data, forKey: "fileFolderMap") }
        if let data = try? JSONEncoder().encode(favoriteFileIDs) { UserDefaults.standard.set(data, forKey: "favoriteFileIDs") }
    }
    
    func createFolder() {
        guard !editingFolderName.isEmpty else { return }
        appFolders.append(AppFolder(name: editingFolderName, category: selectedFolder))
        saveFolders(); editingFolderName = ""
    }
    
    func renameFolder() {
        guard !editingFolderName.isEmpty, let target = editingFolder,
              let index = appFolders.firstIndex(where: { $0.id == target.id }) else { return }
        appFolders[index].name = editingFolderName
        saveFolders(); editingFolderName = ""
    }
    
    func deleteFolder(_ folder: AppFolder) {
        appFolders.removeAll { $0.id == folder.id }
        for (fileID, folderID) in fileFolderMap where folderID == folder.id {
            fileFolderMap.removeValue(forKey: fileID)
        }
        saveFolders()
        if selectedAppFolderID == folder.id { selectedAppFolderID = nil }
    }
    
    func moveSelectedFiles(to folder: AppFolder?) {
        for fileID in selectedFileIDs {
            if let folder = folder { fileFolderMap[fileID] = folder.id }
            else { fileFolderMap.removeValue(forKey: fileID) }
        }
        saveFolders(); isSelectionMode = false; selectedFileIDs.removeAll()
    }
    
    func deleteSelectedFiles() {
        let targets = secretFiles.filter { selectedFileIDs.contains($0.id) }
        for file in targets {
            fileFolderMap.removeValue(forKey: file.id); favoriteFileIDs.remove(file.id)
            try? FileManager.default.removeItem(at: file.url)
            try? FileManager.default.removeItem(at: FileManagerHelper.getCacheURL(for: file))
        }
        saveFolders()
        withAnimation { isSelectionMode = false; selectedFileIDs.removeAll() }
        refreshFiles()
        StorageCleaner.clearAllTempAndCacheData()
    }
    
    func exportSelectedFiles() {
        isProcessing = true; processingMessage = "復号中..."
        let targets = secretFiles.filter { selectedFileIDs.contains($0.id) }
        DispatchQueue.global(qos: .userInitiated).async {
            var tempURLs: [URL] = []
            for file in targets {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Export_" + file.url.lastPathComponent)
                if KeyManager.decryptFile(inputURL: file.url, outputURL: tempURL) { tempURLs.append(tempURL) }
            }
            DispatchQueue.main.async {
                isProcessing = false
                if !tempURLs.isEmpty { self.filesToShare = tempURLs; self.showShareSheet = true }
            }
        }
    }
    
    func cleanupExportedFiles() {
        for url in filesToShare { try? FileManager.default.removeItem(at: url) }
        filesToShare.removeAll()
        withAnimation { isSelectionMode = false; selectedFileIDs.removeAll() }
    }
    
    func checkInitialSetup() {
        if appPasscode.isEmpty || lastAccessDate == 0 { isFirstSetupMode = true; showingPasscodeSetup = true }
        else { checkTimeLimit() }
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
        isProcessing = true; processingMessage = "システムを起動中..."
        DispatchQueue.global(qos: .userInitiated).async {
            KeyManager.createAndSaveKey()
            let loadedFiles = FileManagerHelper.getAllSecretFiles()
            DispatchQueue.main.async {
                self.secretFiles = loadedFiles; self.lastAccessDate = Date().timeIntervalSince1970
                self.isUnlocked = true; self.faceIDFailCount = 0
                self.showPasscodeEntry = false; self.inputPasscode = ""; self.isProcessing = false
            }
        }
    }
    
    func lockApp() {
        isUnlocked = false; secretFiles = []; FileManagerHelper.clearTempCache()
        isSelectionMode = false; selectedFileIDs.removeAll()
        showPasscodeEntry = false; inputPasscode = ""; faceIDFailCount = 0
        statusMessage = "認証してください"
        selectedAppFolderID = nil; showingFavoritesOnly = false; showingGallery = false
        macShowHome = true
    }
    
    func refreshFiles() { secretFiles = FileManagerHelper.getAllSecretFiles() }
    
    func checkTimeLimit() {
        if lastAccessDate == 0 || isDestroyed { return }
        let passed = Date().timeIntervalSince1970 - lastAccessDate
        if passed > timerLimitSeconds {
            isDestroyed = true
            KeyManager.destroyKey(); FileManagerHelper.deleteAllFiles(); FileManagerHelper.clearTempCache()
            appFolders.removeAll(); fileFolderMap.removeAll(); favoriteFileIDs.removeAll(); saveFolders()
        }
    }
    
    func batchDecryptAll() {
        let targets = secretFiles.filter { !FileManager.default.fileExists(atPath: FileManagerHelper.getCacheURL(for: $0).path) }
        if targets.isEmpty { return }
        isProcessing = true; var count = 0
        processingMessage = "一括解読中... (0/\(targets.count))"
        DispatchQueue.global(qos: .userInitiated).async {
            for file in targets {
                autoreleasepool { _ = KeyManager.decryptFile(inputURL: file.url, outputURL: FileManagerHelper.getCacheURL(for: file)) }
                DispatchQueue.main.async { count += 1; processingMessage = "一括解読中... (\(count)/\(targets.count))" }
            }
            DispatchQueue.main.async { isProcessing = false; refreshFiles() }
        }
    }
    
    func processSelectedPhotos() {
        guard !selectedItems.isEmpty else { return }
        isProcessing = true; processingMessage = "極秘処理中...\n（そのままお待ちください）"
        let items = selectedItems; selectedItems = []
        DispatchQueue.global(qos: .userInitiated).async {
            for (index, item) in items.enumerated() {
                DispatchQueue.main.async { processingMessage = "極秘処理中... (\(index + 1)/\(items.count))" }
                let semaphore = DispatchSemaphore(value: 0)
                item.loadTransferable(type: TempMediaFile.self) { result in
                    if case .success(let media?) = result {
                        autoreleasepool {
                            // 実際に受け取ったファイルの拡張子をそのまま使う（オリジナル形式を維持）
                            let ext = media.url.pathExtension.isEmpty ? "data" : media.url.pathExtension
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
        appFolders.removeAll(); fileFolderMap.removeAll(); favoriteFileIDs.removeAll(); saveFolders()
        checkInitialSetup()
        selectedAppFolderID = nil; showingFavoritesOnly = false; showingGallery = false
    }
    
    /// 指定ファイル群をキャッシュに事前解読する（表示の高速化）
    func preDecryptFiles(_ files: [SecretFile]) {
        let targets = files.filter { !FileManager.default.fileExists(atPath: FileManagerHelper.getCacheURL(for: $0).path) }
        guard !targets.isEmpty else { return }
        isProcessing = true
        var count = 0
        processingMessage = "解読中... (0/\(targets.count))"
        DispatchQueue.global(qos: .userInitiated).async {
            for file in targets {
                autoreleasepool { _ = KeyManager.decryptFile(inputURL: file.url, outputURL: FileManagerHelper.getCacheURL(for: file)) }
                DispatchQueue.main.async { count += 1; processingMessage = "解読中... (\(count)/\(targets.count))" }
            }
            DispatchQueue.main.async { isProcessing = false; refreshFiles() }
        }
    }
    
    /// 選択中のフォルダにあるファイルをすべて復号して書き出す
    func decryptCurrentFolderFiles() {
        let files = currentFilteredFiles(for: selectedFolder)
        guard !files.isEmpty else { return }
        selectedFileIDs = Set(files.map { $0.id })
        exportSelectedFiles()
    }
    
    func currentFilteredFiles(for folderIndex: Int) -> [SecretFile] {
        let catFiltered = secretFiles.filter { f in
            switch folderIndex {
            case 0: return f.isImage
            case 1: return f.isVideo
            case 2: return f.isPDF
            default: return !f.isImage && !f.isVideo && !f.isPDF
            }
        }
        if showingFavoritesOnly { return catFiltered.filter { favoriteFileIDs.contains($0.id) } }
        if let folderID = selectedAppFolderID { return catFiltered.filter { fileFolderMap[$0.id] == folderID } }
        return catFiltered.filter { fileFolderMap[$0.id] == nil }
    }
}

// MARK: - 共有UIコンポーネント（iPhone・Mac両方で使う）

struct FolderChip: View {
    let title: String
    var icon: String? = nil
    var customTint: Color = .blue
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon { Image(systemName: icon).font(.subheadline) }
                Text(title).font(.subheadline).fontWeight(isSelected ? .bold : .regular)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(isSelected ? customTint : Color.secondary.opacity(0.15))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey
    var body: some View {
        Text(title).font(.caption).fontWeight(.bold).foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
    }
}

struct TempMediaFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .item) { received in
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "_" + received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            return TempMediaFile(url: tempURL)
        }
    }
}

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

struct TimerDisplayView: View {
    var isUnlocked: Bool
    @AppStorage("lastAccessDate") private var lastAccessDate: Double = 0
    @AppStorage("timerLimitSeconds") private var timerLimitSeconds: Double = 604800
    @State private var timeRemainingString: String = ""
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        Text(timeRemainingString)
            .font(.system(.title2, design: .monospaced)).fontWeight(.bold)
            .foregroundColor(isUnlocked ? .green : .red)
            .onReceive(timer) { _ in updateTime() }
            .onAppear { updateTime() }
    }
    
    func updateTime() {
        if lastAccessDate == 0 { return }
        let passed = Date().timeIntervalSince1970 - lastAccessDate
        if passed > timerLimitSeconds {
            timeRemainingString = "00:00:00"
        } else {
            let rem = max(0, timerLimitSeconds - passed)
            let days = Int(rem) / 86400
            let hours = (Int(rem) % 86400) / 3600
            let minutes = (Int(rem) % 3600) / 60
            let seconds = Int(rem) % 60
            if days > 0 {
                let format = String(localized: "%02d日 %02d:%02d:%02d")
                timeRemainingString = String(format: format, days, hours, minutes, seconds)
            } else {
                timeRemainingString = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            }
        }
    }
}

struct TimerSetupView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("timerLimitSeconds") private var timerLimitSeconds: Double = 604800
    @AppStorage("lastAccessDate") private var lastAccessDate: Double = 0
    @State private var tempTimerLimit: Double = 604800
    
    let options: [(title: LocalizedStringKey, value: Double)] = [
        ("10分", 600), ("30分", 1800), ("1時間", 3600),
        ("1日", 86400), ("3日", 259200), ("1週間", 604800), ("1ヶ月", 2592000)
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 25) {
                Image(systemName: "timer").font(.system(size: 70)).foregroundColor(.red).padding(.top, 30)
                Text("自爆タイマー設定").font(.title2).bold()
                Text("設定した期間アプリを開かなかった場合、\nすべての極秘データが自動的に消去されます。")
                    .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(options, id: \.value) { option in
                            Button(action: { tempTimerLimit = option.value }) {
                                HStack {
                                    Text(option.title).font(.headline)
                                        .foregroundColor(tempTimerLimit == option.value ? .white : .primary)
                                    Spacer()
                                    if tempTimerLimit == option.value {
                                        Image(systemName: "checkmark.circle.fill").foregroundColor(.white)
                                    }
                                }
                                .padding()
                                .background(tempTimerLimit == option.value ? Color.red : Color.secondary.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal, 30).padding(.top, 10)
                }
                Button(action: {
                    timerLimitSeconds = tempTimerLimit
                    lastAccessDate = Date().timeIntervalSince1970
                    dismiss()
                }) {
                    Text("保存して閉じる")
                        .font(.headline).foregroundColor(.white).padding()
                        .frame(maxWidth: .infinity).background(Color.blue).cornerRadius(12)
                }
                .padding(.horizontal, 30).padding(.bottom, 20)
            }
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) { Button("閉じる") { dismiss() } }
#else
                ToolbarItem(placement: .automatic) { Button("閉じる") { dismiss() } }
#endif
            }
            .onAppear { tempTimerLimit = timerLimitSeconds }
        }
    }
}

// MARK: - Mac Toast
struct MacToast: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let count: Int
}

struct MacToastView: View {
    let toast: MacToast
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.icon)
                .foregroundColor(toast.color)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title).font(.headline)
                Text("\(toast.count)件をアップロードしました").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 6)
        .padding(.horizontal, 16)
        .frame(maxWidth: 320)
    }
}
