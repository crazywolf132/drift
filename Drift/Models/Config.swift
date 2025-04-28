//
//  Config.swift
//  Drift
//
//  Created by Brayden Moon on 20/2/2025.
//

import Foundation
import Combine

// MARK: - Configuration Data structures

/// Settings for modifier keys used in shortcuts
public struct KeyModifiers: Codable {
    public var command: Bool
    public var option: Bool
    public var control: Bool
    public var shift: Bool
    
    public init(command: Bool = false, option: Bool = false, control: Bool = false, shift: Bool = false) {
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }
}

/// Settings for status bar emojis
public struct StatusEmojis: Codable {
    public var normal: String
    public var active: String
    public var disabled: String
    
    public init(normal: String = "⚡️", active: String = "🚀", disabled: String = "⚠️") {
        self.normal = normal
        self.active = active
        self.disabled = disabled
    }
}

public struct LeaderKey: Codable {
    public var key: String
    public var modifiers: KeyModifiers
    
    public init(key: String = "space", modifiers: KeyModifiers = KeyModifiers(option: true)) {
        self.key = key
        self.modifiers = modifiers
    }
}

public struct GlobalSettings: Codable {
    public var quickSwitchEnabled: Bool
    public var leaderKey: LeaderKey
    public var statusEmojis: StatusEmojis
    public var useSystemIcons: Bool
    
    public init(quickSwitchEnabled: Bool,
                leaderKey: LeaderKey = LeaderKey(),
                statusEmojis: StatusEmojis = StatusEmojis(),
                useSystemIcons: Bool = true) {
        self.quickSwitchEnabled = quickSwitchEnabled
        self.leaderKey = leaderKey
        self.statusEmojis = statusEmojis
        self.useSystemIcons = useSystemIcons
    }
}

public enum ActionType: String, Codable {
    case group, application, url, command, folder
}

public protocol DriftItem: Codable {
    var key: String { get set }
    var type: ActionType { get }
    var label: String? { get set }
}

public struct Action: DriftItem {
    public var key: String
    public var type: ActionType
    public var label: String?
    public var value: String
    public var windowCycleMethod: String?
    
    public init(key: String, type: ActionType, label: String? = nil, value: String, windowCycleMethod: String? = nil) {
        self.key = key
        self.type = type
        self.label = label
        self.value = value
        self.windowCycleMethod = windowCycleMethod
    }
}

public struct Group: DriftItem {
    public var key: String
    public var type: ActionType = .group
    public var label: String?
    public var actions: [ActionOrGroup]
    
    public init(key: String, label: String? = nil, actions: [ActionOrGroup]) {
        self.key = key
        self.label = label
        self.actions = actions
    }
}

public struct DriftConfiguration: Codable {
    public var settings: GlobalSettings
    public var actions: [ActionOrGroup]
    
    public init(settings: GlobalSettings, actions: [ActionOrGroup]) {
        self.settings = settings
        self.actions = actions
    }
}

// MARK: - Actions

public enum ActionOrGroup: Codable {
    case action(Action)
    case group(Group)
    
    enum CodingKeys: String, CodingKey {
        case type
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ActionType.self, forKey: .type)
        let singleValueContainer = try decoder.singleValueContainer()
        switch type {
        case .group:
            self = .group(try singleValueContainer.decode(Group.self))
        default:
            self = .action(try singleValueContainer.decode(Action.self))
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .action(let action):
            try container.encode(action)
        case .group(let group):
            try container.encode(group)
        }
    }
    
    public var key: String {
        switch self {
        case .action(let a): return a.key
        case .group(let g): return g.key
        }
    }
}

