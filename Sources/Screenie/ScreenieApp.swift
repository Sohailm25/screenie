import AppKit

@MainActor
enum ApplicationMainMenu {
    static func make() -> NSMenu {
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = makeEditMenu()
        mainMenu.addItem(editMenuItem)
        return mainMenu
    }

    private static func makeEditMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(command("Undo", action: "undo:", key: "z"))
        menu.addItem(command("Redo", action: "redo:", key: "z", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(command("Cut", action: "cut:", key: "x"))
        menu.addItem(command("Copy", action: "copy:", key: "c"))
        menu.addItem(command("Paste", action: "paste:", key: "v"))
        menu.addItem(.separator())
        menu.addItem(command("Select All", action: "selectAll:", key: "a"))
        return menu
    }

    private static func command(
        _ title: String,
        action: String,
        key: String,
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: NSSelectorFromString(action),
            keyEquivalent: key
        )
        item.keyEquivalentModifierMask = modifiers
        item.target = nil
        return item
    }
}

@main
enum ScreenieApplication {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.mainMenu = ApplicationMainMenu.make()
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
