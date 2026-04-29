import SwiftUI
import PhotosUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Mac / iPad Body
extension ContentView {
    
    var macLockScreenView: some View {
        VStack(spacing: 30) {
            Spacer()
            Image(systemName: showPasscodeEntry ? "lock.shield.fill" : "touchid")
                .font(.system(size: 60))
                .foregroundColor(showPasscodeEntry ? .orange : .blue)
            
            if showPasscodeEntry {
                VStack(spacing: 20) {
                    Text("パスコードを入力")
                        .font(.headline)
                    
                    PasscodeField(title: "4桁の数字", text: $inputPasscode)
                    
                    Button(action: {
                        if inputPasscode == appPasscode {
                            unlockSystem()
                        } else {
                            statusMessage = "❌ パスコード不一致"
                            inputPasscode = ""
                        }
                    }) {
                        Text("解除する")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(width: 200)
                            .background(Color.orange)
                            .cornerRadius(10)
                    }
                    .disabled(inputPasscode.count < 4)
                    
                    Button("生体認証に戻る") {
                        showPasscodeEntry = false
                    }
                    .font(.caption)
                    .foregroundColor(.gray)
                }
            } else {
                Button(action: { authenticate() }) {
                    HStack {
                        Image(systemName: "touchid")
                        Text("生体認証でロック解除")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(width: 260)
                    .background(Color.blue)
                    .cornerRadius(10)
                }
                
                Button("パスコードを使う") {
                    showPasscodeEntry = true
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .underline()
            }
            
            Spacer()
        }
    }
    
    /// Mac・iPad専用のルートビュー（Finderライクレイアウト）。
    /// ここを修正してもiPhone側（ContentView+iPhone.swift）には影響しない。
    var finderBody: some View {
        Group {
            if isDestroyed {
                destroyedView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !isUnlocked {
                VStack(spacing: 0) {
                    if lastAccessDate != 0 {
                        VStack(spacing: 4) {
                            Text("全ファイル消滅まで残り")
                                .font(.system(.title2, design: .monospaced)).fontWeight(.bold)
                                .foregroundColor(.red)
                            TimerDisplayView(isUnlocked: false)
                        }
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.06))
                        Divider()
                    }
                    macLockScreenView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NavigationSplitView {
                    finderSidebar
                } detail: {
                    if macShowHome {
                        macDashboardView
                    } else {
                        finderDetailView
                    }
                }
                .onChange(of: selectedFolder) { _, _ in
                    folderSelection = .unclassified
                }
                .onChange(of: folderSelection) { _, newValue in
                    guard let selection = newValue else { return }
                    macShowHome = false
                    switch selection {
                    case .favorites:
                        selectedAppFolderID = nil; showingFavoritesOnly = true
                    case .unclassified:
                        selectedAppFolderID = nil; showingFavoritesOnly = false
                    case .folder(let id):
                        selectedAppFolderID = id; showingFavoritesOnly = false
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 8) {
                ForEach(macToastMessages) { toast in
                    MacToastView(toast: toast)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.bottom, 24)
            .animation(.spring(), value: macToastMessages.count)
        }
    }
    
    // MARK: - ダッシュボード（ホーム）
    
    var macDashboardView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                
                // タイマー
                if lastAccessDate != 0 {
                    HStack(spacing: 12) {
                        Image(systemName: "timer").font(.title2).foregroundColor(.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("自爆タイマー").font(.subheadline).foregroundColor(.secondary)
                            Text("全ファイル消滅まであと")
                                .font(.system(.title2, design: .monospaced)).fontWeight(.bold)
                                .foregroundColor(isUnlocked ? .green : .red)
                            TimerDisplayView(isUnlocked: isUnlocked)
                        }
                        Spacer()
                        VStack(spacing: 8) {
                            Button("タイマー設定") { showingTimerSetup = true }
                                .buttonStyle(.bordered)
                            Button("通知設定") { showingNotificationSetup = true }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(12)
                }
                
                // ファイル統計
                let totalCount = secretFiles.count
                let imageCount = secretFiles.filter { $0.isImage }.count
                let videoCount = secretFiles.filter { $0.isVideo }.count
                let pdfCount   = secretFiles.filter { $0.isPDF }.count
                let otherCount = totalCount - imageCount - videoCount - pdfCount
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("保管状況").font(.headline)
                    HStack(spacing: 12) {
                        macStatCard(icon: "photo.fill",          color: .green,  label: "写真",  count: imageCount,  categoryIndex: 0)
                        macStatCard(icon: "play.rectangle.fill", color: .blue,   label: "動画",  count: videoCount,  categoryIndex: 1)
                        macStatCard(icon: "doc.richtext.fill",   color: .red,    label: "PDF",   count: pdfCount,    categoryIndex: 2)
                        macStatCard(icon: "doc.fill",            color: .gray,   label: "その他", count: otherCount, categoryIndex: 3)
                    }
                }
                
                // 操作パネル
                VStack(alignment: .leading, spacing: 12) {
                    Text("操作").font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        macActionButton(
                            label: "写真/動画を追加",
                            icon: "photo.badge.plus",
                            color: .green
                        ) {
                            // PhotosPickerはtoolbar経由なので、ファイル追加シートを開く
                        }
                        .overlay {
                            PhotosPicker(
                                selection: $selectedItems,
                                matching: .any(of: [.images, .videos]),
                                preferredItemEncoding: .current
                            ) { Color.clear }
                        }
                        
                        macActionButton(
                            label: "ファイルを追加",
                            icon: "doc.badge.plus",
                            color: .indigo
                        ) { showFileImporter = true }
                        
                        macActionButton(
                            label: "一括事前解読",
                            icon: "bolt.fill",
                            color: .orange
                        ) { batchDecryptAll() }
                        
                        macActionButton(
                            label: "パスコードを変更",
                            icon: "lock.rotation",
                            color: .teal
                        ) { isFirstSetupMode = false; showingPasscodeSetup = true }
                        
                        macActionButton(
                            label: "システムを初期化",
                            icon: "trash.fill",
                            color: .red
                        ) { showingResetConfirmation = true }
                    }
                }
                
                // D&D アップロードゾーン
                macDropZone
            }
            .padding(28)
        }
    }
    
    // MARK: - D&D ドロップゾーン
    
    private var macDropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isDropTargetedHome ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isDropTargetedHome ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04))
                )
                .frame(height: 180)
            
            VStack(spacing: 12) {
                Image(systemName: isDropTargetedHome ? "arrow.down.doc.fill" : "arrow.down.doc")
                    .font(.system(size: 40))
                    .foregroundColor(isDropTargetedHome ? .accentColor : .secondary)
                Text(isDropTargetedHome ? "ドロップしてアップロード" : "ここにファイルをドロップしてアップロード")
                    .font(.headline)
                    .foregroundColor(isDropTargetedHome ? .accentColor : .secondary)
                Text("画像・動画・PDF・その他のファイルに対応")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isDropTargetedHome)
        .onDrop(of: [.fileURL, .data], isTargeted: $isDropTargetedHome) { providers in
            handleFileDrop(providers: providers)
        }
    }
    
    /// ドロップされたファイルを暗号化してインポートする
    func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        isProcessing = true
        processingMessage = "極秘処理中..."
        
        let group = DispatchGroup()
        var tempURLs: [URL] = []
        
        for provider in providers {
            // まず fileURL として試みる
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                group.enter()
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    defer { group.leave() }
                    var resolved: URL?
                    if let data = item as? Data {
                        var stale = false
                        resolved = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
                        if resolved == nil { resolved = URL(dataRepresentation: data, relativeTo: nil) }
                    } else if let url = item as? URL {
                        resolved = url
                    }
                    guard let src = resolved else { return }
                    // ファイルのコピーを tmp に作成してアクセス権を確保
                    let dst = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + "_" + src.lastPathComponent)
                    let accessing = src.startAccessingSecurityScopedResource()
                    defer { if accessing { src.stopAccessingSecurityScopedResource() } }
                    if (try? FileManager.default.copyItem(at: src, to: dst)) != nil {
                        tempURLs.append(dst)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier("public.data") {
                // ファイル表現としてロードし tmp にコピー
                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: "public.data") { url, _ in
                    defer { group.leave() }
                    guard let src = url else { return }
                    let dst = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + "_" + src.lastPathComponent)
                    if (try? FileManager.default.copyItem(at: src, to: dst)) != nil {
                        tempURLs.append(dst)
                    }
                }
            }
        }
        
        group.notify(queue: .main) {
            guard !tempURLs.isEmpty else { self.isProcessing = false; return }
            DispatchQueue.global(qos: .userInitiated).async {
                // カテゴリ別カウント
                var imagCount = 0; var videoCount = 0; var pdfCount = 0; var otherCount = 0
                for (index, url) in tempURLs.enumerated() {
                    DispatchQueue.main.async {
                        self.processingMessage = "極秘処理中... (\(index + 1)/\(tempURLs.count))"
                    }
                    autoreleasepool {
                        let ext = url.pathExtension.lowercased().isEmpty ? "data" : url.pathExtension.lowercased()
                        KeyManager.createAndSaveKey()
                        _ = KeyManager.encryptFile(
                            inputURL: url,
                            outputURL: FileManagerHelper.generateNewFileURL(originalExtension: ext)
                        )
                        try? FileManager.default.removeItem(at: url)
                        // カテゴリ判定
                        let imageExts = ["jpg","jpeg","png","heic","heif","gif","tiff","bmp","webp","raw"]
                        let videoExts = ["mp4","mov","m4v","avi","mkv","hevc","3gp"]
                        if imageExts.contains(ext) { imagCount += 1 }
                        else if videoExts.contains(ext) { videoCount += 1 }
                        else if ext == "pdf" { pdfCount += 1 }
                        else { otherCount += 1 }
                    }
                }
                DispatchQueue.main.async {
                    self.refreshFiles()
                    self.isProcessing = false
                    // アップロードされたカテゴリのうち最初のものにナビゲート
                    if imagCount > 0 { self.selectedFolder = 0; self.folderSelection = .unclassified; self.macShowHome = false }
                    else if videoCount > 0 { self.selectedFolder = 1; self.folderSelection = .unclassified; self.macShowHome = false }
                    else if pdfCount > 0 { self.selectedFolder = 2; self.folderSelection = .unclassified; self.macShowHome = false }
                    else if otherCount > 0 { self.selectedFolder = 3; self.folderSelection = .unclassified; self.macShowHome = false }
                    // カテゴリごとにトーストを追加
                    var toasts: [MacToast] = []
                    if imagCount > 0 { toasts.append(MacToast(icon: "photo.fill", color: .blue, title: "写真", count: imagCount)) }
                    if videoCount > 0 { toasts.append(MacToast(icon: "play.rectangle.fill", color: .purple, title: "動画", count: videoCount)) }
                    if pdfCount > 0 { toasts.append(MacToast(icon: "doc.richtext.fill", color: .red, title: "PDF", count: pdfCount)) }
                    if otherCount > 0 { toasts.append(MacToast(icon: "doc.fill", color: .gray, title: "その他", count: otherCount)) }
                    self.showMacToasts(toasts)
                }
            }
        }
        return true
    }
    
    func showMacToasts(_ toasts: [MacToast]) {
        for (i, toast) in toasts.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
                withAnimation(.spring()) { self.macToastMessages.append(toast) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation(.easeOut) {
                        self.macToastMessages.removeAll { $0.id == toast.id }
                    }
                }
            }
        }
    }
    
    private func macStatCard(icon: String, color: Color, label: String, count: Int, categoryIndex: Int) -> some View {        Button {
        selectedFolder = categoryIndex
        folderSelection = .unclassified
        selectedAppFolderID = nil
        showingFavoritesOnly = false
        macShowHome = false
    } label: {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundColor(color)
            Text("\(count)").font(.title).bold()
            Text(label).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.secondary.opacity(0.07))
        .cornerRadius(12)
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
    }
    
    private func macActionButton(label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(12)
            .background(Color.secondary.opacity(0.07))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - サイドバー
    
    private var finderSidebar: some View {
        List {
            Section {
                Button { macShowHome = true } label: {
                    HStack { Label("ホーム", systemImage: "house.fill"); Spacer() }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(macShowHome ? Color.accentColor.opacity(0.25) : Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
            
            Section("カテゴリ") {
                ForEach(0..<4, id: \.self) { i in
                    Button {
                        selectedFolder = i; folderSelection = .unclassified; macShowHome = false
                    } label: {
                        HStack {
                            Label(
                                ["写真", "動画", "PDF", "その他"][i],
                                systemImage: ["photo.fill", "play.rectangle.fill", "doc.richtext.fill", "doc.fill"][i]
                            )
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground((!macShowHome && selectedFolder == i) ? Color.accentColor.opacity(0.25) : Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
            }
            
            if !macShowHome {
                Section("フォルダ") {
                    Button { folderSelection = .unclassified } label: {
                        HStack { Label("未分類", systemImage: "tray.2.fill"); Spacer() }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        ((!macShowHome && folderSelection == .unclassified) || sidebarDropTarget == .unclassified)
                        ? Color.accentColor.opacity(sidebarDropTarget == .unclassified ? 0.35 : 0.25)
                        : Color.clear
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .onDrop(of: ["public.plain-text"],
                            isTargeted: Binding(
                                get: { sidebarDropTarget == .unclassified },
                                set: { sidebarDropTarget = $0 ? .unclassified : nil }
                            )) { providers in
                                moveDroppedFiles(providers: providers, to: nil)
                            }
                            .contextMenu {
                                Button {
                                    let targets = secretFiles.filter { f in
                                        let matchCat: Bool
                                        switch selectedFolder {
                                        case 0: matchCat = f.isImage
                                        case 1: matchCat = f.isVideo
                                        case 2: matchCat = f.isPDF
                                        default: matchCat = !f.isImage && !f.isVideo && !f.isPDF
                                        }
                                        return matchCat && fileFolderMap[f.id] == nil && !favoriteFileIDs.contains(f.id)
                                    }
                                    preDecryptFiles(targets)
                                } label: { Label("解読", systemImage: "lock.open.fill") }
                            }
                    
                    Button { folderSelection = .favorites } label: {
                        HStack {
                            Label("お気に入り", systemImage: "heart.fill").foregroundColor(.pink)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        ((!macShowHome && folderSelection == .favorites) || sidebarDropTarget == .favorites)
                        ? Color.accentColor.opacity(sidebarDropTarget == .favorites ? 0.35 : 0.25)
                        : Color.clear
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .onDrop(of: ["public.plain-text"],
                            isTargeted: Binding(
                                get: { sidebarDropTarget == .favorites },
                                set: { sidebarDropTarget = $0 ? .favorites : nil }
                            )) { providers in
                                addDroppedFilesToFavorites(providers: providers)
                            }
                            .contextMenu {
                                Button {
                                    preDecryptFiles(secretFiles.filter { favoriteFileIDs.contains($0.id) })
                                } label: { Label("解読", systemImage: "lock.open.fill") }
                            }
                    
                    ForEach(appFolders.filter { $0.category == selectedFolder }) { folder in
                        Button { folderSelection = .folder(folder.id) } label: {
                            HStack { Label(folder.name, systemImage: "folder.fill"); Spacer() }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            ((!macShowHome && folderSelection == .folder(folder.id)) || sidebarDropTarget == .folder(folder.id))
                            ? Color.accentColor.opacity(sidebarDropTarget == .folder(folder.id) ? 0.35 : 0.25)
                            : Color.clear
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .onDrop(of: ["public.plain-text"],
                                isTargeted: Binding(
                                    get: { sidebarDropTarget == .folder(folder.id) },
                                    set: { sidebarDropTarget = $0 ? .folder(folder.id) : nil }
                                )) { providers in
                                    moveDroppedFiles(providers: providers, to: folder.id)
                                }
                                .contextMenu {
                                    Button {
                                        preDecryptFiles(secretFiles.filter { fileFolderMap[$0.id] == folder.id })
                                    } label: { Label("解読", systemImage: "lock.open.fill") }
                                    Button {
                                        editingFolder = folder; editingFolderName = folder.name
                                        folderAlertMode = .rename; showingFolderAlert = true
                                    } label: { Label("名前を変更", systemImage: "pencil") }
                                    Button(role: .destructive) { deleteFolder(folder) } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !macShowHome {
                    Button {
                        editingFolderName = ""; folderAlertMode = .create; showingFolderAlert = true
                    } label: { Label("フォルダを追加", systemImage: "folder.badge.plus") }
                }
            }
        }
    }
    
    // MARK: - 詳細ペイン
    
    @ViewBuilder
    var finderDetailView: some View {
        VStack(spacing: 0) {
            finderToolbar
            if filteredFiles.isEmpty {
                finderEmptyView
            } else {
                if viewMode == .grid {
                    finderGridView
                } else {
                    finderListView
                }
            }
            finderStatusBar
        }
    }
    
    // MARK: - ツールバー
    
    var finderToolbar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $selectedFolder) {
                Label("写真", systemImage: "photo.fill").tag(0)
                Label("動画", systemImage: "play.rectangle.fill").tag(1)
                Label("PDF", systemImage: "doc.richtext.fill").tag(2)
                Label("その他", systemImage: "doc.fill").tag(3)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            
            Spacer()
            
            if lastAccessDate != 0 {
                VStack(spacing: 1) {
                    Text("全ファイル消滅まであと")
                        .font(.system(.caption, design: .monospaced)).fontWeight(.bold)
                        .foregroundColor(isUnlocked ? .green : .red)
                    HStack(spacing: 4) {
                        Image(systemName: "timer").foregroundColor(.secondary).font(.caption)
                        TimerDisplayView(isUnlocked: isUnlocked)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("検索", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 160)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            
            Picker("表示", selection: $viewMode) {
                Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                Image(systemName: "list.bullet").tag(ViewMode.list)
            }
            .pickerStyle(.segmented)
            .frame(width: 80)
            
            Menu {
                PhotosPicker(
                    selection: $selectedItems,
                    matching: .any(of: [.images, .videos]),
                    preferredItemEncoding: .current
                ) {
                    Label("写真/動画を追加", systemImage: "photo.badge.plus")
                }
                Button { showFileImporter = true } label: {
                    Label("ファイルを追加", systemImage: "doc.badge.plus")
                }
                Divider()
                Button { batchDecryptAll() } label: {
                    Label("一括事前解読", systemImage: "bolt.fill")
                }
                Button { decryptCurrentFolderFiles() } label: {
                    Label("フォルダ内を全て書き出し", systemImage: "lock.open.fill")
                }
                .disabled(filteredFiles.isEmpty)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            
            if !selectedFileIDs.isEmpty {
                Button { exportSelectedFiles() } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("書き出し")
                Button { showingMoveDialog = true } label: {
                    Image(systemName: "folder")
                }
                .help("移動")
                Button { showingMultiDeleteConfirm = true } label: {
                    Image(systemName: "trash").foregroundColor(.red)
                }
                .help("削除")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
    
    // MARK: - グリッドビュー
    
    private var gridDragGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("GridSpace"))
            .onChanged { value in
                if dragStartPos == nil { dragStartPos = value.startLocation }
                dragCurrentPos = value.location
                let rect = CGRect(
                    x: min(value.startLocation.x, value.location.x),
                    y: min(value.startLocation.y, value.location.y),
                    width: abs(value.location.x - value.startLocation.x),
                    height: abs(value.location.y - value.startLocation.y)
                )
                var newlySelected: Set<UUID> = []
                for (id, frame) in gridItemFrames {
                    if rect.intersects(frame) { newlySelected.insert(id) }
                }
                selectedFileIDs = newlySelected
            }
            .onEnded { _ in
                dragStartPos = nil
                dragCurrentPos = nil
            }
    }
    
    private var gridItemsView: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 8)], spacing: 16) {
            ForEach(filteredFiles) { file in
                MacGridItem(
                    file: file,
                    isSelected: selectedFileIDs.contains(file.id),
                    isFavorite: favoriteFileIDs.contains(file.id),
                    onTap: {
                        if selectedFileIDs.contains(file.id) { selectedFileIDs.remove(file.id) }
                        else { selectedFileIDs.insert(file.id) }
                    },
                    onOpen: {
                        if let idx = filteredFiles.firstIndex(where: { $0.id == file.id }) {
                            galleryIndex = idx; showingGallery = true
                        }
                    },
                    contextMenu: AnyView(macContextMenu(for: file))
                )
                .onDrag {
                    let ids = selectedFileIDs.contains(file.id) && !selectedFileIDs.isEmpty
                    ? selectedFileIDs : [file.id]
                    let str = ids.map { $0.uuidString }.joined(separator: ",")
                    return NSItemProvider(object: str as NSString)
                }
                .background(GeometryReader { geo in
                    Color.clear.preference(key: ItemFramePreferenceKey.self,
                                           value: [file.id: geo.frame(in: .named("GridSpace"))])
                })
            }
        }
        .padding(16)
        .padding(.bottom, 60)
        .onPreferenceChange(ItemFramePreferenceKey.self) { frames in
            gridItemFrames = frames
        }
    }
    
    var finderGridView: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                ZStack(alignment: .topLeading) {
                    Color.white.opacity(0.001)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture { selectedFileIDs.removeAll() }
                        .gesture(gridDragGesture)
                    
                    gridItemsView
                    
                    if let start = dragStartPos, let current = dragCurrentPos {
                        let rect = CGRect(
                            x: min(start.x, current.x),
                            y: min(start.y, current.y),
                            width: abs(current.x - start.x),
                            height: abs(current.y - start.y)
                        )
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.2))
                            .border(Color.accentColor, width: 1)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                            .allowsHitTesting(false)
                    }
                }
                .coordinateSpace(name: "GridSpace")
            }
            .background(
                Color.secondary.opacity(0.05)
                    .onTapGesture { selectedFileIDs.removeAll() }
            )
            
            // D&D オーバーレイバー
            fileAreaDropBar
        }
        .onDrop(of: [.fileURL, .data], isTargeted: $isDropTargetedFiles) { providers in
            handleFileDrop(providers: providers)
        }
    }
    
    // MARK: - リストビュー
    
    var finderListView: some View {
        ZStack(alignment: .bottom) {
            Table(filteredFiles, selection: $selectedFileIDs, sortOrder: $sortOrder) {
                TableColumn("名前") { file in
                    HStack(spacing: 8) {
                        Image(systemName: file.typeIcon)
                            .foregroundColor(file.isImage ? .green : file.isVideo ? .blue : file.isPDF ? .red : .gray)
                            .frame(width: 20)
                        Text(file.displayName).lineLimit(1)
                    }
                }
                .width(min: 200, ideal: 300)
                
                TableColumn("種別", value: \.typeLabel) { file in
                    Text(file.typeLabel).foregroundColor(.secondary)
                }
                .width(60)
                
                TableColumn("サイズ") { file in
                    Text(file.fileSizeLabel).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(80)
                
                TableColumn("追加日", value: \.creationDate) { file in
                    Text(file.creationDateLabel).foregroundColor(.secondary)
                }
                .width(min: 130, ideal: 160)
            }
            .contextMenu(forSelectionType: SecretFile.ID.self) { items in
                if let first = items.first, let file = secretFiles.first(where: { $0.id == first }) {
                    macContextMenu(for: file)
                }
            }
            .onChange(of: sortOrder) { newOrder, _ in
                // ソート実装は今後追加予定
            }
            
            // D&D オーバーレイバー
            fileAreaDropBar
        }
        .onDrop(of: [.fileURL, .data], isTargeted: $isDropTargetedFiles) { providers in
            handleFileDrop(providers: providers)
        }
    }
    
    /// グリッド・リスト共通の下部 D&D バー
    private var fileAreaDropBar: some View {
        VStack(spacing: 6) {
            Image(systemName: isDropTargetedFiles ? "arrow.down.doc.fill" : "arrow.down.doc")
                .font(.title3)
                .foregroundColor(isDropTargetedFiles ? .accentColor : .secondary)
            Text(isDropTargetedFiles ? "ドロップしてアップロード" : "ここにファイルをドロップ")
                .font(.subheadline)
                .foregroundColor(isDropTargetedFiles ? .accentColor : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(isDropTargetedFiles ? Color.accentColor.opacity(0.06) : Color.secondary.opacity(0.08))
        .overlay(alignment: .top) { Divider() }
        .animation(.easeInOut(duration: 0.15), value: isDropTargetedFiles)
    }
    
    // MARK: - ステータスバー
    
    var finderStatusBar: some View {
        HStack {
            Text("\(filteredFiles.count)項目")
                .font(.caption).foregroundColor(.secondary)
            if !selectedFileIDs.isEmpty {
                Text("・\(selectedFileIDs.count)項目を選択中")
                    .font(.caption).foregroundColor(.accentColor)
            }
            Spacer()
            let totalBytes = filteredFiles.reduce(Int64(0)) { $0 + $1.fileSizeBytes }
            Text(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
    
    // MARK: - 空ビュー
    
    var finderEmptyView: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: searchText.isEmpty ? "tray" : "magnifyingglass")
                    .font(.system(size: 48)).foregroundColor(.secondary)
                Text(searchText.isEmpty
                     ? (showingFavoritesOnly ? "お気に入りがありません" : "ファイルがありません")
                     : "「\(searchText)」に一致するファイルがありません")
                .foregroundColor(.secondary)
                Spacer()
            }
            
            fileAreaDropBar
        }
        .onDrop(of: [.fileURL, .data], isTargeted: $isDropTargetedFiles) { providers in
            handleFileDrop(providers: providers)
        }
    }
    
    // MARK: - フィルタリング
    
    var filteredFiles: [SecretFile] {
        let base = currentFilteredFiles(for: selectedFolder)
        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
            || $0.fileExtension.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    // MARK: - コンテキストメニュー
    
    /// サイドバーのお気に入りへのファイルドロップ処理
    func addDroppedFilesToFavorites(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { item, _ in
                var str: String?
                if let data = item as? Data { str = String(data: data, encoding: .utf8) }
                else if let s = item as? String { str = s }
                guard let ids = str?.split(separator: ",").compactMap({ UUID(uuidString: String($0)) }),
                      !ids.isEmpty else { return }
                DispatchQueue.main.async {
                    for id in ids {
                        self.favoriteFileIDs.insert(id)
                    }
                    self.saveFolders()
                    self.selectedFileIDs.removeAll()
                }
            }
        }
        return true
    }
    
    /// サイドバーへのファイルドロップ処理
    func moveDroppedFiles(providers: [NSItemProvider], to folderID: UUID?) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { item, _ in
                var str: String?
                if let data = item as? Data { str = String(data: data, encoding: .utf8) }
                else if let s = item as? String { str = s }
                guard let ids = str?.split(separator: ",").compactMap({ UUID(uuidString: String($0)) }),
                      !ids.isEmpty else { return }
                DispatchQueue.main.async {
                    for id in ids {
                        if let folderID = folderID {
                            self.fileFolderMap[id] = folderID
                        } else {
                            self.fileFolderMap.removeValue(forKey: id)
                        }
                    }
                    self.saveFolders()
                    self.selectedFileIDs.removeAll()
                }
            }
        }
        return true
    }
    
    @ViewBuilder
    func macContextMenu(for file: SecretFile) -> some View {
        Button {
            if let idx = filteredFiles.firstIndex(where: { $0.id == file.id }) {
                galleryIndex = idx; showingGallery = true
            }
        } label: { Label("開く", systemImage: "eye") }
        Divider()
        Button {
            withAnimation {
                if favoriteFileIDs.contains(file.id) { favoriteFileIDs.remove(file.id) }
                else { favoriteFileIDs.insert(file.id) }
                saveFolders()
            }
        } label: {
            Label(
                favoriteFileIDs.contains(file.id) ? "お気に入りを解除" : "お気に入りに追加",
                systemImage: favoriteFileIDs.contains(file.id) ? "heart.slash" : "heart"
            )
        }
        Button { selectedFileIDs = [file.id]; showingMoveDialog = true } label: {
            Label("移動", systemImage: "folder")
        }
        Button { selectedFileIDs = [file.id]; exportSelectedFiles() } label: {
            Label("書き出し", systemImage: "square.and.arrow.up")
        }
        Divider()
        Button(role: .destructive) {
            selectedFileIDs = [file.id]; showingMultiDeleteConfirm = true
        } label: { Label("削除", systemImage: "trash") }
    }
}

// MARK: - Mac グリッドアイテム
struct MacGridItem: View {
    let file: SecretFile
    let isSelected: Bool
    let isFavorite: Bool
    let onTap: () -> Void
    let onOpen: () -> Void
    let contextMenu: AnyView
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                FileThumbnailView(file: file, onTap: onTap)
                    .frame(width: 110, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                    )
                
                if isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundColor(.pink)
                        .padding(5)
                        .background(Circle().fill(Color.black.opacity(0.4)))
                        .padding(5)
                }
            }
            .frame(width: 110, height: 90)
            .onTapGesture(count: 2) { onOpen() }
            
            Text(file.displayName)
                .font(.caption).lineLimit(2).multilineTextAlignment(.center).frame(width: 110)
            Text(file.fileSizeLabel)
                .font(.caption2).foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .contextMenu { contextMenu }
    }
}

struct ItemFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
