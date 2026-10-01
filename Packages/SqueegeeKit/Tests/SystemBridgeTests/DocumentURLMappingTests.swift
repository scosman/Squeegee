import Foundation
import Testing
@testable import SystemBridge

@Suite("Document URL mapping")
struct DocumentURLMappingTests {
    // MARK: - documentURLFromString

    @Test("Parses a valid file URL string")
    func validFileURLString() {
        let result = AXHelpers.documentURLFromString("file:///Users/test/doc.txt")
        #expect(result == URL(string: "file:///Users/test/doc.txt"))
    }

    @Test("Rejects a non-file URL string")
    func nonFileURLString() {
        let result = AXHelpers.documentURLFromString("https://example.com/doc.txt")
        #expect(result == nil)
    }

    @Test("Returns nil for empty string")
    func emptyString() {
        #expect(AXHelpers.documentURLFromString("") == nil)
    }

    @Test("Returns nil for nil string")
    func nilString() {
        #expect(AXHelpers.documentURLFromString(nil) == nil)
    }

    @Test("Rejects an invalid URL string")
    func invalidURLString() {
        // A string that URL(string:) cannot parse
        let result = AXHelpers.documentURLFromString("not a url at all ://")
        #expect(result == nil)
    }

    // MARK: - fileURLFromAXURL

    @Test("Accepts a file URL from AXURL attribute")
    func fileURLFromAttribute() {
        let url = URL(fileURLWithPath: "/Users/test/doc.txt")
        let result = AXHelpers.fileURLFromAXURL(url)
        #expect(result == url)
    }

    @Test("Rejects a non-file URL from AXURL attribute")
    func nonFileURLFromAttribute() {
        let url = URL(string: "https://example.com/doc.txt")
        let result = AXHelpers.fileURLFromAXURL(url)
        #expect(result == nil)
    }

    @Test("Returns nil for nil AXURL attribute")
    func nilAttribute() {
        #expect(AXHelpers.fileURLFromAXURL(nil) == nil)
    }

    @Test("Returns nil for non-URL AXURL attribute")
    func nonURLAttribute() {
        let result = AXHelpers.fileURLFromAXURL("just a string" as Any)
        #expect(result == nil)
    }

    // MARK: - resolveDocumentURL (integration)

    @Test("Prefers documentString when both are present")
    func prefersDocumentString() {
        let docURL = URL(fileURLWithPath: "/Users/test/from-doc.txt")
        let axURL = URL(fileURLWithPath: "/Users/test/from-ax.txt")
        let result = AXHelpers.resolveDocumentURL(
            documentString: docURL.absoluteString,
            urlAttribute: axURL
        )
        #expect(result == docURL)
    }

    @Test("Falls back to AXURL when documentString is nil")
    func fallsBackToAXURL() {
        let axURL = URL(fileURLWithPath: "/Users/test/from-ax.txt")
        let result = AXHelpers.resolveDocumentURL(
            documentString: nil,
            urlAttribute: axURL
        )
        #expect(result == axURL)
    }

    @Test("Returns nil when both are nil")
    func bothNil() {
        let result = AXHelpers.resolveDocumentURL(documentString: nil, urlAttribute: nil)
        #expect(result == nil)
    }
}
