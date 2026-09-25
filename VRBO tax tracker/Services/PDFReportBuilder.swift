//
//  PDFReportBuilder.swift
//  VRBO tax tracker
//
//  Renders SwiftUI pages into a real PDF using ImageRenderer, so the exported
//  return summary looks exactly like what the user saw on screen and works the
//  same on iPhone, iPad, Mac and Vision Pro.
//

import CoreGraphics
import Foundation
import SwiftUI

public enum PDFReportBuilder {

    /// US Letter at 72 dpi.
    public static let letterSize = CGSize(width: 612, height: 792)
    /// A4 at 72 dpi, for users outside the US.
    public static let a4Size = CGSize(width: 595, height: 842)

    public static func makePDF(
        pages: [AnyView],
        pageSize: CGSize = letterSize
    ) -> Data? {
        guard !pages.isEmpty else { return nil }

        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }

        for page in pages {
            let renderer = ImageRenderer(
                content: page
                    .frame(width: pageSize.width, height: pageSize.height)
                    .environment(\.colorScheme, .light)
            )
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.isOpaque = true

            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }

        context.closePDF()
        return data as Data
    }
}
