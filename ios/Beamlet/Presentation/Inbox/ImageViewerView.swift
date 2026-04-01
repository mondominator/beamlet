import SwiftUI

struct ImageViewerView: View {
    let image: UIImage
    let file: BeamletFile
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var savedToPhotos = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            scale = value.magnification
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.3)) {
                                if scale < 1.0 { scale = 1.0 }
                                if scale > 5.0 { scale = 5.0 }
                            }
                        }
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if scale <= 1.0 {
                                offset = value.translation
                            }
                        }
                        .onEnded { value in
                            if scale <= 1.0 && abs(value.translation.height) > 100 {
                                onDismiss()
                            } else {
                                withAnimation(.spring(response: 0.3)) {
                                    offset = .zero
                                }
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3)) {
                        scale = scale > 1.0 ? 1.0 : 2.5
                    }
                }

            // Top bar
            VStack {
                HStack {
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial.opacity(0.6))
                            .clipShape(Circle())
                    }

                    Spacer()

                    VStack(spacing: 2) {
                        Text(file.senderName ?? "")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        if let date = file.createdAt {
                            Text(date, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }

                    Spacer()

                    // Spacer for symmetry
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer()

                // Bottom actions
                HStack(spacing: 32) {
                    Button {
                        let ac = UIActivityViewController(activityItems: [image], applicationActivities: nil)
                        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let root = scene.windows.first?.rootViewController?.presentedViewController ?? scene.windows.first?.rootViewController {
                            root.present(ac, animated: true)
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                            Text("Share")
                                .font(.caption2)
                        }
                        .foregroundStyle(.white)
                    }

                    Button {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        withAnimation { savedToPhotos = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { savedToPhotos = false }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: savedToPhotos ? "checkmark.circle.fill" : "square.and.arrow.down")
                                .font(.title3)
                            Text(savedToPhotos ? "Saved" : "Save")
                                .font(.caption2)
                        }
                        .foregroundStyle(savedToPhotos ? .green : .white)
                    }
                }
                .padding(.bottom, 40)
            }
            .opacity(scale > 1.2 ? 0 : 1)
        }
        .statusBarHidden()
    }
}
