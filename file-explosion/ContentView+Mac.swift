import SwiftUI
import PhotosUI

// MARK: - Mac / iPad Body
extension ContentView {

    /// Mac・iPad専用のルートビュー（Finderライクレイアウト）。
    /// ここを修正してもiPhone側（ContentView+iPhone.swift）には影響しない。
    var finderBody: some View {
        Group {
            if !isUnlocked {
                lockScreenView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NavigationSplitView {
                    finderSidebar
                } detail: {
                    finderDetailView
                }
                .onChange(of: selectedFolder) { _, _ in
                    folderSelection = .unclassified
                }
                .onChange(of: folderSelection) { _, newValue in
                    guard let selection = newValue else { return }
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
    }

    // MARK: - サイドバー

    private var finderSidebar: some View {
        List {
            Section("カテゴリ") {
                ForEach(0..<4, id: \.self) { i in
                    Label(
                        ["写真", "動画", "PDF", "その他"][i],
                        systemImage: ["photo.fill", "play.rectangle.fill", "doc.richtext.fill", "doc.fill"][i]
                    )
                    .contentShape(Rectangle())
                    .listRowBackground(selectedFolder == i ? Color.accentColor.opacity(0.25) : Color.clear)
                    .onTapGesture {
                        selectedFolder = i
                        folderSelection = .unclassified
                    }
                }
            }

            Section("フォルダ") {
                Label("未分類", systemImage: "tray.2.fill")
                    .contentShape(Rectangle())
                    .listRowBackground(folderSelection == .unclassified ? Color.accentColor.opacity(0.25) : Color.clear)
                    .onTapGesture { folderSelection = .unclassified }

                Label("お気に入り", systemImage: "heart.fill")
                    .foregroundColor(.pink)
                    .contentShape(Rectangle())
                    .listRowBackground(folderSelection == .favorites ? Color.accentColor.opacity(0.25) : Color.clear)
                    .onTapGesture { folderSelection = .favorites }

                ForEach(appFolders.filter { $0.category == selectedFolder }) { folder in
                    Label(folder.name, systemImage: "folder.fill")
                        .contentShape(Rectangle())
                        .listRowBackground(folderSelection == .folder(folder.id) ? Color.accentColor.opacity(0.25) : Color.clear)
                        .onTapGesture { folderSelection = .folder(folder.id) }
                        .contextMenu {
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
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("LimitBox")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingFolderName = ""
                    folderAlertMode = .create
                    showingFolderAlert = true
                } label: { Label("フォルダを追加", systemImage: "folder.badge.plus") }
            }
        }
    }

    // MARK: - 詳細ペイン

    @ViewBuilder
    var finderDetailView: some View {
        if isDestroyed {
            destroyedView
        } else {
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
                HStack(spacing: 4) {
                    Image(systemName: "timer").foregroundColor(.secondary).font(.caption)
                    TimerDisplayView(isUnlocked: isUnlocked)
                        .font(.system(.caption, design: .monospaced))
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
                PhotosPicker(selection: $selectedItems, matching: .any(of: [.images, .videos])) {
                    Label("写真/動画を追加", systemImage: "photo.badge.plus")
                }
                Button { showFileImporter = true } label: {
                    Label("ファイルを追加", systemImage: "doc.badge.plus")
                }
                Divider()
                Button { batchDecryptAll() } label: {
                    Label("一括事前解読", systemImage: "bolt.fill")
                }
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

    var finderGridView: some View {
        ScrollView {
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
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }

    // MARK: - リストビュー

    var finderListView: some View {
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
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08))
                    .frame(width: 100, height: 80)
                Image(systemName: file.typeIcon)
                    .font(.system(size: 36))
                    .foregroundColor(file.isImage ? .green : file.isVideo ? .blue : file.isPDF ? .red : .gray)
                if isFavorite {
                    Image(systemName: "heart.fill").font(.caption2).foregroundColor(.pink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(6)
                }
            }
            .frame(width: 100, height: 80)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2))

            Text(file.displayName)
                .font(.caption).lineLimit(2).multilineTextAlignment(.center).frame(width: 100)
            Text(file.fileSizeLabel)
                .font(.caption2).foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen() }
        .onTapGesture { onTap() }
        .contextMenu { contextMenu }
    }
}
