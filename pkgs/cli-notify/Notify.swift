import Foundation
import UserNotifications

struct Options {
    var title = "Notification"
    var message: String?
    var subtitle: String?
    var sound: String?
    var identifier: String = UUID().uuidString
    var removeID: String?
}

func parseOptions() -> Options {
    var opts = Options()
    let argv = CommandLine.arguments
    var i = 1
    while i < argv.count {
        let flag = argv[i]
        guard i + 1 < argv.count else {
            FileHandle.standardError.write(Data("missing value for \(flag)\n".utf8))
            exit(2)
        }
        let value = argv[i + 1]
        switch flag {
        case "--title":    opts.title = value
        case "--message":  opts.message = value
        case "--subtitle": opts.subtitle = value
        case "--sound":    opts.sound = value
        case "--group", "--id": opts.identifier = value
        case "--remove":   opts.removeID = value
        default:
            FileHandle.standardError.write(Data("unknown flag: \(flag)\n".utf8))
            exit(2)
        }
        i += 2
    }
    return opts
}

let opts = parseOptions()
let center = UNUserNotificationCenter.current()

if let id = opts.removeID {
    center.removeDeliveredNotifications(withIdentifiers: [id])
    center.removePendingNotificationRequests(withIdentifiers: [id])
    Thread.sleep(forTimeInterval: 0.15)
    exit(0)
}

guard let body = opts.message else {
    FileHandle.standardError.write(Data("--message is required\n".utf8))
    exit(2)
}

let sema = DispatchSemaphore(value: 0)
var status: Int32 = 0

center.requestAuthorization(options: [.alert, .sound]) { granted, error in
    if let error = error {
        FileHandle.standardError.write(Data("auth error: \(error.localizedDescription)\n".utf8))
        status = 1
        sema.signal()
        return
    }
    guard granted else {
        FileHandle.standardError.write(Data("notification authorization denied\n".utf8))
        status = 1
        sema.signal()
        return
    }
    let content = UNMutableNotificationContent()
    content.title = opts.title
    content.body = body
    if let s = opts.subtitle { content.subtitle = s }
    if let s = opts.sound {
        content.sound = (s == "default")
            ? .default
            : UNNotificationSound(named: UNNotificationSoundName(s + ".aiff"))
    }
    let req = UNNotificationRequest(identifier: opts.identifier, content: content, trigger: nil)
    center.add(req) { err in
        if let err = err {
            FileHandle.standardError.write(Data("add failed: \(err.localizedDescription)\n".utf8))
            status = 1
        }
        sema.signal()
    }
}

sema.wait()
exit(status)
