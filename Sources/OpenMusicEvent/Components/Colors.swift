//
//  SkipUI+.swift
//  event-viewer
//
//  Created by Woodrow Melling on 2/21/25.
//

import SwiftUI

#if SKIP
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.surfaceColorAtElevation
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp

let materialSystemBackground = Color(colorImpl: {
    MaterialTheme.colorScheme.surface
})
#endif
