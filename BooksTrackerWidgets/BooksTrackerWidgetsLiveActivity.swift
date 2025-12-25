//
//  BooksTrackerWidgetsLiveActivity.swift
//  BooksTrackerWidgets
//
//  Created by Justin Gardner on 10/4/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct BooksTrackerWidgetsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct BooksTrackerWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BooksTrackerWidgetsAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension BooksTrackerWidgetsAttributes {
    fileprivate static var preview: BooksTrackerWidgetsAttributes {
        BooksTrackerWidgetsAttributes(name: "World")
    }
}

extension BooksTrackerWidgetsAttributes.ContentState {
    fileprivate static var smiley: BooksTrackerWidgetsAttributes.ContentState {
        BooksTrackerWidgetsAttributes.ContentState(emoji: "😀")
     }

     fileprivate static var starEyes: BooksTrackerWidgetsAttributes.ContentState {
         BooksTrackerWidgetsAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: BooksTrackerWidgetsAttributes.preview) {
   BooksTrackerWidgetsLiveActivity()
} contentStates: {
    BooksTrackerWidgetsAttributes.ContentState.smiley
    BooksTrackerWidgetsAttributes.ContentState.starEyes
}
