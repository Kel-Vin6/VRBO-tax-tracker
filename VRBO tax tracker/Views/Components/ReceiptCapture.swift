//
//  ReceiptCapture.swift
//  VRBO tax tracker
//
//  Attaching proof to an expense. Photos come from the library on every
//  platform and from the document scanner on iPhone and iPad, and the text is
//  read on device so the amount, date and merchant can be filled in for you.
//

import PhotosUI
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif
#if os(iOS)
import VisionKit
#endif

/// Renders image data without forcing every call site to know about UIImage
/// versus NSImage.
struct ReceiptImage: View {
    let data: Data
    var contentMode: ContentMode = .fit

    var body: some View {
        if let image = Self.makeImage(from: data) {
            image
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            ZStack {
                Rectangle().fill(Theme.nestedFill)
                Image(systemName: "doc.text.image")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
    }

    static func makeImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #elseif canImport(AppKit)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #else
        return nil
        #endif
    }
}

// MARK: - Document scanner

#if os(iOS)
/// The system document scanner, which deskews and crops the receipt for us and
/// produces a far cleaner image for text recognition than a raw photo.
struct DocumentScannerView: UIViewControllerRepresentable {

    var onScan: ([Data]) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: ([Data]) -> Void
        let onCancel: () -> Void

        init(onScan: @escaping ([Data]) -> Void, onCancel: @escaping () -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            var pages: [Data] = []
            for index in 0..<scan.pageCount {
                if let data = scan.imageOfPage(at: index).jpegData(compressionQuality: 0.8) {
                    pages.append(data)
                }
            }
            onScan(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            onCancel()
        }
    }
}

public var isDocumentScannerAvailable: Bool { VNDocumentCameraViewController.isSupported }
#else
public var isDocumentScannerAvailable: Bool { false }
#endif

// MARK: - Attachment control

/// The receipt slot used by the expense editor and the document vault.
struct ReceiptAttachmentView: View {

    @Binding var data: Data?
    @Binding var fileName: String
    var onRecognized: ((ScannedReceipt) -> Void)?
    /// Opens the document scanner as soon as the view appears, for the
    /// "scan a receipt" quick action.
    var autoStartScanner: Bool = false

    @State private var photoItem: PhotosPickerItem?
    @State private var isScanning = false
    @State private var showingScanner = false
    @State private var showingFullScreen = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let data {
                ReceiptImage(data: data)
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            self.data = nil
                            self.fileName = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.5))
                        }
                        .padding(8)
                        .accessibilityLabel("Remove receipt")
                    }
                    .onTapGesture { showingFullScreen = true }

                if isScanning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading the receipt…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if onRecognized != nil {
                    Button {
                        Task { await recognize(data) }
                    } label: {
                        Label("Read the amount and date again", systemImage: "text.viewfinder")
                            .font(.caption)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    #if os(iOS)
                    if isDocumentScannerAvailable {
                        Button {
                            showingScanner = true
                        } label: {
                            Label("Scan", systemImage: "doc.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    #endif

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose photo", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onAppear {
            #if os(iOS)
            if autoStartScanner, data == nil, isDocumentScannerAvailable {
                showingScanner = true
            }
            #endif
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let loaded = try? await item.loadTransferable(type: Data.self) {
                    data = loaded
                    fileName = "receipt-\(Fmt.fileStamp()).jpg"
                    await recognize(loaded)
                }
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showingScanner) {
            DocumentScannerView { pages in
                showingScanner = false
                guard let first = pages.first else { return }
                data = first
                fileName = "scan-\(Fmt.fileStamp()).jpg"
                Task { await recognize(first) }
            } onCancel: {
                showingScanner = false
            }
            .ignoresSafeArea()
        }
        #endif
        .sheet(isPresented: $showingFullScreen) {
            if let data {
                NavigationStack {
                    ScrollView([.horizontal, .vertical]) {
                        ReceiptImage(data: data)
                            .frame(maxWidth: .infinity)
                    }
                    .navigationTitle("Receipt")
                    .inlineNavigationTitle()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingFullScreen = false }
                        }
                    }
                }
            }
        }
    }

    private func recognize(_ imageData: Data) async {
        guard let onRecognized else { return }
        isScanning = true
        errorMessage = nil
        defer { isScanning = false }
        do {
            let result = try await ReceiptScanner.scan(imageData: imageData)
            if result.hasUsableResult {
                onRecognized(result)
                Haptics.play(.success)
            } else {
                errorMessage = "The receipt was saved, but no amount could be read from it. Fill the fields in by hand."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
