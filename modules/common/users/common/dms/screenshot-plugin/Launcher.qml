// Launcher surface for the `dedsmScreenshot` plugin: the six screenshot choices
// that used to be an anyrun stdin list driven by hyprshot.
//
// The save directory below is substituted in by the dms home-manager module.
// `exec:` actions are split on whitespace and handed to execDetached, so there
// is no shell to expand a `~`: it has to arrive already absolute, and with no
// spaces in it.
import QtQuick
import Quickshell

Item {
    id: root

    // Injected by PluginService; declared null per the plugin interface.
    property var pluginService: null

    // Matches `trigger` in plugin.json. Typing it alone lists every entry below,
    // which is what the CTRL+Print bind does via `spotlight openQuery`.
    property string trigger: "#"

    signal itemsChanged

    // `full` rather than `output`: it captures the *focused* output with no name
    // argument, which is what hyprshot's `-m output` did. `output` in DMS needs
    // an explicit `-o <name>`.
    //
    // Copy entries pass --no-file; the save entries keep DMS's default of writing
    // the file *and* copying it, which is what hyprshot did without
    // --clipboard-only.
    readonly property var entries: [
        {
            name: "Copy Region",
            icon: "material:crop_free",
            comment: "Select a region → clipboard",
            action: "exec:dms screenshot region --no-file",
            categories: ["Screenshot"]
        },
        {
            name: "Copy Window",
            icon: "material:crop_square",
            comment: "Focused window → clipboard",
            action: "exec:dms screenshot window --no-file",
            categories: ["Screenshot"]
        },
        {
            name: "Copy Monitor",
            icon: "material:desktop_windows",
            comment: "Focused monitor → clipboard",
            action: "exec:dms screenshot full --no-file",
            categories: ["Screenshot"]
        },
        {
            name: "Save Region",
            icon: "material:crop_free",
            comment: "Select a region → @saveDir@",
            action: "exec:dms screenshot region -d @saveDir@",
            categories: ["Screenshot"]
        },
        {
            name: "Save Window",
            icon: "material:crop_square",
            comment: "Focused window → @saveDir@",
            action: "exec:dms screenshot window -d @saveDir@",
            categories: ["Screenshot"]
        },
        {
            name: "Save Monitor",
            icon: "material:desktop_windows",
            comment: "Focused monitor → @saveDir@",
            action: "exec:dms screenshot full -d @saveDir@",
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
