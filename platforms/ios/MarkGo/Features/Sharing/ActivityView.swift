import SwiftUI
import UIKit

/// A UIKit wrapper around `UIActivityViewController` for use in SwiftUI.
///
/// This view controller representable takes an array of activity items –
/// strings, URLs, data blobs, images and so on – and presents the standard
/// share sheet when the view appears.  You can customise the set of
/// activities by passing an array of `UIActivity` instances.  In this
/// example we leave it empty to let iOS decide the available actions.
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems,
                                 applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController,
                                context: Context) {
        // No dynamic updates required.  The activity items are supplied at
        // initialisation time and the system manages the share sheet.
    }
}
