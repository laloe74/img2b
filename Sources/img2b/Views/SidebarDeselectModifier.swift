import SwiftUI
import AppKit

struct SidebarClickHandler: ViewModifier {
    @Binding var selectedItemIDs: Set<UUID>
    @State private var token: Any?

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear {
                        let sidebarFrame = geo.frame(in: .global)
                        token = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                            if flags.contains(.command) || flags.contains(.shift) { return event }

                            guard !selectedItemIDs.isEmpty,
                                  let window = event.window
                            else { return event }

                            let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
                            let contentPoint = window.contentView?.convert(point, from: nil) ?? .zero

                            // Check if click is within the sidebar area
                            if sidebarFrame.contains(contentPoint) {
                                // Delay to let List handle selection first;
                                // if selection didn't change, it was a blank click
                                let before = selectedItemIDs
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    if selectedItemIDs == before {
                                        selectedItemIDs = []
                                    }
                                }
                            }

                            return event
                        }
                    }
                    .onDisappear {
                        if let t = token as? NSObject { NSEvent.removeMonitor(t) }
                    }
            })
    }
}

extension View {
    func onSidebarEmptyClick(selectedItemIDs: Binding<Set<UUID>>) -> some View {
        modifier(SidebarClickHandler(selectedItemIDs: selectedItemIDs))
    }
}
