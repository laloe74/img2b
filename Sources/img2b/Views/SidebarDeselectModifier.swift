import SwiftUI
import AppKit

struct SidebarClickHandler: ViewModifier {
    @Binding var selectedItemIDs: Set<UUID>
    @State private var token: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                token = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                    // Don't interfere with Cmd/Shift+click (multi-select)
                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    if flags.contains(.command) || flags.contains(.shift) { return event }

                    guard !selectedItemIDs.isEmpty,
                          let contentView = event.window?.contentView else { return event }

                    let point = contentView.convert(event.locationInWindow, from: nil)
                    guard let hitView = contentView.hitTest(point) else { return event }

                    var v: NSView? = hitView
                    var foundTableView = false
                    var foundRow = false

                    while v != nil {
                        if v is NSTableRowView { foundRow = true }
                        if v is NSTableView { foundTableView = true }
                        v = v?.superview
                    }

                    if foundTableView && !foundRow {
                        DispatchQueue.main.async { selectedItemIDs = [] }
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
    func onSidebarEmptyClick(selectedItemIDs: Binding<Set<UUID>>) -> some View {
        modifier(SidebarClickHandler(selectedItemIDs: selectedItemIDs))
    }
}
