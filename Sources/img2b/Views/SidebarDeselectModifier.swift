import SwiftUI
import AppKit

/// Monitors mouse clicks and deselects sidebar when clicking empty List area.
struct SidebarClickHandler: ViewModifier {
    @Binding var selectedItemID: UUID?

    @State private var token: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                token = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                    guard selectedItemID != nil,
                          let contentView = event.window?.contentView else { return event }

                    let point = contentView.convert(event.locationInWindow, from: nil)
                    guard let hitView = contentView.hitTest(point) else { return event }

                    // Check if the click landed on a sidebar TableView row
                    var v: NSView? = hitView
                    var foundTableView = false
                    var foundRow = false

                    while v != nil {
                        if v is NSTableRowView { foundRow = true }
                        if v is NSTableView { foundTableView = true }
                        v = v?.superview
                    }

                    // Click on sidebar empty space (tableView found, but no row)
                    if foundTableView && !foundRow {
                        DispatchQueue.main.async { selectedItemID = nil }
                    }

                    return event
                }
            }
            .onDisappear {
                if let t = token as? NSObject { NSEvent.removeMonitor(t) }
            }
    }
}

extension View {
    func onSidebarEmptyClick(selectedItemID: Binding<UUID?>) -> some View {
        modifier(SidebarClickHandler(selectedItemID: selectedItemID))
    }
}
