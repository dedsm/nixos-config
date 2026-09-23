// Launcher surface for the `dedsmScreenshot` plugin: the six screenshot choices
// that used to be an anyrun stdin list driven by hyprshot.
//
// Deliberately static. An earlier version enumerated outputs and windows into
// their own entries, which cannot work: `getItems()` is synchronous while any
// enumeration is not, `PluginService.ensureLauncherInstance()` is lazy and never
// pre-created at startup, and `itemsChanged` — which the plugin guide documents
// as triggering a UI refresh — has no listener anywhere in the shell. There is
// no way for a plugin to say "I have more items now", so the picking happens in
// a real selector after the launcher closes instead, which is what hyprshot did.
//
// @shot@ is substituted by the dms home-manager module. An `exec:` action is
// split on whitespace and handed to execDetached, so there is no shell: the path
// must arrive absolute and space-free.
import QtQuick
import Quickshell

Item {
    id: root

    // Injected by PluginService; declared null per the plugin interface.
    property var pluginService: null

    // Matches `trigger` in plugin.json. Typing it alone lists every entry,
    // which is what the CTRL+Print bind does via `spotlight openQuery`.
    property string trigger: "#"

    signal itemsChanged

    // Window and Monitor open a picker, as `hyprshot -m window` and `-m output`
    // did — `-m active` was the modifier that meant "the focused one", and these
    // entries were never the active-only forms.
    readonly property var entries: [
        {
            name: "Copy Region",
            icon: "material:crop_free",
            comment: "Select a region → clipboard",
            action: "exec:@shot@ region copy",
            categories: ["Screenshot"]
        },
        {
            name: "Copy Window",
            icon: "material:crop_square",
            comment: "Pick a window → clipboard",
            action: "exec:@shot@ window copy",
            categories: ["Screenshot"]
        },
        {
            name: "Copy Monitor",
            icon: "material:desktop_windows",
            comment: "Pick a monitor → clipboard",
            action: "exec:@shot@ monitor copy",
            categories: ["Screenshot"]
        },
        {
            name: "Save Region",
            icon: "material:crop_free",
            comment: "Select a region → @saveDir@",
            action: "exec:@shot@ region save",
            categories: ["Screenshot"]
        },
        {
            name: "Save Window",
            icon: "material:crop_square",
            comment: "Pick a window → @saveDir@",
            action: "exec:@shot@ window save",
            categories: ["Screenshot"]
        },
        {
            name: "Save Monitor",
            icon: "material:desktop_windows",
            comment: "Pick a monitor → @saveDir@",
            action: "exec:@shot@ monitor save",
            categories: ["Screenshot"]
        }
    ]

    function getItems(query) {
        if (!query || query.length === 0)
            return root.entries;

        const q = query.toLowerCase();
        return root.entries.filter(item => item.name.toLowerCase().includes(q) || item.comment.toLowerCase().includes(q));
    }

    function executeItem(item) {
        const parts = item.action.split(":");
        if (parts[0] !== "exec")
            return;

        Quickshell.execDetached(parts.slice(1).join(":").split(" "));
    }
}
