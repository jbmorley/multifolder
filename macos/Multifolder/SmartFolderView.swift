// Copyright (c) 2021 InSeven Limited
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import SwiftUI
import UniformTypeIdentifiers

import Interact

struct SmartFolderView: View {

    @Binding var folder: SmartFolder

    @State var selection: Set<URL> = Set()

    func relaunchFinder() {
        let script = """
        tell application \"Finder\" to quit
        tell application \"Finder\" to activate
        """
        guard let appleScript = NSAppleScript(source: script) else {
            print("Failed to create script")
            return
        }
        var errorInfo: NSDictionary? = nil
        appleScript.executeAndReturnError(&errorInfo)
        if let error = errorInfo {
            print(error)
        }
    }

    var body: some View {
        VStack {
            List(selection: $selection) {
                ForEach(folder.paths) { link in
                    HStack {
                        IconView(url: link, size: CGSize(width: 16, height: 16))
                        Text(link.lastPathComponent)
                    }
                    .contextMenu {
                        Button("Remove") {
                            if selection.contains(link) {
                                folder.paths.removeAll { selection.contains($0) }
                            } else {
                                folder.paths.removeAll { $0 == link }
                            }
                        }
                    }
                }
            }
            .onDrop(of: [.fileURL], delegate: FileDropDelegate(files: $folder.paths))
        }
    }
}