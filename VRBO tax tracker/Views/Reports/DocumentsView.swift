//
//  DocumentsView.swift
//  VRBO tax tracker
//

import PhotosUI
import SwiftData
import SwiftUI

struct DocumentsView: View {

    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @Query(sort: \StoredDocument.createdAt, order: .reverse) private var documents: [StoredDocument]
    @Query(sort: \Property.sortIndex) private var properties: [Property]

    @State private var editing: StoredDocument?
    @State private var showingNew = false

    private var expiring: [StoredDocument] {
        documents.filter { document in
            guard document.kind.tracksExpiration, let days = document.daysUntilExpiration else { return false }
            return days <= 60
        }
    }

    private struct KindGroup: Identifiable {
        let kind: DocumentKind
        let documents: [StoredDocument]
        var id: String { kind.rawValue }
    }

    private var grouped: [KindGroup] {
        let groups = Dictionary(grouping: documents, by: \.kind)
        return DocumentKind.allCases.compactMap { kind in
            guard let items = groups[kind], !items.isEmpty else { return nil }
            return KindGroup(kind: kind, documents: items)
        }
    }

    var body: some View {
        Group {
            if documents.isEmpty {
                EmptyStateView(
                    symbol: "folder",
                    title: "Nothing filed yet",
                    message: "Closing statements, permits, insurance policies, Form 1098s and 1099-Ks belong here with the receipts, so the whole year travels as one package.",
                    actionTitle: "Add a document"
                ) { showingNew = true }
            } else {
                List {
                    if !expiring.isEmpty {
                        Section("Expiring soon") {
                            ForEach(expiring) { document in
                                Button { editing = document } label: {
                                    HStack {
                                        Image(systemName: document.kind.symbol)
                                            .foregroundStyle(document.isExpired ? .red : .orange)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(document.displayTitle).font(.subheadline)
                                            Text(document.isExpired
                                                 ? "Expired \(Fmt.shortDate(document.expirationDate ?? Date()))"
                                                 : "Expires in \(document.daysUntilExpiration ?? 0) days")
                                                .font(.caption2)
                                                .foregroundStyle(document.isExpired ? .red : .orange)
                                        }
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    ForEach(grouped) { group in
                        Section(group.kind.title) {
                            ForEach(group.documents) { document in
                                Button { editing = document } label: {
                                    HStack(spacing: 12) {
                                        if let data = document.data {
                                            ReceiptImage(data: data, contentMode: .fill)
                                                .frame(width: 40, height: 40)
                                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                        } else {
                                            Image(systemName: document.kind.symbol)
                                                .frame(width: 40, height: 40)
                                                .foregroundStyle(.tint)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(document.displayTitle).font(.subheadline)
                                            Text("\(document.taxYear)\(document.property.map { " · \($0.displayName)" } ?? "")")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        context.delete(document)
                                        try? context.save()
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .platformListStyle()
            }
        }
        .navigationTitle("Documents")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: {
                    Label("Add document", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNew) { DocumentEditorView(document: nil) }
        .sheet(item: $editing) { document in DocumentEditorView(document: document) }
    }
}

struct DocumentEditorView: View {

    let document: StoredDocument?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    @Query(sort: \Property.sortIndex) private var properties: [Property]

    @State private var title = ""
    @State private var kind: DocumentKind = .other
    @State private var property: Property?
    @State private var taxYear = DateMath.currentYear
    @State private var hasExpiration = false
    @State private var expirationDate = Date()
    @State private var notes = ""
    @State private var data: Data?
    @State private var fileName = ""
    @State private var recognizedText = ""
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Document") {
                    TextField("Title", text: $title)
                    Picker("Kind", selection: $kind) {
                        ForEach(DocumentKind.allCases) { option in
                            Label(option.title, systemImage: option.symbol).tag(option)
                        }
                    }
                    PropertyPickerField(
                        selection: $property,
                        properties: properties,
                        allowsNone: true,
                        noneLabel: "Whole portfolio"
                    )
                    Picker("Tax year", selection: $taxYear) {
                        ForEach(DateMath.selectableYears(), id: \.self) { year in
                            Text(verbatim: "\(year)").tag(year)
                        }
                    }
                }

                if kind.tracksExpiration {
                    Section("Renewal") {
                        Toggle("Track expiry", isOn: $hasExpiration)
                        if hasExpiration {
                            DatePicker("Expires", selection: $expirationDate, displayedComponents: .date)
                            Text("You will be reminded 60, 30 and 7 days before, if notifications are on.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("File") {
                    ReceiptAttachmentView(data: $data, fileName: $fileName) { scanned in
                        recognizedText = scanned.recognizedText
                        if title.isEmpty, let vendor = scanned.suggestedVendor { title = vendor }
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
                }

                if document != nil {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete document", systemImage: "trash")
                        }
                    }
                }
            }
            .platformFormStyle()
            .navigationTitle(document == nil ? "New document" : "Edit document")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(title.isEmpty && data == nil)
                }
            }
            .onAppear(perform: load)
            .confirmationDialog(
                "Delete this document?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let document { context.delete(document) }
                    try? context.save()
                    dismiss()
                }
            }
        }
    }

    private func load() {
        guard let document else {
            taxYear = appState.taxYear
            return
        }
        title = document.title
        kind = document.kind
        property = document.property
        taxYear = document.taxYear
        if let date = document.expirationDate {
            expirationDate = date
            hasExpiration = true
        }
        notes = document.notes
        data = document.data
        fileName = document.fileName
        recognizedText = document.recognizedText
    }

    private func save() {
        let target = document ?? StoredDocument()
        if document == nil { context.insert(target) }
        target.title = title
        target.kind = kind
        target.property = property
        target.taxYear = taxYear
        target.expirationDate = hasExpiration ? expirationDate : nil
        target.notes = notes
        target.data = data
        target.fileName = fileName
        target.contentType = data == nil ? "" : "image/jpeg"
        target.recognizedText = recognizedText
        try? context.save()
        Haptics.play(.success)
        dismiss()
    }
}
