//
//  Delay.swift
//  Drift
//
//  Created by Brayden Moon on 20/2/2025.
//

import Foundation

func delay(_ milliseconds: Int, execute: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds), execute: execute)
}
