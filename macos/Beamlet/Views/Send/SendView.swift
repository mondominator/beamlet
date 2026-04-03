import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct SendView: View {
    @Environment(BeamletAPI.self) private var api
    @State private var viewModel: SendViewModel?
    @State private var showPhotoPicker = false
    @State private var showSendAnimation = false
    @State private var isDropTargeted = false

    private let columns = [GridItem](repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        if let vm = viewModel {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        // MARK: - Drop zone / attachment area
                        if let name = vm.attachmentDisplayName {
                            attachmentPreview(name: name, vm: vm)
                        } else {
                            dropZone(vm: vm)
                        }

                        // MARK: - Contact grid (show when attachment selected)
                        if vm.attachmentDisplayName != nil {
                            contactGrid(vm: vm)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 80)
                    .animation(.easeInOut(duration: 0.25), value: vm.attachmentDisplayName != nil)
                }

                // MARK: - Send button
                if vm.attachmentDisplayName != nil {
                    VStack(spacing: 0) {
                        Divider()

                        if let error = vm.error {
                            Text(error)
                                .font(.system(size: 10))
                                .foregroundStyle(.red)
                                .padding(.top, 6)
                                .padding(.horizontal, 12)
                        }

                        Button {
                            Task { await vm.send() }
                        } label: {
                            if vm.isSending {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    if vm.uploadProgress > 0 {
                                        Text("\(Int(vm.uploadProgress * 100))%")
                                            .font(.system(size: 11))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            } else {
                                Label("Send", systemImage: "paperplane.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        LinearGradient(
                                            colors: vm.canSend
                                                ? [Color(red: 0.55, green: 0.36, blue: 0.96), Color(red: 0.23, green: 0.51, blue: 0.96)]
                                                : [.gray.opacity(0.3), .gray.opacity(0.3)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!vm.canSend)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .background(.bar)
                    .transition(.move(edge: .bottom))
                }
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: Bindable(vm).selectedPhoto,
                matching: .any(of: [.images, .videos])
            )
            .onChange(of: vm.selectedPhoto) {
                vm.clearFileAttachment()
                Task { await vm.loadPhotoData() }
            }
            .overlay {
                if showSendAnimation {
                    sendSuccessOverlay
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: vm.showSuccess) { _, success in
                if success {
                    NSSound.beep()
                    withAnimation(.spring(response: 0.3)) {
                        showSendAnimation = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation {
                            showSendAnimation = false
                        }
                        vm.showSuccess = false
                        vm.reset()
                    }
                }
            }
            .task { await vm.loadUsers() }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { viewModel = SendViewModel(api: api) }
        }
    }

    // MARK: - Drop Zone

    private func dropZone(vm: SendViewModel) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 28))
                .foregroundStyle(isDropTargeted ? .blue : .secondary)

            Text("Drop files here")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isDropTargeted ? .blue : .primary)

            Text("or")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            HStack(spacing: 10) {
                Button {
                    vm.openFilePicker()
                } label: {
                    Label("Browse", systemImage: "folder")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    showPhotoPicker = true
                } label: {
                    Label("Photos", systemImage: "photo.on.rectangle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isDropTargeted ? Color.blue : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 3])
                )
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isDropTargeted ? Color.blue.opacity(0.05) : Color.clear)
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers, vm: vm)
            return true
        }
    }

    // MARK: - Attachment Preview

    private func attachmentPreview(name: String, vm: SendViewModel) -> some View {
        HStack(spacing: 10) {
            Image(systemName: vm.selectedPhotoData != nil ? "photo.fill" : "doc.fill")
                .font(.system(size: 16))
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)
                .background(.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text("Ready to send")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                vm.clearAttachment()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Contact Grid

    private func contactGrid(vm: SendViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Send to")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !vm.selectedUsers.isEmpty {
                    Text("\(vm.selectedUsers.count) selected")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            if vm.isLoadingUsers {
                HStack {
                    Spacer()
                    ProgressView("Loading contacts...")
                        .font(.system(size: 11))
                        .controlSize(.small)
                        .padding(.vertical, 16)
                    Spacer()
                }
            } else if vm.users.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No contacts yet")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Add a contact in Settings to start sharing.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(vm.users) { user in
                        Button {
                            vm.toggleUser(user)
                        } label: {
                            VStack(spacing: 4) {
                                ZStack(alignment: .bottomTrailing) {
                                    AvatarView(name: user.name, size: 40)
                                    if vm.isSelected(user) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.white, .blue)
                                            .offset(x: 2, y: 2)
                                    }
                                }
                                Text(user.name)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Drag & Drop

    private func handleDrop(providers: [NSItemProvider], vm: SendViewModel) {
        guard let provider = providers.first else { return }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                vm.handleFileURLs([url])
            }
        }
    }

    // MARK: - Success Overlay

    private var sendSuccessOverlay: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("Sent!")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .transition(.scale.combined(with: .opacity))
    }
}
