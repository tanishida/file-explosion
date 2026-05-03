import re

with open('LimitBoxShare/ShareViewController.swift', 'r') as f:
    content = f.read()

replacement = """
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    dispatchGroup.enter()
                    
                    let imageType = provider.registeredTypeIdentifiers.first {
                        UTType($0)?.conforms(to: .image) == true
                    } ?? UTType.image.identifier
                    
                    provider.loadItem(forTypeIdentifier: imageType, options: nil) { [weak self] (item, error) in
                        var extractedData: Data? = nil
                        
                        if let url = item as? URL {
                            extractedData = try? Data(contentsOf: url)
                        } else if let image = item as? UIImage {
                            extractedData = image.jpegData(compressionQuality: 1.0)
                        } else if let data = item as? Data {
                            extractedData = data
                        }
                        
                        if let data = extractedData, let uiImage = UIImage(data: data), let jpegData = uiImage.jpegData(compressionQuality: 1.0) {
                            self?.saveDataToSharedContainer(data: jpegData)
                            dispatchGroup.leave()
                            return
                        }
                        
                        // フォールバック: loadDataRepresentation
                        provider.loadDataRepresentation(forTypeIdentifier: imageType) { (data, error) in
                            defer { dispatchGroup.leave() }
                            if let data = data, let uiImage = UIImage(data: data), let jpegData = uiImage.jpegData(compressionQuality: 1.0) {
                                self?.saveDataToSharedContainer(data: jpegData)
                            } else {
                                print("画像データの読み込みに失敗しました: \\(String(describing: error))")
                            }
                        }
                    }
                } else if"""

content = re.sub(r'                if provider.hasItemConformingToTypeIdentifier\(UTType.image.identifier\) \{.*?                } else if', replacement, content, flags=re.DOTALL)

with open('LimitBoxShare/ShareViewController.swift', 'w') as f:
    f.write(content)
