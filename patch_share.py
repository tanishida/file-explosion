with open("LimitBoxShare/ShareViewController.swift", "r") as f:
    text = f.read()

new_text = text.replace("""        // メインスレッドをブロックしないよう非同期で処理する
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.processSharedItems()
        }
    }
    
    private func processSharedItems() {
        guard let extensionContext = self.extensionContext,
              let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            completeRequest()
            return
        }
        
        let dispatchGroup = DispatchGroup()
        
        for item in inputItems {""", """        guard let extensionContext = self.extensionContext,
              let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }
        
        // メインスレッドをブロックしないよう非同期で処理する
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.processSharedItems(inputItems: inputItems)
        }
    }
    
    private func processSharedItems(inputItems: [NSExtensionItem]) {
        let dispatchGroup = DispatchGroup()
        
        for item in inputItems {""")

with open("LimitBoxShare/ShareViewController.swift", "w") as f:
    f.write(new_text)

print("patched")
