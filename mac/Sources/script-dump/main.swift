import Foundation
import FocusUI

// Prints the AppleScript text the app generates for a browser (never runs it), for tools/check_space_scripts.sh.
// usage: script-dump currentTab <app> | switchTo <app> <url> <space> | switchToTitle <app> <title> <space> | close <app> <url>
let a = CommandLine.arguments
func arg(_ i: Int) -> String { i < a.count ? a[i] : "" }
switch arg(1) {
case "currentTab": print(TabScript.currentTab(app: arg(2)) ?? "NIL", terminator: "")
case "switchTo": print(TabScript.switchTo(app: arg(2), url: arg(3), space: arg(4)) ?? "NIL", terminator: "")
case "switchToTitle": print(TabScript.switchToTitle(app: arg(2), title: arg(3), space: arg(4)) ?? "NIL", terminator: "")
case "close": print(TabScript.close(app: arg(2), url: arg(3)) ?? "NIL", terminator: "")
default: print("usage")
}
