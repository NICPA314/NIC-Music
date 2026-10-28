import SwiftUI
import UniformTypeIdentifiers

// Open a security-scoped URL; MusicFileImporter coordinates and owns the durable copy.
// Avoid asking the picker to stage a second copy before it can return the selection.
struct DocumentImportPicker: UIViewControllerRepresentable {
    let types: [UTType]
    var multiple = false
    let onSelection: ([URL]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onSelection) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = multiple
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let selection: ([URL]) -> Void
        init(_ selection: @escaping ([URL]) -> Void) { self.selection = selection }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            NSLog("NICImport: picker returned %ld URL(s)", urls.count)
            selection(urls)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { selection([]) }
    }
}
