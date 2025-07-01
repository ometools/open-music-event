//
//  SnapshotTesting+CustomDump.swift
//  open-music-event
//
//  Created by Woodrow Melling on 6/21/25.
//

import CustomDump
import SnapshotTesting

extension Snapshotting where Format == String {

    public static func customDump(maxDepth: Int) -> Snapshotting {
      SimplySnapshotting.lines.pullback {
          String(customDumping: $0, maxDepth: maxDepth)
      }
  }
}

extension String {
    /// Creates a string dumping the given value.
    public init<Subject>(customDumping subject: Subject, maxDepth: Int) {
        var dump = ""
        customDump(subject, to: &dump, maxDepth: maxDepth)
        self = dump
    }
}
