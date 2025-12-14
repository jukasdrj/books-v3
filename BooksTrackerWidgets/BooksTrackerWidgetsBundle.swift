//
//  BooksTrackerWidgetsBundle.swift
//  BooksTrackerWidgets
//
//  Created by Justin Gardner on 10/4/25.
//

import WidgetKit
import SwiftUI
// import BooksTrackerFeature

@main
struct BooksTrackerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BooksTrackerWidgets()
        BooksTrackerWidgetsControl()
        // TODO: Re-enable in v1.13.0 once provisioning profile is updated
        // if #available(iOS 16.2, *) {
        //     CSVImportLiveActivity()
        // }
    }
}
