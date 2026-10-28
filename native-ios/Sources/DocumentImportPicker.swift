import SwiftUI
import UniformTypeIdentifiers

// Present the system picker through UIKit; do not embed its remote view as a
// SwiftUI sheet's root. The presenter owns the delegate through the handoff.
struct DocumentImportPicker: UIViewControllerRepresentable {
    let types: [UTType]
    var multiple = false
    let onSelection: ([URL]) -> Void

    func makeUIViewController(context: Context) -> Presenter {
        Presenter(types: types, multiple: multiple, selection: onSelection)
    }
    func updateUIViewController(_ controller: Presenter, context: Context) {
        controller.selection = onSelection
    }

    final class Presenter: UIViewController, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
        let types: [UTType]
        let multiple: Bool
        var selection: ([URL]) -> Void
        private var picker: UIDocumentPickerViewController?
        private var started = false
        private var finished = false

        init(types: [UTType], multiple: Bool, selection: @escaping ([URL]) -> Void) {
            self.types = types; self.multiple = multiple; self.selection = selection
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func loadView() { view = UIView(); view.backgroundColor = .clear }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !started else { return }
            started = true
            // UIKit requires directory pickers to use open mode.
            // File selection retains the working import-copy path.
            let copy = !types.contains(.folder)
            let controller = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: copy)
            controller.allowsMultipleSelection = multiple
            controller.delegate = self
            controller.modalPresentationStyle = .fullScreen
            picker = controller
            ImportDiagnostics.record("picker created, types=\(types.map(\.identifier).joined(separator: ",")), multiple=\(multiple), copy=\(copy)")
            present(controller, animated: true) {
                controller.presentationController?.delegate = self
                ImportDiagnostics.record("picker presented by UIKit, delegate retained=\(controller.delegate === self)")
            }
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            ImportDiagnostics.record("picker selected \(urls.count)")
            finish(urls)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            ImportDiagnostics.record("picker cancelled")
            finish([])
        }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            guard !finished else { return }
            ImportDiagnostics.record("picker interactively dismissed")
            finish([])
        }
        private func finish(_ urls: [URL]) {
            guard !finished else { return }
            finished = true
            // Deliver exactly once, after the modal has gone, so import results
            // can present on the app instead of behind the system picker.
            let deliver = {
                ImportDiagnostics.record("picker handoff \(urls.count)")
                self.selection(urls)
                self.picker = nil
            }
            if let picker, picker.presentingViewController != nil {
                picker.dismiss(animated: true, completion: deliver)
            } else { deliver() }
        }
    }
}
