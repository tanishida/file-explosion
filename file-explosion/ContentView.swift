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

struct ContentView: View {
    // --- 状態管理 ---
    @State private var statusMessage: LocalizedStringKey = "認証してください"
    @State private var isDestroyed = false
    @AppStorage("lastAccessDate") private var lastAccessDate: Double = 0
    @AppStorage("timerLimitSeconds") private var timerLimitSeconds: Double = 604800
    @AppStorage("appPasscode") private var appPasscode: String = ""
    
    @State private var isUnlocked = false
    @State private var secretFiles: [SecretFile] = []
    
    // --- フォルダ・お気に入り関連 ---
    @State private var appFolders: [AppFolder] = []
    @State private var fileFolderMap: [UUID: UUID] = [:]
    @State private var favoriteFileIDs: Set<UUID> = []
    
    @State private var selectedAppFolderID: UUID? = nil
    @State private var showingFavoritesOnly = false
    
    @State private var showingFolderAlert = false
    @State private var folderAlertMode: FolderAlertMode = .create
    @State private var editingFolderName = ""
    @State private var editingFolder: AppFolder? = nil
    @State private var showingMoveDialog = false
    
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
    
    // --- ギャラリー連携 ---
    @State private var showingGallery = false
    @State private var galleryIndex: Int = 0
    @State private var selectedFileForGallery: SecretFile? = nil
    
    // --- 表示・タブ関連 ---
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var selectedFolder = 0
    @State private var selectedMainTab = 0
    @Environment(\.scenePhase) var scenePhase
    
    func currentFilteredFiles(for categoryIndex: Int) -> [SecretFile] {
        secretFiles.filter { f in
            let matchCat = (categoryIndex == 0 && f.isImage) || (categoryIndex == 1 && f.isVideo) || (categoryIndex == 2 && f.isPDF) || (categoryIndex == 3 && !f.isImage && !f.isVideo && !f.isPDF)
            if !matchCat { return false }
            if showingFavoritesOnly { return favoriteFileIDs.contains(f.id) }
            if let folderID = selectedAppFolderID { return fileFolderMap[f.id] == folderID }
            else { return fileFolderMap[f.id] == nil && !favoriteFileIDs.contains(f.id) }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 5) {
                    if isDestroyed { Text("【警告】システム停止").font(.subheadline).foregroundColor(.red) }
                    else if isUnlocked { Text("ロック解除中").font(.subheadline).foregroundColor(.green) }
                    else { Text(statusMessage).font(.subheadline).foregroundColor(.primary) }
                    if !isDestroyed && lastAccessDate != 0 { TimerDisplayView(isUnlocked: isUnlocked) }
                }.padding(.vertical, 12).frame(maxWidth: .infinity).background(Color.secondary.opacity(0.05))
                Divider()
                
                if isDestroyed {
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: "bolt.slash.fill").font(.system(size: 60)).foregroundColor(.gray)
                        Text("データは完全に消去されました。\n再構築が必要です。").multilineTextAlignment(.center).foregroundColor(.gray)
                        Button(action: { showingResetConfirmation = true }) { Text("システムを再構築").font(.headline).foregroundColor(.red).padding().frame(maxWidth: .infinity).background(Color.red.opacity(0.1)).cornerRadius(10).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red, lineWidth: 1)) }.padding(.horizontal)
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
            .navigationTitle("LimitBox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isUnlocked {
                    // ▼ 🆕 追加：選択モードの時だけ、左上に「全選択 / 全解除」ボタンを配置
                    if isSelectionMode {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: {
                                // 今画面に表示されているファイルのリストを取得
                                let currentFiles = currentFilteredFiles(for: selectedFolder)
                                
                                if selectedFileIDs.count == currentFiles.count && !currentFiles.isEmpty {
                                    // すべて選択されていれば、全解除
                                    selectedFileIDs.removeAll()
                                } else {
                                    // 1つでも未選択があれば、表示中のファイルを全選択
                                    selectedFileIDs = Set(currentFiles.map { $0.id })
                                }
                            }) {
                                let currentFiles = currentFilteredFiles(for: selectedFolder)
                                Text(selectedFileIDs.count == currentFiles.count && !currentFiles.isEmpty ? "すべて選択解除" : "すべて選択")
                                    .font(.body)
                            }
                        }
                    }
                    
                    // ▼ 既存の右上のボタン（完了ボタン / メニュー）
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if isSelectionMode {
                            Button(action: { withAnimation { isSelectionMode = false; selectedFileIDs.removeAll() } }) { Image(systemName: "xmark").font(.title3).fontWeight(.bold) }
                        } else {
                            Menu {
                                if selectedMainTab == 1 { Button(action: { withAnimation { isSelectionMode = true; selectedFileIDs.removeAll() } }) { Label("選択", systemImage: "checkmark.circle") }; Divider() }
                                Button(action: { showingTimerSetup = true }) { Label("自爆タイマー", systemImage: "timer") }
                                Button(role: .destructive, action: { showingResetConfirmation = true }) { Label("システムを初期化", systemImage: "trash") }
                            } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                        }
                    }
                }
            }
            .onChange(of: selectedMainTab) { newValue in if newValue == 0 { isSelectionMode = false; selectedFileIDs.removeAll() } }
            .onChange(of: selectedFolder) { _ in selectedAppFolderID = nil; showingFavoritesOnly = false }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image, .movie, .pdf, .item], allowsMultipleSelection: true) { result in processImportedFiles(result: result) }
            .onChange(of: selectedItems) { _ in processSelectedPhotos() }
            .onChange(of: timerLimitSeconds) { _ in lastAccessDate = Date().timeIntervalSince1970 }
            .fullScreenCover(isPresented: $showingPasscodeSetup) { PasscodeSetupView(isUnlocked: $isUnlocked, isFirstSetup: isFirstSetupMode) }
            
            .fullScreenCover(isPresented: $showingGallery) {
                GalleryView(
                    files: currentFilteredFiles(for: selectedFolder),
                    currentIndex: $galleryIndex,
                    appFolders: appFolders,
                    currentCategory: selectedFolder,
                    isFavorite: { f in favoriteFileIDs.contains(f.id) },
                    onToggleFavorite: { f in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                            if favoriteFileIDs.contains(f.id) { favoriteFileIDs.remove(f.id) } else { favoriteFileIDs.insert(f.id) }
                            saveFolders()
                        }
                    },
                    onMove: { targetFile, folder in
                        if let folder = folder { fileFolderMap[targetFile.id] = folder.id } else { fileFolderMap.removeValue(forKey: targetFile.id) }
                        saveFolders(); adjustGalleryIndexAfterRemoval()
                    },
                    onDelete: { targetFile in
                        fileFolderMap.removeValue(forKey: targetFile.id); favoriteFileIDs.remove(targetFile.id)
                        try? FileManager.default.removeItem(at: targetFile.url); try? FileManager.default.removeItem(at: FileManagerHelper.getCacheURL(for: targetFile))
                        saveFolders(); refreshFiles(); adjustGalleryIndexAfterRemoval()
                    }
                )
            }
            
            .sheet(isPresented: $showShareSheet, onDismiss: { cleanupExportedFiles() }) { ShareSheet(activityItems: filesToShare) }
            .fullScreenCover(isPresented: $showingTimerSetup) { TimerSetupView() }
            .alert(folderAlertMode == .create ? "新規フォルダ" : "名前を変更", isPresented: $showingFolderAlert) { TextField("フォルダ名", text: $editingFolderName); Button("キャンセル", role: .cancel) { editingFolderName = "" }; Button(folderAlertMode == .create ? "作成" : "保存") { if folderAlertMode == .create { createFolder() } else { renameFolder() } } }
            .confirmationDialog("移動先を選択", isPresented: $showingMoveDialog, titleVisibility: .visible) { Button("未分類に戻す") { moveSelectedFiles(to: nil) }; ForEach(appFolders.filter { $0.category == selectedFolder }) { folder in Button(folder.name) { moveSelectedFiles(to: folder) } }; Button("キャンセル", role: .cancel) {} }
            .alert("【警告】システムの初期化", isPresented: $showingResetConfirmation) { Button("キャンセル", role: .cancel) { }; Button("初期化を実行", role: .destructive) { resetApp() } } message: { Text("全てのデータが完全に消去されます。よろしいですか？\n※パスコード設定は維持されます。") }
            .alert("削除の確認", isPresented: $showingMultiDeleteConfirm) { Button("キャンセル", role: .cancel) { }; Button("削除", role: .destructive) { deleteSelectedFiles() } } message: { Text("選択したファイルを完全に削除しますか？") }
        }
        .overlay {
            if isProcessing { ZStack { Color.black.opacity(0.4).ignoresSafeArea(); VStack(spacing: 20) { ProgressView().scaleEffect(1.5).tint(.white); Text(processingMessage).font(.callout).fontWeight(.bold).foregroundColor(.white).multilineTextAlignment(.center) }.padding(30).background(Color.black.opacity(0.8)).cornerRadius(15) } }
        }
        .disabled(isProcessing)
        .onReceive(timer) { _ in checkTimeLimit() }
        .onAppear { checkInitialSetup(); loadFolders() }
        .onChange(of: scenePhase) { phase in if (phase == .background || phase == .inactive) && isUnlocked { lockApp() } else if phase == .active { checkTimeLimit() } }
    }
    
    func adjustGalleryIndexAfterRemoval() {
        DispatchQueue.main.async {
            let newCount = currentFilteredFiles(for: selectedFolder).count
            if newCount == 0 { showingGallery = false } else if galleryIndex >= newCount { galleryIndex = newCount - 1 }
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
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // ▼ 🆕 未分類フォルダのコンテキストメニューに書き出しを追加！
                    FolderChip(title: "未分類", icon: "tray.2.fill", customTint: .blue, isSelected: selectedAppFolderID == nil && !showingFavoritesOnly) { selectedAppFolderID = nil; showingFavoritesOnly = false }
                        .contextMenu {
                            Button(action: {
                                let targets = secretFiles.filter { f in
                                    let matchCat = (selectedFolder == 0 && f.isImage) || (selectedFolder == 1 && f.isVideo) || (selectedFolder == 2 && f.isPDF) || (selectedFolder == 3 && !f.isImage && !f.isVideo && !f.isPDF)
                                    return matchCat && fileFolderMap[f.id] == nil && !favoriteFileIDs.contains(f.id)
                                }
                                if !targets.isEmpty { selectedFileIDs = Set(targets.map { $0.id }); exportSelectedFiles() }
                            }) { Label("書き出し", systemImage: "square.and.arrow.up") }
                        }
                    
                    FolderChip(title: "お気に入り", icon: "heart.fill", customTint: .pink, isSelected: showingFavoritesOnly) { selectedAppFolderID = nil; showingFavoritesOnly = true }
                        .contextMenu {
                            Button(action: {
                                let targets = secretFiles.filter { f in
                                    let matchCat = (selectedFolder == 0 && f.isImage) || (selectedFolder == 1 && f.isVideo) || (selectedFolder == 2 && f.isPDF) || (selectedFolder == 3 && !f.isImage && !f.isVideo && !f.isPDF)
                                    return matchCat && favoriteFileIDs.contains(f.id)
                                }
                                if !targets.isEmpty { selectedFileIDs = Set(targets.map { $0.id }); exportSelectedFiles() }
                            }) { Label("書き出し", systemImage: "square.and.arrow.up") }
                        }
                    
                    ForEach(appFolders.filter { $0.category == selectedFolder }) { folder in
                        FolderChip(title: folder.name, icon: "folder.fill", customTint: .blue, isSelected: selectedAppFolderID == folder.id && !showingFavoritesOnly) { selectedAppFolderID = folder.id; showingFavoritesOnly = false }
                            .contextMenu {
                                // ▼ 🆕 カスタムフォルダのコンテキストメニューに書き出しを追加！
                                Button(action: {
                                    let targets = secretFiles.filter { fileFolderMap[$0.id] == folder.id }
                                    if !targets.isEmpty { selectedFileIDs = Set(targets.map { $0.id }); exportSelectedFiles() }
                                }) { Label("書き出し", systemImage: "square.and.arrow.up") }
                                
                                Button { editingFolder = folder; editingFolderName = folder.name; folderAlertMode = .rename; showingFolderAlert = true } label: { Label("名前を変更", systemImage: "pencil") }
                                Button(role: .destructive) { deleteFolder(folder) } label: { Label("削除", systemImage: "trash") }
                            }
                    }
                    Button(action: { editingFolderName = ""; folderAlertMode = .create; showingFolderAlert = true }) { Image(systemName: "plus.circle.fill").font(.title2).foregroundColor(.blue) }
                }.padding(.horizontal)
            }.padding(.bottom, 10)
            
            Divider()
            
            TabView(selection: $selectedFolder) { fileGrid(for: 0).tag(0); fileGrid(for: 1).tag(1); fileGrid(for: 2).tag(2); fileGrid(for: 3).tag(3) }
                .tabViewStyle(.page(indexDisplayMode: .never)).animation(.easeInOut, value: selectedFolder)
            
            if isSelectionMode {
                Divider()
                HStack {
                    Button(action: { exportSelectedFiles() }) { VStack { Image(systemName: "square.and.arrow.up").font(.title2); Text("書き出し").font(.caption) } }.disabled(selectedFileIDs.isEmpty)
                    Spacer()
                    Button(action: { showingMoveDialog = true }) { VStack { Image(systemName: "folder").font(.title2); Text("移動").font(.caption) } }.foregroundColor(selectedFileIDs.isEmpty ? .gray : .blue).disabled(selectedFileIDs.isEmpty)
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
        let filtered = currentFilteredFiles(for: folderIndex)
        
        if filtered.isEmpty {
            let emptyMsg = showingFavoritesOnly ? "お気に入りがありません" : (selectedAppFolderID == nil ? "未分類のファイルがありません" : "このフォルダは空です")
            VStack { Spacer(); Text(String(localized: String.LocalizationValue(emptyMsg))).foregroundColor(.gray); Spacer() }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)], spacing: 10) {
                    ForEach(filtered) { file in
                        ZStack(alignment: .bottomTrailing) {
                            FileThumbnailView(file: file) {
                                if isSelectionMode {
                                    if selectedFileIDs.contains(file.id) { selectedFileIDs.remove(file.id) } else { selectedFileIDs.insert(file.id) }
                                } else {
                                    if let idx = filtered.firstIndex(where: { $0.id == file.id }) { galleryIndex = idx; showingGallery = true }
                                }
                            }
                            .contextMenu {
                                if !isSelectionMode {
                                    Button(action: { selectedFileIDs = [file.id]; exportSelectedFiles() }) { Label("書き出し", systemImage: "square.and.arrow.up") }
                                    Button(action: { selectedFileIDs = [file.id]; showingMoveDialog = true }) { Label("移動", systemImage: "folder") }
                                    Button(role: .destructive, action: { selectedFileIDs = [file.id]; showingMultiDeleteConfirm = true }) { Label("削除", systemImage: "trash") }
                                }
                            }
                            
                            if isSelectionMode { Image(systemName: selectedFileIDs.contains(file.id) ? "checkmark.circle.fill" : "circle").font(.title2).foregroundColor(selectedFileIDs.contains(file.id) ? .blue : .white).background(Circle().fill(Color.black.opacity(0.3))).padding(6).allowsHitTesting(false) }
                        }
                        .overlay(alignment: .bottomLeading) {
                            if !isSelectionMode {
                                Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { if favoriteFileIDs.contains(file.id) { favoriteFileIDs.remove(file.id) } else { favoriteFileIDs.insert(file.id) }; saveFolders() } }) { Image(systemName: favoriteFileIDs.contains(file.id) ? "heart.fill" : "heart").font(.title3).foregroundColor(favoriteFileIDs.contains(file.id) ? .pink : .white).frame(width: 36, height: 36).background(Circle().fill(Color.black.opacity(0.4))).contentShape(Circle()) }.buttonStyle(.plain).padding(8).transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                }.padding().animation(.easeInOut(duration: 0.2), value: isSelectionMode)
            }
        }
    }
    
    // MARK: - フォルダ・お気に入り操作ロジック
    func loadFolders() { if let data = UserDefaults.standard.data(forKey: "appFolders"), let decoded = try? JSONDecoder().decode([AppFolder].self, from: data) { appFolders = decoded }; if let data = UserDefaults.standard.data(forKey: "fileFolderMap"), let decoded = try? JSONDecoder().decode([UUID: UUID].self, from: data) { fileFolderMap = decoded }; if let data = UserDefaults.standard.data(forKey: "favoriteFileIDs"), let decoded = try? JSONDecoder().decode(Set<UUID>.self, from: data) { favoriteFileIDs = decoded } }
    func saveFolders() { if let data = try? JSONEncoder().encode(appFolders) { UserDefaults.standard.set(data, forKey: "appFolders") }; if let data = try? JSONEncoder().encode(fileFolderMap) { UserDefaults.standard.set(data, forKey: "fileFolderMap") }; if let data = try? JSONEncoder().encode(favoriteFileIDs) { UserDefaults.standard.set(data, forKey: "favoriteFileIDs") } }
    func createFolder() { guard !editingFolderName.isEmpty else { return }; appFolders.append(AppFolder(name: editingFolderName, category: selectedFolder)); saveFolders(); editingFolderName = "" }
    func renameFolder() { guard !editingFolderName.isEmpty, let target = editingFolder, let index = appFolders.firstIndex(where: { $0.id == target.id }) else { return }; appFolders[index].name = editingFolderName; saveFolders(); editingFolderName = "" }
    func deleteFolder(_ folder: AppFolder) { appFolders.removeAll { $0.id == folder.id }; for (fileID, folderID) in fileFolderMap { if folderID == folder.id { fileFolderMap.removeValue(forKey: fileID) } }; saveFolders(); if selectedAppFolderID == folder.id { selectedAppFolderID = nil } }
    func moveSelectedFiles(to folder: AppFolder?) { for fileID in selectedFileIDs { if let folder = folder { fileFolderMap[fileID] = folder.id } else { fileFolderMap.removeValue(forKey: fileID) } }; saveFolders(); isSelectionMode = false; selectedFileIDs.removeAll() }
    
    // MARK: - メインロジック群
    func deleteSelectedFiles() {
        let targets = secretFiles.filter { selectedFileIDs.contains($0.id) }
        for file in targets {
            fileFolderMap.removeValue(forKey: file.id)
            favoriteFileIDs.remove(file.id)
            try? FileManager.default.removeItem(at: file.url)
            try? FileManager.default.removeItem(at: FileManagerHelper.getCacheURL(for: file))
        }
        saveFolders()
        withAnimation { isSelectionMode = false; selectedFileIDs.removeAll() }
        refreshFiles()
        
        StorageCleaner.clearAllTempAndCacheData()
    }
    func exportSelectedFiles() { isProcessing = true; processingMessage = "復号中..."; let targets = secretFiles.filter { selectedFileIDs.contains($0.id) }; DispatchQueue.global(qos: .userInitiated).async { var tempURLs: [URL] = []; for file in targets { let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Export_" + file.url.lastPathComponent); if KeyManager.decryptFile(inputURL: file.url, outputURL: tempURL) { tempURLs.append(tempURL) } }; DispatchQueue.main.async { isProcessing = false; if !tempURLs.isEmpty { self.filesToShare = tempURLs; self.showShareSheet = true } } } }
    func cleanupExportedFiles() { for url in filesToShare { try? FileManager.default.removeItem(at: url) }; filesToShare.removeAll(); withAnimation { isSelectionMode = false; selectedFileIDs.removeAll() } }
    func checkInitialSetup() { if appPasscode.isEmpty || lastAccessDate == 0 { isFirstSetupMode = true; showingPasscodeSetup = true } else { checkTimeLimit() } }
    func authenticate() { let context = LAContext(); if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) { context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "システムを解除します") { success, _ in DispatchQueue.main.async { if success { unlockSystem() } else { faceIDFailCount += 1; if faceIDFailCount >= 3 { showPasscodeEntry = true; statusMessage = "パスコードを入力してください" } else { statusMessage = "認証失敗 (\(faceIDFailCount)/3)" } } } } } else { showPasscodeEntry = true } }
    func unlockSystem() { isProcessing = true; processingMessage = "システムを起動中..."; DispatchQueue.global(qos: .userInitiated).async { KeyManager.createAndSaveKey(); let loadedFiles = FileManagerHelper.getAllSecretFiles(); DispatchQueue.main.async { self.secretFiles = loadedFiles; self.lastAccessDate = Date().timeIntervalSince1970; self.isUnlocked = true; self.faceIDFailCount = 0; self.showPasscodeEntry = false; self.inputPasscode = ""; self.isProcessing = false } } }
    func lockApp() { isUnlocked = false; secretFiles = []; FileManagerHelper.clearTempCache(); isSelectionMode = false; selectedFileIDs.removeAll(); showPasscodeEntry = false; inputPasscode = ""; faceIDFailCount = 0; statusMessage = "認証してください"; selectedAppFolderID = nil; showingFavoritesOnly = false; showingGallery = false }
    func refreshFiles() { secretFiles = FileManagerHelper.getAllSecretFiles() }
    func checkTimeLimit() { if lastAccessDate == 0 || isDestroyed { return }; let passed = Date().timeIntervalSince1970 - lastAccessDate; if passed > timerLimitSeconds { isDestroyed = true; KeyManager.destroyKey(); FileManagerHelper.deleteAllFiles(); FileManagerHelper.clearTempCache(); appFolders.removeAll(); fileFolderMap.removeAll(); favoriteFileIDs.removeAll(); saveFolders() } }
    func batchDecryptAll() { let targets = secretFiles.filter { !FileManager.default.fileExists(atPath: FileManagerHelper.getCacheURL(for: $0).path) }; if targets.isEmpty { return }; isProcessing = true; var count = 0; processingMessage = "一括解読中... (0/\(targets.count))"; DispatchQueue.global(qos: .userInitiated).async { for file in targets { autoreleasepool { _ = KeyManager.decryptFile(inputURL: file.url, outputURL: FileManagerHelper.getCacheURL(for: file)) }; DispatchQueue.main.async { count += 1; processingMessage = "一括解読中... (\(count)/\(targets.count))" } }; DispatchQueue.main.async { isProcessing = false; refreshFiles() } } }
    func processSelectedPhotos() { guard !selectedItems.isEmpty else { return }; isProcessing = true; processingMessage = "極秘処理中...\n（そのままお待ちください）"; let items = selectedItems; selectedItems = []; DispatchQueue.global(qos: .userInitiated).async { for (index, item) in items.enumerated() { DispatchQueue.main.async { processingMessage = "極秘処理中... (\(index + 1)/\(items.count))" }; let semaphore = DispatchSemaphore(value: 0); let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "data"; item.loadTransferable(type: TempMediaFile.self) { result in if case .success(let media?) = result { autoreleasepool { KeyManager.createAndSaveKey(); _ = KeyManager.encryptFile(inputURL: media.url, outputURL: FileManagerHelper.generateNewFileURL(originalExtension: ext)); try? FileManager.default.removeItem(at: media.url) } }; semaphore.signal() }; semaphore.wait() }; DispatchQueue.main.async { refreshFiles(); isProcessing = false } } }
    func processImportedFiles(result: Result<[URL], Error>) { if case .success(let urls) = result { isProcessing = true; processingMessage = "極秘処理中..."; DispatchQueue.global(qos: .userInitiated).async { for (index, url) in urls.enumerated() { DispatchQueue.main.async { processingMessage = "極秘処理中... (\(index + 1)/\(urls.count))" }; autoreleasepool { if url.startAccessingSecurityScopedResource() { KeyManager.createAndSaveKey(); _ = KeyManager.encryptFile(inputURL: url, outputURL: FileManagerHelper.generateNewFileURL(originalExtension: url.pathExtension)); url.stopAccessingSecurityScopedResource() } } }; DispatchQueue.main.async { refreshFiles(); isProcessing = false } } } }
    func resetApp() { lastAccessDate = 0; isDestroyed = false; isUnlocked = false; secretFiles = []; KeyManager.destroyKey(); FileManagerHelper.deleteAllFiles(); FileManagerHelper.clearTempCache(); appFolders.removeAll(); fileFolderMap.removeAll(); favoriteFileIDs.removeAll(); saveFolders(); checkInitialSetup(); selectedAppFolderID = nil; showingFavoritesOnly = false; showingGallery = false }
}

// MARK: - 小さなUIパーツ
struct FolderChip: View {
    let title: String; var icon: String? = nil; var customTint: Color = .blue; let isSelected: Bool; let action: () -> Void
    var body: some View { Button(action: action) { HStack(spacing: 6) { if let icon = icon { Image(systemName: icon).font(.subheadline) }; Text(title).font(.subheadline).fontWeight(isSelected ? .bold : .regular) }.padding(.horizontal, 16).padding(.vertical, 8).background(isSelected ? customTint : Color.secondary.opacity(0.15)).foregroundColor(isSelected ? .white : .primary).cornerRadius(20) } }
}

struct SectionHeader: View { let title: LocalizedStringKey; var body: some View { Text(title).font(.caption).fontWeight(.bold).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal) } }
struct TempMediaFile: Transferable { let url: URL; static var transferRepresentation: some TransferRepresentation { FileRepresentation(importedContentType: .item) { received in let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + received.file.lastPathComponent); try FileManager.default.copyItem(at: received.file, to: tempURL); return TempMediaFile(url: tempURL) } } }
struct ShareSheet: UIViewControllerRepresentable { var activityItems: [Any]; func makeUIViewController(context: Context) -> UIActivityViewController { return UIActivityViewController(activityItems: activityItems, applicationActivities: nil) }; func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {} }

struct TimerDisplayView: View {
    var isUnlocked: Bool; @AppStorage("lastAccessDate") private var lastAccessDate: Double = 0; @AppStorage("timerLimitSeconds") private var timerLimitSeconds: Double = 604800; @State private var timeRemainingString: String = ""
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View { Text(timeRemainingString).font(.system(.title2, design: .monospaced)).fontWeight(.bold).foregroundColor(isUnlocked ? .green : .red).onReceive(timer) { _ in updateTime() }.onAppear { updateTime() } }
    func updateTime() { if lastAccessDate == 0 { return }; let passed = Date().timeIntervalSince1970 - lastAccessDate; if passed > timerLimitSeconds { timeRemainingString = "00日 00:00:00" } else { let rem = max(0, timerLimitSeconds - passed); let format = String(localized: "%02d日 %02d:%02d:%02d"); timeRemainingString = String(format: format, Int(rem)/86400, (Int(rem)%86400)/3600, (Int(rem)%3600)/60, Int(rem)%60) } }
}

struct TimerSetupView: View {
    @Environment(\.dismiss) var dismiss; @AppStorage("timerLimitSeconds") private var timerLimitSeconds: Double = 604800; @AppStorage("lastAccessDate") private var lastAccessDate: Double = 0; @State private var tempTimerLimit: Double = 604800
    let options: [(title: LocalizedStringKey, value: Double)] = [ ("10分", 600), ("30分", 1800), ("1時間", 3600), ("1日", 86400), ("3日", 259200), ("1週間", 604800), ("1ヶ月", 2592000) ]
    var body: some View {
        NavigationStack {
            VStack(spacing: 25) {
                Image(systemName: "timer").font(.system(size: 70)).foregroundColor(.red).padding(.top, 30); Text("自爆タイマー設定").font(.title2).bold(); Text("設定した期間アプリを開かなかった場合、\nすべての極秘データが自動的に消去されます。").font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                ScrollView { VStack(spacing: 12) { ForEach(options, id: \.value) { option in Button(action: { tempTimerLimit = option.value }) { HStack { Text(option.title).font(.headline).foregroundColor(tempTimerLimit == option.value ? .white : .primary); Spacer(); if tempTimerLimit == option.value { Image(systemName: "checkmark.circle.fill").foregroundColor(.white) } }.padding().background(tempTimerLimit == option.value ? Color.red : Color.secondary.opacity(0.1)).cornerRadius(12) } } }.padding(.horizontal, 30).padding(.top, 10) }
                Button(action: { timerLimitSeconds = tempTimerLimit; lastAccessDate = Date().timeIntervalSince1970; dismiss() }) { Text("保存して閉じる").font(.headline).foregroundColor(.white).padding().frame(maxWidth: .infinity).background(Color.blue).cornerRadius(12) }.padding(.horizontal, 30).padding(.bottom, 20)
            }.navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("閉じる") { dismiss() } } }.onAppear { tempTimerLimit = timerLimitSeconds }
        }
    }
}
