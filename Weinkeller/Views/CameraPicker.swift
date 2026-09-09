import SwiftUI
import UIKit

/// Direkter Zugriff auf die Kamera.
///
/// SwiftUI hat dafür nichts Eigenes — `PhotosPicker` holt nur aus der Mediathek.
/// Ohne das hier müsste der Besitzer erst die Kamera-App öffnen, fotografieren,
/// zurückwechseln und das Bild suchen. Für 500 Flaschen ist das kein Weg.
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .rear
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Sterne zum Bewerten. 0 heisst „noch nicht bewertet".
struct RatingStars: View {
    @Binding var rating: Int
    var size: CGFloat = 26
    var interactive: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(star <= rating ? Theme.typeWeiss : Theme.mutedDim)
                    .onTapGesture {
                        guard interactive else { return }
                        // Nochmal auf denselben Stern tippen löscht die Bewertung.
                        rating = (rating == star) ? 0 : star
                    }
            }
            if interactive && rating > 0 {
                Button("löschen") { rating = 0 }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mutedDim)
                    .padding(.leading, 4)
            }
        }
    }
}
