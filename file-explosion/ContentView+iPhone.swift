import SwiftUI
import PhotosUI

// MARK: - iPhone Body
extension ContentView {
    
    /// iPhone専用のルートビュー。
    var iPhoneBody: some View {
        NavigationStack {
            mainContentView
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
        }
    }
    
    // MARK: - メインコンテンツ
    
    @ViewBuilder
    var mainContentView: some View {
        if isDestroyed {
            destroyedView
        } else {
            VStack(spacing: 0) {
                statusBanner
                Divider()
                if !isUnlocked {
                    lockScreenView
                } else {
                    TabView(selection: $selectedMainTab) {
                        controlPanelView
                            .tabItem { Label("操作", systemImage: "slider.horizontal.3") }
                            .tag(0)
                        folderView
                            .tabItem { Label("ファイル", systemImage: "folder.fill") }
                            .tag(1)
                    }
                }
            }
        }
    }
    
    private var statusBanner: some View {
        VStack(spacing: 5) {
            if isDestroyed {
                Text("【警告】システム停止").font(.subheadline).foregroundColor(.red)
            } else if isUnlocked {
                Text("ロック解除中").font(.subheadline).foregroundColor(.green)
            } else {
                Text(statusMessage).font(.subheadline).foregroundColor(.primary)
            }
            if !isDestroyed && lastAccessDate != 0 {
                Text("全ファイル消滅まであと")
                    .font(.system(.title2, design: .monospaced)).fontWeight(.bold)
                    .foregroundColor(isUnlocked ? .green : .red)
                TimerDisplayView(isUnlocked: isUnlocked)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.05))
    }
    
    // MARK: - ロック画面
    
    var lockScreenView: some View {
        VStack(spacing: 30) {
            Spacer()
            Image(systemName: showPasscodeEntry ? "lock.shield.fill" : "faceid")
                .font(.system(size: 60))
                .foregroundColor(showPasscodeEntry ? .orange : .blue)
            if showPasscodeEntry {
                VStack(spacing: 20) {
                    Text("パスコードを入力").font(.headline)
                    PasscodeField(title: "4桁の数字", text: $inputPasscode)
                    Button(action: {
                        if inputPasscode == appPasscode { unlockSystem() }
                        else { statusMessage = "❌ パスコード不一致"; inputPasscode = "" }
                    }) {
                        Text("解除する")
                            .font(.headline).foregroundColor(.white).padding()
                            .frame(width: 200).background(Color.orange).cornerRadius(10)
                    }
                    .disabled(inputPasscode.count < 4)
                    Button("Face IDに戻る") { showPasscodeEntry = false }
                        .font(.caption).foregroundColor(.gray)
                }
            } else {
                Button(action: { authenticate() }) {
                    HStack {
                        Image(systemName: "faceid")
                        Text("Face ID でロック解除")
                    }
                    .font(.headline).foregroundColor(.white).padding()
                    .frame(width: 250).background(Color.blue).cornerRadius(10)
                }
                Button("パスコードを使う") { showPasscodeEntry = true }
                    .font(.subheadline).foregroundColor(.secondary).underline()
            }
            Spacer()
        }
    }
    
    // MARK: - コントロールパネル
    
    var controlPanelView: some View {
        ScrollView {
            VStack(spacing: 25) {
                SectionHeader(title: "セキュリティ管理")
                Button(action: { isFirstSetupMode = false; showingPasscodeSetup = true }) {
                    Label("パスコードを変更する", systemImage: "lock.rotation")
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.orange).foregroundColor(.white).cornerRadius(10)
                }
                .padding(.horizontal)
                
                SectionHeader(title: "パフォーマンス")
                Button(action: { batchDecryptAll() }) {
                    Label("全ファイルを一括事前解読", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.blue).foregroundColor(.white).cornerRadius(10)
                }
                .padding(.horizontal)
                
                SectionHeader(title: "極秘データの追加")
                HStack(spacing: 15) {
                    PhotosPicker(
                        selection: $selectedItems,
                        matching: .any(of: [.images, .videos]),
                        preferredItemEncoding: .current
                    ) {
                        VStack {
                            Image(systemName: "photo.fill")
                            Text("写真/動画").font(.caption2)
                        }
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.green).foregroundColor(.white).cornerRadius(10)
                    }
                    Button(action: { showFileImporter = true }) {
                        VStack {
                            Image(systemName: "doc.badge.plus")
                            Text("ファイル").font(.caption2)
                        }
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.indigo).foregroundColor(.white).cornerRadius(10)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }
    
    // MARK: - フォルダビュー
    
    var folderView: some View {
        VStack(spacing: 0) {
            Picker("フォルダ", selection: $selectedFolder) {
                Text("写真").tag(0)
                Text("動画").tag(1)
                Text("PDF").tag(2)
                Text("他").tag(3)
            }
            .pickerStyle(.segmented)
            .padding()
            
            folderChipScroll
            
            Divider()
            
            TabView(selection: $selectedFolder) {
                fileGrid(for: 0).tag(0)
                fileGrid(for: 1).tag(1)
                fileGrid(for: 2).tag(2)
                fileGrid(for: 3).tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: selectedFolder)
            
            if isSelectionMode {
                iPhoneSelectionBar
            }
        }
    }
    
    private var folderChipScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                FolderChip(title: "未分類", icon: "tray.2.fill", customTint: .blue,
                           isSelected: selectedAppFolderID == nil && !showingFavoritesOnly) {
                    selectedAppFolderID = nil; showingFavoritesOnly = false
                }
                           .contextMenu {
                               Button(action: {
                                   let targets = secretFiles.filter { f in
                                       let matchCat = categoryMatches(f, folder: selectedFolder)
                                       return matchCat && fileFolderMap[f.id] == nil && !favoriteFileIDs.contains(f.id)
                                   }
                                   preDecryptFiles(targets)
                               }) { Label("フォルダ内のファイルを全て解読", systemImage: "lock.open.fill") }
                               Button(action: {
                                   let targets = secretFiles.filter { f in
                                       let matchCat = categoryMatches(f, folder: selectedFolder)
                                       return matchCat && fileFolderMap[f.id] == nil && !favoriteFileIDs.contains(f.id)
                                   }
                                   if !targets.isEmpty { selectedFileIDs = Set(targets.map { $0.id }); exportSelectedFiles() }
                               }) { Label("書き出し", systemImage: "square.and.arrow.up") }
                           }
                
                FolderChip(title: "お気に入り", icon: "heart.fill", customTint: .pink,
                           isSelected: showingFavoritesOnly) {
                    selectedAppFolderID = nil; showingFavoritesOnly = true
                }
                           .contextMenu {
                               Button(action: {
                                   let targets = secretFiles.filter { f in
                                       categoryMatches(f, folder: selectedFolder) && favoriteFileIDs.contains(f.id)
                                   }
                                   preDecryptFiles(targets)
                               }) { Label("フォルダ内のファイルを全て解読", systemImage: "lock.open.fill") }
                               Button(action: {
                                   let targets = secretFiles.filter { f in
                                       categoryMatches(f, folder: selectedFolder) && favoriteFileIDs.contains(f.id)
                                   }
                                   if !targets.isEmpty { selectedFileIDs = Set(targets.map { $0.id }); exportSelectedFiles() }
                               }) { Label("書き出し", systemImage: "square.and.arrow.up") }
                           }
                
                ForEach(appFolders.filter { $0.category == selectedFolder }) { folder in
                    FolderChip(title: folder.name, icon: "folder.fill", customTint: .blue,
                               isSelected: selectedAppFolderID == folder.id && !showingFavoritesOnly) {
                        selectedAppFolderID = folder.id; showingFavoritesOnly = false
                    }
                               .contextMenu {
                                   Button(action: {
                                       let targets = secretFiles.filter { fileFolderMap[$0.id] == folder.id }
                                       preDecryptFiles(targets)
                                   }) { Label("フォルダ内のファイルを全て解読", systemImage: "lock.open.fill") }
                                   Button(action: {
                                       let targets = secretFiles.filter { fileFolderMap[$0.id] == folder.id }
                                       if !targets.isEmpty { selectedFileIDs = Set(targets.map { $0.id }); exportSelectedFiles() }
                                   }) { Label("書き出し", systemImage: "square.and.arrow.up") }
                                   Button {
                                       editingFolder = folder
                                       editingFolderName = folder.name
                                       folderAlertMode = .rename
                                       showingFolderAlert = true
                                   } label: { Label("名前を変更", systemImage: "pencil") }
                                   Button(role: .destructive) { deleteFolder(folder) } label: {
                                       Label("削除", systemImage: "trash")
                                   }
                               }
                }
                
                Button(action: { editingFolderName = ""; folderAlertMode = .create; showingFolderAlert = true }) {
                    Image(systemName: "plus.circle.fill").font(.title2).foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 10)
    }
    
    private var iPhoneSelectionBar: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 4) {
                let countFormat = String(localized: "%lld項目を選択")
                Text(String(format: countFormat, selectedFileIDs.count))
                    .font(.caption).foregroundColor(.secondary)
                HStack(spacing: 0) {
                    Button(action: { exportSelectedFiles() }) {
                        VStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up").font(.title2)
                            Text("書き出し").font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(selectedFileIDs.isEmpty)
                    
                    Button(action: { showingMoveDialog = true }) {
                        VStack(spacing: 4) {
                            Image(systemName: "folder").font(.title2)
                            Text("移動").font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .foregroundColor(selectedFileIDs.isEmpty ? .gray : .blue)
                    .disabled(selectedFileIDs.isEmpty)
                    
                    Button(action: { showingMultiDeleteConfirm = true }) {
                        VStack(spacing: 4) {
                            Image(systemName: "trash").font(.title2)
                            Text("削除").font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .foregroundColor(selectedFileIDs.isEmpty ? .gray : .red)
                    .disabled(selectedFileIDs.isEmpty)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 12)
            .background(Color.secondary.opacity(0.1))
            .transition(.move(edge: .bottom))
        }
    }
    
    // MARK: - ファイルグリッド
    
    @ViewBuilder
    func fileGrid(for folderIndex: Int) -> some View {
        let filtered = currentFilteredFiles(for: folderIndex)
        
        if filtered.isEmpty {
            let emptyMsg = showingFavoritesOnly
            ? "お気に入りがありません"
            : (selectedAppFolderID == nil ? "未分類のファイルがありません" : "このフォルダは空です")
            VStack {
                Spacer()
                Text(String(localized: String.LocalizationValue(emptyMsg))).foregroundColor(.gray)
                Spacer()
            }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)], spacing: 10) {
                    ForEach(filtered) { file in
                        ZStack(alignment: .bottomTrailing) {
                            FileThumbnailView(file: file) {
                                if isSelectionMode {
                                    if selectedFileIDs.contains(file.id) { selectedFileIDs.remove(file.id) }
                                    else { selectedFileIDs.insert(file.id) }
                                } else {
                                    if let idx = filtered.firstIndex(where: { $0.id == file.id }) {
                                        galleryIndex = idx; showingGallery = true
                                    }
                                }
                            }
                            .contextMenu {
                                if !isSelectionMode {
                                    Button(action: { selectedFileIDs = [file.id]; exportSelectedFiles() }) {
                                        Label("書き出し", systemImage: "square.and.arrow.up")
                                    }
                                    Button(action: { selectedFileIDs = [file.id]; showingMoveDialog = true }) {
                                        Label("移動", systemImage: "folder")
                                    }
                                    Button(role: .destructive, action: {
                                        selectedFileIDs = [file.id]; showingMultiDeleteConfirm = true
                                    }) {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                            }
                            
                            if isSelectionMode {
                                Image(systemName: selectedFileIDs.contains(file.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundColor(selectedFileIDs.contains(file.id) ? .blue : .white)
                                    .background(Circle().fill(Color.black.opacity(0.3)))
                                    .padding(6)
                                    .allowsHitTesting(false)
                            }
                        }
                        .overlay(alignment: .bottomLeading) {
                            if !isSelectionMode {
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                        if favoriteFileIDs.contains(file.id) { favoriteFileIDs.remove(file.id) }
                                        else { favoriteFileIDs.insert(file.id) }
                                        saveFolders()
                                    }
                                }) {
                                    Image(systemName: favoriteFileIDs.contains(file.id) ? "heart.fill" : "heart")
                                        .font(.title3)
                                        .foregroundColor(favoriteFileIDs.contains(file.id) ? .pink : .white)
                                        .frame(width: 36, height: 36)
                                        .background(Circle().fill(Color.black.opacity(0.4)))
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .padding(8)
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                }
                .padding()
                .animation(.easeInOut(duration: 0.2), value: isSelectionMode)
            }
        }
    }
    
    // MARK: - ナビゲーションツールバー
    
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        if isUnlocked {
            if isSelectionMode {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        let currentFiles = currentFilteredFiles(for: selectedFolder)
                        if selectedFileIDs.count == currentFiles.count && !currentFiles.isEmpty {
                            selectedFileIDs.removeAll()
                        } else {
                            selectedFileIDs = Set(currentFiles.map { $0.id })
                        }
                    }) {
                        let currentFiles = currentFilteredFiles(for: selectedFolder)
                        Text(selectedFileIDs.count == currentFiles.count && !currentFiles.isEmpty
                             ? "すべて選択解除" : "すべて選択")
                        .font(.body)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if isSelectionMode {
                    Button(action: {
                        withAnimation { isSelectionMode = false; selectedFileIDs.removeAll() }
                    }) {
                        Image(systemName: "xmark").font(.title3).fontWeight(.bold)
                    }
                } else {
                    Menu {
                        if selectedMainTab == 1 {
                            Button(action: {
                                withAnimation { isSelectionMode = true; selectedFileIDs.removeAll() }
                            }) { Label("選択", systemImage: "checkmark.circle") }
                            Button(action: {
                                preDecryptFiles(currentFilteredFiles(for: selectedFolder))
                            }) {
                                Label("フォルダ内のファイルを全て解読", systemImage: "lock.open.fill")
                            }
                            .disabled(currentFilteredFiles(for: selectedFolder).isEmpty)
                            Button(action: { decryptCurrentFolderFiles() }) {
                                Label("フォルダ内を全て書き出し", systemImage: "square.and.arrow.up")
                            }
                            .disabled(currentFilteredFiles(for: selectedFolder).isEmpty)
                            Divider()
                        }
                        Button(action: { showingTimerSetup = true }) {
                            Label("自爆タイマー", systemImage: "timer")
                        }
                        Button(role: .destructive, action: { showingResetConfirmation = true }) {
                            Label("システムを初期化", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3)
                    }
                }
            }
        }
    }
    
    // MARK: - ヘルパー
    
    private func categoryMatches(_ f: SecretFile, folder: Int) -> Bool {
        switch folder {
        case 0: return f.isImage
        case 1: return f.isVideo
        case 2: return f.isPDF
        default: return !f.isImage && !f.isVideo && !f.isPDF
        }
    }
}
