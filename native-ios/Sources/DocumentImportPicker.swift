import SwiftUI
import UniformTypeIdentifiers
import OSLog

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
        ImportDiagnostics.record("picker created, types=\(types.map(\.identifier).joined(separator: ",")), multiple=\(multiple)")
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {
        context.coordinator.selection = onSelection
    }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var selection: ([URL]) -> Void
        init(_ selection: @escaping ([URL]) -> Void) { self.selection = selection }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            Logger(subsystem: "app.nicpa.amllplayer.test", category: "Import").notice("Picker delivered \(urls.count) selected URL(s)")
            ImportDiagnostics.record("picker selected \(urls.count)")
            selection(urls)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            Logger(subsystem: "app.nicpa.amllplayer.test", category: "Import").notice("Picker cancelled")
            ImportDiagnostics.record("picker cancelled")
            selection([])
        }
    }
}
