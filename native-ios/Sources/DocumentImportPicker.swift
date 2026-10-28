import SwiftUI
import UniformTypeIdentifiers

// Ask the provider for a local copy. The delegate forwards the selected URLs once;
// the library owns the import task so closing the picker cannot cancel it.
struct DocumentImportPicker: UIViewControllerRepresentable {
    let types: [UTType]
    var multiple = false
    var asCopy = true
    let onSelection: ([URL]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onSelection) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: asCopy)
        picker.allowsMultipleSelection = multiple
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let selection: ([URL]) -> Void
        init(_ selection: @escaping ([URL]) -> Void) { self.selection = selection }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { selection(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { selection([]) }
    }
}
