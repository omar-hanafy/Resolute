import AppKit
import ResoluteKit

/// Turns `MenuNode`s into AppKit menu items.
@MainActor
enum MenuRenderer {
    static func fill(_ menu: NSMenu, with nodes: [MenuNode], target: AnyObject?, action: Selector?) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        for node in nodes {
            menu.addItem(makeItem(node, target: target, action: action))
        }
    }

    static func makeItem(_ node: MenuNode, target: AnyObject?, action: Selector?) -> NSMenuItem {
        switch node {
        case .separator:
            return .separator()
        case .header(let title):
            return .sectionHeader(title: title)
        case .item(let model):
            let item = NSMenuItem(
                title: model.title,
                action: model.action == nil ? nil : action,
                keyEquivalent: model.keyEquivalent
            )
            item.target = model.action == nil ? nil : target
            item.representedObject = model.action.map(MenuActionBox.init)
            item.isEnabled = model.isEnabled
            item.state = model.isChecked ? .on : .off
            if let symbolName = model.symbolName {
                item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            }
            if let badge = model.badge {
                item.badge = NSMenuItemBadge(string: badge)
            }
            if #available(macOS 14.4, *), let subtitle = model.subtitle {
                item.subtitle = subtitle
            }
            if let children = model.submenu {
                let submenu = NSMenu(title: model.title)
                fill(submenu, with: children, target: target, action: action)
                item.submenu = submenu
            }
            return item
        }
    }

    /// The rendered menu in `MenuModel.render`'s format, to check what AppKit received.
    static func describe(_ menu: NSMenu) -> String {
        describe(menu, depth: 0).joined(separator: "\n")
    }

    private static func describe(_ menu: NSMenu, depth: Int) -> [String] {
        let indent = String(repeating: "    ", count: depth)
        var lines: [String] = []
        for item in menu.items {
            if item.isSeparatorItem {
                lines.append("\(indent)---")
                continue
            }
            if item.isSectionHeader {
                lines.append("\(indent)# \(item.title)")
                continue
            }
            var line = indent + (item.state == .on ? "✓ " : "  ") + item.title
            if #available(macOS 14.4, *), let subtitle = item.subtitle {
                line += " — \(subtitle)"
            }
            if let badge = item.badge?.stringValue {
                line += " [\(badge)]"
            }
            if !item.isEnabled { line += " (disabled)" }
            if item.submenu != nil { line += " ▸" }
            lines.append(line)
            if let submenu = item.submenu {
                lines += describe(submenu, depth: depth + 1)
            }
        }
        return lines
    }
}

/// Carries a `MenuAction` in `NSMenuItem.representedObject`.
final class MenuActionBox: NSObject {
    let action: MenuAction

    init(_ action: MenuAction) {
        self.action = action
    }
}
