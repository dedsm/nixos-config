// Launcher surface for the `dedsmScreencast` plugin: the screen-recording
// counterpart of `dedsmScreenshot`, and static for the same reasons (see that
// plugin's header) — the picking happens after the launcher closes.
//
// Where the screenshot picker's second axis is copy/save, this one's is audio:
// a video has no useful clipboard form, so every recording is saved, and the
// choice that matters is whether sound goes in with it.
//
// Stopping is not an entry. CTRL+SHIFT+Print stops a running recording instead
// of opening this list, and picking any entry here while one runs stops it too.
//
// @rec@ is substituted by the dms home-manager module. As with the screenshot
// plugin, an `exec:` action is split on whitespace with no shell in between, so
// the path must arrive absolute and space-free.
import QtQuick
import Quickshell

Item {
    id: root

    // Injected by PluginService; declared null per the plugin interface.
    property var pluginService: null

    // Matches `trigger` in plugin.json; `dms-screencast menu` opens the
    // launcher with exactly this query.
    property string trigger: "!"

    signal itemsChanged

    // Region uses DMS's own selector, Monitor slurp's, and Window the portal's
    // share dialog — the only capture that follows a window across workspaces.
    readonly property var entries: [
        {
            name: "Record Region",
            icon: "material:crop_free",
            comment: "Select a region → @saveDir@",
            action: "exec:@rec@ start region silent",
            categories: ["Screencast"]
        },
        {
            name: "Record Window",
            icon: "material:crop_square",
            comment: "Pick a window, follows it → @saveDir@",
            action: "exec:@rec@ start window silent",
            categories: ["Screencast"]
        },
        {
            name: "Record Monitor",
            icon: "material:desktop_windows",
            comment: "Pick a monitor → @saveDir@",
            action: "exec:@rec@ start monitor silent",
            categories: ["Screencast"]
        },
        {
            name: "Record Region with Audio",
            icon: "material:crop_free",
            comment: "Desktop audio + microphone → @saveDir@",
            action: "exec:@rec@ start region audio",
            categories: ["Screencast"]
        },
        {
            name: "Record Window with Audio",
            icon: "material:crop_square",
            comment: "Desktop audio + microphone → @saveDir@",
            action: "exec:@rec@ start window audio",
            categories: ["Screencast"]
        },
        {
            name: "Record Monitor with Audio",
            icon: "material:desktop_windows",
            comment: "Desktop audio + microphone → @saveDir@",
            action: "exec:@rec@ start monitor audio",
            categories: ["Screencast"]
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
