import Foundation
import SwiftUI
#if os(macOS)
import Quartz
#else
import QuickLook
#endif

/// Системный просмотр файла прямо в окне: так открываются Excel, Keynote, Pages и всё,
/// что читалка не переводит в текст. Для Word и PowerPoint это вид «Оригинал».
public struct QuickLookView: View {
    let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var body: some View {
        Representable(url: url)
    }

    #if os(macOS)
    private struct Representable: NSViewRepresentable {
        let url: URL

        func makeNSView(context: Context) -> QLPreviewView {
            let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
            view.autostarts = true
            view.previewItem = url as NSURL
            return view
        }

        func updateNSView(_ view: QLPreviewView, context: Context) {
            if (view.previewItem as? NSURL) as URL? != url {
                view.previewItem = url as NSURL
            }
        }
    }
    #else
    private struct Representable: UIViewControllerRepresentable {
        let url: URL

        func makeCoordinator() -> Coordinator { Coordinator(url: url) }

        func makeUIViewController(context: Context) -> QLPreviewController {
            let controller = QLPreviewController()
            controller.dataSource = context.coordinator
            return controller
        }

        func updateUIViewController(_ controller: QLPreviewController, context: Context) {
            if context.coordinator.url != url {
                context.coordinator.url = url
                controller.reloadData()
            }
        }

        final class Coordinator: NSObject, QLPreviewControllerDataSource {
            var url: URL

            init(url: URL) {
                self.url = url
            }

            func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

            func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
                url as NSURL
            }
        }
    }
    #endif
}
